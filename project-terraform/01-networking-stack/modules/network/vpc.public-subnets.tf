# Subnets publicas, uma por AZ (ADR-0001 §6). Custo US$ 0,00.
#
# 10.0.0.0/26 em us-east-1a e 10.0.0.64/26 em us-east-1b, com 59 IPs utilizaveis
# cada (64 - 5 reservados pela AWS). Os valores concretos vivem em
# terraform.tfvars da raiz; aqui so ha referencia a variavel.
#
# map_public_ip_on_launch = true e habilitacao, nao exposicao (ADR-0001 §9): quem
# controla o acesso e o Security Group da aplicacao, que pertence ao ADR de
# compute. Nenhum recurso com IP publico e criado por este modulo.
#
# O sufixo do Name (`1a`, `1b`) sai dos dois ultimos caracteres do nome da AZ, e
# nao de literal, para respeitar o criterio de aceite do §14: nenhum CIDR, AZ,
# nome ou ARN hardcoded dentro de modules/network.

resource "aws_subnet" "public" {
  count = length(var.availability_zones)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidr_blocks[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-${var.environment}-subnet-public-${substr(var.availability_zones[count.index], -2, -1)}"
  }
}
