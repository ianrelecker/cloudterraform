# AWS Kendra with S3 Data Source Terraform Module

This Terraform configuration creates an AWS Kendra search index with an S3 data source, enabling intelligent document search across all items in an S3 bucket.

## Architecture

- **S3 Bucket**: Private, encrypted storage for documents with versioning enabled
- **Kendra Index**: Intelligent search index for document discovery
- **S3 Data Source**: Connects Kendra to the S3 bucket for automatic indexing
- **IAM Roles**: Secure permissions for Kendra to access S3 resources

## Features

- ✅ Private S3 bucket with encryption and public access blocked
- ✅ Automated document indexing from S3
- ✅ Configurable inclusion/exclusion patterns
- ✅ Scheduled sync with customizable cron expression
- ✅ Metadata configuration for enhanced search
- ✅ Proper IAM roles and policies following least privilege

## Prerequisites

- AWS CLI configured with appropriate permissions
- Terraform >= 1.0
- AWS provider >= 5.0

## Quick Start

1. **Clone and configure**:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your specific values
   ```

2. **Deploy**:
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

3. **Upload documents to S3**:
   ```bash
   aws s3 cp your-document.pdf s3://your-bucket-name/documents/
   ```

4. **Trigger sync** (or wait for scheduled sync):
   ```bash
   aws kendra start-data-source-sync-job \
     --id <data-source-id> \
     --index-id <index-id>
   ```

## Configuration

### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `s3_bucket_name` | Unique S3 bucket name | `"my-kendra-docs-bucket-123"` |
| `kendra_index_name` | Kendra index name | `"my-document-search"` |

### Optional Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `aws_region` | `"us-east-1"` | AWS region |
| `kendra_edition` | `"ENTERPRISE_EDITION"` | Kendra edition (GenAI Enterprise recommended) |
| `s3_inclusion_prefixes` | `[]` | S3 prefixes to include |
| `s3_exclusion_patterns` | `["*.tmp", "*.log", ...]` | File patterns to exclude |
| `sync_schedule` | `"cron(0 2 * * ? *)"` | Daily sync at 2 AM UTC |

## Supported File Types

Kendra supports many document formats including:
- PDF, DOC, DOCX, PPT, PPTX
- TXT, RTF, CSV, TSV
- HTML, XML, JSON
- And more (max 50MB per file)

## Security Features

- **Private S3 Bucket**: Public access completely blocked
- **Encryption**: Server-side encryption enabled
- **IAM Roles**: Separate roles for index and data source with minimal permissions
- **VPC Support**: Can be configured for VPC-only access

## Cost Breakdown

### Kendra Index Pricing (2025)

| Edition | Hourly Rate | Monthly Cost | Documents | Queries/Day | Free Trial |
|---------|-------------|--------------|-----------|-------------|------------|
| **GenAI Enterprise** (default) | $0.32/hour | **~$230** | 20,000 | 8,000 | 750 hours |
| Developer Edition | $1.125/hour | ~$810 | 10,000 | 4,000 | 750 hours |
| Basic Enterprise | $1.40/hour | ~$1,008 | 100,000 | 8,000 | None |

### Additional Costs

**S3 Data Source Connector:**
- Base fee: $0.35/hour = **~$252/month**
- Document scanning: $1 per 1M documents scanned

**S3 Storage:**
- Standard storage: ~$0.023/GB/month
- Typical cost: **$1-20/month** (depends on document volume)

### Total Monthly Cost Examples

**Small Organization (GenAI Enterprise + S3 Connector):**
- Index: $230/month
- Connector: $252/month
- S3 Storage: ~$5/month
- **Total: ~$487/month**

**Development/Testing (Developer Edition):**
- First month: $252/month (free 750 hours + connector)
- Ongoing: $1,062/month ($810 + $252)

**Large Enterprise (Basic Enterprise):**
- Index: $1,008/month
- Connector: $252/month
- S3 Storage: ~$50/month
- **Total: ~$1,310/month**

### Free Tier Benefits

- **750 hours free** for first 30 days on GenAI Enterprise or Developer editions
- Effective **first month cost: ~$252** (connector fees only)
- No free tier for Basic Enterprise Edition

### Cost Optimization Tips

- **Use GenAI Enterprise Edition** - Most cost-effective for production workloads
- **Monitor document limits** - Additional storage units cost extra
- **Delete unused indices** - Billing continues even if empty
- **Optimize sync frequency** - Reduce connector scanning costs
- **Implement S3 lifecycle policies** - Archive old documents to cheaper storage classes
- **Use inclusion/exclusion patterns** - Index only relevant documents

## Monitoring and Logs

The configuration includes CloudWatch logging permissions. Monitor:
- Data source sync jobs
- Index utilization
- Query performance
- Error logs

## Examples

### Basic Configuration
```hcl
s3_bucket_name    = "my-docs-bucket-unique"
kendra_index_name = "company-knowledge-base"
```

### Advanced Configuration
```hcl
s3_bucket_name = "enterprise-docs-bucket"
kendra_index_name = "enterprise-search"
kendra_edition = "ENTERPRISE_EDITION"
s3_inclusion_prefixes = [
  "public-docs/",
  "policies/",
  "procedures/"
]
s3_exclusion_patterns = [
  "*/drafts/*",
  "*.tmp",
  "*confidential*"
]
```

## Outputs

| Output | Description |
|--------|-------------|
| `s3_bucket_name` | Created S3 bucket name |
| `kendra_index_id` | Kendra index ID for queries |
| `kendra_data_source_id` | Data source ID for sync operations |

## Cleanup

```bash
terraform destroy
```

**Note**: Ensure S3 bucket is empty before destroying, or enable `force_destroy = true` in the S3 bucket resource.

## Troubleshooting

### Common Issues

1. **Sync Failures**: Check IAM permissions and S3 bucket access
2. **No Search Results**: Verify documents are in included prefixes
3. **Permission Errors**: Ensure Kendra service role has S3 access

### Useful Commands

```bash
# Check data source status
aws kendra describe-data-source --id <data-source-id> --index-id <index-id>

# List sync jobs
aws kendra list-data-source-sync-jobs --id <data-source-id> --index-id <index-id>

# Query the index
aws kendra query --index-id <index-id> --query-text "your search terms"
```