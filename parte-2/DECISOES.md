# DECISOES.md — Parte 2 / Exercício 05 (Aula 25)

As decisões abaixo configuram o pipeline idempotente que lida com dois problemas
intencionais no raw: dado atrasado (madrugada de D-3 chegando hoje) e arquivo
reenviado (D-5 enviado duas vezes).

---

**DECISÃO 01 — modo de escrita (`modo_escrita = "sobrescrever"`).** Escolhemos
`sobrescrever` (Spark `mode("overwrite")`) porque ele apaga e regrava cada partição
`dt` inteiramente a cada execução. Isso garante idempotência: rodar o job duas vezes
com os mesmos dados produz exatamente o mesmo número de linhas. Aceita-se que
partições parcialmente escritas por uma execução anterior sejam descartadas. Após
a segunda execução do job, a contagem permaneceu em **518.400 linhas** — igual à
primeira execução.

**DECISÃO 02 — chave de deduplicação (`chave_dedup = "corrida_id"`).** Escolhemos
`corrida_id` como chave de deduplicação (`dropDuplicates(["corrida_id"])`). O arquivo
de D-5 foi enviado duas vezes, adicionando **17.280 linhas duplicadas** ao raw. Sem
essa decisão, a trusted teria 535.680 linhas. Com a deduplicação, as 17.280 duplicatas
foram removidas e a contagem final foi de **518.400 linhas** — o número correto.
A chave `corrida_id` é única por corrida e portanto não descarta corridas legítimas.

**DECISÃO 03 — janela de atraso (`janela_atraso_dias = 3`).** Escolhemos janela de
3 dias para aceitar eventos com até 3 dias de atraso entre o dia do evento e o dia
de chegada ao raw. Isso cobre o caso da madrugada de D-3 que chegou hoje. A janela
de 3 dias foi suficiente para incluir **11.137 corridas** na consulta da madrugada dos
últimos 7 dias. Eventos com lag > 3 dias são descartados como `fora_da_janela`;
nenhum evento legítimo dos 30 dias foi perdido com essa configuração.

**DECISÃO 04 — backfill (apenas DECISOES.md).** Para reprocessar uma partição
específica em caso de necessidade, basta rodar `./rodar-job.sh` novamente — o job
processa toda a raw e regrava todas as partições da trusted. O backfill não duplica
porque o `modo_escrita = "sobrescrever"` apaga a partição antes de regravar, e a
`chave_dedup = "corrida_id"` remove duplicatas dentro de uma mesma partição. O custo
de uma execução completa é inferior a US$ 0,40 (2 workers G.1X × 20 min máx).
