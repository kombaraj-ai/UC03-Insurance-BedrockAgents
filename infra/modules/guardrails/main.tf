# Guardrail content (denied topics, PII entities, content filter strengths)
# changes on a compliance/legal review cadence independent of the rest of
# the infra -- kept in its own module so that cadence doesn't get tangled up
# with agent/Lambda changes. This is a first-draft policy (see variable
# descriptions and docs/decision-log.md); it needs legal review before a
# real production launch, particularly the denied-topic list, which touches
# state-specific unauthorized-practice-of-law rules.

resource "aws_bedrock_guardrail" "this" {
  name                      = "${var.name_prefix}-guardrail"
  description               = "AutoClaim IQ safety guardrail: content filters, PII handling, denied topics."
  blocked_input_messaging   = var.blocked_input_messaging
  blocked_outputs_messaging = var.blocked_outputs_messaging

  content_policy_config {
    dynamic "filters_config" {
      for_each = var.content_filters
      content {
        type            = filters_config.value.type
        input_strength  = filters_config.value.input_strength
        output_strength = filters_config.value.output_strength
      }
    }
  }

  sensitive_information_policy_config {
    dynamic "pii_entities_config" {
      for_each = var.pii_entities
      content {
        type   = pii_entities_config.value.type
        action = pii_entities_config.value.action
      }
    }
  }

  topic_policy_config {
    dynamic "topics_config" {
      for_each = var.denied_topics
      content {
        name       = topics_config.value.name
        definition = topics_config.value.definition
        examples   = topics_config.value.examples
        type       = "DENY"
      }
    }
  }

  tags = var.tags
}

# Published, immutable version: the agent should pin to a stable version
# rather than DRAFT, the same way it pins a Lambda alias rather than $LATEST.
resource "aws_bedrock_guardrail_version" "this" {
  guardrail_arn = aws_bedrock_guardrail.this.guardrail_arn
  description   = "Initial production version"
}
