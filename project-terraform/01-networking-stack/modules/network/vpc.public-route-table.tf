# Route table publica, uma so, compartilhada pelas duas subnets publicas
# (ADR-0001 §6). Custo US$ 0,00 — route table, rota e associacao nao sao
# tarifadas.
#
# Uma RT unica para as duas AZs porque o caminho de saida e identico nas duas: o
# Internet Gateway e regional, nao zonal, entao separar por AZ nao traria
# beneficio nenhum. As route tables privadas seguem o criterio oposto e sao uma
# por AZ — ver vpc.private-route-tables.tf e o motivo la.
#
# A rota e um `aws_route` separado em vez de um bloco `route` inline no route
# table. O provider proibe misturar os dois no mesmo recurso ("will cause a
# conflict of rule settings and will overwrite rules"), e as rotas privadas
# PRECISAM ser recursos independentes para poderem ser condicionadas ao NAT.
# Manter os dois lados simetricos evita que alguem acrescente um bloco inline
# aqui mais tarde e sobrescreva a rota sem perceber.

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.project_name}-${var.environment}-rt-public"
  }
}

# 0.0.0.0/0 e a definicao de "rota default", nao um endereco deste ambiente.
# Deixa-lo literal e deliberado e nao conflita com o criterio de aceite do §14
# ("nenhum CIDR hardcoded"), que trata dos CIDRs da VPC e das subnets.
#
# `gateway_id` e o argumento certo para um Internet Gateway. Apontar um NAT aqui
# compila e aplica — a API da AWS aceita —, mas produz diff permanente, porque a
# API devolve o alvo no atributo especifico (`nat_gateway_id`).
resource "aws_route" "public" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

# Uma associacao por subnet publica, todas para a mesma route table. Sem
# associacao explicita a subnet cairia na main route table da VPC, que este
# modulo nao gerencia — o comportamento seria decidido por omissao.
resource "aws_route_table_association" "public" {
  count = length(var.availability_zones)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}
