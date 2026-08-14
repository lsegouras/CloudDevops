# NAT Gateway zonal unico e o Elastic IP dele (ADR-0001 §5, Opcao A).
# CONDICIONAIS: nenhum dos dois existe enquanto enable_nat_gateway = false, que e
# o default e o estado permanente do laboratorio.
#
# ATENCAO — E AQUI QUE MORA 100% DO CUSTO DESTA STACK.
# US$ 0,050/h enquanto existir (NAT US$ 0,045 + IPv4 publico US$ 0,005), mais
# US$ 0,045/GB processado. Uma semana esquecido = 168 h x US$ 0,050 = US$ 8,40,
# ou seja, mais que o teto de US$ 5,00 do curso INTEIRO (ADR-0001 R0).
# Fechar a janela: `terraform apply` sem -var. Nao e `destroy` — ver §13.
#
# O EIP e o NAT usam a MESMA variavel de count, nao duas. E isso que impede o EIP
# orfao de ADR-0001 R6: um EIP alocado e nao anexado custa os mesmos US$ 0,005/h
# de um EIP em uso, entao uma condicao que derrubasse so o NAT deixaria custo
# correndo com nada funcionando — a falha mais silenciosa possivel aqui.

resource "aws_eip" "nat" {
  #checkov:skip=CKV2_AWS_19: o EIP esta anexado a um NAT Gateway via allocation_id, nao a uma instancia EC2 — o check nao modela essa associacao. Nao e EIP orfao: o risco de EIP orfao e o R6 do ADR-0001 e esta mitigado pelo count compartilhado com o NAT, logo abaixo. Supressao autorizada nominalmente por ADR-0002 §5.3.
  count = var.enable_nat_gateway ? 1 : 0

  domain = "vpc"

  tags = {
    Name = "${var.project_name}-${var.environment}-eip-natgw-${substr(var.nat_gateway_az, -2, -1)}"
  }
}

# `depends_on` explicito no IGW: o NAT so consegue rotear com o gateway ja
# anexado a VPC, e essa dependencia nao aparece no grafo sozinha, porque nenhum
# argumento deste recurso referencia o IGW. Exigido por ADR-0001 §15, ponto 3, e
# recomendado pelo proprio provider.
#
# O EIP acima nao leva `depends_on`: a nota do provider sobre EIP precisar do IGW
# vale para EIP associado a `instance` ou `network_interface`, que nao e o caso —
# aqui ele e so uma alocacao, e quem faz a associacao e o NAT, que ja depende.
#
# `subnet_id` resolve a AZ escolhida para o indice da subnet publica
# correspondente, em vez de fixar [0]. Trocar var.nat_gateway_az para a outra AZ
# e a recuperacao prevista em R1 e passa a funcionar sem editar codigo.
resource "aws_nat_gateway" "this" {
  count = var.enable_nat_gateway ? 1 : 0

  allocation_id     = aws_eip.nat[0].id
  subnet_id         = aws_subnet.public[index(var.availability_zones, var.nat_gateway_az)].id
  availability_mode = "zonal"
  connectivity_type = "public"

  tags = {
    Name = "${var.project_name}-${var.environment}-natgw-${substr(var.nat_gateway_az, -2, -1)}"
  }

  depends_on = [aws_internet_gateway.this]
}
