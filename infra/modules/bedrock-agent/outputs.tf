output "agent_id" {
  value = aws_bedrockagent_agent.this.agent_id
}

output "agent_arn" {
  value = aws_bedrockagent_agent.this.agent_arn
}

output "agent_alias_id" {
  value = aws_bedrockagent_agent_alias.this.agent_alias_id
}

output "agent_alias_arn" {
  value = aws_bedrockagent_agent_alias.this.agent_alias_arn
}
