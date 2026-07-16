# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

AutoClaim IQ: an AWS Bedrock Agents platform for a car insurance company. One Bedrock Agent with two Action Groups (Function schema for policy verification, OpenAPI schema for claims), a Knowledge Base backed by S3 Vectors with event-driven auto-sync, real DynamoDB-backed business logic, and a Cognito-authenticated public API. All infrastructure is Terraform (pinned to `1.15.7`, AWS provider `>= 6.27.0`). `PROJECT-IDEA.md` is the original (demo-quality) design conversation this project deliberately rebuilds away from — `docs/decision-log.md` documents each specific correction.

## Commands

### Terraform

State backend must be bootstrapped once per AWS account/region before anything else:

```bash
cd infra/bootstrap && terraform init && terraform apply   # local state, one-time only
```

Then the main environment:

```bash
cd infra/live/dev
terraform init      # backend "s3" block in versions.tf must point at the bootstrap outputs first
terraform plan
terraform apply
```

Validating a single module in isolation (every module under `infra/modules/*`, plus `infra/bootstrap` and `infra/live/dev`, is independently `init`-able with `-backend=false`):

```bash
cd infra/modules/<name> && terraform init -backend=false -input=false && terraform validate
```

### Local dev-loop (no CI/CD in this project — this is the substitute)

```bash
make preflight     # terraform fmt -recursive + validate every module + full pytest suite
make fmt           # terraform fmt -recursive infra
make validate      # terraform validate across every module + bootstrap + live/dev
make lint          # tflint per module (requires tflint + aws ruleset installed separately)
make checkov       # checkov -d infra --config-file .checkov.yaml (requires checkov installed separately)
```

### Python / Lambda tests

One virtualenv at repo root covers all 4 Lambda services:

```bash
python -m venv .venv
.venv/bin/pip install -r services/policy_handler/requirements-dev.txt \
                       -r services/claims_handler/requirements-dev.txt \
                       -r services/kb_sync_handler/requirements-dev.txt \
                       -r services/client_api_handler/requirements-dev.txt
make test          # loops pytest once per service directory
```

Run a single service's suite or a single test directly:

```bash
.venv/bin/python -m pytest services/claims_handler/tests -v
.venv/bin/python -m pytest services/claims_handler/tests/test_handler.py::test_create_claim_happy_path -v
```

**Never run `pytest services/` across all four service directories in one process.** Every service's business module is literally named `handler` (each is an independently zipped, isolated Lambda deployable, not a shared package) — a single interpreter importing more than one `handler.py` will silently reuse whichever one it imported first via `sys.modules`, testing the wrong code. `pytest.ini` sets `--import-mode=importlib` only to fix a pytest *collection*-time name collision on the repeated `test_handler.py` basename; it does not make combined runs safe. Always invoke per-service, as `make test` does.

### Data seeding / Knowledge Base upload (after the first `apply`)

```bash
make seed-policies    # populates the Policies table from data-seed/sample-data/policies.json
make seed-claims      # optional pre-existing sample claims
make upload-kb-docs   # uploads knowledge-base/seed-docs/ -- triggers auto-sync ingestion via S3 event
```

## Architecture

### Module dependency graph and the IAM-cycle-avoidance pattern

`infra/modules/iam` is the intended single source of truth for IAM role definitions, but three resources have real, AWS-generated (non-predictable) ARNs that create a circular dependency if `iam` tried to grant permissions on them directly:

- `modules/kb-s3vectors` needs `bedrock_kb_role_arn` from `iam` to create the Knowledge Base (`role_arn` field) — so `iam` can't *also* depend on the KB's ARN for the agent's `Retrieve`/`RetrieveAndGenerate` permission or the sync Lambda's `StartIngestionJob` permission.
- `modules/bedrock-agent` needs `agent_role_arn` from `iam` to create the agent — so `iam` can't *also* depend on the agent/alias ARN for the client-API role's `InvokeAgent` permission.

The fix used throughout: the resource-owning module (`kb-s3vectors`, `bedrock-agent`) takes the *target role's name* as an input and attaches a small supplemental `aws_iam_role_policy` directly, using its own just-created real ARN. So when tracing what a role can do, you must check **both** `infra/modules/iam/*.tf` (base permissions: DynamoDB, logs, KMS, X-Ray) **and** the supplemental grant inside whichever module owns the specific resource being accessed. `docs/iam-matrix.md` is the authoritative combined view — keep it in sync when touching IAM.

