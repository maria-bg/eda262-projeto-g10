variable "regiao" {
  type    = string
  default = "us-east-1"
}

variable "turma" {
  type        = string
  description = "Identificador da turma (vai na tag Turma)."
}

variable "owner" {
  type        = string
  description = "E-mail de quem responde pela stack (vai na tag Owner)."
}

variable "sufixo" {
  type        = string
  description = "Sufixo unico do grupo: so minusculas e numeros (o Glue nao aceita hifen)."
  validation {
    condition     = can(regex("^[a-z0-9]+$", var.sufixo))
    error_message = "Use apenas letras minusculas e numeros."
  }
}

# DECISÃO 01 — a chave de partição da trusted. A primeira chave é sempre dt.
variable "chaves_particao" {
  type = list(string)
  validation {
    condition     = try(var.chaves_particao[0], "") == "dt"
    error_message = "A primeira chave precisa ser dt: a pergunta filtra por data."
  }
}

# DECISÃO 02 — quantos arquivos por pasta de partição (1 a 4).
variable "arquivos_por_pasta" {
  type = number
  validation {
    condition     = var.arquivos_por_pasta >= 1 && var.arquivos_por_pasta <= 4
    error_message = "Entre 1 e 4 arquivos por pasta."
  }
}

# DECISÃO 03 (exercício 04) — a META de custo da pergunta da madrugada, em bytes.
variable "meta_bytes_madrugada" {
  type = number
  validation {
    condition     = var.meta_bytes_madrugada > 0 && var.meta_bytes_madrugada <= 1048576
    error_message = "A meta tem de caber em 1 MiB (1.048.576 bytes)."
  }
}

# DECISÃO 04 (exercício 04) — o TETO do workgroup, em bytes.
variable "teto_bytes" {
  type = number
  validation {
    condition     = var.teto_bytes >= 10485760
    error_message = "O Athena recusa teto abaixo de 10 MiB (10.485.760 bytes)."
  }
}

# DECISÃO 01 (exercício 05) — modo de escrita na trusted.
variable "modo_escrita" {
  type        = string
  description = "Como o job grava a trusted: sobrescrever (overwrite) ou append."
  validation {
    condition     = contains(["sobrescrever", "append"], var.modo_escrita)
    error_message = "Use sobrescrever ou append."
  }
}

# DECISÃO 02 (exercício 05) — chave de deduplicação.
variable "chave_dedup" {
  type        = string
  description = "Coluna usada para deduplicar antes de gravar. Use corrida_id ou nenhuma."
  validation {
    condition     = contains(["corrida_id", "nenhuma"], var.chave_dedup)
    error_message = "Use corrida_id ou nenhuma."
  }
}

# DECISÃO 03 (exercício 05) — janela de atraso em dias.
variable "janela_atraso_dias" {
  type        = number
  description = "Máximo de dias que um evento pode chegar atrasado (0-7)."
  validation {
    condition     = var.janela_atraso_dias >= 0 && var.janela_atraso_dias <= 7
    error_message = "Entre 0 e 7 dias."
  }
}
