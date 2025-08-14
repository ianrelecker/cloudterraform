variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "s3_bucket_name" {
  description = "Name of the S3 bucket for Kendra documents"
  type        = string
}

variable "kendra_index_name" {
  description = "Name of the Kendra index"
  type        = string
}

variable "kendra_edition" {
  description = "Kendra index edition (DEVELOPER_EDITION or ENTERPRISE_EDITION). ENTERPRISE_EDITION uses GenAI Enterprise Edition by default, which is more cost-effective."
  type        = string
  default     = "ENTERPRISE_EDITION"
  validation {
    condition     = contains(["DEVELOPER_EDITION", "ENTERPRISE_EDITION"], var.kendra_edition)
    error_message = "Kendra edition must be either DEVELOPER_EDITION or ENTERPRISE_EDITION."
  }
}

variable "s3_inclusion_prefixes" {
  description = "List of S3 prefixes to include in the index"
  type        = list(string)
  default     = []
}

variable "s3_exclusion_patterns" {
  description = "List of patterns to exclude from indexing"
  type        = list(string)
  default     = ["*.tmp", "*.log", "*.backup", "*/.DS_Store"]
}

variable "s3_metadata_prefix" {
  description = "S3 prefix for metadata files"
  type        = string
  default     = "metadata/"
}

variable "sync_schedule" {
  description = "Cron expression for data source sync schedule"
  type        = string
  default     = "cron(0 2 * * ? *)"
}

variable "metadata_configurations" {
  description = "Document metadata configurations for the Kendra index"
  type = list(object({
    name = string
    type = string
    search = optional(object({
      displayable = optional(bool, true)
      facetable   = optional(bool, false)
      searchable  = optional(bool, true)
      sortable    = optional(bool, false)
    }))
  }))
  default = [
    {
      name = "_created_at"
      type = "DATE_VALUE"
      search = {
        displayable = true
        facetable   = true
        searchable  = false
        sortable    = true
      }
    },
    {
      name = "_file_type"
      type = "STRING_VALUE"
      search = {
        displayable = true
        facetable   = true
        searchable  = false
        sortable    = false
      }
    }
  ]
}