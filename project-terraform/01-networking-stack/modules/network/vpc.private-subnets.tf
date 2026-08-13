# Subnets privadas, uma por AZ (ADR-0001 §6). Custo US$ 0,00.
#
# 10.0.0.128/26 em us-east-1a e 10.0.0.192/26 em us-east-1b, com 59 IPs
# utilizaveis cada. Somadas as publicas, os quatro /26 preenchem o /24 exatamente
# e a VPC fica 100% alocada — consequencia aceita em ADR-0001 R2.
#
# map_public_ip_on_launch = false e o que torna estas subnets privadas do lado da
# instancia. Do lado da rede, o que garante privacidade e a ausencia de rota de
# entrada: no estado base as route tables privadas (etapa 3) nao tem rota
# default, e o NAT Gateway (etapa 4) so existe quando enable_nat_gateway = true.

resource "aws_subnet" "private" {
  count = length(var.availability_zones)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.private_subnet_cidr_blocks[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.project_name}-${var.environment}-subnet-private-${substr(var.availability_zones[count.index], -2, -1)}"
  }
}
