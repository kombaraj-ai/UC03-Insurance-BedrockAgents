variable "name_prefix" {
  type = string
}

variable "account_id" {
  type = string
}

variable "region" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

# ---------------------------------------------------------------------------
# Cross-module references.
#
# Lambda function ARNs are passed in as plain function-name STRINGS (not
# module output attribute references) and reassembled into ARNs here via
# string interpolation. This is deliberate: the Bedrock agent role's
# lambda:InvokeFunction permission needs those ARNs, but the Lambda
# resources themselves need *this* module's role ARNs as their execution
# role. Referencing real resource attributes in both directions would be a
# dependency cycle; Lambda ARNs are fully deterministic
# (arn:aws:lambda:<region>:<account_id>:function:<name>) so a plain string
# variable avoids the cycle without sacrificing correctness.
# ---------------------------------------------------------------------------

variable "policy_lambda_function_name" {
  type = string
}

variable "claims_lambda_function_name" {
  type = string
}

variable "kb_sync_lambda_function_name" {
  type = string
}

variable "client_api_lambda_function_name" {
  type = string
}

# NOTE: this module deliberately does NOT take agent_arn/agent_alias_arn,
# kb_arn, or kb_vector_bucket_arn/kb_vector_index_arn as inputs. Each of
# those is produced by a module (bedrock-agent, kb-s3vectors) that itself
# needs a role ARN *from this module* as an input (agent_resource_role_arn /
# role_arn). Taking their outputs here would create a two-way dependency
# cycle (iam -> that module -> iam). Instead, the permissions that target
# those specific, non-predictable-ID resources are attached as supplemental
# aws_iam_role_policy resources inside the modules that create them
# (modules/bedrock-agent grants its own role InvokeAgent; modules/kb-s3vectors
# grants its own role Retrieve/StartIngestionJob/s3vectors access) -- see the
# role *_name outputs below, which those modules consume for exactly that.

variable "model_invoke_arns" {
  description = "Foundation model / cross-region inference profile ARN(s) the agent is allowed to invoke."
  type        = list(string)
}

variable "kb_embedding_model_arn" {
  type = string
}

variable "kb_source_bucket_arn" {
  type = string
}

variable "guardrail_arn" {
  type = string
}

variable "policies_table_arn" {
  type = string
}

variable "policies_table_lastname_gsi_arn" {
  type = string
}

variable "claims_table_arn" {
  type = string
}

variable "claims_table_policyid_gsi_arn" {
  type = string
}

variable "kms_log_key_arn" {
  type = string
}
