# PDF Repairer - Serverless PDF Repair

A serverless PDF repair service that automatically processes PDF files uploaded to S3, reconstructing cross-reference tables and normalizing structure by re-reading and re-writing PDFs. Files are automatically deleted on a schedule for privacy.

## Architecture

- S3 Bucket: Stores uploaded and processed PDF files
- Lambda Function: Repairs PDFs using pypdf by tolerant parsing and rewriting
- API Gateway: Provides download endpoints for processed files
- DynamoDB: Tracks processing metadata and status
- Web UI: Simple interface for upload and download

## Features

- Automatic PDF repair on S3 upload
- Optional metadata removal for privacy
- Download API for processed files
- Processing status tracking
- CORS enabled for web uploads
- CloudWatch logging
- Auto-cleanup of old files

## Quick Start

1) Configure bucket name

Edit `s3pdfrepair-config.yaml` and set a globally unique `bucket_name`.

2) Deploy infrastructure

terraform init
terraform plan
terraform apply

3) Use the web interface
- After deployment, use the public website URL from `terraform output website_url`
- Or open local `web-ui/index-ready.html` (auto-configured)
- Or upload directly to S3 `uploads/` folder

## Configuration

Edit `s3pdfrepair-config.yaml`:

- remove_metadata: true|false
- delete_original_after_processing: true|false
- delete_processed_after_download: true|false
- host_website: true|false

## File Structure

├── main.tf
├── s3pdfrepair-config.yaml
├── src/
│   ├── lambda_function.py
│   ├── download_handler.py
│   ├── cleanup_lambda.py
│   └── requirements.txt
└── web-ui/
    ├── index.html
    └── index-ready.html

## Usage Examples

Upload to S3:
aws s3 cp document.pdf s3://your-bucket-name/uploads/

Download processed file (via API):
curl "https://your-api-id.execute-api.region.amazonaws.com/prod/download/document_repaired.pdf"

## Processing Logic

1. PDF uploaded to S3 `uploads/`
2. S3 triggers Lambda
3. Lambda downloads and repairs PDF:
   - Tolerant parse with `strict=False`
   - Rewrite with `PdfWriter` (rebuild xref and structure)
   - Optionally removes metadata
4. Repaired PDF saved to `processed/` with `_repaired.pdf` suffix
5. Metadata stored to DynamoDB (if configured)
6. Optional deletion of original file

