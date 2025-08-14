output "s3_bucket_name" {
  description = "Name of the created S3 bucket"
  value       = aws_s3_bucket.kendra_documents.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the created S3 bucket"
  value       = aws_s3_bucket.kendra_documents.arn
}

output "kendra_index_id" {
  description = "ID of the Kendra index"
  value       = aws_kendra_index.main.id
}

output "kendra_index_arn" {
  description = "ARN of the Kendra index"
  value       = aws_kendra_index.main.arn
}

output "kendra_data_source_id" {
  description = "ID of the Kendra S3 data source"
  value       = aws_kendra_data_source.s3_data_source.id
}

output "kendra_role_arn" {
  description = "ARN of the Kendra service role"
  value       = aws_iam_role.kendra_role.arn
}

output "kendra_data_source_role_arn" {
  description = "ARN of the Kendra data source role"
  value       = aws_iam_role.kendra_data_source_role.arn
}