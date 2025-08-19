import json
import boto3
import os
import logging
from urllib.parse import unquote_plus
from datetime import datetime

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
s3_client = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    """
    Handle file downloads and delete processed files after download
    """
    try:
        # Extract filename from path parameters
        filename = event.get('pathParameters', {}).get('filename')
        if not filename:
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'Filename not provided'})
            }
        
        filename = unquote_plus(filename)
        bucket_name = os.environ.get('S3_BUCKET_NAME')
        processed_folder = os.environ.get('PROCESSED_FOLDER', 'processed/')
        processed_key = f"{processed_folder}{filename}"
        
        logger.info(f"Download request for: {processed_key}")
        
        # Check if file exists
        try:
            s3_client.head_object(Bucket=bucket_name, Key=processed_key)
        except s3_client.exceptions.NoSuchKey:
            return {
                'statusCode': 404,
                'body': json.dumps({'error': 'File not found'})
            }
        
        # Generate presigned URL for download
        download_url = s3_client.generate_presigned_url(
            'get_object',
            Params={'Bucket': bucket_name, 'Key': processed_key},
            ExpiresIn=300  # 5 minutes
        )
        
        # Log download but don't delete - let 12-hour cleanup handle deletion
        logger.info(f"File downloaded: {processed_key}")
        
        return {
            'statusCode': 302,
            'headers': {
                'Location': download_url,
                'Content-Type': 'application/pdf'
            },
            'body': ''
        }
        
    except Exception as e:
        logger.error(f"Error handling download: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': 'Internal server error'})
        }

def update_download_metadata(processed_key):
    """
    Update DynamoDB with download timestamp
    """
    try:
        table_name = os.environ.get('DYNAMODB_TABLE')
        if not table_name:
            return
        
        table = dynamodb.Table(table_name)
        
        # Find the record by processed_key
        response = table.scan(
            FilterExpression='processed_key = :pk',
            ExpressionAttributeValues={':pk': processed_key}
        )
        
        if response['Items']:
            item = response['Items'][0]
            table.update_item(
                Key={'file_id': item['file_id']},
                UpdateExpression='SET download_timestamp = :dt, #status = :status',
                ExpressionAttributeNames={'#status': 'status'},
                ExpressionAttributeValues={
                    ':dt': datetime.utcnow().isoformat(),
                    ':status': 'downloaded'
                }
            )
            
    except Exception as e:
        logger.warning(f"Failed to update download metadata: {str(e)}")