Similarly, Lambda function ARNs are passed into `modules/iam` as plain name **strings** (computed as locals in `infra/live/dev/main.tf`, e.g. `"${local.name_prefix}-policy-handler"`) rather than as module output references, and reassembled into ARNs via string interpolation inside `iam`. This is the same cycle-avoidance trick applied one level earlier: it lets `iam`'s `bedrock_agent_role` grant `lambda:InvokeFunction` on the action-group Lambdas without waiting on the `lambda-function` module instances that themselves need `iam`'s role ARNs.

### Request flow

```
Cognito-authenticated client -> API Gateway (HTTP API, JWT authorizer) -> Client API Lambda
  --InvokeAgent--> Bedrock Agent (Claude + Guardrail)
        |-- PolicyActionGroup (Function schema)  -> Policy Lambda  -> Policies (DynamoDB)
        |-- ClaimsActionGroup (OpenAPI schema)    -> Claims Lambda -> Claims (DynamoDB), read-only cross-check of Policies
        `-- Knowledge Base (S3 Vectors RAG)       <- KB source bucket <- S3 event -> Sync Lambda -> StartIngestionJob
```

The two action-group Lambdas receive **different event envelopes** from Bedrock and must be parsed accordingly: `services/policy_handler` uses the Function-schema shape (`event["parameters"]`, response under `response.functionResponse.responseBody.TEXT.body`); `services/claims_handler` uses the OpenAPI/API-schema shape (`event["apiPath"]` / `event["httpMethod"]` / `event["requestBody"]`, response under `response.responseBody["application/json"].body`, with an `httpStatusCode`). Don't assume the two Lambdas' `handler.py` files are interchangeable in structure — they intentionally are not.

### Claim confirmation lives in the OpenAPI schema, not Terraform

`schemas/claims-openapi.yaml` marks `POST /claims` with `x-requireConfirmation: ENABLED`. The installed Bedrock provider's Function-schema `functions` block has no `require_confirmation` argument (confirmed directly against the provider schema during the build) — for OpenAPI-schema action groups, confirmation is declared in the schema document itself, which Bedrock parses at the agent level. Because of this, `services/claims_handler` never sees a "pending confirmation" state in its event payload: Bedrock withholds the Lambda invocation entirely until the end user confirms, then invokes it once. The handler still uses a conditional `PutItem` (`attribute_not_exists(claimNumber)`) for idempotency as a defensive measure, independent of the confirmation flow.

### Session identity, not client-supplied session IDs

`services/client_api_handler/src/session_id.py` derives the Bedrock `sessionId` deterministically from the authenticated Cognito `sub` claim (`sha256(sub)`) rather than accepting any client-supplied session identifier. This is a deliberate security boundary: it prevents one authenticated user from addressing (and continuing) another user's agent conversation. If per-user multiple conversation threads are ever needed, the additional thread identifier must still be scoped under the verified `sub` — never a bare client-supplied value.

### Provider-version-sensitive resources

`infra/modules/bedrock-agent/main.tf` documents two known `terraform-provider-aws` quirks that shape its structure: (1) concurrent action-group changes against the same agent can race an implicit "Preparing" state, mitigated with an explicit `depends_on` chain forcing serial application (policy action group -> claims action group -> KB association -> alias); (2) guardrail association at agent-creation time has needed a follow-up apply in some provider versions. Re-verify both against the currently pinned provider version before assuming a single-pass `apply` always works. `infra/modules/kb-s3vectors` is flagged similarly as the newest, least battle-tested AWS surface in the stack (S3 Vectors + the KB's `S3_VECTORS` storage configuration).

### What's deliberately not built

No VPC/PrivateLink, no WAF in front of API Gateway, no customer-managed KMS keys on DynamoDB/S3 (only CloudWatch Logs get a CMK), no custom domain on API Gateway, no multi-region/DR, no CI/CD pipeline. These are documented trade-offs (see README "Security review" and `docs/decision-log.md`), not oversights — don't silently "fix" them without flagging the scope change.
