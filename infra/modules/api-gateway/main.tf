# Public entry point: HTTP API + Cognito JWT authorizer. Every route
# requires the authorizer -- there is no open/anonymous route anywhere,
# unlike the reference design's Lambda Function URL with
# authorization_type = "NONE".

resource "aws_apigatewayv2_api" "this" {
  name          = "${var.name_prefix}-api"
  protocol_type = "HTTP"
  description   = "AutoClaim IQ public API -- authenticated access to the Bedrock Agent."

  cors_configuration {
    allow_credentials = true
    allow_origins     = var.cors_allowed_origins
    allow_methods     = ["POST"]
    allow_headers     = ["content-type", "authorization"]
    max_age           = 300
  }

  tags = var.tags
}

resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id           = aws_apigatewayv2_api.this.id
  name             = "${var.name_prefix}-cognito-jwt"
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]

  jwt_configuration {
    audience = [var.cognito_user_pool_client_id]
    issuer   = var.cognito_user_pool_issuer
  }
}

resource "aws_apigatewayv2_integration" "client_api" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.client_api_lambda_invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
  timeout_milliseconds   = 29000
}

resource "aws_apigatewayv2_route" "chat" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "POST /chat"
  target             = "integrations/${aws_apigatewayv2_integration.client_api.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_cloudwatch_log_group" "access_logs" {
  name              = "/aws/apigateway/${var.name_prefix}-api"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.log_kms_key_arn

  tags = var.tags
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_burst_limit   = var.throttling_burst_limit
    throttling_rate_limit    = var.throttling_rate_limit
    logging_level            = "INFO"
    detailed_metrics_enabled = true
  }

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.access_logs.arn
    format = jsonencode({
      requestId          = "$context.requestId"
      ip                 = "$context.identity.sourceIp"
      requestTime        = "$context.requestTime"
      routeKey           = "$context.routeKey"
      status             = "$context.status"
      integrationLatency = "$context.integrationLatency"
      # The verified Cognito `sub` claim is logged for audit purposes.
      # Never log the raw Authorization header/JWT itself.
      userSub = "$context.authorizer.claims.sub"
    })
  }

  tags = var.tags
}

resource "aws_lambda_permission" "allow_apigateway_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.client_api_lambda_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}
