data "aws_caller_identity" "current" {}

locals {
  name_prefix = "autoclaim-iq-${var.environment}"
  account_id  = data.aws_caller_identity.current.account_id

  common_tags = {
    Project     = "autoclaim-iq"
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  # Predictable Lambda function names -- passed to modules/iam as plain
  # strings (not module output references) so the iam module can construct
  # their ARNs via string interpolation without depending on the
  # lambda-function module resources themselves. See
  # infra/modules/iam/variables.tf for why this matters.
  policy_lambda_function_name     = "${local.name_prefix}-policy-handler"
  claims_lambda_function_name     = "${local.name_prefix}-claims-handler"
  kb_sync_lambda_function_name    = "${local.name_prefix}-kb-sync-handler"
  client_api_lambda_function_name = "${local.name_prefix}-client-api-handler"

  embedding_model_arn = "arn:aws:bedrock:${var.aws_region}::foundation-model/${var.embedding_model_id}"

  # Foundation model invoke permissions. If foundation_model_id looks like a
  # cross-region inference profile (prefixed "us."/"eu."/"apac."/"global."),
  # grant both the inference-profile ARN and a same-family foundation-model
  # wildcard (inference profiles route to underlying regional models) --
  # verify this exact ARN shape against current Bedrock IAM docs at apply
  # time, cross-region inference profile ARNs are a newer surface.
  is_inference_profile = can(regex("^(us|eu|apac|global)\\.", var.foundation_model_id))
  # Strip the region-routing prefix (e.g. "us.") to get the underlying
  # model ID the profile routes to, e.g.
  # "us.anthropic.claude-sonnet-4-5-20250929-v1:0" -> "anthropic.claude-sonnet-4-5-20250929-v1:0".
  inference_profile_model_id = trimprefix(var.foundation_model_id, "${split(".", var.foundation_model_id)[0]}.")

  model_invoke_arns = local.is_inference_profile ? [
    "arn:aws:bedrock:${var.aws_region}:${local.account_id}:inference-profile/${var.foundation_model_id}",
    "arn:aws:bedrock:*::foundation-model/${local.inference_profile_model_id}",
    ] : [
    "arn:aws:bedrock:${var.aws_region}::foundation-model/${var.foundation_model_id}",
  ]
}

# ==========================================
# Cross-cutting: encryption + data layer
# ==========================================
module "kms" {
  source = "../../modules/kms"

  name        = "${local.name_prefix}-logs"
  description = "CMK for CloudWatch Logs across AutoClaim IQ (${var.environment})."
  account_id  = local.account_id
  region      = var.aws_region
  tags        = local.common_tags
}

module "dynamodb" {
  source = "../../modules/dynamodb"

  name_prefix = local.name_prefix
  tags        = local.common_tags
}

# ==========================================
# S3: OpenAPI schema bucket + KB source-docs bucket
# ==========================================
module "schema_bucket" {
  source = "../../modules/s3-secure-bucket"

  bucket_name = "${local.name_prefix}-assets-${local.account_id}"
  tags        = local.common_tags
}

resource "aws_s3_object" "openapi_schema" {
  bucket = module.schema_bucket.bucket_name
  key    = "schemas/claims-openapi.yaml"
  source = "${path.root}/../../../schemas/claims-openapi.yaml"
  etag   = filemd5("${path.root}/../../../schemas/claims-openapi.yaml")
}

module "kb_docs_bucket" {
  source = "../../modules/s3-secure-bucket"

  bucket_name = "${local.name_prefix}-kb-docs-${local.account_id}"
  tags        = local.common_tags
}

# ==========================================
# Guardrails
# ==========================================
module "guardrails" {
  source = "../../modules/guardrails"

  name_prefix = local.name_prefix
  tags        = local.common_tags
}

# ==========================================
# IAM (central role definitions -- see module for why some permissions on
# non-predictable-ID resources are attached in the owning module instead)
# ==========================================
module "iam" {
  source = "../../modules/iam"

  name_prefix = local.name_prefix
  account_id  = local.account_id
  region      = var.aws_region
  tags        = local.common_tags

  policy_lambda_function_name     = local.policy_lambda_function_name
  claims_lambda_function_name     = local.claims_lambda_function_name
  kb_sync_lambda_function_name    = local.kb_sync_lambda_function_name
  client_api_lambda_function_name = local.client_api_lambda_function_name

  model_invoke_arns      = local.model_invoke_arns
  kb_embedding_model_arn = local.embedding_model_arn
  kb_source_bucket_arn   = module.kb_docs_bucket.bucket_arn
  guardrail_arn          = module.guardrails.guardrail_arn

  policies_table_arn              = module.dynamodb.policies_table_arn
  policies_table_lastname_gsi_arn = module.dynamodb.policies_table_lastname_gsi_arn
  claims_table_arn                = module.dynamodb.claims_table_arn
  claims_table_policyid_gsi_arn   = module.dynamodb.claims_table_policyid_gsi_arn

  kms_log_key_arn = module.kms.key_arn
}

# ==========================================
# Action-group Lambdas (Policy, Claims)
# ==========================================
module "policy_lambda" {
  source = "../../modules/lambda-function"

  function_name = local.policy_lambda_function_name
  description   = "Bedrock Action Group Lambda: verifies policyholder identity (Function schema)."
  source_dir    = "${path.root}/../../../services/policy_handler/src"
  role_arn      = module.iam.policy_lambda_role_arn

  environment_variables = {
    POLICIES_TABLE_NAME = module.dynamodb.policies_table_name
    LOG_LEVEL           = "INFO"
  }

  log_kms_key_arn    = module.kms.key_arn
  log_retention_days = var.log_retention_days
  tags               = local.common_tags
}

module "claims_lambda" {
  source = "../../modules/lambda-function"

  function_name = local.claims_lambda_function_name
  description   = "Bedrock Action Group Lambda: files/looks up claims (OpenAPI schema)."
  source_dir    = "${path.root}/../../../services/claims_handler/src"
  role_arn      = module.iam.claims_lambda_role_arn

  environment_variables = {
    CLAIMS_TABLE_NAME   = module.dynamodb.claims_table_name
    POLICIES_TABLE_NAME = module.dynamodb.policies_table_name
    LOG_LEVEL           = "INFO"
  }

  log_kms_key_arn    = module.kms.key_arn
  log_retention_days = var.log_retention_days
  tags               = local.common_tags
}

# ==========================================
# Knowledge Base (S3 Vectors) + auto-sync pipeline
# ==========================================
module "kb" {
  source = "../../modules/kb-s3vectors"

  name_prefix = local.name_prefix
  account_id  = local.account_id

  kb_role_arn              = module.iam.bedrock_kb_role_arn
  kb_role_name             = module.iam.bedrock_kb_role_name
  bedrock_agent_role_name  = module.iam.bedrock_agent_role_name
  kb_sync_lambda_role_name = module.iam.kb_sync_lambda_role_name

  kb_source_bucket_arn = module.kb_docs_bucket.bucket_arn
  embedding_model_arn  = local.embedding_model_arn
  vector_dimension     = var.vector_dimension

  tags = local.common_tags
}

module "kb_sync_lambda" {
  source = "../../modules/lambda-function"

  function_name = local.kb_sync_lambda_function_name
  description   = "S3 event -> Bedrock Knowledge Base ingestion trigger (auto-sync, no manual Sync click)."
  source_dir    = "${path.root}/../../../services/kb_sync_handler/src"
  role_arn      = module.iam.kb_sync_lambda_role_arn
  timeout       = 60

  environment_variables = {
    KNOWLEDGE_BASE_ID = module.kb.knowledge_base_id
    DATA_SOURCE_ID    = module.kb.data_source_id
    LOG_LEVEL         = "INFO"
  }

  log_kms_key_arn    = module.kms.key_arn
  log_retention_days = var.log_retention_days
  tags               = local.common_tags
}

module "kb_sync_wiring" {
  source = "../../modules/kb-sync-lambda"

  source_bucket_id  = module.kb_docs_bucket.bucket_id
  source_bucket_arn = module.kb_docs_bucket.bucket_arn

  sync_lambda_function_name = module.kb_sync_lambda.function_name
  sync_lambda_function_arn  = module.kb_sync_lambda.function_arn
}

# ==========================================
# Bedrock Agent (agent, both action groups, KB association, alias)
# ==========================================
module "bedrock_agent" {
  source = "../../modules/bedrock-agent"

  name_prefix    = local.name_prefix
  agent_role_arn = module.iam.bedrock_agent_role_arn

  foundation_model_id = var.foundation_model_id

  guardrail_id      = module.guardrails.guardrail_id
  guardrail_version = module.guardrails.guardrail_version

  kb_id = module.kb.knowledge_base_id

  policy_lambda_arn = module.policy_lambda.function_arn
  claims_lambda_arn = module.claims_lambda.function_arn

  openapi_schema_s3_bucket = module.schema_bucket.bucket_name
  openapi_schema_s3_key    = aws_s3_object.openapi_schema.key

  client_api_lambda_role_name = module.iam.client_api_lambda_role_name

  tags = local.common_tags
}

# ==========================================
# Cognito + API Gateway + Client API Lambda
# ==========================================
module "cognito" {
  source = "../../modules/cognito"

  name_prefix       = local.name_prefix
  callback_urls     = var.cognito_callback_urls
  mfa_configuration = var.mfa_configuration
  tags              = local.common_tags
}

module "client_api_lambda" {
  source = "../../modules/lambda-function"

  function_name = local.client_api_lambda_function_name
  description   = "Public API entry point: authenticated HTTP -> bedrock-agent-runtime:InvokeAgent."
  source_dir    = "${path.root}/../../../services/client_api_handler/src"
  role_arn      = module.iam.client_api_lambda_role_arn
  timeout       = 60

  environment_variables = {
    AGENT_ID       = module.bedrock_agent.agent_id
    AGENT_ALIAS_ID = module.bedrock_agent.agent_alias_id
    LOG_LEVEL      = "INFO"
  }

  log_kms_key_arn    = module.kms.key_arn
  log_retention_days = var.log_retention_days
  tags               = local.common_tags
}

module "api_gateway" {
  source = "../../modules/api-gateway"

  name_prefix          = local.name_prefix
  cors_allowed_origins = var.cors_allowed_origins

  cognito_user_pool_issuer    = module.cognito.issuer_url
  cognito_user_pool_client_id = module.cognito.user_pool_client_id

  client_api_lambda_invoke_arn    = module.client_api_lambda.invoke_arn
  client_api_lambda_function_name = module.client_api_lambda.function_name

  log_kms_key_arn    = module.kms.key_arn
  log_retention_days = var.log_retention_days
  tags               = local.common_tags
}

# ==========================================
# Observability
# ==========================================
module "observability" {
  source = "../../modules/observability"

  name_prefix = local.name_prefix
  region      = var.aws_region
  alarm_email = var.alarm_email

  lambda_function_names = {
    policy_handler     = module.policy_lambda.function_name
    claims_handler     = module.claims_lambda.function_name
    kb_sync_handler    = module.kb_sync_lambda.function_name
    client_api_handler = module.client_api_lambda.function_name
  }

  lambda_timeout_seconds = {
    policy_handler     = 30
    claims_handler     = 30
    kb_sync_handler    = 60
    client_api_handler = 60
  }

  api_id   = module.api_gateway.api_id
  api_name = "${local.name_prefix}-api"

  dynamodb_table_names = {
    policies = module.dynamodb.policies_table_name
    claims   = module.dynamodb.claims_table_name
  }

  tags = local.common_tags
}
