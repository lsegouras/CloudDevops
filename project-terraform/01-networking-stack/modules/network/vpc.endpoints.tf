# VPC Endpoints (ADR-0001 §6). Os dois custam US$ 0,00 e sao permanentes: nao ha
# `count` neste arquivo, porque nao ha nada aqui que consuma orcamento.
#
# APENAS Gateway Endpoint. O ADR-0001 §6 descartou explicitamente os Interface
# Endpoints de ECR (`ecr.api` e `ecr.dkr`): dois endpoints em duas AZs custariam
# US$ 0,01/h cada por AZ = US$ 0,04/h, ou US$ 29,20/mes — quase seis vezes o teto
# do curso inteiro, e quase o preco de um NAT Gateway ligado o tempo todo. Se
# aparecer necessidade de acesso privado ao ECR, ela pertence ao ADR de compute,
# nao a este arquivo.

# `region` (nao `name`) e o atributo correto no provider AWS 6.x — `name` e `id`
# estao ambos deprecados neste data source. Verificado via MCP terraform contra a
# versao 6.59.0, a mesma do .terraform.lock.hcl.
#
# A regiao e lida do provider da raiz em vez de virar variavel: `us-east-1`
# literal aqui violaria o criterio de aceite do ADR-0001 §14, que proibe AZ, CIDR,
# nome ou ARN hardcoded dentro de modules/network.
data "aws_region" "current" {}

# Gateway Endpoint de S3 — o unico endpoint gratuito util aqui (ADR-0001 §6).
# Existe por um motivo de custo bem especifico: o ECR guarda as camadas de imagem
# no S3, entao com este endpoint o download pesado de um `docker pull` sai pela
# rede da AWS em vez de atravessar o NAT Gateway a US$ 0,045/GB. E o que sustenta
# a premissa P2 do ADR-0001.
#
# Segundo efeito, que so aparece com a janela de custo fechada: o acesso a S3
# continua funcionando com `enable_nat_gateway = false`, porque o trafego vai pela
# rota de prefix list que a AWS injeta nas route tables associadas, e nao pela
# rota default inexistente.
#
# `vpc_endpoint_type = "Gateway"` e o default do provider, mas vai explicito: e a
# diferenca entre US$ 0,00 e US$ 0,01/h por AZ, cara demais para ficar implicita.
# Confirmado na conta via ec2:DescribeVpcEndpointServices que
# `com.amazonaws.<regiao>.s3` e oferecido nos DOIS tipos, Gateway e Interface —
# omitir o argumento nao daria erro, daria a fatura errada.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"

  tags = {
    Name = "${var.project_name}-${var.environment}-vpce-s3"
  }
}

# Associacao as DUAS route tables privadas (ADR-0001 §15, ponto 4). Uma subnet
# privada so alcanca o endpoint se a route table dela estiver associada; associar
# so a RT da AZ a levaria a AZ b a pagar NAT pelo trafego de S3.
#
# Recurso de associacao separado em vez do argumento `route_table_ids` do proprio
# `aws_vpc_endpoint`: a documentacao do provider adverte que usar os dois caminhos
# para o mesmo endpoint gera conflito de associacao, com uma sobrescrevendo a
# outra. Escolhido o recurso separado porque e o que o ADR-0001 §15 nomeia.
#
# As subnets publicas ficam de fora de proposito: elas saem pelo IGW, que ja e
# gratuito, entao o endpoint nao economizaria nada la.
resource "aws_vpc_endpoint_route_table_association" "s3_private" {
  count = length(var.availability_zones)

  route_table_id  = aws_route_table.private[count.index].id
  vpc_endpoint_id = aws_vpc_endpoint.s3.id
}

# EC2 Instance Connect Endpoint (ADR-0001 §9). Custo US$ 0,00.
#
# E o unico caminho de acesso a uma instancia em subnet privada previsto por este
# ADR, e o motivo de ter sido escolhido sobre o SSM Session Manager e o custo: o
# agente do SSM precisa alcancar os endpoints do Systems Manager, o que exigiria o
# NAT ligado ou tres Interface Endpoints a US$ 0,06/h em 2 AZs. O EIC Endpoint
# funciona com o NAT DESLIGADO, que e o estado padrao deste laboratorio.
#
# Fica no indice 0 — a primeira AZ da lista — e nao em var.nat_gateway_az, mesmo
# que hoje as duas apontem para a mesma AZ. Sao decisoes independentes: trocar a
# AZ do NAT e a recuperacao prevista em ADR-0001 R1, e nao ha razao para essa
# troca recriar tambem o endpoint de acesso, que nao tem nada a ver com egress.
#
# `security_group_ids` EXPLICITO (ADR-0002 §5.2). Sem este argumento a AWS associa
# o default security group da VPC ao endpoint — e vpc.security-groups.tf esvazia
# esse SG por decisao do ADR-0001 §9. O endpoint era criado sem erro e a conexao
# do §7 passo 12 falhava depois, em runtime. Era a divergencia escalada na etapa 4,
# e o ADR-0002 a fecha com dois SGs dedicados, nao um: o default vazio quebrava o
# caminho nos dois sentidos.
#
# `preserve_client_ip = false` EXPLICITO, e nao por omissao, porque as fontes
# oficiais se contradizem sobre o default — verificado via MCP nesta sessao e na
# do Arquiteto: a documentacao do provider Terraform declara `Default: true`, a do
# CloudFormation e do CDK declaram `Default: false`. Deixar implicito faria o
# comportamento depender de qual documento o leitor abriu (ADR-0002 R18). Com a
# regra por referencia de SG o valor nao altera a conectividade — o que importa
# aqui e o registro da ambiguidade.
resource "aws_ec2_instance_connect_endpoint" "this" {
  subnet_id          = aws_subnet.private[0].id
  security_group_ids = [aws_security_group.eice.id]
  preserve_client_ip = false

  tags = {
    Name = "${var.project_name}-${var.environment}-eice-private-${substr(var.availability_zones[0], -2, -1)}"
  }
}
