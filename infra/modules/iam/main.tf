locals {
  policy_lambda_arn     = "arn:aws:lambda:${var.region}:${var.account_id}:function:${var.policy_lambda_function_name}"
  claims_lambda_arn     = "arn:aws:lambda:${var.region}:${var.account_id}:function:${var.claims_lambda_function_name}"
  kb_sync_lambda_arn    = "arn:aws:lambda:${var.region}:${var.account_id}:function:${var.kb_sync_lambda_function_name}"
  client_api_lambda_arn = "arn:aws:lambda:${var.region}:${var.account_id}:function:${var.client_api_lambda_function_name}"

  policy_log_group_arn     = "arn:aws:logs:${var.region}:${var.account_id}:log-group:/aws/lambda/${var.policy_lambda_function_name}:*"
  claims_log_group_arn     = "arn:aws:logs:${var.region}:${var.account_id}:log-group:/aws/lambda/${var.claims_lambda_function_name}:*"
  kb_sync_log_group_arn    = "arn:aws:logs:${var.region}:${var.account_id}:log-group:/aws/lambda/${var.kb_sync_lambda_function_name}:*"
  client_api_log_group_arn = "arn:aws:logs:${var.region}:${var.account_id}:log-group:/aws/lambda/${var.client_api_lambda_function_name}:*"
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}
