#!/usr/bin/env bash
# verificacao/verifica.sh — Script de aceite da AV1
# Uso: ./verificacao/verifica.sh
# Imprime [PASSA] ou [FALHA] para cada critério e retorna exit code 1 se houver falha.

set -euo pipefail

REGION="us-east-1"
TURMA="eda262"
GRUPO="g10"
PREFIX="${TURMA}-${GRUPO}"

TRUSTED_BUCKET="${PREFIX}-lake-trusted"
ATHENA_RESULTS_BUCKET="${PREFIX}-athena-results"
GLUE_DB="${TURMA}_${GRUPO}_farmacia"
GLUE_TABLE="itens_pedido"
WORKGROUP="${PREFIX}-workgroup"

PASSA=0
FALHA=0

check() {
  local desc="$1"
  local result="$2"
  if [ "$result" = "ok" ]; then
    echo "[PASSA] $desc"
    PASSA=$((PASSA + 1))
  else
    echo "[FALHA] $desc — $result"
    FALHA=$((FALHA + 1))
  fi
}

# 1. Bucket trusted existe
if aws s3api head-bucket --bucket "$TRUSTED_BUCKET" --region "$REGION" 2>/dev/null; then
  check "Bucket '$TRUSTED_BUCKET' existe" "ok"
else
  check "Bucket '$TRUSTED_BUCKET' existe" "bucket não encontrado"
fi

# 2. Bucket athena-results existe
if aws s3api head-bucket --bucket "$ATHENA_RESULTS_BUCKET" --region "$REGION" 2>/dev/null; then
  check "Bucket '$ATHENA_RESULTS_BUCKET' existe" "ok"
else
  check "Bucket '$ATHENA_RESULTS_BUCKET' existe" "bucket não encontrado"
fi

# 3. Glue database existe
if aws glue get-database --name "$GLUE_DB" --region "$REGION" >/dev/null 2>&1; then
  check "Glue database '$GLUE_DB' existe" "ok"
else
  check "Glue database '$GLUE_DB' existe" "database não encontrado"
fi

# 4. Glue table itens_pedido existe
if aws glue get-table --database-name "$GLUE_DB" --name "$GLUE_TABLE" --region "$REGION" >/dev/null 2>&1; then
  check "Glue table '$GLUE_TABLE' existe em '$GLUE_DB'" "ok"
else
  check "Glue table '$GLUE_TABLE' existe em '$GLUE_DB'" "tabela não encontrada"
fi

# 5. Athena workgroup existe
if aws athena get-work-group --work-group "$WORKGROUP" --region "$REGION" >/dev/null 2>&1; then
  check "Athena workgroup '$WORKGROUP' existe" "ok"
else
  check "Athena workgroup '$WORKGROUP' existe" "workgroup não encontrado"
fi

# 6. Tag turma no bucket trusted
TAG_TURMA=$(aws s3api get-bucket-tagging --bucket "$TRUSTED_BUCKET" --region "$REGION" 2>/dev/null \
  | python3 -c "import sys,json; tags={t['Key']:t['Value'] for t in json.load(sys.stdin).get('TagSet',[])}; print(tags.get('turma',''))" 2>/dev/null || echo "")
if [ "$TAG_TURMA" = "$TURMA" ]; then
  check "Bucket trusted tem tag turma=$TURMA" "ok"
else
  check "Bucket trusted tem tag turma=$TURMA" "tag turma='$TAG_TURMA' (esperado '$TURMA')"
fi

# 7. Tag grupo no bucket trusted
TAG_GRUPO=$(aws s3api get-bucket-tagging --bucket "$TRUSTED_BUCKET" --region "$REGION" 2>/dev/null \
  | python3 -c "import sys,json; tags={t['Key']:t['Value'] for t in json.load(sys.stdin).get('TagSet',[])}; print(tags.get('grupo',''))" 2>/dev/null || echo "")
if [ "$TAG_GRUPO" = "$GRUPO" ]; then
  check "Bucket trusted tem tag grupo=$GRUPO" "ok"
else
  check "Bucket trusted tem tag grupo=$GRUPO" "tag grupo='$TAG_GRUPO' (esperado '$GRUPO')"
fi

# 8. Tag projeto no bucket trusted
TAG_PROJETO=$(aws s3api get-bucket-tagging --bucket "$TRUSTED_BUCKET" --region "$REGION" 2>/dev/null \
  | python3 -c "import sys,json; tags={t['Key']:t['Value'] for t in json.load(sys.stdin).get('TagSet',[])}; print(tags.get('projeto',''))" 2>/dev/null || echo "")
if [ "$TAG_PROJETO" = "engenharia-de-dados" ]; then
  check "Bucket trusted tem tag projeto=engenharia-de-dados" "ok"
else
  check "Bucket trusted tem tag projeto=engenharia-de-dados" "tag projeto='$TAG_PROJETO'"
fi

# 9. Glue table tem schema com ao menos 9 colunas (não inferida por crawler)
NUM_COLS=$(aws glue get-table --database-name "$GLUE_DB" --name "$GLUE_TABLE" --region "$REGION" 2>/dev/null \
  | python3 -c "import sys,json; t=json.load(sys.stdin); cols=t['Table']['StorageDescriptor']['Columns']; print(len(cols))" 2>/dev/null || echo "0")
if [ "$NUM_COLS" -ge 9 ] 2>/dev/null; then
  check "Glue table tem schema declarado (>= 9 colunas, atual: $NUM_COLS)" "ok"
else
  check "Glue table tem schema declarado (>= 9 colunas)" "encontradas $NUM_COLS colunas"
fi

# 10. Workgroup tem output location configurado
OUTPUT_LOC=$(aws athena get-work-group --work-group "$WORKGROUP" --region "$REGION" 2>/dev/null \
  | python3 -c "import sys,json; wg=json.load(sys.stdin); print(wg['WorkGroup']['Configuration']['ResultConfiguration'].get('OutputLocation',''))" 2>/dev/null || echo "")
if [ -n "$OUTPUT_LOC" ]; then
  check "Workgroup tem output location configurado ($OUTPUT_LOC)" "ok"
else
  check "Workgroup tem output location configurado" "OutputLocation não encontrado"
fi

# Resumo
echo ""
echo "══════════════════════════════════════"
echo "  RESULTADO: $PASSA PASSA  |  $FALHA FALHA"
echo "══════════════════════════════════════"

if [ "$FALHA" -gt 0 ]; then
  exit 1
fi
exit 0
