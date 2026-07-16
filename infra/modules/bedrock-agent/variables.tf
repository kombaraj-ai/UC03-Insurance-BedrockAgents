variable "name_prefix" {
  type = string
}

variable "agent_role_arn" {
  type = string
}

variable "foundation_model_id" {
  description = <<-EOT
    Bedrock model ID or cross-region inference profile ID, e.g.
    "us.anthropic.claude-sonnet-4-5-20250929-v1:0". Verify against the
    current Bedrock model catalog for your target region before applying --
    Anthropic/AWS ship new model versions regularly and IDs are
    region-specific.
  EOT
  type        = string
}

variable "instruction" {
  type    = string
  default = <<-EOT
    You are AutoClaim IQ, AutoClaim Insurance Co.'s virtual assistant for
    auto insurance policyholders. Your job is to verify policyholder
    identity, answer coverage and claims-process questions using the
    knowledge base, and help policyholders file and check on claims.

    Rules you must always follow:
    1. Before discussing any specific policy or filing a claim, verify the
       caller's identity using verifyAndRetrievePolicy (policy number +
       last name). Never assume identity from what the caller states.
    2. Never file a claim (createClaim) without first explicitly asking the
       caller to confirm the accident date and description back to them and
       getting their agreement to proceed.
    3. Ground coverage, deductible, and claims-process answers in the
       knowledge base. If the knowledge base does not have an answer, say so
       rather than guessing.
    4. Never provide legal or medical advice, or compare AutoClaim Co. to
       named competitors -- politely decline and suggest the appropriate
       professional if asked.
    5. Never repeat back a policyholder's full SSN, card number, or bank
       account number, even if they provide one.
  EOT
}

variable "idle_session_ttl_in_seconds" {
  type    = number
  default = 1800
}

variable "guardrail_id" {
  type = string
}

variable "guardrail_version" {
  type = string
}

variable "kb_id" {
  type = string
}

variable "policy_lambda_arn" {
  type = string
}

variable "claims_lambda_arn" {
  type = string
}

variable "openapi_schema_s3_bucket" {
  type = string
}

variable "openapi_schema_s3_key" {
  type = string
}

variable "alias_name" {
  type    = string
  default = "live"
}

variable "client_api_lambda_role_name" {
  description = "Client API Lambda's IAM role name (from modules/iam) -- used to attach the supplemental InvokeAgent policy here (see main.tf note on avoiding an iam<->bedrock-agent cycle)."
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
