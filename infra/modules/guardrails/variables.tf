variable "name_prefix" {
  type = string
}

variable "blocked_input_messaging" {
  type    = string
  default = "I can't help with that request. Let's get back to your policy or claim -- how can I help?"
}

variable "blocked_outputs_messaging" {
  type    = string
  default = "I'm not able to provide that kind of guidance. I'd recommend speaking with your claims adjuster or a licensed professional for that."
}

variable "content_filters" {
  description = "Bedrock content-policy filters. PROMPT_ATTACK only supports input filtering (output_strength must be NONE)."
  type = list(object({
    type            = string
    input_strength  = string
    output_strength = string
  }))
  default = [
    { type = "SEXUAL", input_strength = "HIGH", output_strength = "HIGH" },
    { type = "VIOLENCE", input_strength = "HIGH", output_strength = "HIGH" },
    { type = "HATE", input_strength = "HIGH", output_strength = "HIGH" },
    { type = "INSULTS", input_strength = "MEDIUM", output_strength = "MEDIUM" },
    { type = "MISCONDUCT", input_strength = "HIGH", output_strength = "HIGH" },
    { type = "PROMPT_ATTACK", input_strength = "HIGH", output_strength = "NONE" },
  ]
}

variable "pii_entities" {
  description = "PII entities relevant to an insurance workflow. High-sensitivity financial identifiers are blocked outright; lower-risk contact PII is anonymized so the conversation can still reference \"your policy on file\" without echoing the raw value."
  type = list(object({
    type   = string
    action = string
  }))
  default = [
    { type = "US_SOCIAL_SECURITY_NUMBER", action = "BLOCK" },
    { type = "CREDIT_DEBIT_CARD_NUMBER", action = "BLOCK" },
    { type = "CREDIT_DEBIT_CARD_CVV", action = "BLOCK" },
    { type = "US_BANK_ACCOUNT_NUMBER", action = "BLOCK" },
    { type = "DRIVER_ID", action = "ANONYMIZE" },
    { type = "EMAIL", action = "ANONYMIZE" },
    { type = "PHONE", action = "ANONYMIZE" },
    { type = "NAME", action = "ANONYMIZE" },
  ]
}

variable "denied_topics" {
  description = "Topics AutoClaim IQ should decline to engage with -- a first draft pending legal/compliance review, not a finalized policy."
  type = list(object({
    name       = string
    definition = string
    examples   = list(string)
  }))
  default = [
    {
      name       = "Legal Advice"
      definition = "Providing legal opinions, interpreting liability or fault, or advising on litigation strategy."
      examples   = ["Am I legally liable for this accident?", "Should I sue the other driver?"]
    },
    {
      name       = "Medical Advice"
      definition = "Diagnosing injuries or recommending medical treatment."
      examples   = ["Is my neck injury whiplash?", "What medication should I take for my injury?"]
    },
    {
      name       = "Competitor Comparison"
      definition = "Comparing this insurer's rates or products to named competitors, or disparaging competitors."
      examples   = ["Is Geico cheaper than you?", "Why is Progressive better?"]
    },
    {
      name       = "Financial or Investment Advice"
      definition = "Giving financial planning or investment advice unrelated to auto insurance coverage."
      examples   = ["Should I invest my claim payout in stocks?"]
    },
  ]
}

variable "tags" {
  type    = map(string)
  default = {}
}
