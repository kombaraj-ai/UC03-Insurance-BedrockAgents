# Reusable Lambda baseline shared by all 4 functions in this stack (policy
# handler, claims handler, KB sync handler, client API handler). Each call
# site still supplies its own least-privilege IAM role (built in
# modules/iam) -- this module only standardizes packaging, logging,
# encryption, tracing, and retry/DLQ configuration so those concerns can't
# silently drift between functions.

data "archive_file" "this" {
  type        = "zip"
  source_dir  = var.source_dir
  output_path = "${path.module}/.build/${var.function_name}.zip"
}

# Created explicitly, ahead of the function, so the log group is
# KMS-encrypted with an explicit retention period from day one -- Lambda's
# auto-created log groups are unencrypted with no expiry.
resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.log_kms_key_arn

  tags = var.tags
}

resource "aws_lambda_function" "this" {
  function_name = var.function_name
  description   = var.description
  role          = var.role_arn
  handler       = var.handler
  runtime       = var.runtime
  memory_size   = var.memory_size
  timeout       = var.timeout

  filename         = data.archive_file.this.output_path
  source_code_hash = data.archive_file.this.output_base64sha256

  reserved_concurrent_executions = var.reserved_concurrent_executions

  environment {
    variables = var.environment_variables
  }

  tracing_config {
    mode = var.tracing_mode
  }

  dynamic "dead_letter_config" {
    for_each = var.dead_letter_target_arn != null ? [1] : []
    content {
      target_arn = var.dead_letter_target_arn
    }
  }

  depends_on = [aws_cloudwatch_log_group.this]

  tags = var.tags
}

resource "aws_lambda_function_event_invoke_config" "this" {
  function_name          = aws_lambda_function.this.function_name
  maximum_retry_attempts = var.maximum_retry_attempts
}
