# trusted-parquet.py — job Glue do Exercício 05 (Aula 25).
#
# ENTRADA ....... s3://<bucket>/raw/corridas/dt=AAAA-MM-DD/*.json
#                 o mesmo JSON cru dos Labs 04 e 05: 9 campos, ~1,5% dos `valor` como "17,82".
#                 Dois problemas intencionais no cru:
#                   (a) madrugada de D-3 chegou hoje (dado atrasado);
#                   (b) arquivo de D-5 enviado duas vezes (duplicata).
# PROCESSAMENTO . lê a raw com schema declarado, filtra eventos fora da janela de atraso
#                 (DECISÃO 03), deduplica por chave (DECISÃO 02) e grava a trusted
#                 em Parquet + Snappy, com modo de escrita escolhido (DECISÃO 01).
# SAÍDA ......... s3://<bucket>/trusted/corridas/dt=AAAA-MM-DD/part-*.snappy.parquet
#                 + s3://<bucket>/relatorios/trusted-parquet.json (conferência).
#
# A tabela NÃO é criada aqui: está declarada no Terraform (aws_glue_catalog_table).
# O job só grava os arquivos. Rodar de novo com modo=sobrescrever não duplica.

import json
import sys

from pyspark.sql import functions as F
from pyspark.sql import types as T

SCHEMA_RAW = T.StructType([
    T.StructField("corrida_id",    T.StringType()),
    T.StructField("motorista_id",  T.StringType()),
    T.StructField("passageiro_id", T.StringType()),
    T.StructField("bairro",        T.StringType()),
    T.StructField("data_corrida",  T.StringType()),
    T.StructField("fim",           T.StringType()),
    T.StructField("distancia_km",  T.DoubleType()),
    T.StructField("duracao_min",   T.DoubleType()),
    T.StructField("valor",         T.StringType()),
])


def transformar(df):
    """Tipagem, campos derivados e coluna dt (partição da trusted = data do evento)."""
    inicio = F.to_timestamp(F.col("data_corrida"))
    return df.select(
        "corrida_id", "motorista_id", "passageiro_id", "bairro",
        inicio.alias("inicio"),
        F.to_timestamp(F.col("fim")).alias("fim"),
        "distancia_km", "duracao_min",
        F.regexp_replace(F.col("valor"), ",", ".").cast("double").alias("valor"),
        F.hour(inicio).alias("faixa_hora"),
        F.date_format(F.to_date(F.col("data_corrida")), "yyyy-MM-dd").alias("dt"),
    )


def gravar(df, destino, chaves, arquivos_por_pasta, modo_spark):
    """Grava em Parquet + Snappy, particionado por `chaves`, com o modo escolhido."""
    df = df.repartition(*[F.col(c) for c in chaves])
    escrita = df.write.mode(modo_spark).partitionBy(*chaves).option("compression", "snappy")
    if arquivos_por_pasta > 1:
        maior = df.groupBy(*chaves).count().agg(F.max("count")).first()[0]
        escrita = escrita.option("maxRecordsPerFile", -(-maior // arquivos_por_pasta))
    escrita.parquet(destino)


def main():
    import boto3
    from awsglue.context import GlueContext
    from awsglue.utils import getResolvedOptions
    from pyspark.context import SparkContext

    args = getResolvedOptions(
        sys.argv,
        ["BUCKET", "CHAVES", "ARQUIVOS_POR_PASTA", "MODO", "CHAVE", "JANELA"],
    )
    bucket           = args["BUCKET"]
    chaves           = [c.strip() for c in args["CHAVES"].split(",") if c.strip()]
    arquivos         = int(args["ARQUIVOS_POR_PASTA"])
    modo             = args["MODO"]          # "sobrescrever" ou "append"
    chave_dedup      = args["CHAVE"]         # "corrida_id" ou "nenhuma"
    janela           = int(args["JANELA"])   # 0–7 dias

    modo_spark = "overwrite" if modo == "sobrescrever" else "append"

    if chaves[0] != "dt":
        raise ValueError("a primeira chave de partição precisa ser dt")

    sc    = SparkContext.getOrCreate()
    spark = GlueContext(sc).spark_session
    spark.conf.set("spark.sql.session.timeZone", "UTC")
    spark.conf.set("spark.sql.sources.partitionColumnTypeInference.enabled", "false")

    # Lê o cru; o Spark injeta a coluna de partição como "dt" → renomeia para dt_chegada
    raw = (
        spark.read.schema(SCHEMA_RAW).json(f"s3://{bucket}/raw/corridas/")
        .withColumnRenamed("dt", "dt_chegada")
    )
    linhas_raw = raw.count()

    # Calcula atraso: dias entre a data de chegada e a data do evento
    raw = raw.withColumn(
        "lag",
        F.datediff(F.to_date(F.col("dt_chegada")), F.to_date(F.col("data_corrida"))),
    )

    aceito        = raw.filter(F.col("lag") <= janela)
    n_fora        = raw.filter(F.col("lag") >  janela).count()

    # Transforma (dt aqui é a data do evento, usada como partição da trusted)
    trusted = transformar(aceito)

    # Deduplicação opcional
    antes_dedup = trusted.count()
    if chave_dedup != "nenhuma":
        trusted = trusted.dropDuplicates([chave_dedup])
    n_duplicatas = antes_dedup - trusted.count()

    trusted = trusted.cache()

    destino = f"s3://{bucket}/trusted/corridas/"
    gravar(trusted, destino, chaves, arquivos, modo_spark)

    # Conferência: relê a saída e mede arquivos + bytes no S3
    s3 = boto3.client("s3")
    n_arq, n_bytes = 0, 0
    for pagina in s3.get_paginator("list_objects_v2").paginate(
        Bucket=bucket, Prefix="trusted/corridas/"
    ):
        for obj in pagina.get("Contents", []):
            if obj["Key"].endswith(".parquet"):
                n_arq   += 1
                n_bytes += obj["Size"]

    saida           = spark.read.parquet(destino)
    linhas_na_tabela = saida.count()

    relatorio = {
        "modo":               modo,
        "chave_dedup":        chave_dedup,
        "janela_atraso_dias": janela,
        "chaves":             chaves,
        "arquivos_por_pasta": arquivos,
        "linhas_raw":         linhas_raw,
        "fora_da_janela":     n_fora,
        "duplicatas_removidas": n_duplicatas,
        "linhas_na_tabela":   linhas_na_tabela,
        "arquivos":           n_arq,
        "bytes":              n_bytes,
    }
    relatorio["ok"] = (
        relatorio["linhas_na_tabela"] == 518400
        and relatorio["fora_da_janela"] + relatorio["duplicatas_removidas"] + relatorio["linhas_na_tabela"] == linhas_raw
    )
    texto = json.dumps(relatorio, indent=2)
    print(texto)
    s3.put_object(
        Bucket=bucket,
        Key="relatorios/trusted-parquet.json",
        Body=texto.encode("utf-8"),
        ContentType="application/json",
    )
    if not relatorio["ok"]:
        raise RuntimeError("conferência falhou: " + texto)


if __name__ == "__main__":
    main()
