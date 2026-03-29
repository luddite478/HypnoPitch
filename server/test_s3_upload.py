#!/usr/bin/env python3
"""
Test script for Digital Ocean Spaces S3 upload
Run: python test_s3_upload.py
"""
import os
import boto3
from botocore.exceptions import ClientError
from dotenv import load_dotenv

# Load environment variables
load_dotenv('.prod.env')

def test_s3_upload():
    """Test S3 upload to Digital Ocean Spaces"""
    
    # Get credentials from environment
    endpoint_url = os.getenv("S3_ENDPOINT_URL")
    region = os.getenv("S3_REGION")
    access_key = os.getenv("S3_ACCESS_KEY")
    secret_key = os.getenv("S3_SECRET_KEY")
    bucket_name = os.getenv("S3_BUCKET_NAME")
    env = os.getenv("ENV", "test")
    
    print("📋 Configuration:")
    print(f"   Endpoint: {endpoint_url}")
    print(f"   Region: {region}")
    print(f"   Bucket: {bucket_name}")
    print(f"   Access Key: {access_key[:10]}...")
    print(f"   Environment: {env}")
    print()
    
    # Validate configuration
    if not all([endpoint_url, access_key, secret_key, bucket_name]):
        print("❌ Missing S3 configuration in .prod.env")
        return False
    
    try:
        # Initialize boto3 client
        print("🔧 Initializing boto3 client...")
        client = boto3.client(
            's3',
            endpoint_url=endpoint_url,
            aws_access_key_id=access_key,
            aws_secret_access_key=secret_key,
            region_name=region
        )
        print("✅ Client initialized")
        print()
        
        # Create test file content
        test_content = b"This is a test audio file upload from HypnoPitch app"
        file_key = f"{env}/renders/test_upload_123.mp3"
        
        print(f"📤 Uploading test file: {file_key}")
        
        # Upload using put_object
        client.put_object(
            Bucket=bucket_name,
            Key=file_key,
            Body=test_content,
            ContentType='audio/mpeg',
            ACL='public-read'
        )
        
        # Construct public URL
        public_url = f"https://{bucket_name}.{endpoint_url.replace('https://', '')}/{file_key}"
        
        print("✅ Upload successful!")
        print(f"📍 Public URL: {public_url}")
        print()
        
        # Verify the file exists
        print("🔍 Verifying upload...")
        response = client.head_object(Bucket=bucket_name, Key=file_key)
        print(f"✅ File exists! Size: {response['ContentLength']} bytes")
        print(f"   Content-Type: {response.get('ContentType', 'N/A')}")
        print()
        
        # Clean up (optional)
        cleanup = input("🗑️  Delete test file? (y/n): ").strip().lower()
        if cleanup == 'y':
            client.delete_object(Bucket=bucket_name, Key=file_key)
            print("✅ Test file deleted")
        else:
            print(f"ℹ️  Test file kept at: {file_key}")
        
        return True
        
    except ClientError as e:
        print(f"❌ S3 Error: {e}")
        print(f"   Error Code: {e.response.get('Error', {}).get('Code', 'Unknown')}")
        print(f"   Error Message: {e.response.get('Error', {}).get('Message', 'Unknown')}")
        return False
    except Exception as e:
        print(f"❌ Unexpected error: {e}")
        return False

if __name__ == "__main__":
    print("=" * 60)
    print("🧪 Digital Ocean Spaces S3 Upload Test")
    print("=" * 60)
    print()
    
    success = test_s3_upload()
    
    print()
    print("=" * 60)
    if success:
        print("✅ Test PASSED - S3 upload is working!")
    else:
        print("❌ Test FAILED - Check configuration and credentials")
    print("=" * 60)

