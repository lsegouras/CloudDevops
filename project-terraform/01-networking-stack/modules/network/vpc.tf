# Recurso raiz do dominio de rede (ADR-0001 §6). Este arquivo contem o aws_vpc e
# nada mais, conforme .claude/skills/terraform-naming/SKILL.md.
#
# enable_dns_support e enable_dns_hostnames sao fixados em true por decisao do
# ADR-0001 §6 e cobrados pelo criterio de aceite do §14. Nao sao parametrizados
# porque nao variam por ambiente: o padrao do provider para enable_dns_hostnames
# e false, entao a atribuicao explicita e obrigatoria.

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr_block
  instance_tenancy     = "default"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-${var.environment}-vpc"
  }
}
