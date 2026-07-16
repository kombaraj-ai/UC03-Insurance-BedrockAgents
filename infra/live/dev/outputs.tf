output "api_endpoint" {
  description = "Public HTTPS endpoint. POST {api_endpoint}chat with a Cognito bearer token."
  value       = module.api_gateway.api_endpoint
}

output "cognito_user_pool_id" {
  value = module.cognito.user_pool_id
}

output "cognito_user_pool_client_id" {
  value = module.cognito.user_pool_client_id
}

output "agent_id" {
  value = module.bedrock_agent.agent_id
}

output "agent_alias_id" {
  value = module.bedrock_agent.agent_alias_id
}

output "knowledge_base_id" {
  value = module.kb.knowledge_base_id
}

output "kb_source_bucket_name" {
  description = "Upload documents here (knowledge-base/upload_seed_docs.sh) to trigger auto-sync ingestion."
  value       = module.kb_docs_bucket.bucket_name
}

output "policies_table_name" {
  value = module.dynamodb.policies_table_name
}

output "claims_table_name" {
  value = module.dynamodb.claims_table_name
}

output "observability_dashboard_name" {
  value = module.observability.dashboard_name
}
