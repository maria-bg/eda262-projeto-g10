# Exercício 06 · Grupo 10

## DECISÃO 01 — o alcance da Prefeitura na refined (`escopo_prefeitura`)

Concedemos à Prefeitura acesso apenas a `madrugada_bairro`, o que exige uma nova concessão para cada tabela futura, e a consulta no Athena como `prefeitura` somou **11.137 corridas** de madrugada nos últimos sete dias da carga.

## DECISÃO 02 — as colunas que a analista não vê (`colunas_ocultas_analista`)

Ocultamos `passageiro_id` e `motorista_id` para a analista, mantendo **9 das 11 colunas de dados**, incluindo `corrida_id` para localizar corridas reclamadas, e no Athena `count(bairro)` retornou **518.400** enquanto as duas consultas aos IDs ocultos foram recusadas.

## DECISÃO 03 — o contrato da refined (`contrato_refined`)

Conferimos no Glue a descrição de **129 caracteres** que documenta o total de corridas e a receita da madrugada por bairro e dia, sem identificadores, com atualização a cada execução do job `refined` após a carga `trusted`, sob responsabilidade da Engenharia de Dados do Grupo 10, e comentários nas quatro colunas, incluindo `dt`.
