output "trusted_bucket" {
  description = "Nome do bucket S3 da camada trusted"
  value       = aws_s3_bucket.trusted.bucket
}

output "athena_results_bucket" {
  description = "Nome do bucket S3 para resultados do Athena"
  value       = aws_s3_bucket.athena_results.bucket
}

output "glue_database" {
  description = "Nome do banco de dados no Glue Data Catalog"
  value       = aws_glue_catalog_database.farmacia.name
}

output "athena_workgroup" {
  description = "Nome do workgroup do Athena"
  value       = aws_athena_workgroup.main.name
}

output "query_business" {
  description = "Consulta SQL para responder a pergunta de negócio"
  value       = <<-SQL
    SELECT
        categoria,
        SUM(CAST(quantidade AS DOUBLE) * CAST(preco_unitario AS DOUBLE)) AS receita_total,
        AVG(CAST(quantidade AS DOUBLE) * CAST(preco_unitario AS DOUBLE)) AS ticket_medio,
        COUNT(DISTINCT pedido_id)                                        AS total_pedidos
    FROM "${aws_glue_catalog_database.farmacia.name}"."${aws_glue_catalog_table.itens_pedido.name}"
    WHERE data_pedido >= DATE_FORMAT(DATE_ADD('day', -30, CURRENT_DATE), '%Y-%m-%d')
    GROUP BY categoria
    ORDER BY receita_total DESC;
  SQL
}
