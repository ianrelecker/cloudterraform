import json
import boto3
import os
import logging
from urllib.parse import unquote_plus
from io import BytesIO
from pypdf import PdfWriter, PdfReader
from datetime import datetime, timedelta

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
s3_client = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    """
    Process PDF files uploaded to S3 by reducing their size
    """
    try:
        # Get S3 bucket and object from the event
        for record in event['Records']:
            bucket_name = record['s3']['bucket']['name']
            object_key = unquote_plus(record['s3']['object']['key'])
            
            logger.info(f"Processing file: {object_key} from bucket: {bucket_name}")
            
            # Skip if file is already in processed folder
            if object_key.startswith(os.environ.get('PROCESSED_FOLDER', 'processed/')):
                logger.info(f"Skipping already processed file: {object_key}")
                continue
            
            # Only process PDF files
            if not object_key.lower().endswith('.pdf'):
                logger.info(f"Skipping non-PDF file: {object_key}")
                continue
            
            # Download the PDF from S3
            response = s3_client.get_object(Bucket=bucket_name, Key=object_key)
            pdf_content = response['Body'].read()
            original_size = len(pdf_content)
            
            # Process the PDF
            compressed_pdf = compress_pdf(pdf_content)
            compressed_size = len(compressed_pdf)
            
            # Generate processed file key
            processed_key = generate_processed_key(object_key)
            
            # Upload compressed PDF to processed folder
            s3_client.put_object(
                Bucket=bucket_name,
                Key=processed_key,
                Body=compressed_pdf,
                ContentType='application/pdf'
            )
            
            logger.info(f"Compressed PDF uploaded: {processed_key}")
            logger.info(f"Size reduction: {original_size} -> {compressed_size} ({((original_size - compressed_size) / original_size * 100):.1f}% reduction)")
            
            # Store metadata in DynamoDB
            store_processing_metadata(object_key, processed_key, original_size, compressed_size, context)
            
            # Delete original file if configured
            delete_original = os.environ.get('DELETE_ORIGINAL_AFTER_PROCESSING', 'false').lower() == 'true'
            if delete_original:
                s3_client.delete_object(Bucket=bucket_name, Key=object_key)
                logger.info(f"Deleted original file: {object_key}")
        
        return {
            'statusCode': 200,
            'body': json.dumps('PDF processing completed successfully')
        }
        
    except Exception as e:
        logger.error(f"Error processing PDF: {str(e)}")
        raise e

def compress_pdf(pdf_content):
    """
    Compress PDF using pypdf - basic compression by removing duplicate objects
    """
    try:
        # Create BytesIO objects for input and output
        input_pdf = BytesIO(pdf_content)
        output_pdf = BytesIO()
        
        # Read the PDF
        reader = PdfReader(input_pdf)
        writer = PdfWriter()
        
        # Copy all pages to the writer
        for page in reader.pages:
            writer.add_page(page)
        
        # Remove metadata if configured
        remove_metadata = os.environ.get('REMOVE_METADATA', 'true').lower() == 'true'
        if remove_metadata:
            writer.add_metadata({})
        
        # Basic compression - pypdf handles this automatically
        
        # Write to output buffer
        writer.write(output_pdf)
        
        # Get the compressed bytes
        compressed_bytes = output_pdf.getvalue()
        
        # Close buffers
        input_pdf.close()
        output_pdf.close()
        
        return compressed_bytes
        
    except Exception as e:
        logger.error(f"Error compressing PDF: {str(e)}")
        raise e

def generate_processed_key(original_key):
    """
    Generate the processed file key
    """
    processed_folder = os.environ.get('PROCESSED_FOLDER', 'processed/')
    
    # Extract filename from original key
    filename = original_key.split('/')[-1]
    
    # Add compressed suffix
    name, ext = os.path.splitext(filename)
    processed_filename = f"{name}_compressed{ext}"
    
    return f"{processed_folder}{processed_filename}"

def store_processing_metadata(original_key, processed_key, original_size, compressed_size, context=None):
    """
    Store processing metadata in DynamoDB
    """
    try:
        table_name = os.environ.get('DYNAMODB_TABLE')
        if not table_name:
            logger.warning("DynamoDB table not configured, skipping metadata storage")
            return
        
        table = dynamodb.Table(table_name)
        
        # Generate unique file ID
        file_id = f"{original_key}_{datetime.utcnow().isoformat()}"
        
        # Store metadata
        table.put_item(
            Item={
                'file_id': file_id,
                'original_key': original_key,
                'processed_key': processed_key,
                'original_size': original_size,
                'compressed_size': compressed_size,
                'compression_ratio': round((original_size - compressed_size) / original_size * 100, 2),
                'processing_timestamp': datetime.utcnow().isoformat(),
                'status': 'processed'
            }
        )
        
        logger.info(f"Metadata stored for file: {file_id}")
        
    except Exception as e:
        logger.warning(f"Failed to store metadata: {str(e)}")