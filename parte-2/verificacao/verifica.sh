#!/usr/bin/env bash
# =============================================================================
# verifica.sh — Exercício 05 (Aula 25): pipeline idempotente com janela de
# atraso e deduplicação.
# Roda na SUA conta, da raiz do pacote. Imprime PASSA/FALHA por critério.
#
#   ./verificacao/verifica.sh                 # critérios 0 a 4 e 6 (stack no ar, job rodado)
#   ./verificacao/verifica.sh --pos-destroy   # critério 5 (rode depois do destroy)
# =============================================================================
set -uo pipefail

RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
TFDIR="${TFDIR:-$RAIZ/terraform}"
DECISOES="${DECISOES:-$RAIZ/DECISOES.md}"
REGIAO="${AWS_REGION:-us-east-1}"
POS=0; [ "${1:-}" = "--pos-destroy" ] && POS=1

G=$'\e[32m'; R=$'\e[31m'; D=$'\e[2m'; B=$'\e[1m'; X=$'\e[0m'
notas=0; total=0
linha(){ printf '%s\n' "----------------------------------------------------------------"; }
pass(){ notas=$((notas+$2)); total=$((total+$2)); printf "${G}PASSA${X}  [%s]  (%s%%)  %s\n" "$1" "$2" "$3"; }
fail(){ total=$((total+$2)); printf "${R}FALHA${X}  [%s]  (%s%%)  %s\n" "$1" "$2" "$3"; }
info(){ printf "${D}       %s${X}\n" "$1"; }
tfout(){ terraform -chdir="$TFDIR" output -raw "$1" 2>/dev/null; }
tfvar(){ grep -E "^\s*$1\s*=" "$TFDIR/terraform.tfvars" 2>/dev/null | head -1 | sed -E 's/^[^=]*=\s*"?([^"#]*)"?.*/\1/' | xargs; }

athena(){
  local qid estado bytes
  qid="$(aws athena start-query-execution --work-group "$WG" --region "$REGIAO" \
         --query-string "$1" --query QueryExecutionId --output text 2>/dev/null)" \
    || { echo "ERRO 0 -"; return; }
  while true; do
    estado="$(aws athena get-query-execution --query-execution-id "$qid" \
              --region "$REGIAO" --query QueryExecution.Status.State --output text)"
    case "$estado" in SUCCEEDED|FAILED|CANCELLED) break ;; esac
    sleep 2
  done
  bytes="$(aws athena get-query-execution --query-execution-id "$qid" \
           --region "$REGIAO" \
           --query QueryExecution.Statistics.DataScannedInBytes --output text)"
  echo "$estado ${bytes:-0} $qid"
}
resultado(){ aws athena get-query-results --query-execution-id "$1" --region "$REGIAO" \
               --query 'ResultSet.Rows[1:].Data[*].VarCharValue' --output text; }
motivo(){    aws athena get-query-execution --query-execution-id "$1" --region "$REGIAO" \
               --query QueryExecution.Status.StateChangeReason --output text; }
relatorio(){
  aws s3 cp "s3://$BUCKET/relatorios/trusted-parquet.json" - \
    --region "$REGIAO" 2>/dev/null \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('$1',''))" 2>/dev/null \
  || echo ""
}

# ------------------------------------------------------------ pós-destroy -----
if [ "$POS" = "1" ]; then
  echo "${B}Critério 5 — destroy limpo${X}"; linha
  SUF="$(tfvar sufixo)"
  sobra=""
  aws s3api head-bucket --bucket "eda-a25-lake-$SUF"       --region "$REGIAO" >/dev/null 2>&1 && sobra="$sobra bucket"
  aws glue get-job       --job-name "eda-a25-trusted-$SUF"  --region "$REGIAO" >/dev/null 2>&1 && sobra="$sobra job"
  aws glue get-database  --name "eda_a25_$SUF"              --region "$REGIAO" >/dev/null 2>&1 && sobra="$sobra database"
  aws athena get-work-group --work-group "eda-a25-wg-$SUF"  --region "$REGIAO" >/dev/null 2>&1 && sobra="$sobra workgroup"
  aws iam get-role --role-name "eda-a25-glue-$SUF" >/dev/null 2>&1 && sobra="$sobra papel"
  if [ -z "$sobra" ]; then pass "5" 10 "nenhum recurso eda-a25-*-$SUF sobrou."
  else fail "5" 10 "sobrou:$sobra"; fi
  linha; printf "${B}Critério 5: %s/10%%${X}\n" "$notas"; exit 0
