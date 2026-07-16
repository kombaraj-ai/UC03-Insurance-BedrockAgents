# AutoClaim IQ

Production-grade AWS Bedrock Agents platform for a car insurance company. One Bedrock Agent, two Action Groups (Function schema + OpenAPI schema), a Knowledge Base backed by S3 Vectors with event-driven auto-sync, real DynamoDB-backed business logic, and an authenticated public API -- all provisioned via modular Terraform.

This project intentionally rebuilds a prior, demo-quality version of the same idea (see `PROJECT-IDEA.md`) that had: a monolithic `main.tf`, Lambdas returning hardcoded fake data, an unauthenticated public Lambda Function URL, `Resource = ["*"]` IAM policies, and no tests/observability. None of that carries over here -- see `docs/decision-log.md` for the specific corrections.

## Architecture

```
Cognito-authenticated client
        |
        v
API Gateway (HTTP API, JWT authorizer)
        |
        v
Client API Lambda --InvokeAgent--> Bedrock Agent (Claude, Guardrail-attached)
                                        |            |
                          PolicyActionGroup   ClaimsActionGroup      Knowledge Base
                          (Function schema)   (OpenAPI schema)       (S3 Vectors RAG)
                                |                    |                     |
                        Policy Lambda         Claims Lambda          KB source bucket
                                |                    |                     |
                          Policies table       Claims table      S3 event -> Sync Lambda
                            (DynamoDB)          (DynamoDB)         -> StartIngestionJob
```

## Repository layout

