# PDF Size Reducer - Serverless PDF Compression

A serverless PDF compression service that automatically processes PDF files uploaded to S3, reducing their size while maintaining quality. Files are automatically deleted after processing and download for privacy.

## Architecture

- **S3 Bucket**: Stores uploaded and processed PDF files
- **Lambda Function**: Processes PDFs using PyMuPDF to reduce file size
- **API Gateway**: Provides download endpoints for processed files
- **DynamoDB**: Tracks processing metadata and status
- **Web UI**: Simple interface for upload and download

## Features

- Automatic PDF compression on S3 upload
- Configurable compression settings via YAML
- Image optimization within PDFs
- Metadata removal for privacy
- Download API for processed files
- Processing status tracking
- CORS enabled for web uploads
- CloudWatch logging
- **Auto-cleanup**: Original files deleted after processing
- **Privacy-focused**: Processed files deleted after download

## Quick Start

### 1. Configure bucket name
```bash
# Edit s3processor-config.yaml - change bucket name to be globally unique
vim s3processor-config.yaml
# Change: bucket_name: "pdf-upload-processor-CHANGE-ME-12345"
# To:     bucket_name: "your-unique-name-here"
```

### 2. Deploy infrastructure
```bash
terraform init
terraform plan
terraform apply
```

### 3. Use the web interface
- After deployment, use the public website URL from `terraform output website_url`
- Or open local `web-ui/index-ready.html` (auto-configured)
- Or upload directly to S3 `uploads/` folder

## Configuration

Edit `s3processor-config.yaml`:

```yaml
# PDF processing settings
compression_quality: 70    # 1-100, lower = more compression
max_width: 1200           # pixels, resize images in PDF
max_height: 1600          # pixels, resize images in PDF
remove_metadata: true     # remove PDF metadata
optimize_images: true     # compress images within PDF

# File cleanup (privacy settings)
delete_original_after_processing: true   # delete original after compression
delete_processed_after_download: true    # delete compressed file after download
processed_file_ttl_hours: 24            # max lifetime for processed files

# Web hosting
host_website: true                       # create public S3 website for the web UI
```

## File Structure

```
├── main.tf                     # Terraform infrastructure
├── s3processor-config.yaml     # Configuration variables
├── src/
│   ├── lambda_function.py      # PDF processing Lambda
│   ├── download_handler.py     # Download API Lambda
│   └── requirements.txt        # Python dependencies
├── web-ui/
│   ├── index.html              # Web UI template
│   └── index-ready.html        # Auto-generated ready UI (after terraform apply)
├── terraform.tfvars.example    # Variable overrides example
└── README.md                   # This file
```

## Usage Examples

### Direct S3 Upload
```bash
aws s3 cp document.pdf s3://your-bucket-name/uploads/
```

### Download Processed File
```bash
# Via web UI (recommended)
open web-ui/index-ready.html

# Via API Gateway directly
curl "https://your-api-id.execute-api.region.amazonaws.com/prod/download/document_compressed.pdf"
```

### Monitor Processing
```bash
# Check Lambda logs
aws logs tail /aws/lambda/pdf-size-reducer --follow

# Check DynamoDB processing table
aws dynamodb scan --table-name pdf-processor-processing-table
```

## Processing Logic

1. PDF uploaded to S3 `uploads/` folder
2. S3 triggers Lambda function
3. Lambda downloads and processes PDF:
   - Compresses images within PDF
   - Resizes large images
   - Removes metadata (optional)
   - Optimizes for smaller file size
4. Compressed PDF saved to `processed/` folder
5. Processing metadata stored in DynamoDB
6. **Original file deleted** (configurable)
7. When user downloads via API Gateway:
   - Download handler provides secure download URL
   - **Processed file deleted immediately after download** (configurable)

## Cost Estimate

**Light usage** (10 PDFs/hour): ~$0.01/hour
**Moderate usage** (100 PDFs/hour): ~$0.10/hour  
**Heavy usage** (1000 PDFs/hour): ~$1.00/hour

Most costs are usage-based, so zero usage = near-zero cost.

## Optional Customization

### Backend Configuration
Update `main.tf` if you need a different Terraform state bucket:
```hcl
backend "s3" {
  bucket = "your-terraform-state-bucket"
  region = "your-region"
}
```

### Variable Overrides
Copy `terraform.tfvars.example` to `terraform.tfvars` and customize:
```bash
cp terraform.tfvars.example terraform.tfvars
vim terraform.tfvars
```

### CORS Security
For production, update `s3processor-config.yaml`:
```yaml
cors_allowed_origins: ["https://yourdomain.com"]
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| **"Bucket already exists"** | Change `bucket_name` in config to be globally unique |
| **"Backend bucket not found"** | Update `main.tf` backend bucket to an existing S3 bucket |
| **Lambda timeout errors** | Increase `lambda_timeout` in config for large PDFs |
| **PyMuPDF import errors** | Lambda layer may be needed for production |
| **API Gateway 403 errors** | Check IAM role permissions and API Gateway configuration |
| **CORS errors in browser** | Update `cors_allowed_origins` in config with your domain |

### Validation Commands

```bash
# Check if bucket name is available
aws s3 ls s3://your-bucket-name-here 2>&1 | grep -q "NoSuchBucket" && echo "Available" || echo "Taken"

# Validate Terraform configuration
terraform validate

# Check AWS credentials
aws sts get-caller-identity

# Test Lambda function
aws lambda invoke --function-name pdf-size-reducer --payload '{}' /tmp/test-response.json
```

## Security Considerations

- S3 bucket has CORS enabled for web uploads
- Lambda has minimal IAM permissions
- API Gateway only allows GET requests to processed files
- No public read access to upload folder
- Processed files accessible via signed URLs or API Gateway
- Automatic file cleanup for privacy

## Dependencies

- **Terraform**: >= 1.6.0
- **AWS Provider**: ~> 5.0
- **Python**: 3.11 (Lambda runtime)
- **PyMuPDF**: PDF processing
- **Pillow**: Image compression

## License

This is example infrastructure code. Customize for your use case.