locals {
  nome   = "eda-a29-${var.sufixo}"
  bucket = "eda-a29-lake-${var.sufixo}"
  banco  = "eda_a29_${var.sufixo}"
  perfis = toset(["prefeitura", "analista"])
  # partition projection: o Athena calcula as pastas dt= por regra (Exercício 04)
  projecao = {
    "projection.enabled"          = "true"
    "projection.dt.type"          = "date"
    "projection.dt.format"        = "yyyy-MM-dd"
    "projection.dt.range"         = "NOW-60DAYS,NOW+1DAYS"
    "projection.dt.interval"      = "1"
    "projection.dt.interval.unit" = "DAYS"
  }
  colunas_raw = [
    ["corrida_id", "string"], ["motorista_id", "string"], ["passageiro_id", "string"], ["bairro", "string"],
    ["data_corrida", "string"], ["fim", "string"], ["distancia_km", "double"], ["duracao_min", "double"],
    ["valor", "string"],
  ]
  colunas_trusted = [
    ["corrida_id", "string"], ["motorista_id", "string"], ["passageiro_id", "string"], ["bairro", "string"],
    ["inicio", "timestamp"], ["fim", "timestamp"], ["distancia_km", "double"], ["duracao_min", "double"],
    ["valor", "double"], ["faixa_hora", "int"], ["chegada", "string"],
  ]
  parquet = {
    input  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"
    serde  = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
  }
}

data "aws_caller_identity" "eu" {}

# ------------------------------------------------------------------ 1. as três camadas
resource "aws_s3_bucket" "lake" {
  bucket        = local.bucket
  force_destroy = true
}

resource "aws_glue_catalog_database" "camada" {
  for_each     = toset(["raw", "trusted", "refined"])
  name         = "${local.banco}_${each.key}"
  location_uri = "s3://${aws_s3_bucket.lake.id}/${each.key}/"
}

# A conta é compartilhada. O criador do database pode remover o acesso padrão no
# próprio database. A API do Glue aceita uma lista vazia para os grants das novas
# tabelas, que o provider AWS 5 não envia pelo bloco create_table_default_permission.
resource "terraform_data" "permissoes_camada" {
  for_each = aws_glue_catalog_database.camada
  input    = each.value.name

  lifecycle {
    replace_triggered_by = [aws_glue_catalog_database.camada[each.key]]
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    environment = {
      AWS_DEFAULT_REGION = var.regiao
      AWS_PAGER          = ""
      DATABASE           = each.value.name
      DATABASE_INPUT = jsonencode({
        Name                          = each.value.name
        LocationUri                   = each.value.location_uri
        CreateTableDefaultPermissions = []
      })
      LF_RESOURCE = jsonencode({ Database = { Name = each.value.name } })
    }
    command = <<-EOT
      set -euo pipefail
      aws glue update-database --name "$DATABASE" --database-input "$DATABASE_INPUT"
      principal=DataLakePrincipalIdentifier=IAM_ALLOWED_PRINCIPALS
      permissoes=$(aws lakeformation list-permissions --principal "$principal" \
        --resource "$LF_RESOURCE" --query 'PrincipalResourcePermissions[].Permissions[]' --output text)
      if [[ "$permissoes" == ALL ]]; then
        aws lakeformation revoke-permissions --principal "$principal" --resource "$LF_RESOURCE" --permissions ALL
      fi
    EOT
  }
}

resource "aws_glue_catalog_table" "raw" {
  name          = "corridas"
  database_name = terraform_data.permissoes_camada["raw"].output
  description   = "Corridas como o export mandou. dt = dia em que o arquivo chegou."
  table_type    = "EXTERNAL_TABLE"
  parameters = merge(local.projecao, {
    "classification"            = "json"
    "storage.location.template" = "s3://${local.bucket}/raw/corridas/dt=$${dt}/"
  })
  partition_keys {
    name = "dt"
    type = "string"
  }
  storage_descriptor {
    location      = "s3://${local.bucket}/raw/corridas/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"
    ser_de_info {
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"
    }
    dynamic "columns" {
      for_each = local.colunas_raw
      content {
        name = columns.value[0]
        type = columns.value[1]
      }
    }
  }
}