```
.
├── .checkov.yaml                     # Checkov config: documented skip-checks for deliberate trade-offs (no VPC/CMK/WAF)
├── .gitignore                        # excludes .venv, .terraform, tfstate, zips, __pycache__, real terraform.tfvars
├── .tflint.hcl                       # tflint config: aws ruleset plugin + naming-convention rules
├── CLAUDE.md                         # guidance for Claude Code instances working in this repo
├── Makefile                          # fmt/validate/lint/checkov/test/preflight + seed/upload targets
├── PROJECT-IDEA.md                   # original demo-quality design conversation this project rebuilds away from
├── pytest.ini                        # pytest --import-mode=importlib + warning against combined `pytest services/` runs
├── README.md                         # this file: architecture, deployment steps, security review
│
├── data-seed/                        # scripts + sample data to populate DynamoDB after the first apply
│   ├── sample-data/
│   │   ├── claims.json               # sample pre-existing claims, for exercising getClaimStatus
│   │   └── policies.json             # sample policyholders, for exercising verify/createClaim
│   ├── seed_claims.py                # loads sample-data/claims.json into the Claims table
│   └── seed_policies.py              # loads sample-data/policies.json into the Policies table
│
├── docs/
│   ├── decision-log.md                # ADR-style entries for non-obvious design decisions
│   └── iam-matrix.md                  # every IAM role, its permissions, and exact resource scope
│
├── infra/
│   ├── bootstrap/                     # one-time, local-state config: Terraform state S3 bucket + DynamoDB lock table
│   │   ├── main.tf                    # S3 state bucket + DynamoDB lock table resources
│   │   ├── outputs.tf                 # state_bucket_name / lock_table_name, fed into infra/live/<env>/versions.tf
│   │   ├── README.md                  # why this exists, how to apply it once, operational rules
│   │   ├── variables.tf               # region/project/bucket/table name inputs
│   │   └── versions.tf                # provider requirements -- deliberately no backend block (chicken-and-egg)
│   │
│   ├── live/dev/                      # root composition: wires every module together for the "dev" environment
│   │   ├── main.tf                    # instantiates all 12 modules + the OpenAPI schema S3 object, in dependency order
│   │   ├── outputs.tf                 # api_endpoint, agent_id, table names, cognito ids, etc.
│   │   ├── providers.tf               # aws provider config + default_tags
│   │   ├── terraform.tfvars.example   # copy to terraform.tfvars and fill in real values before applying
│   │   ├── variables.tf                # environment, region, model ids, CORS/callback URLs, etc.
│   │   └── versions.tf                # pinned Terraform/provider versions + S3 backend block
│   │
│   └── modules/
│       ├── api-gateway/                # HTTP API + Cognito JWT authorizer + route/stage/access-logs (public entry point)
│       │   ├── main.tf                 # API, authorizer, integration, route, stage, access log group, Lambda permission
│       │   ├── outputs.tf              # api_endpoint, api_id
│       │   ├── variables.tf            # CORS origins, Cognito issuer/client id, client Lambda ARNs, throttling
│       │   └── versions.tf             # provider requirement
│       │
│       ├── bedrock-agent/              # the Bedrock Agent, both action groups, KB association, alias (highest-risk module)
│       │   ├── main.tf                 # agent, PolicyActionGroup, ClaimsActionGroup, KB association, alias + supplemental IAM/Lambda-invoke grants
│       │   ├── outputs.tf              # agent_id/arn, agent_alias_id/arn
│       │   ├── variables.tf            # model id, instruction, guardrail id/version, KB id, Lambda ARNs, client API role name
│       │   └── versions.tf             # provider requirement
│       │
│       ├── cognito/                    # identity provider for the public API
│       │   ├── main.tf                 # user pool (password policy, MFA), app client (no secret, PKCE-style)
│       │   ├── outputs.tf              # user_pool_id, user_pool_client_id, issuer_url
│       │   ├── variables.tf            # callback/logout URLs, MFA configuration
│       │   └── versions.tf             # provider requirement
│       │
│       ├── dynamodb/                   # Policies and Claims tables -- the real data layer
│       │   ├── main.tf                 # both tables, GSIs, PITR, SSE, prevent_destroy
│       │   ├── outputs.tf              # table names/ARNs, GSI ARNs, claims stream ARN
│       │   ├── variables.tf            # name_prefix, tags
│       │   └── versions.tf             # provider requirement
│       │
│       ├── guardrails/                 # Bedrock Guardrail: content filters, PII handling, denied topics
│       │   ├── main.tf                 # guardrail + published guardrail version
│       │   ├── outputs.tf              # guardrail_id, guardrail_arn, guardrail_version
│       │   ├── variables.tf            # content filter / PII entity / denied topic lists (with sensible defaults)
│       │   └── versions.tf             # provider requirement
│       │
│       ├── iam/                        # central IAM role definitions -- base permissions (see docs/iam-matrix.md for the full picture)
│       │   ├── bedrock_agent_role.tf   # the agent's own execution role (InvokeModel, ApplyGuardrail, Lambda invoke)
│       │   ├── bedrock_kb_role.tf      # the Knowledge Base's execution role (embedding model, source bucket read)
│       │   ├── lambda_roles.tf         # the 4 Lambda execution roles (policy, claims, kb-sync, client-api) + X-Ray attachments
│       │   ├── main.tf                 # shared locals (constructed Lambda/log-group ARNs) + the Lambda assume-role policy
│       │   ├── outputs.tf              # every role's ARN and name (names feed kb-s3vectors/bedrock-agent's supplemental grants)
│       │   ├── variables.tf            # cross-module inputs, with a note on why KB/agent ARNs are deliberately NOT accepted here
│       │   └── versions.tf             # provider requirement
│       │
│       ├── kb-s3vectors/               # Knowledge Base storage: S3 Vectors bucket/index + the KB + S3 data source
│       │   ├── main.tf                 # vector bucket, vector index, knowledge base, data source + supplemental IAM grants
│       │   ├── outputs.tf              # knowledge_base_id/arn, data_source_id, vector bucket/index ARNs
│       │   ├── variables.tf            # embedding model, chunking config, role names for supplemental grants
│       │   └── versions.tf             # provider requirement
│       │
│       ├── kb-sync-lambda/             # wires the S3 auto-sync trigger (bucket notification -> sync Lambda)
│       │   ├── main.tf                 # Lambda permission for S3 invoke + S3 bucket notification
│       │   ├── variables.tf            # source bucket + sync Lambda identifiers
│       │   └── versions.tf             # provider requirement
│       │
│       ├── kms/                        # CMK used to encrypt every CloudWatch Log Group in the stack
│       │   ├── main.tf                 # KMS key (with a CloudWatch Logs usage policy) + alias
│       │   ├── outputs.tf              # key_arn, key_id, alias_name
│       │   ├── variables.tf            # name, description, account/region, rotation
│       │   └── versions.tf             # provider requirement
│       │
│       ├── lambda-function/            # generic reusable Lambda baseline (packaging, log group, tracing, retries)
│       │   ├── main.tf                 # archive_file zip, KMS-encrypted log group, Lambda function, event-invoke config
│       │   ├── outputs.tf              # function_arn/name, invoke_arn, log group name/arn
│       │   ├── variables.tf            # source_dir, handler, role_arn, env vars, memory/timeout, tracing, retries
│       │   └── versions.tf             # provider + archive provider requirements
│       │
│       ├── observability/              # CloudWatch alarms, SNS topic, and an overview dashboard
│       │   ├── main.tf                 # per-Lambda error/throttle/duration alarms, API GW 4xx/5xx, DynamoDB throttle alarms, dashboard
│       │   ├── outputs.tf              # sns_topic_arn, dashboard_name
│       │   ├── variables.tf            # function/table name maps, alarm email, api id/name
│       │   └── versions.tf             # provider requirement
│       │
│       └── s3-secure-bucket/           # generic hardened S3 bucket (versioned, encrypted, public-access blocked, deny-non-TLS)
│           ├── main.tf                 # bucket + versioning + SSE + public-access-block + bucket policy + optional lifecycle rules
│           ├── outputs.tf              # bucket_name/arn/id
│           ├── variables.tf            # bucket_name, kms_key_arn, force_destroy, lifecycle_rules
│           └── versions.tf             # provider requirement
│
├── knowledge-base/
│   ├── seed-docs/
│   │   ├── claims-process-guide.md    # sample KB doc: filing flow, claim status lifecycle, special cases
│   │   ├── coverage-faq.md            # sample KB doc: comprehensive/collision coverage, deductibles, exclusions
│   │   └── glossary.md                # sample KB doc: rental reimbursement terms + insurance glossary
│   └── upload_seed_docs.sh            # uploads seed-docs/ to the KB source bucket, triggering auto-sync ingestion
│
├── schemas/
│   └── claims-openapi.yaml            # ClaimsActionGroup OpenAPI schema (createClaim has x-requireConfirmation: ENABLED)
│
└── services/
    ├── claims_handler/                 # Bedrock Action Group Lambda: createClaim + getClaimStatus (OpenAPI schema)
    │   ├── requirements-dev.txt        # test-only deps (boto3, moto, pytest)
    │   ├── requirements.txt            # runtime deps (none -- boto3 ships with the Lambda runtime)
    │   ├── src/
    │   │   ├── adjuster_assignment.py  # deterministic hash-based adjuster assignment (not a hardcoded name)
    │   │   ├── claim_id.py             # real, collision-checkable claim number generation
    │   │   ├── dynamo_client.py        # DynamoDB access (Claims read/write, Policies read-only)
    │   │   └── handler.py              # routes POST /claims and GET /claims/{claimNumber}, builds the OpenAPI response envelope
    │   └── tests/
    │       ├── conftest.py             # moto-backed Policies/Claims table fixtures
    │       └── test_handler.py         # happy path, validation, idempotent collision retry, error sanitization
    │
    ├── client_api_handler/             # public API entry point Lambda, behind API Gateway
    │   ├── requirements-dev.txt        # test-only deps
    │   ├── requirements.txt            # runtime deps (none)
    │   ├── src/
    │   │   ├── handler.py              # parses JWT claims, calls bedrock-agent-runtime:InvokeAgent, returns the completion
    │   │   └── session_id.py           # derives the Bedrock sessionId from the Cognito `sub` (never client-supplied)
    │   └── tests/
    │       ├── conftest.py             # fake bedrock-agent-runtime client fixture
    │       ├── test_handler.py         # auth checks, request validation, error sanitization
    │       └── test_session_id.py      # session id determinism/uniqueness per user
    │
    ├── kb_sync_handler/                # S3 event -> Bedrock Knowledge Base ingestion trigger
    │   ├── requirements-dev.txt        # test-only deps
    │   ├── requirements.txt            # runtime deps (none)
    │   ├── src/
    │   │   └── handler.py              # calls bedrock-agent:StartIngestionJob, treats an already-running sync as a no-op
    │   └── tests/
    │       ├── conftest.py             # env var fixtures
    │       └── test_handler.py         # success, conflict, not-found, and unexpected-error handling (botocore Stubber)
    │
    └── policy_handler/                 # Bedrock Action Group Lambda: verifyAndRetrievePolicy (Function schema)
        ├── requirements-dev.txt        # test-only deps
        ├── requirements.txt            # runtime deps (none)
        ├── src/
        │   ├── dynamo_client.py        # DynamoDB access (Policies read-only)
        │   └── handler.py              # validates input, verifies policy+lastName, builds the Function-schema response envelope
        └── tests/
            ├── conftest.py             # moto-backed Policies table fixture
            └── test_handler.py         # found/mismatch/not-found/invalid-input/unhandled-error cases
```

