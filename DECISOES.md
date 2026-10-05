# DECISOES.md — Parte 1

## Cenário

**Domínio:** Farmácia online  
**Slug:** `farmacia-online`  
**Grupo:** g10 | **Turma:** eda262

**Pergunta de negócio:**
> Quais categorias de produto geraram mais receita nos últimos 30 dias, e qual o ticket médio por categoria?

---

## Grão

**Grão da tabela `itens_pedido`:** 1 linha = 1 item de pedido

Justificativa: o nível mais atômico de análise é o item — permite agregar por categoria, produto, período e cliente sem perda de informação. Agregar no grão de pedido esconderia a composição por categoria.

---

## Schema da tabela trusted

| Coluna            | Tipo   | Descrição |
|-------------------|--------|-----------|
| `pedido_id`       | string | Identificador único do pedido |
| `item_id`         | string | Identificador único do item no pedido |
| `produto_nome`    | string | Nome do produto |
| `categoria`       | string | Categoria: medicamentos, higiene, dermocosmeticos, vitaminas, equipamentos |
| `quantidade`      | int    | Quantidade de unidades |
| `preco_unitario`  | double | Preço unitário em BRL |
| `data_pedido`     | string | Data do pedido (YYYY-MM-DD) |
| `status_pagamento`| string | Status: pago, pendente, cancelado |
| `cliente_id`      | string | Identificador único do cliente |

**Schema declarado no IaC** via `aws_glue_catalog_table` com OpenCSVSerde — não inferido por Crawler.

---

## Limpeza aplicada (raw → trusted)

| Problema (raw)                          | Tratamento (trusted) |
|-----------------------------------------|----------------------|
| `categoria` com case inconsistente      | `LOWER(categoria)` |
| `quantidade` negativa ou string         | Linhas descartadas |
| `preco_unitario` com vírgula decimal    | `REPLACE(',', '.')` + cast |
| `preco_unitario` nulo ou zero           | Linhas descartadas |
| `data_pedido` em formato DD/MM/AAAA     | Conversão para YYYY-MM-DD |
| `produto_nome` = `"null"` (string)      | Substituído por NULL |
| Linhas duplicadas (mesmo `item_id`)     | Deduplicação por `item_id` |

---

## Por que CSV e não Parquet (AV1)

Parquet está **fora do escopo da AV1** (requisito introduzido na Parte 2). O CSV simplifica o processo de carga manual dos dados nesta entrega e é suportado nativamente pelo OpenCSVSerde no Glue.

---

## Custo da consulta

Consulta executada no Athena workgroup `eda262-g10-workgroup`, região `us-east-1`.

| Métrica | Valor medido |
|---------|-------------|
| Dados escaneados | 34.183 bytes (0,033 MB) |
| Mínimo cobrado por query | 10 MB |
| Custo por consulta | $0,00005 USD (10 MB × $0,000005/MB) |
| Tempo de execução | < 2 s |

Precificação Athena: $5,00 por TB escaneado = $0,000005 por MB. Cada consulta tem mínimo de 10 MB cobrado.

---

## Decisões de nomenclatura

| Item | Nome escolhido | Justificativa |
|------|---------------|---------------|
| Repositório | `eda262-projeto-g10` | Padrão obrigatório do guia |
| Bucket trusted | `eda262-g10-lake-trusted` | Padrão obrigatório do guia |
| Bucket resultados | `eda262-g10-athena-results` | Padrão `eda262-gNN-<recurso>` |
| Glue database | `eda262_g10_farmacia` | Underscores (Glue não aceita hífens em nomes de DB) |
| Glue table | `itens_pedido` | Nome reflete o grão: itens de pedido |
| Athena workgroup | `eda262-g10-workgroup` | Padrão `eda262-gNN-<recurso>` |
| Bucket state | `eda262-g10-terraform-state` | Separado do data lake; criado via bootstrap |
| DynamoDB locks | `eda262-g10-terraform-locks` | Par obrigatório do backend S3 |

---

## Backend remoto e workspace

- **Backend:** S3 (`eda262-g10-terraform-state`) + DynamoDB (`eda262-g10-terraform-locks`) para locking  
- **Workspace:** padrão (`default`) — workspace separado por ambiente está fora do escopo da AV1  
- **Módulo:** toda a infraestrutura encapsulada em `modules/data-lake`, chamado de `parte-1/main.tf`
