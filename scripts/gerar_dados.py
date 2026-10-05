import csv
import os
import random
import uuid
from datetime import datetime, timedelta

random.seed(42)

CATEGORIAS = ["medicamentos", "higiene", "dermocosmeticos", "vitaminas", "equipamentos"]

PRODUTOS = {
    "medicamentos": [
        "Dipirona 500mg", "Paracetamol 750mg", "Ibuprofeno 600mg",
        "Amoxicilina 500mg", "Omeprazol 20mg",
    ],
    "higiene": [
        "Sabonete Líquido 250ml", "Shampoo Anticaspa 300ml",
        "Fio Dental 50m", "Escova de Dente Macia",
    ],
    "dermocosmeticos": [
        "Protetor Solar FPS 50", "Hidratante Facial 60g",
        "Creme para Mãos 100g", "Sérum Vitamina C 30ml",
    ],
    "vitaminas": [
        "Vitamina C 1g Efervescente", "Ômega 3 1000mg",
        "Vitamina D3 2000UI", "Complexo B 60 cápsulas",
    ],
    "equipamentos": [
        "Termômetro Digital", "Medidor de Pressão Automático",
        "Inalador Nebulizador", "Glicosímetro",
    ],
}

PRECOS = {
    "Dipirona 500mg": 8.90, "Paracetamol 750mg": 7.50, "Ibuprofeno 600mg": 12.30,
    "Amoxicilina 500mg": 18.90, "Omeprazol 20mg": 15.40,
    "Sabonete Líquido 250ml": 9.90, "Shampoo Anticaspa 300ml": 22.50,
    "Fio Dental 50m": 5.80, "Escova de Dente Macia": 8.20,
    "Protetor Solar FPS 50": 45.90, "Hidratante Facial 60g": 32.00,
    "Creme para Mãos 100g": 18.50, "Sérum Vitamina C 30ml": 89.90,
    "Vitamina C 1g Efervescente": 24.90, "Ômega 3 1000mg": 38.90,
    "Vitamina D3 2000UI": 29.90, "Complexo B 60 cápsulas": 19.90,
    "Termômetro Digital": 59.90, "Medidor de Pressão Automático": 189.90,
    "Inalador Nebulizador": 149.90, "Glicosímetro": 79.90,
}


def data_aleatoria():
    dias_atras = random.randint(0, 60)
    return (datetime.now() - timedelta(days=dias_atras)).strftime("%Y-%m-%d")


def gerar_linha_limpa(pedido_id, item_counter):
    categoria = random.choice(CATEGORIAS)
    produto = random.choice(PRODUTOS[categoria])
    return {
        "pedido_id": pedido_id,
        "item_id": f"ITEM-{item_counter:05d}",
        "produto_nome": produto,
        "categoria": categoria,
        "quantidade": random.randint(1, 5),
        "preco_unitario": PRECOS[produto],
        "data_pedido": data_aleatoria(),
        "status_pagamento": random.choice(["pago", "pendente", "cancelado"]),
        "cliente_id": f"CLI-{random.randint(1000, 9999)}",
    }


def introduzir_sujeira(linhas):
    resultado = list(linhas)
    n = len(resultado)

    # ~5% duplicatas
    for _ in range(int(n * 0.05)):
        linha = dict(random.choice(resultado))
        resultado.append(linha)

    # ~3% quantidade negativa ou string
    indices = random.sample(range(len(resultado)), int(n * 0.03))
    for i in indices:
        resultado[i] = dict(resultado[i])
        resultado[i]["quantidade"] = random.choice([-1, -2, "dois", "tres"])

    # ~3% preco_unitario com vírgula ou nulo
    indices = random.sample(range(len(resultado)), int(n * 0.03))
    for i in indices:
        resultado[i] = dict(resultado[i])
        preco = resultado[i]["preco_unitario"]
        resultado[i]["preco_unitario"] = random.choice([
            str(preco).replace(".", ","),
            "",
        ])

    # ~3% data com formato errado DD/MM/YYYY
    indices = random.sample(range(len(resultado)), int(n * 0.03))
    for i in indices:
        resultado[i] = dict(resultado[i])
        data = resultado[i]["data_pedido"]
        try:
            dt = datetime.strptime(data, "%Y-%m-%d")
            resultado[i]["data_pedido"] = dt.strftime("%d/%m/%Y")
        except ValueError:
            pass

    # ~2% categoria com case inconsistente
    indices = random.sample(range(len(resultado)), int(n * 0.02))
    for i in indices:
        resultado[i] = dict(resultado[i])
        resultado[i]["categoria"] = resultado[i]["categoria"].capitalize()

    # ~2% produto_nome como string "null"
    indices = random.sample(range(len(resultado)), int(n * 0.02))
    for i in indices:
        resultado[i] = dict(resultado[i])
        resultado[i]["produto_nome"] = "null"

    random.shuffle(resultado)
    return resultado


def main():
    os.makedirs("dados", exist_ok=True)

    linhas_limpas = []
    item_counter = 1
    pedidos = [f"PED-{i:04d}" for i in range(1, 121)]

    for pedido_id in pedidos:
        num_itens = random.randint(1, 5)
        for _ in range(num_itens):
            linhas_limpas.append(gerar_linha_limpa(pedido_id, item_counter))
            item_counter += 1
        if len(linhas_limpas) >= 500:
            break

    linhas_sujas = introduzir_sujeira(linhas_limpas)

    campos = [
        "pedido_id", "item_id", "produto_nome", "categoria",
        "quantidade", "preco_unitario", "data_pedido",
        "status_pagamento", "cliente_id",
    ]

    caminho = os.path.join("dados", "itens_pedido_raw.csv")
    with open(caminho, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=campos)
        writer.writeheader()
        writer.writerows(linhas_sujas)

    print(f"Arquivo gerado: {caminho} ({len(linhas_sujas)} linhas)")


if __name__ == "__main__":
    main()