## Prerequisites

- Terraform 1.15.7 (exact version pinned in `infra/*/versions.tf`)
- AWS CLI configured with credentials that can create Bedrock, IAM, Lambda, DynamoDB, S3, Cognito, and API Gateway resources
- Python 3.12 (matches the Lambda runtime) with `pip`
- Access to the target Bedrock model(s) requested/enabled in the AWS Console for your region (Anthropic Claude model in use, and the Titan embedding model)

## Deploying

### 1. Bootstrap the Terraform state backend (once per account/region)

```bash
cd infra/bootstrap
terraform init
terraform apply
```

Note the `state_bucket_name` and `lock_table_name` outputs.

### 2. Configure the backend and variables

```bash
cd infra/live/dev
```

Edit `versions.tf`'s `backend "s3"` block with the bootstrap outputs (or pass them via `-backend-config` flags), then:

```bash
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: set foundation_model_id to a model ID/inference
# profile currently available in your region, plus alarm_email,
# cors_allowed_origins, cognito_callback_urls
terraform init
```

### 3. Run the local test/lint suite before applying

```bash
cd ../../..            # repo root
python -m venv .venv
.venv/bin/pip install -r services/policy_handler/requirements-dev.txt \
                       -r services/claims_handler/requirements-dev.txt \
                       -r services/kb_sync_handler/requirements-dev.txt \
                       -r services/client_api_handler/requirements-dev.txt
make preflight          # terraform fmt/validate across every module + full pytest suite
```

