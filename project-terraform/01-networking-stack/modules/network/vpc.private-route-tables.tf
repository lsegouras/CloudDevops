# Route tables privadas, uma por AZ (ADR-0001 §6). Custo US$ 0,00.
#
# Uma RT por AZ mesmo existindo um unico NAT Gateway compartilhado. Route table
# nao custa nada, e ter duas mantem barata tanto a migracao para um NAT por AZ
# quanto a troca para a Opcao D do ADR-0001 §4 (rota apontando para a ENI de uma
# NAT instance) — nos dois casos muda so o alvo da rota, nao a estrutura. Com uma
# RT compartilhada, qualquer uma dessas mudancas exigiria redesenhar o modulo.
#
# ESTADO BASE (enable_nat_gateway = false): as duas RTs existem, estao associadas
# as suas subnets e NAO tem rota default. E isso que torna a subnet privada de
# fato privada com a janela de custo fechada — sem rota para 0.0.0.0/0 nao ha
# saida, e sem rota de entrada nao ha alcance de fora. O trafego interno da VPC
# continua funcionando pela rota `local` implicita, que a AWS cria sozinha e o
# provider nao gerencia.

resource "aws_route_table" "private" {
  count = length(var.availability_zones)

  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.project_name}-${var.environment}-rt-private-${substr(var.availability_zones[count.index], -2, -1)}"
  }
}

# Associacao 1:1 com a subnet privada da mesma AZ — o indice e o mesmo nas duas
# listas porque ambas sao derivadas de var.availability_zones, na mesma ordem.
resource "aws_route_table_association" "private" {
  count = length(var.availability_zones)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# Rota de egress — CONDICIONAL. E o terceiro item que enable_nat_gateway
# controla, alem do EIP e do proprio NAT (ADR-0001 §15, ponto 1). Esquecer estas
# rotas nao geraria custo, geraria subnet privada sem saida com o NAT ligado e
# pago: o pior dos dois mundos.
#
# As DUAS route tables apontam para o MESMO NAT Gateway, que vive na AZ de
# var.nat_gateway_az. O trafego originado na outra AZ atravessa a fronteira de AZ
# para sair — e exatamente o que o passo 12 do ADR-0001 §7 vai comprovar, subindo
# a instancia de teste na AZ b. E tambem o SPOF aceito em R1.
#
# Estes sao 2 dos 4 recursos que o criterio de aceite do §14 espera ver em
# `plan -var="enable_nat_gateway=true"`; os outros 2 estao em vpc.nat-gateway.tf.
resource "aws_route" "private" {
  count = var.enable_nat_gateway ? length(var.availability_zones) : 0

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[0].id
}