resource "aws_glue_catalog_table" "trusted" {
  name          = "corridas"
  database_name = terraform_data.permissoes_camada["trusted"].output
  description   = "Uma linha por corrida, limpa e tipada. dt = dia em que a corrida aconteceu."
  table_type    = "EXTERNAL_TABLE"
  parameters = merge(local.projecao, {
    "classification"            = "parquet"
    "storage.location.template" = "s3://${local.bucket}/trusted/corridas/dt=$${dt}/"
  })
  partition_keys {
    name = "dt"
    type = "string"
  }
  storage_descriptor {
    location      = "s3://${local.bucket}/trusted/corridas/"
    input_format  = local.parquet.input
    output_format = local.parquet.output
    ser_de_info {
      serialization_library = local.parquet.serde
    }
    dynamic "columns" {
      for_each = local.colunas_trusted
      content {
        name = columns.value[0]
        type = columns.value[1]
      }
    }
  }
}

# A refined: a resposta pronta, sem id. DECISÃO 03: o contrato dela no catálogo.
resource "aws_glue_catalog_table" "refined" {
  name          = "madrugada_bairro"
  database_name = terraform_data.permissoes_camada["refined"].output
  # DECISÃO 03 — o contrato. Ligue a descrição, o dono, a atualização e os três comentários
  # às partes de var.contrato_refined (variables.tf). O verifica.sh lê tudo isso no catálogo.
  description = var.contrato_refined.descricao
  table_type  = "EXTERNAL_TABLE"
  parameters = merge(local.projecao, {
    "classification"            = "parquet"
    "storage.location.template" = "s3://${local.bucket}/refined/madrugada_bairro/dt=$${dt}/"
    "dono"                      = var.contrato_refined.dono
    "grao"                      = "uma linha por bairro e dia"
    "atualizacao"               = var.contrato_refined.atualizacao
  })
  partition_keys {
    name    = "dt"
    type    = "string"
    comment = "dia em que as corridas aconteceram (AAAA-MM-DD)"
  }
  storage_descriptor {
    location      = "s3://${local.bucket}/refined/madrugada_bairro/"
    input_format  = local.parquet.input
    output_format = local.parquet.output
    ser_de_info {
      serialization_library = local.parquet.serde
    }
    columns {
      name    = "bairro"
      type    = "string"
      comment = var.contrato_refined.comentarios.bairro
    }
    columns {
      name    = "corridas"
      type    = "bigint"
      comment = var.contrato_refined.comentarios.corridas
    }
    columns {
      name    = "receita"
      type    = "double"
      comment = var.contrato_refined.comentarios.receita
    }
  }
}

# ------------------------------------------------------------------ 2. os dois jobs
# O papel dos jobs: lê e escreve só neste bucket, direto no S3 (o job não passa pelo catálogo).
resource "aws_iam_role" "job" {
  name = "${local.nome}-glue"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "glue.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role_policy_attachment" "glue" {
  role       = aws_iam_role.job.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy" "bucket" {
  name = "bucket-rw"
  role = aws_iam_role.job.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
      Resource = [aws_s3_bucket.lake.arn, "${aws_s3_bucket.lake.arn}/*"]
    }]
  })
}

resource "aws_s3_object" "script" {
  for_each = toset(["pipeline-corridas.py", "refinar-madrugada.py"])
  bucket   = aws_s3_bucket.lake.id
  key      = "scripts/${each.key}"
  source   = "${path.module}/scripts/${each.key}"
  etag     = filemd5("${path.module}/scripts/${each.key}")
}