`make lint` / `make checkov` are available too if you have `tflint` / `checkov` installed locally (not required).

### 4. Apply

```bash
cd infra/live/dev
terraform plan
terraform apply
```

### 5. Seed data and the Knowledge Base

```bash
cd ../..                # repo root
make seed-policies       # populates the Policies table with sample policyholders
make seed-claims         # optional: a couple of pre-existing sample claims
make upload-kb-docs      # uploads knowledge-base/seed-docs/ -- triggers auto-sync ingestion
```

Check the Knowledge Base's data source sync history in the Bedrock console to confirm the ingestion job started automatically after the upload -- no manual "Sync" click required.

### 6. Create a test Cognito user and get a bearer token

```bash
aws cognito-idp admin-create-user \
  --user-pool-id "$(cd infra/live/dev && terraform output -raw cognito_user_pool_id)" \
  --username testuser@example.com --temporary-password 'TempPass123!' --message-action SUPPRESS

aws cognito-idp admin-set-user-password \
  --user-pool-id "$(cd infra/live/dev && terraform output -raw cognito_user_pool_id)" \
  --username testuser@example.com --password 'RealPass123!' --permanent

aws cognito-idp initiate-auth \
  --client-id "$(cd infra/live/dev && terraform output -raw cognito_user_pool_client_id)" \
  --auth-flow USER_PASSWORD_AUTH \
  --auth-parameters USERNAME=testuser@example.com,PASSWORD='RealPass123!'
# copy the AccessToken from the response
```

### 7. Exercise the API

```bash
API_URL="$(cd infra/live/dev && terraform output -raw api_endpoint)"
TOKEN="<AccessToken from step 6>"

curl -X POST "${API_URL}chat" \
  -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" \
  -d '{"prompt": "What is my deductible if a tree branch falls on my car?"}'

curl -X POST "${API_URL}chat" \
  -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" \
  -d '{"prompt": "Hi, my policy number is POL-998877 and my last name is Smith. Can you verify my policy?"}'

curl -X POST "${API_URL}chat" \
  -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" \
  -d '{"prompt": "My name is Smith, policy POL-998877. I hit a deer today. Please file a claim for me."}'
```

The last one should trigger the agent's confirmation round-trip before it actually calls `createClaim` -- respond affirmatively in a follow-up message with the same bearer token to complete the filing.

### 8. Tear down

Empty the two S3 buckets (schema + KB docs) first -- Terraform won't delete non-empty buckets -- then:

```bash
cd infra/live/dev
terraform destroy
```

The state backend (`infra/bootstrap`) is not part of this and should be left alone; see `infra/bootstrap/README.md`.

## Security review -- what's deliberately not built

Documented explicitly rather than silently omitted (see `docs/decision-log.md` for more):

- No VPC / PrivateLink -- this is a fully serverless stack; all protection is IAM + application-layer.
- No WAF in front of API Gateway -- JWT auth + stage throttling only.
- No customer-managed KMS keys on DynamoDB/S3 -- only CloudWatch Logs get a dedicated CMK.
- No custom domain/ACM certificate on API Gateway -- ships on the default `execute-api` endpoint.
- No multi-region/DR strategy -- single region, no cross-region replication.
- No CI/CD pipeline -- single environment, applied manually; `make preflight` is the local substitute for CI gating.
- Guardrail content (denied topics, PII entity list) is a first draft pending legal/compliance review, not a finalized policy.

## Facts to re-verify before/at build time

Called out inline in code comments too, but worth repeating: the exact current Bedrock model ID for your region (`foundation_model_id`), the `aws_s3vectors_*` resource/IAM action set (a newer AWS surface), and the exact `InvokeAgent` confirmation round-trip shape used when a user confirms a pending `createClaim`. None of these block the build, but don't assume the values in this repo are still current -- check the live AWS/Terraform provider docs.
