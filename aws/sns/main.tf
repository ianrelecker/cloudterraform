terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }

  backend "s3" {
    bucket = "terraform-state-cloudterraform"
    key    = "sns.terraform.tfstate"
    region = "us-west-2"
  }
}

########################################
# Provider
########################################
provider "aws" {
  region = local.region
}

########################################
# Config loading (YAML is optional)
########################################
locals {
  config_file = fileexists("${path.module}/sns-config.yaml") ? yamldecode(file("${path.module}/sns-config.yaml")) : {}
}

########################################
# Variables (optional overrides)
########################################
variable "prefix" {
  type    = string
  default = null
}

variable "region" {
  type    = string
  default = null
}

variable "topic_name" {
  type    = string
  default = null
}

variable "phone_number" {
  type    = string
  default = null
}

variable "create_iam_user" {
  type    = bool
  default = null
}

variable "iam_username" {
  type    = string
  default = null
}

variable "default_sms_type" { # "Transactional" or "Promotional"
  type    = string
  default = null
}

variable "monthly_spend_limit" { # USD as string, e.g., "5"
  type    = string
  default = null
}

variable "default_sender_id" {
  type    = string
  default = null
}

variable "usage_report_s3_bucket" {
  type    = string
  default = null
}

########################################
# Derived locals from YAML or variables
########################################
locals {
  prefix                 = coalesce(var.prefix,                 try(local.config_file.prefix,                 "sns"))
  region                 = coalesce(var.region,                 try(local.config_file.region,                 "us-west-2"))
  topic_name             = coalesce(var.topic_name,             try(local.config_file.topic_name,             "${local.prefix}-grafana-alerts"))
  phone_number           = coalesce(var.phone_number,           try(local.config_file.phone_number,           null))
  create_iam_user        = coalesce(var.create_iam_user,        try(local.config_file.create_iam_user,        true))
  iam_username           = coalesce(var.iam_username,           try(local.config_file.iam_username,           "grafana-sns-user"))
  default_sms_type = (
    var.default_sms_type != null && var.default_sms_type != ""
  ) ? var.default_sms_type : try(local.config_file.default_sms_type, null)

  monthly_spend_limit = (
    var.monthly_spend_limit != null && var.monthly_spend_limit != ""
  ) ? var.monthly_spend_limit : try(local.config_file.monthly_spend_limit, null)

  default_sender_id = (
    var.default_sender_id != null && var.default_sender_id != ""
  ) ? var.default_sender_id : try(local.config_file.default_sender_id, null)

  usage_report_s3_bucket = (
    var.usage_report_s3_bucket != null && var.usage_report_s3_bucket != ""
  ) ? var.usage_report_s3_bucket : try(local.config_file.usage_report_s3_bucket, null)

  enable_sms_prefs = (
    local.default_sms_type != null ||
    local.monthly_spend_limit != null ||
    local.default_sender_id != null ||
    local.usage_report_s3_bucket != null
  )
}

########################################
# SNS Topic for Grafana Alerts
########################################
resource "aws_sns_topic" "grafana_alerts" {
  name = local.topic_name

  tags = {
    Name        = local.topic_name
    Description = "Grafana alert notifications topic"
  }
}

########################################
# SMS Subscription (to your phone)
########################################
resource "aws_sns_topic_subscription" "sms" {
  count     = local.phone_number != null && local.phone_number != "" ? 1 : 0
  topic_arn = aws_sns_topic.grafana_alerts.arn
  protocol  = "sms"
  endpoint  = local.phone_number # E.164 format, e.g., +15551234567
}

########################################
# Optional: Account-level SMS preferences
########################################
resource "aws_sns_sms_preferences" "this" {
  count = local.enable_sms_prefs ? 1 : 0

  # Any null values are ignored by the provider
  default_sms_type       = local.default_sms_type
  monthly_spend_limit    = local.monthly_spend_limit
  default_sender_id      = local.default_sender_id
  usage_report_s3_bucket = local.usage_report_s3_bucket
}

########################################
# IAM user with publish-only access for Grafana
########################################
resource "aws_iam_user" "grafana_sns_user" {
  count = local.create_iam_user ? 1 : 0
  name  = "${local.prefix}-${local.iam_username}"
  path  = "/"

  tags = {
    Name        = "${local.prefix}-${local.iam_username}"
    Description = "Publish-only IAM user for Grafana to SNS"
  }
}

resource "aws_iam_access_key" "grafana_sns_user" {
  count = local.create_iam_user ? 1 : 0
  user  = aws_iam_user.grafana_sns_user[0].name
}

data "aws_iam_policy_document" "publish_to_topic" {
  count = local.create_iam_user ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "sns:Publish"
    ]
    resources = [
      aws_sns_topic.grafana_alerts.arn
    ]
  }
}

resource "aws_iam_user_policy" "grafana_sns_publish" {
  count  = local.create_iam_user ? 1 : 0
  name   = "${local.prefix}-sns-publish-${aws_sns_topic.grafana_alerts.name}"
  user   = aws_iam_user.grafana_sns_user[0].name
  policy = data.aws_iam_policy_document.publish_to_topic[0].json
}

########################################
# Outputs
########################################
output "sns_topic_name" {
  value = aws_sns_topic.grafana_alerts.name
}

output "sns_topic_arn" {
  value = aws_sns_topic.grafana_alerts.arn
}

output "sms_subscription_endpoint" {
  value = local.phone_number
}

output "iam_user_arn" {
  value = local.create_iam_user ? aws_iam_user.grafana_sns_user[0].arn : null
}

output "access_key_id" {
  value     = local.create_iam_user ? aws_iam_access_key.grafana_sns_user[0].id : null
  sensitive = false
}

output "secret_access_key" {
  value     = local.create_iam_user ? aws_iam_access_key.grafana_sns_user[0].secret : null
  sensitive = true
}

output "grafana_contact_point_hint" {
  value = {
    type              = "Amazon SNS"
    region            = local.region
    topic_arn         = aws_sns_topic.grafana_alerts.arn
    access_key_id     = local.create_iam_user ? aws_iam_access_key.grafana_sns_user[0].id : null
    secret_access_key = local.create_iam_user ? aws_iam_access_key.grafana_sns_user[0].secret : null
  }
  sensitive = true
  description = "Values to configure Grafana's Amazon SNS contact point"
}
