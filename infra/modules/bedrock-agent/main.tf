# The highest blast-radius, most provider-version-sensitive resource in the
# stack. Two known terraform-provider-aws quirks shape the structure below:
#
# 1. Creating/changing multiple action groups against the same agent
#    concurrently can race the agent's implicit "Preparing" state
#    (terraform-provider-aws issues #42845, #39400). Fixed here by an
#    explicit depends_on chain that forces Terraform to apply the action
#    groups, KB association, and alias strictly one after another instead of
#    in parallel.
# 2. Associating a guardrail at agent-creation time has, in some provider
#    versions, needed a follow-up apply rather than working in one pass
#    (issue #39404). If `terraform apply` reports the guardrail wasn't
#    attached after the first run, re-running apply resolves it.
#
# Re-verify both against the pinned provider version before assuming this
# always applies in one pass.

resource "aws_bedrockagent_agent" "this" {
  agent_name                  = "${var.name_prefix}-autoclaim-agent"
  agent_resource_role_arn     = var.agent_role_arn
  foundation_model            = var.foundation_model_id
  instruction                 = var.instruction
  idle_session_ttl_in_seconds = var.idle_session_ttl_in_seconds
  description                 = "AutoClaim IQ: verifies policies, files/looks up claims, and answers coverage questions grounded in the knowledge base."
  prepare_agent               = true

  guardrail_configuration = [{
    guardrail_identifier = var.guardrail_id
    guardrail_version    = var.guardrail_version
  }]

  tags = var.tags
}

resource "aws_bedrockagent_agent_action_group" "policy" {
  action_group_name          = "PolicyActionGroup"
  agent_id                   = aws_bedrockagent_agent.this.agent_id
  agent_version              = "DRAFT"
  description                = "Verifies policyholder identity and retrieves active policy details."
  skip_resource_in_use_check = true
  prepare_agent              = true

  action_group_executor {
    lambda = var.policy_lambda_arn
  }

  function_schema {
    member_functions {
      functions {
        name        = "verifyAndRetrievePolicy"
        description = "Validates the customer's identity (policy number + last name) and retrieves active auto insurance policy details. Always call this before discussing policy specifics or filing a claim."

        parameters {
          map_block_key = "policyId"
          type          = "string"
          description   = "The unique policy number provided by the user, e.g. POL-998877."
          required      = true
        }
        parameters {
          map_block_key = "lastName"
          type          = "string"
          description   = "The last name of the primary policyholder, used for identity verification."
          required      = true
        }
      }
    }
  }
}

resource "aws_bedrockagent_agent_action_group" "claims" {
  action_group_name          = "ClaimsActionGroup"
  agent_id                   = aws_bedrockagent_agent.this.agent_id
  agent_version              = "DRAFT"
  description                = "Files new claims and looks up claim status. createClaim requires end-user confirmation (declared via x-requireConfirmation in the OpenAPI schema)."
  skip_resource_in_use_check = true
  prepare_agent              = true

  action_group_executor {
    lambda = var.claims_lambda_arn
  }

  api_schema {
    s3 {
      s3_bucket_name = var.openapi_schema_s3_bucket
      s3_object_key  = var.openapi_schema_s3_key
    }
  }

  depends_on = [aws_bedrockagent_agent_action_group.policy]
}

resource "aws_bedrockagent_agent_knowledge_base_association" "this" {
  agent_id             = aws_bedrockagent_agent.this.agent_id
  agent_version        = "DRAFT"
  knowledge_base_id    = var.kb_id
  knowledge_base_state = "ENABLED"
  description          = "Use this to answer coverage, deductible, and claims-process questions grounded in AutoClaim Co.'s official guidelines."

  depends_on = [aws_bedrockagent_agent_action_group.claims]
}

resource "aws_bedrockagent_agent_alias" "this" {
  agent_alias_name = var.alias_name
  agent_id         = aws_bedrockagent_agent.this.agent_id
  description      = "Stable alias the client API invokes -- pinned the same way a Lambda alias pins a version, rather than pointing clients at DRAFT."

  depends_on = [
    aws_bedrockagent_agent_action_group.policy,
    aws_bedrockagent_agent_action_group.claims,
    aws_bedrockagent_agent_knowledge_base_association.this,
  ]
}

# ---------------------------------------------------------------------------
# Supplemental IAM policy + resource-based Lambda permissions, attached here
# rather than in modules/iam.
#
# This module already depends on modules/iam for agent_role_arn (the
# agent's own execution role), so it's a one-directional dependency
# (bedrock-agent -> iam). If modules/iam also tried to grant the client-api
# Lambda's role permission to invoke THIS agent/alias, that would create a
# cycle (iam -> bedrock-agent -> iam). Attaching that policy here instead --
# where the real agent/alias ARNs are locally available as resource
# attributes -- avoids that cycle entirely.
# ---------------------------------------------------------------------------

resource "aws_iam_role_policy" "client_api_role_invoke_agent" {
  name = "${var.name_prefix}-client-api-role-invoke-agent"
  role = var.client_api_lambda_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "InvokeAgent"
        Effect   = "Allow"
        Action   = ["bedrock:InvokeAgent"]
        Resource = [aws_bedrockagent_agent.this.agent_arn, aws_bedrockagent_agent_alias.this.agent_alias_arn]
      }
    ]
  })
}

resource "aws_lambda_permission" "allow_agent_invoke_policy_lambda" {
  statement_id  = "AllowBedrockAgentInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.policy_lambda_arn
  principal     = "bedrock.amazonaws.com"
  source_arn    = aws_bedrockagent_agent.this.agent_arn
}

resource "aws_lambda_permission" "allow_agent_invoke_claims_lambda" {
  statement_id  = "AllowBedrockAgentInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.claims_lambda_arn
  principal     = "bedrock.amazonaws.com"
  source_arn    = aws_bedrockagent_agent.this.agent_arn
}