fi

echo "${B}Exercício 05 — verificação (região $REGIAO)${X}"; linha

BUCKET="$(tfout bucket_name)"; DB="$(tfout database_name)"; TABELA="$(tfout trusted_table_name)"
WG="$(tfout workgroup_name)"; JOB="$(tfout job_name)"

if [ -z "$BUCKET" ] || [ -z "$TABELA" ] || [ -z "$WG" ]; then
  fail "0" 0 "não li os outputs do Terraform — rodou o terraform apply? (TFDIR=$TFDIR)"; exit 2
fi

# --------------------------------------------- critério 0 (eliminatório) -----
echo "${B}Critério 0 — Terraform com backend remoto, trusted em Parquet (ELIMINATÓRIO)${X}"
if ! grep -rqE 'backend\s+"s3"' "$TFDIR"/*.tf 2>/dev/null; then
  fail "0" 0 "não achei backend \"s3\" — o estado precisa estar no backend remoto."; exit 2
fi
SERDE="$(aws glue get-table --database-name "$DB" --name "$TABELA" --region "$REGIAO" \
         --query Table.StorageDescriptor.SerdeInfo.SerializationLibrary --output text 2>/dev/null)"
if [ "${SERDE##*.}" != "ParquetHiveSerDe" ]; then
  fail "0" 0 "a trusted não está declarada como Parquet (SerDe: ${SERDE:-nenhum})."; exit 2
fi
printf "${G}OK${X}     [0]  backend s3 e trusted em Parquet\n"; linha

# ------------------------------------------ critério 1 (madrugada 11137) -----
echo "${B}Critério 1 — madrugada dos últimos 7 dias = 11.137 corridas${X}"
DESDE="$(python3 -c 'import datetime as d; print(d.date.today() - d.timedelta(days=6))')"
SQL1="SELECT count(*) FROM $DB.$TABELA WHERE dt >= '$DESDE' AND faixa_hora BETWEEN 0 AND 5"
read -r E1 B1 Q1 <<<"$(athena "$SQL1")"
if [ "$E1" = "SUCCEEDED" ]; then
  N1="$(resultado "$Q1")"
  if [ "$N1" = "11137" ]; then
    pass "1" 20 "11.137 corridas na madrugada dos últimos 7 dias."
  else
    fail "1" 20 "achei $N1 corridas (esperado 11137). Verifique DECISÕES 01, 02 e 03."
    info "modo=$(relatorio modo)  chave=$(relatorio chave_dedup)  janela=$(relatorio janela_atraso_dias)"
    info "fora_da_janela=$(relatorio fora_da_janela)  duplicatas=$(relatorio duplicatas_removidas)"
  fi
else fail "1" 20 "a consulta não rodou ($E1): $(motivo "$Q1")"; fi
linha

# ---------------------------------------------- critério 2 (idempotência) -----
echo "${B}Critério 2 — idempotência: segunda execução não muda a contagem${X}"
ANTES="$(relatorio linhas_na_tabela)"
if [ -z "$ANTES" ]; then
  fail "2" 25 "não li o relatório s3://$BUCKET/relatorios/trusted-parquet.json — rodou o job?"
else
  info "contagem antes da segunda execução: $ANTES linhas"
  RUN_ID="$(aws glue start-job-run --job-name "$JOB" --region "$REGIAO" \
             --query JobRunId --output text 2>/dev/null)"
  if [ -z "$RUN_ID" ]; then
    fail "2" 25 "não consegui disparar o job $JOB"
  else
    info "segunda execução disparada: $RUN_ID — aguardando (~3 min)..."
    while true; do
      EST="$(aws glue get-job-run --job-name "$JOB" --run-id "$RUN_ID" \
              --region "$REGIAO" --query JobRun.JobRunState --output text)"
      case "$EST" in SUCCEEDED|FAILED|STOPPED|TIMEOUT|ERROR) break ;; esac
      sleep 20
    done
    if [ "$EST" != "SUCCEEDED" ]; then
      fail "2" 25 "a segunda execução terminou com $EST."
    else
      PROJ="$(aws glue get-table --database-name "$DB" --name "$TABELA" \
              --region "$REGIAO" \
              --query 'Table.Parameters."projection.enabled"' \
              --output text 2>/dev/null)"
      if [ "$PROJ" != "true" ]; then
        QR="$(aws athena start-query-execution --work-group "$WG" --region "$REGIAO" \
               --query-string "MSCK REPAIR TABLE $DB.$TABELA" \
               --query QueryExecutionId --output text 2>/dev/null || true)"
        if [ -n "$QR" ]; then
          while true; do
            ER="$(aws athena get-query-execution --query-execution-id "$QR" \
                  --region "$REGIAO" --query QueryExecution.Status.State --output text 2>/dev/null || echo "FAILED")"
            case "$ER" in SUCCEEDED|FAILED|CANCELLED) break ;; esac
            sleep 3
          done
        fi
      fi
      DEPOIS="$(relatorio linhas_na_tabela)"
      info "contagem depois da segunda execução: $DEPOIS linhas"
      if [ "$ANTES" = "$DEPOIS" ]; then
        pass "2" 25 "idempotente: antes=$ANTES depois=$DEPOIS."
      else
        fail "2" 25 "contagem mudou: antes=$ANTES depois=$DEPOIS — verifique DECISÃO 01 (modo_escrita)."
      fi
    fi
  fi
fi
linha

# ----------------------------------------- critério 3 (518400 sem duplicata) -----
echo "${B}Critério 3 — 518.400 linhas, 518.400 corridas distintas${X}"
SQL3="SELECT count(*) AS total, count(DISTINCT corrida_id) AS distintas FROM $DB.$TABELA"
read -r E3 B3 Q3 <<<"$(athena "$SQL3")"
if [ "$E3" = "SUCCEEDED" ]; then
  read -r TOT DIST <<<"$(resultado "$Q3")"
  if [ "$TOT" = "518400" ] && [ "$DIST" = "518400" ]; then
    pass "3" 15 "518.400 linhas, 518.400 corridas distintas."
  else
    fail "3" 15 "total=$TOT distintas=$DIST (esperado 518400 nos dois)."
    info "duplicatas_removidas=$(relatorio duplicatas_removidas)"
  fi
else fail "3" 15 "a consulta não rodou ($E3): $(motivo "$Q3")"; fi
linha

# -------------------------------------------- critério 4 (state remoto) -----
echo "${B}Critério 4 — state remoto existe no backend S3${X}"
STATE_KEY="$(grep -E '^\s*key\s*=' "$TFDIR/backend.hcl" 2>/dev/null | head -1 | awk -F'"' '{print $2}')"
STATE_BUCKET="$(grep -E '^\s*bucket\s*=' "$TFDIR/backend.hcl" 2>/dev/null | head -1 | awk -F'"' '{print $2}')"
if aws s3api head-object --bucket "$STATE_BUCKET" --key "$STATE_KEY" --region "$REGIAO" >/dev/null 2>&1; then
  pass "4" 10 "state remoto encontrado: s3://$STATE_BUCKET/$STATE_KEY"
else
  fail "4" 10 "state remoto não encontrado em s3://$STATE_BUCKET/$STATE_KEY"
fi
linha

# ---------------------------------------------- critério 6 (decisões) -----
echo "${B}Critério 6 — DECISOES.md (avaliação manual)${X}"
if [ -f "$DECISOES" ]; then
  nd="$(grep -ciE 'DECIS[ÃA]O\s*(0?[1-4])' "$DECISOES" || true)"
  info "encontrei $nd ocorrências de decisão em $DECISOES — avaliado manualmente (20%)."
else
  info "não achei $DECISOES — uma frase por decisão (01 a 04), cada uma com número medido."
fi
linha

echo "${B}Critérios automáticos: $notas / $total pontos-percentuais${X}"
info "faltam critério 5 (./verificacao/verifica.sh --pos-destroy) e 6 (manual)."
echo
echo "${B}Cole no PR:${X}"
echo "  modo=$(relatorio modo)  chave=$(relatorio chave_dedup)  janela=$(relatorio janela_atraso_dias)  linhas=$(relatorio linhas_na_tabela)  fora=$(relatorio fora_da_janela)  dedup=$(relatorio duplicatas_removidas)  criterios_auto=$notas/$total  data=$(date -u +%FT%TZ)"