# raw -> trusted: o job do Exercício 05, com as decisões do gabarito dele.
resource "aws_glue_job" "trusted" {
  name              = "${local.nome}-trusted"
  role_arn          = aws_iam_role.job.arn
  glue_version      = "4.0"
  worker_type       = "G.1X"
  number_of_workers = 2
  timeout           = 15
  max_retries       = 0
  command {
    name            = "glueetl"
    python_version  = "3"
    script_location = "s3://${aws_s3_bucket.lake.id}/${aws_s3_object.script["pipeline-corridas.py"].key}"
  }
  default_arguments = {
    "--BUCKET"              = aws_s3_bucket.lake.id
    "--TABELA"              = "corridas"
    "--MODO"                = "sobrescrever"
    "--CHAVE"               = "corrida_id"
    "--JANELA"              = "3"
    "--DIAS"                = "todos"
    "--job-language"        = "python"
    "--job-bookmark-option" = "job-bookmark-disable"
  }
}

# trusted -> refined: a madrugada por bairro e dia, sem nenhum id.
resource "aws_glue_job" "refined" {
  name              = "${local.nome}-refined"
  role_arn          = aws_iam_role.job.arn
  glue_version      = "4.0"
  worker_type       = "G.1X"
  number_of_workers = 2
  timeout           = 15
  max_retries       = 0
  command {
    name            = "glueetl"
    python_version  = "3"
    script_location = "s3://${aws_s3_bucket.lake.id}/${aws_s3_object.script["refinar-madrugada.py"].key}"
  }
  default_arguments = {
    "--BUCKET"              = aws_s3_bucket.lake.id
    "--DIAS"                = "todos"
    "--job-language"        = "python"
    "--job-bookmark-option" = "job-bookmark-disable"
  }
}

moved {
  from = aws_athena_workgroup.wg
  to   = aws_athena_workgroup.wg["prefeitura"]
}

# Cada perfil tem seu próprio histórico de consultas e prefixo de resultados.
resource "aws_athena_workgroup" "wg" {
  for_each      = local.perfis
  name          = each.key == "prefeitura" ? "${local.nome}-wg" : "${local.nome}-wg-analista"
  force_destroy = true
  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = false
    bytes_scanned_cutoff_per_query     = 209715200
    result_configuration {
      output_location = "s3://${aws_s3_bucket.lake.id}/athena-results/${each.key}/"
    }
  }
}

# ------------------------------------------------------------------ 3. o Lake Formation responde pelas pastas
# O papel que o Lake Formation assume para ler, em nome de quem consulta, as pastas registradas.
resource "aws_iam_role" "lf" {
  name = "${local.nome}-lf"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "lakeformation.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role_policy" "lf" {
  name = "camadas-rw"
  role = aws_iam_role.lf.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
      Resource = [for c in ["raw", "trusted", "refined"] : "${aws_s3_bucket.lake.arn}/${c}/*"] },
      { Effect = "Allow", Action = ["s3:ListBucket"], Resource = [aws_s3_bucket.lake.arn] },
    ]
  })
}

resource "aws_lakeformation_resource" "camada" {
  for_each   = toset(["raw", "trusted", "refined"])
  arn        = "${aws_s3_bucket.lake.arn}/${each.key}"
  role_arn   = aws_iam_role.lf.arn
  depends_on = [aws_iam_role_policy.lf, terraform_data.permissoes_camada]
}

# ------------------------------------------------------------------ 4. os dois perfis de consumo
# O IAM dá acesso ao workgroup e resultados do próprio perfil, ao catálogo do grupo
# e às credenciais do Lake Formation.
moved {
  from = aws_iam_policy.consumo
  to   = aws_iam_policy.consumo["prefeitura"]
}

