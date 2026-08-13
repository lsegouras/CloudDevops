# ADR-0001 §8 — composicao raiz -> module. O module e implementado nas etapas 2 a 4;
# ate la esta chamada nao resolve e `terraform init` falha por modulo ausente.
#
# Nenhum literal de ambiente (CIDR, AZ, nome, flag) e passado aqui: tudo vem de
# variables.tf com valores em terraform.tfvars.

module "network" {
  source = "./modules/network"

  project_name = var.project_name
  environment  = var.environment

  vpc_cidr_block             = var.vpc_cidr_block
  availability_zones         = var.availability_zones
  public_subnet_cidr_blocks  = var.public_subnet_cidr_blocks
  private_subnet_cidr_blocks = var.private_subnet_cidr_blocks

  nat_gateway_az              = var.nat_gateway_az
  enable_nat_gateway          = var.enable_nat_gateway
  enable_flow_logs            = var.enable_flow_logs
  flow_logs_retention_in_days = var.flow_logs_retention_in_days
}
