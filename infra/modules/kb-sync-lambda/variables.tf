variable "source_bucket_id" {
  description = "The KB source-docs bucket's id/name (from modules/s3-secure-bucket)."
  type        = string
}

variable "source_bucket_arn" {
  type = string
}

variable "sync_lambda_function_name" {
  description = "Function name of the already-created KB sync Lambda (from modules/lambda-function)."
  type        = string
}

variable "sync_lambda_function_arn" {
  type = string
}
