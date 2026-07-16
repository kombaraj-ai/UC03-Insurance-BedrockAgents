output "knowledge_base_id" {
  value = aws_bedrockagent_knowledge_base.this.id
}

output "knowledge_base_arn" {
  value = aws_bedrockagent_knowledge_base.this.arn
}

output "data_source_id" {
  value = aws_bedrockagent_data_source.s3_docs.data_source_id
}

output "vector_bucket_arn" {
  value = aws_s3vectors_vector_bucket.kb.vector_bucket_arn
}

output "vector_index_arn" {
  value = aws_s3vectors_index.kb.index_arn
}
