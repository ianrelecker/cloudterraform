import json
import boto3
import os
import logging
from urllib.parse import unquote_plus
from io import BytesIO
from pypdf import PdfWriter, PdfReader
from datetime import datetime

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
s3_client = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')


def lambda_handler(event, context):
    """
    Repair PDF files uploaded to S3 by re-reading and re-writing them
    to reconstruct cross-reference tables, clean metadata (optional), and
    normalize structure.
    """
    try:
        for record in event['Records']:
            bucket_name = record['s3']['bucket']['name']
            object_key = unquote_plus(record['s3']['object']['key'])

            logger.info(f"Repairing file: {object_key} from bucket: {bucket_name}")

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

            # Repair the PDF
            repaired_pdf, repair_notes = repair_pdf(pdf_content)
            repaired_size = len(repaired_pdf)

            # Generate processed file key
            processed_key = generate_processed_key(object_key)

            # Upload repaired PDF to processed folder
            s3_client.put_object(
                Bucket=bucket_name,
                Key=processed_key,
                Body=repaired_pdf,
                ContentType='application/pdf'
            )

            logger.info(f"Repaired PDF uploaded: {processed_key}")
            logger.info(
                f"Size: {original_size} -> {repaired_size} ({((repaired_size - original_size) / original_size * 100):.1f}% change)"
            )

            # Store metadata in DynamoDB (if configured)
            store_repair_metadata(object_key, processed_key, original_size, repaired_size, repair_notes)

            # Delete original file if configured
            delete_original = os.environ.get('DELETE_ORIGINAL_AFTER_PROCESSING', 'false').lower() == 'true'
            if delete_original:
                s3_client.delete_object(Bucket=bucket_name, Key=object_key)
                logger.info(f"Deleted original file: {object_key}")

        return {
            'statusCode': 200,
            'body': json.dumps('PDF repair completed successfully')
        }

    except Exception as e:
        logger.error(f"Error repairing PDF: {str(e)}")
        raise e


def repair_pdf(pdf_content):
    """
    Attempt to repair a PDF by:
    - Parsing with PdfReader in non-strict mode to tolerate minor errors
    - Rewriting the document structure with PdfWriter
    - Optionally clearing metadata

    Returns a tuple of (repaired_bytes, repair_notes)
    """
    notes = []
    input_pdf = BytesIO(pdf_content)
    output_pdf = BytesIO()

    try:
        # Tolerate minor structural issues
        reader = PdfReader(input_pdf, strict=False)

        # Handle encrypted PDFs with empty password if possible
        if getattr(reader, 'is_encrypted', False):
            try:
                if reader.decrypt(""):
                    notes.append('decrypted_with_empty_password')
                else:
                    # Some versions return 0/False on success; attempt anyway
                    notes.append('attempted_empty_password_decrypt')
            except Exception:
                notes.append('decrypt_attempt_failed')

        writer = PdfWriter()

        # Copy all pages to reconstruct xref and objects
        for page in reader.pages:
            writer.add_page(page)

        # Optionally strip metadata
        remove_metadata = os.environ.get('REMOVE_METADATA', 'true').lower() == 'true'
        if remove_metadata:
            writer.add_metadata({})
            notes.append('metadata_cleared')

        # Write repaired output
        writer.write(output_pdf)
        repaired_bytes = output_pdf.getvalue()
        notes.append('rewritten_structure')

        return repaired_bytes, notes

    except Exception as e:
        logger.error(f"Error during PDF repair: {str(e)}")
        raise e
    finally:
        input_pdf.close()
        output_pdf.close()


def generate_processed_key(original_key):
    """
    Generate the processed (repaired) file key
    """
    processed_folder = os.environ.get('PROCESSED_FOLDER', 'processed/')

    filename = original_key.split('/')[-1]
    name, ext = os.path.splitext(filename)
    processed_filename = f"{name}_repaired{ext}"

    return f"{processed_folder}{processed_filename}"


def store_repair_metadata(original_key, processed_key, original_size, repaired_size, notes):
    """
    Store repair metadata in DynamoDB, if a table is configured via DYNAMODB_TABLE.
    """
    try:
        table_name = os.environ.get('DYNAMODB_TABLE')
        if not table_name:
            logger.info("DynamoDB table not configured; skipping metadata storage")
            return

        table = dynamodb.Table(table_name)
        file_id = f"{original_key}_{datetime.utcnow().isoformat()}"

        item = {
            'file_id': file_id,
            'original_key': original_key,
            'processed_key': processed_key,
            'original_size': original_size,
            'repaired_size': repaired_size,
            'size_delta': repaired_size - original_size,
            'repair_notes': notes,
            'processing_timestamp': datetime.utcnow().isoformat(),
            'status': 'repaired'
        }

        table.put_item(Item=item)
        logger.info(f"Repair metadata stored for file: {file_id}")

    except Exception as e:
        logger.warning(f"Failed to store repair metadata: {str(e)}")

