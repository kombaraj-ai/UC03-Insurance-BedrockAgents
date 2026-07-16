output "bedrock_agent_role_arn" {
  value = aws_iam_role.bedrock_agent.arn
}

output "bedrock_agent_role_name" {
  value = aws_iam_role.bedrock_agent.name
}

output "bedrock_kb_role_arn" {
  value = aws_iam_role.bedrock_kb.arn
}

output "bedrock_kb_role_name" {
  value = aws_iam_role.bedrock_kb.name
}

output "policy_lambda_role_arn" {
  value = aws_iam_role.policy_lambda.arn
}

output "claims_lambda_role_arn" {
  value = aws_iam_role.claims_lambda.arn
}

output "kb_sync_lambda_role_arn" {
  value = aws_iam_role.kb_sync_lambda.arn
}

output "kb_sync_lambda_role_name" {
  value = aws_iam_role.kb_sync_lambda.name
}

output "client_api_lambda_role_arn" {
  value = aws_iam_role.client_api_lambda.arn
}

output "client_api_lambda_role_name" {
  value = aws_iam_role.client_api_lambda.name
}