resource "aws_iam_policy" "consumo" {
  for_each = local.perfis
  name     = each.key == "prefeitura" ? "${local.nome}-consumo" : "${local.nome}-consumo-analista"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["athena:StartQueryExecution", "athena:GetQueryExecution", "athena:GetQueryResults", "athena:StopQueryExecution", "athena:GetWorkGroup"],
      Resource = [aws_athena_workgroup.wg[each.key].arn] },
      { Effect = "Allow", Action = ["glue:GetDatabase", "glue:GetDatabases", "glue:GetTable", "glue:GetTables", "glue:GetPartition", "glue:GetPartitions"],
        Resource = concat(
          ["arn:aws:glue:${var.regiao}:${data.aws_caller_identity.eu.account_id}:catalog"],
          [for db in aws_glue_catalog_database.camada : db.arn],
          [for db in aws_glue_catalog_database.camada : "arn:aws:glue:${var.regiao}:${data.aws_caller_identity.eu.account_id}:table/${db.name}/*"],
      ) },
      { Effect = "Allow", Action = ["lakeformation:GetDataAccess"], Resource = ["*"] },
      { Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject", "s3:AbortMultipartUpload"],
      Resource = ["${aws_s3_bucket.lake.arn}/athena-results/${each.key}/*"] },
      { Effect = "Allow", Action = ["s3:GetBucketLocation"], Resource = [aws_s3_bucket.lake.arn] },
      { Effect = "Allow", Action = ["s3:ListBucket"], Resource = [aws_s3_bucket.lake.arn],
      Condition = { StringLike = { "s3:prefix" = ["athena-results/${each.key}/*", "athena-results/${each.key}"] } } },
    ]
  })
}

resource "aws_iam_role" "perfil" {
  for_each = local.perfis
  name     = "${local.nome}-${each.key}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.eu.account_id}:root" },
    Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role_policy_attachment" "perfil" {
  for_each   = aws_iam_role.perfil
  role       = each.value.name
  policy_arn = aws_iam_policy.consumo[each.key].arn
}

# ------------------------------------------------------------------ 5. permissão por camada
#                  raw    trusted                  refined
#   prefeitura      -        -                     lê (DECISÃO 01: o banco ou a tabela)
#   analista        -     lê, menos as colunas      lê
#                         da DECISÃO 02
resource "aws_lakeformation_permissions" "ver_banco" {
  for_each = {
    "prefeitura-refined" = ["prefeitura", "refined"]
    "analista-trusted"   = ["analista", "trusted"]
    "analista-refined"   = ["analista", "refined"]
  }
  principal   = aws_iam_role.perfil[each.value[0]].arn
  permissions = ["DESCRIBE"]
  database {
    name = terraform_data.permissoes_camada[each.value[1]].output
  }
}

# DECISÃO 01 — o alcance da Prefeitura na refined (var.escopo_prefeitura).
# banco: wildcard = true (todas as tabelas, inclusive as futuras), sem name.
# tabela: name = a madrugada_bairro, sem wildcard. Um dos dois fica null.
resource "aws_lakeformation_permissions" "prefeitura_refined" {
  principal   = aws_iam_role.perfil["prefeitura"].arn
  permissions = ["SELECT", "DESCRIBE"]
  table {
    database_name = aws_glue_catalog_table.refined.database_name
    name          = var.escopo_prefeitura == "tabela" ? aws_glue_catalog_table.refined.name : null
    wildcard      = var.escopo_prefeitura == "banco" ? true : null
  }
}

resource "aws_lakeformation_permissions" "analista_refined" {
  principal   = aws_iam_role.perfil["analista"].arn
  permissions = ["SELECT", "DESCRIBE"]
  table {
    database_name = aws_glue_catalog_table.refined.database_name
    name          = aws_glue_catalog_table.refined.name
  }
}

# DECISÃO 02 — a analista lê a trusted inteira, menos as colunas da lista.
resource "aws_lakeformation_permissions" "analista_trusted" {
  principal   = aws_iam_role.perfil["analista"].arn
  permissions = ["SELECT"]
  table_with_columns {
    database_name         = aws_glue_catalog_table.trusted.database_name
    name                  = aws_glue_catalog_table.trusted.name
    wildcard              = true
    excluded_column_names = var.colunas_ocultas_analista
  }
}
