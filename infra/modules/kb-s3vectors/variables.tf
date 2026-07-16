variable "name_prefix" {
  type = string
}

variable "account_id" {
  description = "Used to build a globally-unique S3 Vectors bucket name."
  type        = string
}

variable "kb_role_arn" {
  description = "IAM role ARN the Knowledge Base assumes (from modules/iam)."
  type        = string
}

variable "kb_role_name" {
  description = "Same role as kb_role_arn, by name -- used to attach the supplemental s3vectors access policy here (see main.tf note on avoiding an iam<->kb-s3vectors cycle)."
  type        = string
}

variable "bedrock_agent_role_name" {
  description = "Bedrock agent's IAM role name (from modules/iam) -- used to attach the supplemental KB-retrieve policy here."
  type        = string
}

variable "kb_sync_lambda_role_name" {
  description = "KB sync Lambda's IAM role name (from modules/iam) -- used to attach the supplemental StartIngestionJob policy here."
  type        = string
}

variable "kb_source_bucket_arn" {
  description = "ARN of the S3 bucket holding raw source documents (from modules/s3-secure-bucket)."
  type        = string
}

variable "embedding_model_arn" {
  description = "Bedrock embedding model ARN, e.g. amazon.titan-embed-text-v2:0. Verify current model ID/ARN in the target region before applying."
  type        = string
}

variable "vector_dimension" {
  description = "Embedding vector dimension. Titan Text Embeddings V2 supports 256/512/1024."
  type        = number
  default     = 1024
}

variable "distance_metric" {
  type    = string
  default = "cosine"
}

variable "chunking_max_tokens" {
  type    = number
  default = 300
}

variable "chunking_overlap_percentage" {
  type    = number
  default = 20
}

variable "tags" {
  type    = map(string)
  default = {}
}
