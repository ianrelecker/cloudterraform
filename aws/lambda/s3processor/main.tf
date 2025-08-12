terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }

  backend "s3" {
    bucket = "terraform-state-cloudterraform"
    key    = "pdf-processor.terraform.tfstate"
    region = "us-west-2"
  }
}

provider "aws" {
  region = local.region
}

# -------- Load YAML Configuration --------
locals {
  config = yamldecode(file("${path.module}/s3processor-config.yaml"))
}

# -------- Variables (override via -var or tfvars) --------
variable "prefix" { default = null }
variable "region" { default = null }
variable "bucket_name" { default = null }
variable "lambda_function_name" { default = null }
variable "compression_quality" { default = null }
variable "max_width" { default = null }
variable "max_height" { default = null }

# Use YAML config as defaults, allow variable overrides
locals {
  prefix               = var.prefix != null ? var.prefix : local.config.prefix
  region               = var.region != null ? var.region : local.config.region
  bucket_name          = var.bucket_name != null ? var.bucket_name : local.config.bucket_name
  lambda_function_name = var.lambda_function_name != null ? var.lambda_function_name : local.config.lambda_function_name
  compression_quality  = var.compression_quality != null ? var.compression_quality : local.config.compression_quality
  max_width            = var.max_width != null ? var.max_width : local.config.max_width
  max_height           = var.max_height != null ? var.max_height : local.config.max_height
}

# -------- Data Sources --------
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# -------- S3 Bucket for PDF Upload/Processing --------
resource "aws_s3_bucket" "pdf_bucket" {
  bucket = local.bucket_name

  tags = {
    Name        = "${local.prefix}-bucket"
    Environment = "production"
  }
}

resource "aws_s3_bucket_versioning" "pdf_bucket_versioning" {
  bucket = aws_s3_bucket.pdf_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "pdf_bucket_encryption" {
  bucket = aws_s3_bucket.pdf_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_cors_configuration" "pdf_bucket_cors" {
  bucket = aws_s3_bucket.pdf_bucket.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "POST", "PUT", "DELETE", "HEAD"]
    allowed_origins = local.config.cors_allowed_origins
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

resource "aws_s3_bucket_public_access_block" "pdf_bucket_pab" {
  bucket = aws_s3_bucket.pdf_bucket.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "pdf_bucket_policy" {
  bucket     = aws_s3_bucket.pdf_bucket.id
  depends_on = [aws_s3_bucket_public_access_block.pdf_bucket_pab]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowPublicUploads"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.pdf_bucket.arn}/${local.config.upload_folder}*"
      }
    ]
  })
}

# -------- Cleanup Lambda Function --------
data "archive_file" "cleanup_lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/src/cleanup_lambda.py"
  output_path = "${path.module}/cleanup_lambda.zip"
}

resource "aws_lambda_function" "cleanup_function" {
  filename         = data.archive_file.cleanup_lambda_zip.output_path
  function_name    = "${local.lambda_function_name}-cleanup"
  role             = aws_iam_role.lambda_role.arn
  handler          = "cleanup_lambda.lambda_handler"
  source_code_hash = data.archive_file.cleanup_lambda_zip.output_base64sha256
  runtime          = local.config.lambda_runtime
  timeout          = 60

  environment {
    variables = {
      S3_BUCKET_NAME     = aws_s3_bucket.pdf_bucket.bucket
      AUTO_CLEANUP_HOURS = local.config.auto_cleanup_hours
      UPLOAD_FOLDER      = local.config.upload_folder
      PROCESSED_FOLDER   = local.config.processed_folder
    }
  }

  tags = {
    Name = "${local.prefix}-cleanup-lambda"
  }
}

# CloudWatch Event Rule to trigger cleanup every 6 hours
resource "aws_cloudwatch_event_rule" "cleanup_schedule" {
  name                = "${local.prefix}-cleanup-schedule"
  description         = "Trigger cleanup Lambda every 6 hours"
  schedule_expression = "rate(6 hours)"

  tags = {
    Name = "${local.prefix}-cleanup-schedule"
  }
}

resource "aws_cloudwatch_event_target" "cleanup_target" {
  rule      = aws_cloudwatch_event_rule.cleanup_schedule.name
  target_id = "CleanupLambdaTarget"
  arn       = aws_lambda_function.cleanup_function.arn
}

resource "aws_lambda_permission" "allow_eventbridge_cleanup" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cleanup_function.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.cleanup_schedule.arn
}

resource "aws_s3_bucket_notification" "pdf_bucket_notification" {
  bucket = aws_s3_bucket.pdf_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.pdf_processor.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = local.config.upload_folder
    filter_suffix       = ".pdf"
  }

  depends_on = [aws_lambda_permission.s3_invoke]
}

# -------- DynamoDB Table for Tracking --------
resource "aws_dynamodb_table" "pdf_processing_table" {
  name         = "${local.prefix}-processing-table"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "file_id"

  attribute {
    name = "file_id"
    type = "S"
  }

  tags = {
    Name = "${local.prefix}-processing-table"
  }
}

