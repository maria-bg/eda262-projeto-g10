module "data_lake" {
  source = "./modules/data-lake"

  grupo  = var.grupo
  turma  = var.turma
  region = var.region
}
