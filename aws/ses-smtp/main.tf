terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
  
  backend "s3" {
    bucket = "terraform-state-cloudterraform"
    key    = "ses-smtp.terraform.tfstate"
    region = "us-west-2"
  }
}

provider "aws" {
  region = local.region
}

# -------- Load config from YAML ----------
locals {
  config_file = fileexists("${path.module}/ses-smtp-config.yaml") ? yamldecode(file("${path.module}/ses-smtp-config.yaml")) : {}
}

# -------- Vars (override via -var or tfvars) ----------
variable "prefix"          { 
  default = null
  type = string
}
variable "region"          { 
  default = null
  type = string
}
variable "domain_name"     {
  description = "Domain name for SES"
  type        = string
  default = null
}
variable "mail_from_subdomain" { 
  description = "Subdomain for MAIL FROM (e.g., 'mail' for mail.example.com). Leave empty to use domain directly."
  default = null
  type = string
}
variable "create_smtp_user" {
  description = "Whether to create an IAM user for SMTP authentication"
  default = null
  type = bool
}
variable "smtp_username" {
  description = "Username for SMTP IAM user"
  default = null
  type = string
}

# -------- Computed values from YAML or variables ----------
locals {
  prefix                = coalesce(var.prefix, try(local.config_file.prefix, "ses-smtp"))
  region                = coalesce(var.region, try(local.config_file.region, "us-west-2"))
  domain_name           = coalesce(var.domain_name, try(local.config_file.domain_name, null))
  mail_from_subdomain   = var.mail_from_subdomain != null ? var.mail_from_subdomain : try(local.config_file.mail_from_subdomain, "")
  create_smtp_user      = coalesce(var.create_smtp_user, try(local.config_file.create_smtp_user, true))
  smtp_username         = coalesce(var.smtp_username, try(local.config_file.smtp_username, "ses-smtp-user"))
}

# ----------------- SES Domain Identity -----------------
resource "aws_ses_domain_identity" "domain" {
  domain = local.domain_name
}

resource "aws_ses_domain_dkim" "domain_dkim" {
  domain = aws_ses_domain_identity.domain.domain
}

resource "aws_ses_domain_mail_from" "mail_from" {
  domain                 = aws_ses_domain_identity.domain.domain
  mail_from_domain       = local.mail_from_subdomain != "" ? "${local.mail_from_subdomain}.${local.domain_name}" : local.domain_name
  behavior_on_mx_failure = "UseDefaultValue"
}

# ----------------- IAM User for SMTP -----------------
resource "aws_iam_user" "smtp_user" {
  count = local.create_smtp_user ? 1 : 0
  name  = "${local.prefix}-${local.smtp_username}"
  path  = "/"

  tags = {
    Name        = "${local.prefix}-smtp-user"
    Description = "IAM user for SES SMTP authentication"
  }
}

resource "aws_iam_access_key" "smtp_user" {
  count = local.create_smtp_user ? 1 : 0
  user  = aws_iam_user.smtp_user[0].name
}

data "aws_iam_policy_document" "ses_smtp_policy" {
  count = local.create_smtp_user ? 1 : 0

  statement {
    effect = "Allow"
    
    actions = [
      "ses:SendRawEmail",
      "ses:SendEmail"
    ]
    
    resources = [
      aws_ses_domain_identity.domain.arn
    ]
  }
}

resource "aws_iam_user_policy" "smtp_user_policy" {
  count  = local.create_smtp_user ? 1 : 0
  name   = "${local.prefix}-ses-smtp-policy"
  user   = aws_iam_user.smtp_user[0].name
  policy = data.aws_iam_policy_document.ses_smtp_policy[0].json
}

# No locals needed - AWS provider handles SES SMTP password generation

# --------------- Outputs ---------------
output "domain_identity_arn" { 
  value = aws_ses_domain_identity.domain.arn 
}

output "domain_verification_token" { 
  value = aws_ses_domain_identity.domain.verification_token 
}

output "dkim_tokens" { 
  value = aws_ses_domain_dkim.domain_dkim.dkim_tokens 
}

output "mail_from_domain" { 
  value = aws_ses_domain_mail_from.mail_from.mail_from_domain 
}

output "smtp_endpoint" { 
  value = "email-smtp.${local.region}.amazonaws.com" 
}

output "smtp_port" { 
  value = "587" 
  description = "SMTP port for TLS connection (also supports 25, 465)"
}

output "smtp_username" { 
  value = local.create_smtp_user ? aws_iam_access_key.smtp_user[0].id : null
  sensitive = false
}

output "smtp_password" { 
  value = local.create_smtp_user ? aws_iam_access_key.smtp_user[0].ses_smtp_password_v4 : null
  sensitive = true
  description = "SES SMTP password (AWS-generated)"
}

output "iam_user_arn" { 
  value = local.create_smtp_user ? aws_iam_user.smtp_user[0].arn : null 
}

# DNS Records needed (informational outputs)
output "dns_verification_record" {
  value = {
    name  = "_amazonses.${local.domain_name}"
    type  = "TXT"
    value = aws_ses_domain_identity.domain.verification_token
  }
  description = "DNS TXT record needed to verify domain ownership"
}

output "dkim_dns_records" {
  value = [
    for token in aws_ses_domain_dkim.domain_dkim.dkim_tokens : {
      name  = "${token}._domainkey.${local.domain_name}"
      type  = "CNAME"
      value = "${token}.dkim.amazonses.com"
    }
  ]
  description = "DNS CNAME records needed for DKIM signing"
}

output "mail_from_dns_records" {
  value = local.mail_from_subdomain != "" ? [
    {
      name  = aws_ses_domain_mail_from.mail_from.mail_from_domain
      type  = "MX"
      value = "10 feedback-smtp.${local.region}.amazonses.com"
    },
    {
      name  = aws_ses_domain_mail_from.mail_from.mail_from_domain
      type  = "TXT"
      value = "v=spf1 include:amazonses.com ~all"
    }
  ] : [
    {
      name  = local.domain_name
      type  = "TXT"
      value = "v=spf1 include:amazonses.com ~all"
    }
  ]
  description = "DNS records needed for MAIL FROM domain (MX record only needed for subdomain)"
}