locals {
  prefix = "${var.turma}-${var.grupo}"
  tags = {
    turma   = var.turma
    grupo   = var.grupo
    projeto = "engenharia-de-dados"
  }
}

# ─── Buckets S3 ───────────────────────────────────────────────────────────────

resource "aws_s3_bucket" "trusted" {
  bucket = "${local.prefix}-lake-trusted"

  tags = local.tags
}

resource "aws_s3_bucket_public_access_block" "trusted" {
  bucket                  = aws_s3_bucket.trusted.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket" "athena_results" {
  bucket = "${local.prefix}-athena-results"

  tags = local.tags
}

resource "aws_s3_bucket_public_access_block" "athena_results" {
  bucket                  = aws_s3_bucket.athena_results.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ─── Glue Data Catalog ────────────────────────────────────────────────────────

resource "aws_glue_catalog_database" "farmacia" {
  name        = "${var.turma}_${var.grupo}_farmacia"
  description = "Banco de dados do cenário farmácia online — grupo ${var.grupo}"

  tags = local.tags
}

resource "aws_glue_catalog_table" "itens_pedido" {
  name          = "itens_pedido"
  database_name = aws_glue_catalog_database.farmacia.name
  description   = "Grão: 1 linha = 1 item de pedido"
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    "classification"              = "csv"
    "skip.header.line.count"      = "1"
    "use.null.for.invalid.data"   = "true"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.trusted.bucket}/itens_pedido/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      name                  = "OpenCSVSerde"
      serialization_library = "org.apache.hadoop.hive.serde2.OpenCSVSerde"

      parameters = {
        "separatorChar" = ","
        "quoteChar"     = "\""
        "escapeChar"    = "\\"
      }
    }

    columns {
      name    = "pedido_id"
      type    = "string"
      comment = "Identificador único do pedido"
    }

    columns {
      name    = "item_id"
      type    = "string"
      comment = "Identificador único do item no pedido"
    }

    columns {
      name    = "produto_nome"
      type    = "string"
      comment = "Nome do produto"
    }

    columns {
      name    = "categoria"
      type    = "string"
      comment = "Categoria do produto: medicamentos, higiene, dermocosmeticos, vitaminas, equipamentos"
    }

    columns {
      name    = "quantidade"
      type    = "int"
      comment = "Quantidade de unidades do item"
    }

    columns {
      name    = "preco_unitario"
      type    = "double"
      comment = "Preço unitário do produto em BRL"
    }

    columns {
      name    = "data_pedido"
      type    = "string"
      comment = "Data do pedido no formato YYYY-MM-DD"
    }

    columns {
      name    = "status_pagamento"
      type    = "string"
      comment = "Status do pagamento: pago, pendente, cancelado"
    }

    columns {
      name    = "cliente_id"
      type    = "string"
      comment = "Identificador único do cliente"
    }
  }
}

# ─── Athena Workgroup ─────────────────────────────────────────────────────────

resource "aws_athena_workgroup" "main" {
  name        = "${local.prefix}-workgroup"
  description = "Workgroup do grupo ${var.grupo} — cenário farmácia online"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results.bucket}/query-results/"
    }
  }

  tags = local.tags
}
