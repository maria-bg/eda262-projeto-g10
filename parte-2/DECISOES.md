# DECISOES.md — Parte 2 / Exercício 04 (Aula 21)

Primeiro incremento da AV2. As configurações declaradas representam as decisões tomadas para o laboratório, enquanto os valores apresentados nas decisões abaixo foram obtidos durante a execução real na AWS.

**DECISÃO 01 — chave de partição.** Escolhi `dt` porque a pergunta da madrugada filtra diretamente essa chave e permite partition pruning. Dessa forma, aceito ler as colunas necessárias de todos os bairros nos dias selecionados, evitando consultar partições fora da janela. Na consulta oficial de 7 dias foram acessadas 7 partições e 7 arquivos, um arquivo por dia.

**DECISÃO 02 — arquivos por pasta.** Escolhi 1 arquivo por pasta para reduzir a quantidade de arquivos pequenos, rodapés e requisições ao S3, aceitando menor paralelismo neste volume. Após a execução, foram gerados 30 arquivos Parquet, totalizando 18.143.089 bytes, com tamanho médio de 604.769,63 bytes por arquivo. O menor arquivo possui 603.763 bytes e o maior 605.934 bytes. Na janela de 7 dias, os rodapés dos 7 arquivos somaram 14.602 bytes.

**DECISÃO 03 — a meta de custo.** Declarei inicialmente 524.288 bytes (512 KiB), usando como referência os aproximadamente 0,4 MB apresentados pelo professor no Lab 05 e mantendo a meta abaixo de 1 MiB. Na execução real, a pergunta da madrugada leu 355.803 bytes no Athena, ficando dentro da meta declarada. A consulta retornou 22 bairros e somou 11.137 corridas, conforme o resultado esperado.

**DECISÃO 04 — o teto do workgroup.** Declarei 10.485.760 bytes (10 MiB), com `enforce_workgroup_configuration = true`, para permitir consultas pequenas e corretamente particionadas e impedir consultas que escaneiem um volume excessivo de dados. A pergunta da madrugada passou lendo 355.803 bytes. Já a consulta ampla foi cancelada ao atingir o limite de 10.485.760 bytes, com o motivo `Bytes scanned limit was exceeded`. O trade-off dessa decisão é que consultas legítimas que precisem ler mais de 10 MiB também serão interrompidas.

**DECISÃO 05 — o registro das partições.** Escolhi `MSCK REPAIR TABLE`, com `projecao = {}` e execução pelo `rodar-job.sh`, por ser uma forma simples de registrar no Glue as partições existentes no S3. Na execução foram registradas 30 partições, e o MSCK levou aproximadamente 4,92 segundos, com 4.508 ms reportados como tempo de execução pelo Athena. Caso uma nova pasta de partição seja adicionada posteriormente, como em um dia 31, será necessário executar novamente o `MSCK REPAIR TABLE` para que ela seja registrada no catálogo.

## Evidências da execução

- A carga raw gerou 30 objetos, totalizando 117.655.606 bytes e 518.400 eventos.
- O Glue Job terminou com status `SUCCEEDED`, processando 518.400 linhas raw e gerando 518.400 linhas trusted em 30 dias.
- Foram produzidos 30 arquivos Parquet, totalizando 18.143.089 bytes.
- A consulta oficial utilizou filtro pela partição `dt`, abriu 7 arquivos, retornou 22 bairros e 11.137 corridas e leu 355.803 bytes.
- Os rodapés dos 7 arquivos Parquet consultados somaram 14.602 bytes.
- A consulta ampla foi cancelada pelo limite do workgroup ao atingir 10.485.760 bytes, com a mensagem `Bytes scanned limit was exceeded`.
- O `MSCK REPAIR TABLE` registrou 30 partições e levou aproximadamente 4,92 segundos.
- O `./verificacao/verifica.sh` atingiu `70 / 70` pontos-percentuais nos critérios automáticos.
- Após a remoção da infraestrutura, a saída de `./verificacao/verifica.sh --pos-destroy` deve ser anexada ao PR como evidência do critério de destroy limpo.