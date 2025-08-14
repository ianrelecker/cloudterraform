terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

locals {
  common_tags = {
    Environment = var.environment
    Project     = "kendra-s3-search"
    ManagedBy   = "Terraform"
  }
}

resource "aws_s3_bucket" "kendra_documents" {
  bucket = var.s3_bucket_name
  tags   = local.common_tags
}

resource "aws_s3_bucket_versioning" "kendra_documents" {
  bucket = aws_s3_bucket.kendra_documents.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "kendra_documents" {
  bucket = aws_s3_bucket.kendra_documents.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "kendra_documents" {
  bucket = aws_s3_bucket.kendra_documents.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "kendra_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["kendra.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "kendra_role" {
  name               = "${var.kendra_index_name}-role"
  assume_role_policy = data.aws_iam_policy_document.kendra_assume_role.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "kendra_policy" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.kendra_documents.arn,
      "${aws_s3_bucket.kendra_documents.arn}/*"
    ]
  }
  
  statement {
    effect = "Allow"
    actions = [
      "kendra:BatchPutDocument",
      "kendra:BatchDeleteDocument"
    ]
    resources = ["*"]
  }
  
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }
}

resource "aws_iam_role_policy" "kendra_policy" {
  name   = "${var.kendra_index_name}-policy"
  role   = aws_iam_role.kendra_role.id
  policy = data.aws_iam_policy_document.kendra_policy.json
}

data "aws_iam_policy_document" "kendra_data_source_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["kendra.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "kendra_data_source_role" {
  name               = "${var.kendra_index_name}-datasource-role"
  assume_role_policy = data.aws_iam_policy_document.kendra_data_source_assume_role.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "kendra_data_source_policy" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.kendra_documents.arn,
      "${aws_s3_bucket.kendra_documents.arn}/*"
    ]
  }
}

resource "aws_iam_role_policy" "kendra_data_source_policy" {
  name   = "${var.kendra_index_name}-datasource-policy"
  role   = aws_iam_role.kendra_data_source_role.id
  policy = data.aws_iam_policy_document.kendra_data_source_policy.json
}

resource "aws_kendra_index" "main" {
  name        = var.kendra_index_name
  description = "Kendra index for S3 document search"
  edition     = var.kendra_edition
  role_arn    = aws_iam_role.kendra_role.arn
  tags        = local.common_tags

  dynamic "document_metadata_configuration_updates" {
    for_each = var.metadata_configurations
    content {
      name = document_metadata_configuration_updates.value.name
      type = document_metadata_configuration_updates.value.type
      
      dynamic "search" {
        for_each = document_metadata_configuration_updates.value.search != null ? [1] : []
        content {
          displayable = document_metadata_configuration_updates.value.search.displayable
          facetable   = document_metadata_configuration_updates.value.search.facetable
          searchable  = document_metadata_configuration_updates.value.search.searchable
          sortable    = document_metadata_configuration_updates.value.search.sortable
        }
      }
    }
  }
}

resource "aws_kendra_data_source" "s3_data_source" {
  index_id = aws_kendra_index.main.id
  name     = "${var.kendra_index_name}-s3-datasource"
  type     = "S3"
  role_arn = aws_iam_role.kendra_data_source_role.arn
  tags     = local.common_tags

  configuration {
    s3_configuration {
      bucket_name                = aws_s3_bucket.kendra_documents.bucket
      inclusion_prefixes         = var.s3_inclusion_prefixes
      exclusion_patterns         = var.s3_exclusion_patterns
      documents_metadata_configuration {
        s3_prefix = var.s3_metadata_prefix
      }
    }
  }

  schedule = var.sync_schedule
}