# Internet Gateway anexado a VPC (ADR-0001 §6). Custo US$ 0,00.
#
# E a dependencia de entrada do NAT Gateway da etapa 4: o NAT so funciona com o
# IGW ja anexado, e por isso o ADR-0001 §15 ponto 3 exige depends_on explicito
# la — nao aqui.

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.project_name}-${var.environment}-igw"
  }
}
