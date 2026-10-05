output "trusted_bucket" {
  description = "Nome do bucket S3 da camada trusted"
  value       = module.data_lake.trusted_bucket
}

output "athena_results_bucket" {
  description = "Nome do bucket S3 para resultados do Athena"
  value       = module.data_lake.athena_results_bucket
}

output "glue_database" {
  description = "Nome do banco de dados no Glue Data Catalog"
  value       = module.data_lake.glue_database
}

output "athena_workgroup" {
  description = "Nome do workgroup do Athena"
  value       = module.data_lake.athena_workgroup
}

output "query_business" {
  description = "Consulta SQL para responder a pergunta de negócio"
  value       = module.data_lake.query_business
}
