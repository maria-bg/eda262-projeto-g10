output "state_bucket" {
  description = "Nome do bucket S3 para armazenar o Terraform state"
  value       = aws_s3_bucket.state.bucket
}

output "lock_table" {
  description = "Nome da tabela DynamoDB para locking do state"
  value       = aws_dynamodb_table.locks.name
}