# -------- IAM Role for Lambda --------
resource "aws_iam_role" "lambda_role" {
  name = "${local.prefix}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${local.prefix}-lambda-role"
  }
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "${local.prefix}-lambda-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "${aws_s3_bucket.pdf_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.pdf_bucket.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          aws_dynamodb_table.pdf_processing_table.arn
        ]
      }
    ]
  })
}

# -------- Lambda Function Package --------
resource "null_resource" "lambda_dependencies" {
  triggers = {
    requirements = filemd5("${path.module}/src/requirements.txt")
    source_code  = filemd5("${path.module}/src/lambda_function.py")
  }

  provisioner "local-exec" {
    command = "cd ${path.module} && python3 -m pip install -r src/requirements.txt -t src/ --upgrade"
  }
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/src"
  output_path = "${path.module}/lambda_function.zip"
  depends_on  = [null_resource.lambda_dependencies]
}

# -------- Lambda Function --------
resource "aws_lambda_function" "pdf_processor" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = local.lambda_function_name
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime          = local.config.lambda_runtime
  timeout          = local.config.lambda_timeout
  memory_size      = local.config.lambda_memory

  environment {
    variables = {
      UPLOAD_FOLDER       = local.config.upload_folder
      PROCESSED_FOLDER    = local.config.processed_folder
      COMPRESSION_QUALITY = local.compression_quality
      MAX_WIDTH           = local.max_width
      MAX_HEIGHT          = local.max_height
      REMOVE_METADATA                   = local.config.remove_metadata
      OPTIMIZE_IMAGES                   = local.config.optimize_images
      DYNAMODB_TABLE                    = aws_dynamodb_table.pdf_processing_table.name
      DELETE_ORIGINAL_AFTER_PROCESSING  = local.config.delete_original_after_processing
      DELETE_PROCESSED_AFTER_DOWNLOAD   = local.config.delete_processed_after_download
    }
  }

  tags = {
    Name = "${local.prefix}-lambda"
  }
}

# -------- Lambda Permission for S3 --------
resource "aws_lambda_permission" "s3_invoke" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.pdf_processor.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.pdf_bucket.arn
}

# -------- CloudWatch Log Group --------
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.lambda_function_name}"
  retention_in_days = local.config.log_retention_days

  tags = {
    Name = "${local.prefix}-lambda-logs"
  }
}

# -------- Download Lambda Function --------
data "archive_file" "download_lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/src/download_handler.py"
  output_path = "${path.module}/download_lambda.zip"
}

resource "aws_lambda_function" "download_handler" {
  count            = local.config.create_api_gateway ? 1 : 0
  filename         = data.archive_file.download_lambda_zip.output_path
  function_name    = "${local.lambda_function_name}-download"
  role             = aws_iam_role.lambda_role.arn
  handler          = "download_handler.lambda_handler"
  source_code_hash = data.archive_file.download_lambda_zip.output_base64sha256
  runtime          = local.config.lambda_runtime
  timeout          = 30

  environment {
    variables = {
      S3_BUCKET_NAME                    = local.bucket_name
      PROCESSED_FOLDER                  = local.config.processed_folder
      DYNAMODB_TABLE                    = aws_dynamodb_table.pdf_processing_table.name
      DELETE_PROCESSED_AFTER_DOWNLOAD   = local.config.delete_processed_after_download
    }
  }

  tags = {
    Name = "${local.prefix}-download-lambda"
  }
}

