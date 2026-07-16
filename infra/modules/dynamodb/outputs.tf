output "policies_table_name" {
  value = aws_dynamodb_table.policies.name
}

output "policies_table_arn" {
  value = aws_dynamodb_table.policies.arn
}

output "policies_table_lastname_gsi_arn" {
  value = "${aws_dynamodb_table.policies.arn}/index/LastNameIndex"
}

output "claims_table_name" {
  value = aws_dynamodb_table.claims.name
}

output "claims_table_arn" {
  value = aws_dynamodb_table.claims.arn
}

output "claims_table_policyid_gsi_arn" {
  value = "${aws_dynamodb_table.claims.arn}/index/PolicyIdIndex"
}

output "claims_table_stream_arn" {
  value = aws_dynamodb_table.claims.stream_arn
}
