# Decision Log

Short ADR-style entries for decisions that aren't obvious from reading the code.

## S3 Vectors instead of OpenSearch Serverless

**Decision:** The Knowledge Base's vector store is Amazon S3 Vectors (`infra/modules/kb-s3vectors`), not OpenSearch Serverless.

**Why:** OpenSearch Serverless bills for idle capacity units even at zero query volume, which is a poor fit for a project-scale RAG pipeline with light, bursty traffic. S3 Vectors is natively S3-backed, pay-per-use, and (as of this build) directly supported as a Bedrock Knowledge Base storage backend via `aws_bedrockagent_knowledge_base.storage_configuration.s3_vectors_configuration`.

**Trade-off:** S3 Vectors is a newer AWS service than OpenSearch Serverless -- less battle-tested, and its exact IAM action set / resource ARN shape should be re-verified against current AWS docs before any provider upgrade.

## Session ID derived from Cognito `sub`, never client-supplied

**Decision:** `services/client_api_handler/src/session_id.py` derives the Bedrock `sessionId` deterministically from the authenticated Cognito `sub` claim (`sha256(sub)`), rather than accepting a `sessionId` in the request body.

**Why:** A client-supplied session ID lets any authenticated caller address (and potentially continue) another user's conversation with the agent -- a session/IDOR hijack. Binding session identity to the verified JWT claim closes that off entirely: a caller can only ever address their own session.

**Trade-off:** A user can't run multiple independent conversation threads (today, one user = one session). If that's needed later, a thread ID should be a server-generated value scoped under the user's `sub`, never a bare client-supplied value.

## Confirmation for `createClaim` lives in the OpenAPI schema, not Terraform

**Decision:** `POST /claims` is marked `x-requireConfirmation: ENABLED` in `schemas/claims-openapi.yaml`, not via a Terraform-level flag.

**Why:** The installed `aws_bedrockagent_agent_action_group` Function-schema `functions` block has no `require_confirmation` argument (verified directly against the provider schema, not assumed) -- confirmation for OpenAPI/API-schema action groups is declared as an `x-requireConfirmation` extension in the OpenAPI document itself, which Bedrock parses. Because of this, `services/claims_handler` never sees a "pending confirmation" state: Bedrock withholds the Lambda invocation entirely until the end user confirms, then invokes it once. The handler stays idempotent (conditional `PutItem`) as a defensive measure regardless.

## Supplemental IAM policies attached outside `modules/iam`

**Decision:** Three permissions (agent's KB-retrieve, sync Lambda's ingestion trigger, client API's InvokeAgent) are attached as small `aws_iam_role_policy` resources inside `modules/kb-s3vectors` and `modules/bedrock-agent`, rather than centralized in `modules/iam`.

**Why:** Both of those modules need a role ARN *from* `modules/iam` to create their primary resource (the KB's `role_arn`, the agent's `agent_resource_role_arn`). If `modules/iam` also needed those modules' output ARNs to build its own policies, that's a circular module dependency Terraform can't resolve. Attaching the permission where the real ARN is already a local resource attribute avoids the cycle without loosening the permission at all. See `docs/iam-matrix.md` for the full breakdown.

## Real claim numbers and adjuster assignment, not mocked strings

**Decision:** `services/claims_handler` generates a real, collision-checked claim number (`CLM-<year>-<random 6 digits>` with a conditional `PutItem`) and assigns an adjuster via a deterministic hash over a small roster, instead of the reference design's hardcoded `"CLM-" + timestamp` / `"Sarah Jenkins"`.

**Why:** The brief was explicitly "not a demo" -- a Lambda that always returns the same fake adjuster name regardless of input isn't exercising real business logic, and a timestamp-based ID has real (if small) collision risk under concurrent requests. The conditional write plus retry loop makes claim creation genuinely safe under concurrency.

## Single Bedrock Agent, not multi-agent collaboration

**Decision:** One agent with two Action Groups (Function schema for Policy, OpenAPI schema for Claims), not a Supervisor + collaborator-agents topology.

**Why:** The original ask was specifically to demonstrate both Action Group schema types end-to-end; a multi-agent split would roughly triple the Terraform/IAM surface for a workflow that doesn't yet need independently-scaling specialized agents. Confirmed with the user before building (see plan).