resource "aws_lambda_permission" "api_gateway_invoke_download" {
  count         = local.config.create_api_gateway ? 1 : 0
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.download_handler[0].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.pdf_api[0].execution_arn}/*/*"
}

# -------- API Gateway for Download Endpoint --------
resource "aws_api_gateway_rest_api" "pdf_api" {
  count = local.config.create_api_gateway ? 1 : 0
  name  = local.config.api_gateway_name

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name = "${local.prefix}-api"
  }
}

resource "aws_api_gateway_resource" "download_resource" {
  count       = local.config.create_api_gateway ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.pdf_api[0].id
  parent_id   = aws_api_gateway_rest_api.pdf_api[0].root_resource_id
  path_part   = "download"
}

resource "aws_api_gateway_resource" "file_resource" {
  count       = local.config.create_api_gateway ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.pdf_api[0].id
  parent_id   = aws_api_gateway_resource.download_resource[0].id
  path_part   = "{filename}"
}

resource "aws_api_gateway_method" "download_method" {
  count         = local.config.create_api_gateway ? 1 : 0
  rest_api_id   = aws_api_gateway_rest_api.pdf_api[0].id
  resource_id   = aws_api_gateway_resource.file_resource[0].id
  http_method   = "GET"
  authorization = "NONE"

  request_parameters = {
    "method.request.path.filename" = true
  }
}

resource "aws_api_gateway_integration" "lambda_integration" {
  count                   = local.config.create_api_gateway ? 1 : 0
  rest_api_id             = aws_api_gateway_rest_api.pdf_api[0].id
  resource_id             = aws_api_gateway_resource.file_resource[0].id
  http_method             = aws_api_gateway_method.download_method[0].http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.download_handler[0].invoke_arn
}

# AWS_PROXY integration handles responses automatically

# API Gateway now uses Lambda proxy integration - no additional IAM role needed

# -------- API Gateway Deployment --------
resource "aws_api_gateway_deployment" "pdf_api_deployment" {
  count       = local.config.create_api_gateway ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.pdf_api[0].id

  depends_on = [
    aws_api_gateway_method.download_method,
    aws_api_gateway_integration.lambda_integration
  ]

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.download_resource[0].id,
      aws_api_gateway_method.download_method[0].id,
      aws_api_gateway_integration.lambda_integration[0].id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "pdf_api_stage" {
  count         = local.config.create_api_gateway ? 1 : 0
  deployment_id = aws_api_gateway_deployment.pdf_api_deployment[0].id
  rest_api_id   = aws_api_gateway_rest_api.pdf_api[0].id
  stage_name    = "prod"

  tags = {
    Name = "${local.prefix}-api-stage"
  }
}

# -------- Outputs --------
output "s3_bucket_name" {
  description = "Name of the S3 bucket for PDF uploads"
  value       = aws_s3_bucket.pdf_bucket.bucket
}

output "s3_upload_url" {
  description = "S3 bucket URL for uploads"
  value       = "s3://${aws_s3_bucket.pdf_bucket.bucket}/${local.config.upload_folder}"
}

output "lambda_function_name" {
  description = "Name of the PDF processing Lambda function"
  value       = aws_lambda_function.pdf_processor.function_name
}

output "lambda_function_arn" {
  description = "ARN of the PDF processing Lambda function"
  value       = aws_lambda_function.pdf_processor.arn
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table for tracking processing"
  value       = aws_dynamodb_table.pdf_processing_table.name
}

output "api_gateway_url" {
  description = "API Gateway URL for file downloads"
  value       = local.config.create_api_gateway ? "https://${aws_api_gateway_rest_api.pdf_api[0].id}.execute-api.${data.aws_region.current.name}.amazonaws.com/prod/download" : null
}

output "download_example_url" {
  description = "Example download URL for processed files"
  value       = local.config.create_api_gateway ? "https://${aws_api_gateway_rest_api.pdf_api[0].id}.execute-api.${data.aws_region.current.name}.amazonaws.com/prod/download/filename_compressed.pdf" : null
}

output "web_ui_file" {
  description = "Ready-to-use web UI file with populated configuration"
  value       = "${path.module}/web-ui/index-ready.html"
}

output "website_url" {
  description = "Public website URL for the PDF processor"
  value       = local.config.host_website ? "http://${aws_s3_bucket.web_ui_bucket[0].bucket}.s3-website-${data.aws_region.current.name}.amazonaws.com" : "Website hosting disabled"
}

# S3 bucket for hosting the web UI
resource "aws_s3_bucket" "web_ui_bucket" {
  count  = local.config.host_website ? 1 : 0
  bucket = "${local.bucket_name}-web"

  tags = {
    Name = "${local.prefix}-web-bucket"
  }
}

resource "aws_s3_bucket_website_configuration" "web_ui_website" {
  count  = local.config.host_website ? 1 : 0
  bucket = aws_s3_bucket.web_ui_bucket[0].id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}

resource "aws_s3_bucket_public_access_block" "web_ui_pab" {
  count  = local.config.host_website ? 1 : 0
  bucket = aws_s3_bucket.web_ui_bucket[0].id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "web_ui_policy" {
  count      = local.config.host_website ? 1 : 0
  bucket     = aws_s3_bucket.web_ui_bucket[0].id
  depends_on = [aws_s3_bucket_public_access_block.web_ui_pab]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.web_ui_bucket[0].arn}/*"
      }
    ]
  })
}

# Generate and upload web UI
resource "aws_s3_object" "web_ui_html" {
  count        = local.config.host_website ? 1 : 0
  bucket       = aws_s3_bucket.web_ui_bucket[0].id
  key          = "index.html"
  content_type = "text/html"
  
  content = templatefile("${path.module}/web-ui/index.html", {
    s3_bucket_name    = aws_s3_bucket.pdf_bucket.bucket
    region           = local.region
    upload_folder    = local.config.upload_folder
    processed_folder = local.config.processed_folder
    api_gateway_url  = local.config.create_api_gateway ? "https://${aws_api_gateway_rest_api.pdf_api[0].id}.execute-api.${data.aws_region.current.name}.amazonaws.com/prod/download" : ""
  })

  tags = {
    Name = "${local.prefix}-web-ui"
  }
}

# Generate local copy for reference
resource "local_file" "web_ui" {
  content = templatefile("${path.module}/web-ui/index.html", {
    s3_bucket_name    = aws_s3_bucket.pdf_bucket.bucket
    region           = local.region
    upload_folder    = local.config.upload_folder
    processed_folder = local.config.processed_folder
    api_gateway_url  = local.config.create_api_gateway ? "https://${aws_api_gateway_rest_api.pdf_api[0].id}.execute-api.${data.aws_region.current.name}.amazonaws.com/prod/download" : ""
  })
  filename = "${path.module}/web-ui/index-ready.html"
}