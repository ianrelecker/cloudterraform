import json
import boto3
import os
import logging
from datetime import datetime, timedelta

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
s3_client = boto3.client('s3')

def lambda_handler(event, context):
    """
    Clean up files older than configured hours from S3 bucket
    """
    try:
        bucket_name = os.environ.get('S3_BUCKET_NAME')
        cleanup_hours = int(os.environ.get('AUTO_CLEANUP_HOURS', '12'))
        upload_folder = os.environ.get('UPLOAD_FOLDER', 'uploads/')
        processed_folder = os.environ.get('PROCESSED_FOLDER', 'processed/')
        
        if not bucket_name:
            logger.error("S3_BUCKET_NAME environment variable not set")
            return {
                'statusCode': 500,
                'body': json.dumps('S3_BUCKET_NAME not configured')
            }
        
        # Calculate cutoff time
        cutoff_time = datetime.utcnow() - timedelta(hours=cleanup_hours)
        logger.info(f"Cleaning up files older than {cutoff_time} in bucket {bucket_name}")
        
        deleted_count = 0
        
        # Clean upload folder
        deleted_count += cleanup_folder(bucket_name, upload_folder, cutoff_time)
        
        # Clean processed folder
        deleted_count += cleanup_folder(bucket_name, processed_folder, cutoff_time)
        
        logger.info(f"Cleanup completed. Deleted {deleted_count} files.")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Cleanup completed. Deleted {deleted_count} files.',
                'cutoff_time': cutoff_time.isoformat(),
                'cleanup_hours': cleanup_hours
            })
        }
        
    except Exception as e:
        logger.error(f"Error during cleanup: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Cleanup failed: {str(e)}')
        }

def cleanup_folder(bucket_name, folder_prefix, cutoff_time):
    """
    Clean up files in a specific folder older than cutoff_time
    """
    deleted_count = 0
    
    try:
        # List objects in the folder
        paginator = s3_client.get_paginator('list_objects_v2')
        pages = paginator.paginate(Bucket=bucket_name, Prefix=folder_prefix)
        
        objects_to_delete = []
        
        for page in pages:
            if 'Contents' not in page:
                continue
                
            for obj in page['Contents']:
                # Check if object is older than cutoff time
                if obj['LastModified'].replace(tzinfo=None) < cutoff_time:
                    objects_to_delete.append({'Key': obj['Key']})
                    logger.info(f"Marking for deletion: {obj['Key']} (modified: {obj['LastModified']})")
        
        # Delete objects in batches
        if objects_to_delete:
            # S3 delete_objects can handle up to 1000 objects at once
            for i in range(0, len(objects_to_delete), 1000):
                batch = objects_to_delete[i:i+1000]
                s3_client.delete_objects(
                    Bucket=bucket_name,
                    Delete={'Objects': batch}
                )
                deleted_count += len(batch)
                logger.info(f"Deleted batch of {len(batch)} files from {folder_prefix}")
        
        return deleted_count
        
    except Exception as e:
        logger.error(f"Error cleaning up folder {folder_prefix}: {str(e)}")
        return deleted_count

