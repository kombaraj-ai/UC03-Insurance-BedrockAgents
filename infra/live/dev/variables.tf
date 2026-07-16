variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "foundation_model_id" {
  description = <<-EOT
    Bedrock model ID or cross-region inference profile ID for the agent,
    e.g. "us.anthropic.claude-sonnet-4-5-20250929-v1:0". Verify against the
    current Bedrock model catalog for var.aws_region before applying --
    model availability and IDs are region-specific and change over time.
  EOT
  type        = string
}

variable "embedding_model_id" {
  description = "Bedrock embedding model ID used by the Knowledge Base."
  type        = string
  default     = "amazon.titan-embed-text-v2:0"
}

variable "vector_dimension" {
  description = "Must match the embedding model's supported output dimension (Titan Text Embeddings V2 supports 256/512/1024)."
  type        = number
  default     = 1024
}

variable "alarm_email" {
  description = "Email subscribed to the CloudWatch alarm SNS topic. Leave null to skip."
  type        = string
  default     = null
}

variable "cors_allowed_origins" {
  description = "Exact frontend origin(s) allowed to call the API. Replace the default before deploying a real frontend."
  type        = list(string)
  default     = ["http://localhost:3000"]
}

variable "cognito_callback_urls" {
  description = "Exact OAuth callback URL(s) for the Cognito app client."
  type        = list(string)
  default     = ["http://localhost:3000/callback"]
}

variable "mfa_configuration" {
  type    = string
  default = "OPTIONAL"
}

variable "log_retention_days" {
  type    = number
  default = 90
}
