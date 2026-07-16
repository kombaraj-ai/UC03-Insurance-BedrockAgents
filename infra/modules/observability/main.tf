# Cross-cutting observability: alarms + a dashboard that read every other
# module's outputs (Lambda function names, the API's id, the DynamoDB table
# names) without modifying any of them -- kept separate so alarm-threshold
# tuning never touches the resources being monitored.

resource "aws_sns_topic" "alarms" {
  name = "${var.name_prefix}-alarms"
  tags = var.tags
}

resource "aws_sns_topic_subscription" "alarm_email" {
  count     = var.alarm_email != null ? 1 : 0
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# ---------------------------------------------------------------------------
# Per-Lambda alarms: errors, throttles, and duration approaching timeout.
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  for_each = var.lambda_function_names

  alarm_name          = "${var.name_prefix}-${each.key}-errors"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = each.value }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "lambda_throttles" {
  for_each = var.lambda_function_names

  alarm_name          = "${var.name_prefix}-${each.key}-throttles"
  namespace           = "AWS/Lambda"
  metric_name         = "Throttles"
  dimensions          = { FunctionName = each.value }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  for_each = var.lambda_function_names

  alarm_name         = "${var.name_prefix}-${each.key}-duration-near-timeout"
  namespace          = "AWS/Lambda"
  metric_name        = "Duration"
  dimensions         = { FunctionName = each.value }
  extended_statistic = "p99"
  period             = 300
  evaluation_periods = 2
  # 80% of the function's configured timeout, converted to milliseconds.
  threshold           = var.lambda_timeout_seconds[each.key] * 1000 * 0.8
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]
  tags                = var.tags
}

# ---------------------------------------------------------------------------
# API Gateway (HTTP API): 4xx rate and 5xx count on the $default stage.
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "api_5xx" {
  alarm_name          = "${var.name_prefix}-api-5xx"
  namespace           = "AWS/ApiGateway"
  metric_name         = "5xx"
  dimensions          = { ApiId = var.api_id, Stage = "$default" }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "api_4xx_rate" {
  alarm_name          = "${var.name_prefix}-api-4xx-elevated"
  namespace           = "AWS/ApiGateway"
  metric_name         = "4xx"
  dimensions          = { ApiId = var.api_id, Stage = "$default" }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 2
  threshold           = 20
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]
  tags                = var.tags
}

# ---------------------------------------------------------------------------
# DynamoDB throttle alarms -- on-demand billing can still throttle under
# partition hot-spotting.
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "dynamodb_throttles" {
  for_each = var.dynamodb_table_names

  alarm_name          = "${var.name_prefix}-${each.key}-throttled-requests"
  namespace           = "AWS/DynamoDB"
  metric_name         = "ThrottledRequests"
  dimensions          = { TableName = each.value }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]
  tags                = var.tags
}

# ---------------------------------------------------------------------------
# At-a-glance dashboard across the full request path: API GW -> Client
# Lambda -> Bedrock Agent -> action-group Lambdas -> DynamoDB.
# ---------------------------------------------------------------------------
locals {
  lambda_widgets = [
    for key, function_name in var.lambda_function_names : {
      type   = "metric"
      width  = 12
      height = 6
      properties = {
        title   = "Lambda: ${key}"
        view    = "timeSeries"
        stacked = false
        region  = var.region
        metrics = [
          ["AWS/Lambda", "Invocations", "FunctionName", function_name, { stat = "Sum" }],
          ["AWS/Lambda", "Errors", "FunctionName", function_name, { stat = "Sum" }],
          ["AWS/Lambda", "Throttles", "FunctionName", function_name, { stat = "Sum" }],
          ["AWS/Lambda", "Duration", "FunctionName", function_name, { stat = "p99" }],
        ]
      }
    }
  ]

  api_widget = {
    type   = "metric"
    width  = 12
    height = 6
    properties = {
      title   = "API Gateway (${var.api_name})"
      view    = "timeSeries"
      stacked = false
      region  = var.region
      metrics = [
        ["AWS/ApiGateway", "Count", "ApiId", var.api_id, "Stage", "$default", { stat = "Sum" }],
        ["AWS/ApiGateway", "4xx", "ApiId", var.api_id, "Stage", "$default", { stat = "Sum" }],
        ["AWS/ApiGateway", "5xx", "ApiId", var.api_id, "Stage", "$default", { stat = "Sum" }],
        ["AWS/ApiGateway", "IntegrationLatency", "ApiId", var.api_id, "Stage", "$default", { stat = "p99" }],
      ]
    }
  }

  dynamodb_widget = {
    type   = "metric"
    width  = 12
    height = 6
    properties = {
      title   = "DynamoDB"
      view    = "timeSeries"
      stacked = false
      region  = var.region
      metrics = [
        for key, table_name in var.dynamodb_table_names :
        ["AWS/DynamoDB", "ThrottledRequests", "TableName", table_name, { stat = "Sum", label = key }]
      ]
    }
  }

  unpositioned_widgets = concat(local.lambda_widgets, [local.api_widget, local.dynamodb_widget])

  # CloudWatch dashboards require explicit x/y placement -- without it every
  # widget defaults to (0,0) and stacks on top of each other. Lay widgets out
  # two per row.
  dashboard_widgets = [
    for idx, widget in local.unpositioned_widgets : merge(widget, {
      x = (idx % 2) * widget.width
      y = floor(idx / 2) * widget.height
    })
  ]
}

resource "aws_cloudwatch_dashboard" "this" {
  dashboard_name = "${var.name_prefix}-overview"
  dashboard_body = jsonencode({ widgets = local.dashboard_widgets })
}
