# IAM Matrix

Every role in this stack, what it's allowed to do, and exactly what it's scoped to.
No role in this project grants `Resource = ["*"]` for a scopable action. Keep this file in sync with `infra/modules/iam/*.tf` and the supplemental policies in `infra/modules/kb-s3vectors/main.tf` and `infra/modules/bedrock-agent/main.tf`.

| Role | Defined in | Trust principal | Key permissions | Resource scope |
|---|---|---|---|---|
| `<prefix>-bedrock-agent-role` | `modules/iam/bedrock_agent_role.tf` | `bedrock.amazonaws.com` (SourceAccount-scoped) | `bedrock:InvokeModel[WithResponseStream]`, `bedrock:ApplyGuardrail`, `lambda:InvokeFunction` | Specific model/inference-profile ARN(s); specific guardrail ARN; exactly the Policy + Claims Lambda ARNs |
| | + `modules/kb-s3vectors/main.tf` | | `bedrock:Retrieve`, `bedrock:RetrieveAndGenerate` | The specific Knowledge Base ARN (attached here, not in `modules/iam`, to avoid an iam<->kb-s3vectors dependency cycle -- see that module's comments) |
| `<prefix>-bedrock-kb-role` | `modules/iam/bedrock_kb_role.tf` | `bedrock.amazonaws.com` (SourceAccount-scoped) | `bedrock:InvokeModel`, `s3:GetObject`/`ListBucket` | Embedding model ARN only; KB source-docs bucket only |
| | + `modules/kb-s3vectors/main.tf` | | `s3vectors:PutVectors/GetVectors/QueryVectors/DeleteVectors/GetIndex/ListVectors` | The specific vector bucket + index ARN (attached here for the same cycle-avoidance reason) |
| `<prefix>-policy-lambda-role` | `modules/iam/lambda_roles.tf` | `lambda.amazonaws.com` | `dynamodb:GetItem`, `dynamodb:Query` | `Policies` table + `LastNameIndex` GSI only -- **no write access** (this Lambda only verifies) |
| `<prefix>-claims-lambda-role` | `modules/iam/lambda_roles.tf` | `lambda.amazonaws.com` | `dynamodb:GetItem/PutItem/UpdateItem/Query` on Claims; `dynamodb:GetItem` on Policies | Own table + GSI; **read-only** cross-reference to Policies (to check `ACTIVE` status) |
| `<prefix>-kb-sync-lambda-role` | `modules/iam/lambda_roles.tf` | `lambda.amazonaws.com` | `s3:GetObject` on the source bucket | KB source-docs bucket only |
| | + `modules/kb-s3vectors/main.tf` | | `bedrock:StartIngestionJob`, `bedrock:GetIngestionJob` | The specific Knowledge Base ARN |
| `<prefix>-client-api-lambda-role` | `modules/iam/lambda_roles.tf` | `lambda.amazonaws.com` | (logs/kms/X-Ray only here) | n/a |
| | + `modules/bedrock-agent/main.tf` | | `bedrock:InvokeAgent` | The specific agent ARN **and** alias ARN (attached here for the same cycle-avoidance reason) |

Every role also gets: `logs:CreateLogStream`/`PutLogEvents` scoped to its own `/aws/lambda/<function-name>` log group, and `kms:Decrypt`/`GenerateDataKey` scoped to the shared logging CMK (`modules/kms`). The three Lambda-invoking roles (client API, policy, claims, kb-sync) also get the AWS-managed `AWSXRayDaemonWriteAccess` policy -- X-Ray write actions don't support resource-level scoping.

## Why some permissions live outside `modules/iam`

`modules/iam` is the single source of truth for role *definitions* and any permission whose target ARN is either static (a Bedrock foundation-model ARN) or already available from a module that doesn't itself need an `iam` module output. Three permissions can't follow that pattern without creating a circular module dependency:

- The agent's KB-retrieve and the sync Lambda's ingestion permissions target the Knowledge Base's ARN, but `modules/kb-s3vectors` needs `bedrock_kb_role_arn` from `modules/iam` to create the KB in the first place. If `modules/iam` also needed the KB's ARN back, that's a cycle.
- The client API role's `InvokeAgent` permission targets the agent/alias ARN, but `modules/bedrock-agent` needs `agent_role_arn` from `modules/iam`. Same problem in reverse.

Both are resolved the same way: the resource-owning module (`kb-s3vectors`, `bedrock-agent`) takes the target role's *name* as an input and attaches a small supplemental `aws_iam_role_policy` to it directly, using its own real, just-created ARN. This keeps every permission scoped exactly as tightly as if it lived in `modules/iam`, just declared in a different file.
