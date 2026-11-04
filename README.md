# eda262-projeto-g10 — Farmácia Online

Plataforma de dados para análise de pedidos de farmácia online.  
**Grupo:** g10 | **Turma:** eda262 | **Região:** us-east-1

**Pergunta de negócio:**  
> Quais categorias de produto geraram mais receita nos últimos 30 dias, e qual o ticket médio por categoria?

---

## Pré-requisitos

- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) configurado (`aws configure`)
- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5
- Python 3.8+
- Permissões AWS: S3, DynamoDB, Glue, Athena

---

## Passo a passo: deploy

### 1. Bootstrap — criar bucket de state e tabela de locks

```bash
cd bootstrap
terraform init
terraform apply
cd ..
```

Isso cria:
- `eda262-g10-terraform-state` (bucket S3 para o state)
- `eda262-g10-terraform-locks` (tabela DynamoDB para locking)

### 2. Gerar os dados brutos

```bash
cd scripts
python3 gerar_dados.py
cd ..
```

Arquivo gerado: `dados/itens_pedido_raw.csv`

### 3. Upload dos dados para o S3 (camada trusted)

Após o `terraform apply` da parte-1, faça o upload:

```bash
aws s3 cp dados/itens_pedido_raw.csv \
  s3://eda262-g10-lake-trusted/itens_pedido/itens_pedido.csv \
  --region us-east-1
```

### 4. Deploy da infraestrutura — Parte 1

```bash
cd parte-1
terraform init
terraform apply
cd ..
```

Recursos provisionados:
- `eda262-g10-lake-trusted` — bucket S3 da camada trusted
- `eda262-g10-athena-results` — bucket S3 para resultados do Athena
- `eda262_g10_farmacia` — Glue Data Catalog database
- `itens_pedido` — Glue table com schema declarado no IaC
- `eda262-g10-workgroup` — Athena workgroup

---

## Rodar a query de negócio no Athena

No console AWS ou via CLI, execute no workgroup `eda262-g10-workgroup`:

```sql
SELECT
    categoria,
    SUM(CAST(quantidade AS DOUBLE) * CAST(preco_unitario AS DOUBLE)) AS receita_total,
    AVG(CAST(quantidade AS DOUBLE) * CAST(preco_unitario AS DOUBLE)) AS ticket_medio,
    COUNT(DISTINCT pedido_id)                                        AS total_pedidos
FROM "eda262_g10_farmacia"."itens_pedido"
WHERE data_pedido >= DATE_FORMAT(DATE_ADD('day', -30, CURRENT_DATE), '%Y-%m-%d')
GROUP BY categoria
ORDER BY receita_total DESC;
```

Após rodar, anote o custo (MB escaneados) e preencha o campo **Custo da consulta** no `DECISOES.md`.

---

## Rodar o script de verificação

```bash
chmod +x verificacao/verifica.sh
./verificacao/verifica.sh
```

Todos os critérios devem imprimir `[PASSA]`.

---

## Destroy — remover toda a infraestrutura

**Importante:** destruir na ordem inversa para não deixar recurso órfão.

### 1. Remover dados do bucket trusted (S3 não destrói bucket com objetos)

```bash
aws s3 rm s3://eda262-g10-lake-trusted --recursive --region us-east-1
aws s3 rm s3://eda262-g10-athena-results --recursive --region us-east-1
```

### 2. Destroy da parte-1

```bash
cd parte-1
terraform destroy
cd ..
```

### 3. Destroy do bootstrap

```bash
aws s3 rm s3://eda262-g10-terraform-state --recursive --region us-east-1
cd bootstrap
terraform destroy
cd ..
```

---

## Configuração de conta

| Parâmetro | Valor |
|-----------|-------|
| Região | `us-east-1` |
| State bucket | `eda262-g10-terraform-state` |
| Lock table | `eda262-g10-terraform-locks` |
| State key | `parte-1/terraform.tfstate` |

### Parte 2 — Trusted em Parquet particionado

O Lab 21 (`parte-2/`) é o primeiro incremento da AV2, independente dos recursos
da Parte 1: corridas em Parquet + Snappy, particionadas por `dt`.

A implementação utiliza 1 arquivo Parquet por dia, `MSCK REPAIR TABLE` para
registro das partições e WorkGroup do Athena com limite de 10 MiB.

Na validação:
- 518.400 corridas em 30 dias;
- 30 arquivos Parquet;
- consulta de 7 dias lendo 355.803 bytes;
- 11.137 corridas em 22 bairros;
- critérios automáticos: 70/70;
- destroy limpo: 10/10.

Consulte [`parte-2/DECISOES.md`](parte-2/DECISOES.md) para as decisões e medições.
