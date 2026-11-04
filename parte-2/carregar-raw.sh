#!/usr/bin/env bash
# Uso: ./carregar-raw.sh            (rode da raiz do pacote, depois do terraform apply)
# Gera 30 dias de corridas (seed 42), copia para a raw do bucket do grupo,
# depois simula dois problemas do Exercício 05:
#   (a) madrugada de D-3 chegando hoje (dado atrasado);
#   (b) arquivo de D-5 reenviado (duplicata).
set -euo pipefail
cd "$(dirname "$0")"
REGION=us-east-1
BUCKET="$(terraform -chdir=terraform output -raw bucket_name)"
SAIDA=/tmp/eda-a25

# Aritmética de data portável: macOS usa -v, Linux usa -d
if [ "$(uname)" = "Darwin" ]; then
  HOJE=$(date +%Y-%m-%d)
  D3=$(date -v-3d +%Y-%m-%d)
  D5=$(date -v-5d +%Y-%m-%d)
else
  HOJE=$(date +%Y-%m-%d)
  D3=$(date -d '3 days ago' +%Y-%m-%d)
  D5=$(date -d '5 days ago' +%Y-%m-%d)
fi

echo ">> [1/4] gerando 30 dias de corridas em $SAIDA (seed 42, ~10 s)"
rm -rf "$SAIDA"
python3 app/gerador-eventos.py --dias 30 --taxa 12 --seed 42 --saida "$SAIDA" | sed -n '1,6p'

echo ">> [2/4] copiando para s3://$BUCKET/raw/ (~112 MB; depende da rede)"
aws s3 rm "s3://$BUCKET/raw/" --recursive --region "$REGION" --only-show-errors
aws s3 sync "$SAIDA/raw/" "s3://$BUCKET/raw/" --region "$REGION" --only-show-errors

echo ">> [3/4] simulando dado atrasado: madrugada de $D3 chegando hoje ($HOJE)"
aws s3api copy-object \
  --copy-source "$BUCKET/raw/corridas/dt=$D3/parte-0001.json" \
  --bucket "$BUCKET" \
  --key "raw/corridas/dt=$HOJE/parte-atrasada-d3.json" \
  --region "$REGION" > /dev/null
echo "  copiado dt=$D3/parte-0001.json → dt=$HOJE/parte-atrasada-d3.json"

echo ">> [4/4] simulando reenvio: arquivo de $D5 enviado uma segunda vez"
aws s3api copy-object \
  --copy-source "$BUCKET/raw/corridas/dt=$D5/parte-0001.json" \
  --bucket "$BUCKET" \
  --key "raw/corridas/dt=$D5/parte-reenvio.json" \
  --region "$REGION" > /dev/null
echo "  copiado dt=$D5/parte-0001.json → dt=$D5/parte-reenvio.json"

echo ""
aws s3 ls "s3://$BUCKET/raw/corridas/" --recursive --summarize --region "$REGION" | tail -2
echo "esperado: Total Objects: 32 (30 dias + 1 atrasado + 1 reenvio)"
echo ""
echo "datas relevantes:"
echo "  hoje: $HOJE"
echo "  D-3 (atrasado): $D3"
echo "  D-5 (reenvio):  $D5"
