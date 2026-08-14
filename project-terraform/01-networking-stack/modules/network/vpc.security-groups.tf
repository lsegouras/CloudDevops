# Security groups deste modulo (ADR-0001 §9, emendado por ADR-0002 §5.2).
# Os tres custam US$ 0,00: security group e regra de security group nao sao
# recursos tarifados, em nenhuma quantidade.
#
# FRONTEIRA, fixada por ADR-0002 §5.2: a camada de rede e dona dos security
# groups DOS ENDPOINTS QUE ELA CRIA e DO CAMINHO DE VALIDACAO QUE O §7 DELA
# PROPRIA EXIGE. SG de workload — aplicacao, load balancer, banco — continua
# pertencendo ao ADR de compute. Nenhum dos dois SGs abaixo serve a uma
# aplicacao, entao o §9 do ADR-0001 segue verdadeiro.
#
# --- Default Security Group da VPC, esvaziado (ADR-0001 §9) ------------------
#
# `aws_default_security_group` nao CRIA nada — ele adota o SG que a AWS ja criou
# junto com a VPC. Ao adotar, o provider remove imediatamente TODAS as regras de
# ingress e egress e recria apenas as declaradas aqui. Como nao ha nenhum bloco
# declarado, o SG fica sem regra alguma e se torna inutilizavel por acidente: um
# recurso que caia nele por omissao nao conversa com ninguem, em nenhuma direcao.
# E o comportamento desejado, e o que resolve o CKV2_AWS_12 do checkov.
#
# ADR-0002 §9: agora NENHUM recurso depende deste SG — o EIC Endpoint passou a
# receber o seu proprio, logo abaixo. E essa a condicao que torna esvazia-lo uma
# decisao segura em vez de uma quebra silenciosa. Ate a etapa 4 o endpoint caia
# aqui por omissao, e o `apply` passava enquanto a conexao falhava.
#
# ATENCAO — NAO REPLICAR ESTE PADRAO EM `aws_default_network_acl`. ADR-0001 §9 e R5.
# O recurso tem nome parecido e comportamento OPOSTO: declarar a NACL default sem
# blocos remove as regras 100 allow-all e derruba TODO o trafego da VPC, inclusive
# o interno. A NACL default fica deliberadamente fora do Terraform, e o criterio
# de aceite do §14 exige confirmar que ela esta ausente do state.
#
# Remover este bloco do codigo no futuro nao restaura as regras originais: o SG
# sai do state e fica exatamente como esta, vazio, sob gestao manual.
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.project_name}-${var.environment}-sg-default-locked"
  }
}

# --- Caminho de acesso do §7 passo 12 (ADR-0002 §5.2) ------------------------
#
# Dois SGs, nao um. O default SG vazio quebrava o caminho nos DOIS sentidos: o
# endpoint nao saia E a instancia-alvo nao deixava entrar nem sair. Um SG so no
# endpoint destravaria metade do problema e o passo 12 falharia igual, agora no
# `curl`/`docker pull` em vez de no SSH.
#
# REGRAS SEMPRE COMO RECURSO SEPARADO, NUNCA BLOCO `ingress`/`egress` INLINE.
# Duas razoes independentes, ambas duras (ADR-0002 §8):
#   1. O provider adverte formalmente contra misturar `aws_vpc_security_group_*_rule`
#      com blocos inline no mesmo SG — da conflito de regra e diff perpetuo.
#   2. Os dois SGs se referenciam MUTUAMENTE. Com blocos inline isso seria um
#      CICLO DE DEPENDENCIA entre os dois recursos, e o grafo do Terraform nao
#      fecha. Com regras separadas os SGs nascem primeiro e as regras depois.
#
# Nao ha `count` em nenhum recurso desta secao: nada aqui consome orcamento, e o
# caminho de acesso precisa existir no estado base, com a janela de custo FECHADA
# — e justamente com o NAT desligado que o EIC Endpoint e o unico acesso.

# SG do endpoint. Sem nenhuma regra de INGRESS, e isso e deliberado: a
# documentacao da AWS ("Security groups for EC2 Instance Connect Endpoint") diz
# que o trafego que chega ao endpoint vindo do servico EIC e permitido
# INDEPENDENTE das regras de ingress. Acrescentar ingress aqui nao aumentaria a
# funcionalidade, so a superficie.
resource "aws_security_group" "eice" {
  name        = "${var.project_name}-${var.environment}-sg-eice"
  description = "EC2 Instance Connect Endpoint: egress SSH para as instancias do laboratorio. Criado por ADR-0002."
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "${var.project_name}-${var.environment}-sg-eice"
  }
}

# SG da instancia descartavel do §7 passo 12.
#
# ATENCAO — ESTE SG NAO E ANEXADO POR ESTE MODULO. A instancia nasce FORA do
# Terraform, por desenho: ela e efemera e nao pertence ao state. Quem a lanca
# precisa passar este SG explicitamente em `--security-group-ids`, e o ID sai do
# output `lab_access_security_group_id`. Esquecer disso joga a instancia no
# default SG vazio e reproduz exatamente a falha que esta emenda existe para
# eliminar (ADR-0002 R14 e criterio de aceite A10).
resource "aws_security_group" "lab_access" {
  #checkov:skip=CKV2_AWS_5: este SG e anexado no LANCAMENTO da instancia descartavel, fora do Terraform e por desenho — a instancia e efemera e nao pertence ao state, entao nenhum recurso deste modulo o referencia e o check nao tem como enxergar a associacao. E o ID previsto pelo ADR-0002 §5.3 e confirmado por medicao. Supressao autorizada nominalmente por ADR-0002 §5.3.
  name        = "${var.project_name}-${var.environment}-sg-lab-access"
  description = "Instancia descartavel do laboratorio: ingress SSH do EIC Endpoint, egress HTTPS e DNS. Criado por ADR-0002."
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "${var.project_name}-${var.environment}-sg-lab-access"
  }
}

# Egress TCP/22 do endpoint para o alvo, POR REFERENCIA DE SG e nao por CIDR.
#
# A escolha nao e estetica. A documentacao da AWS e explicita: a regra por
# referencia de security group funciona "whether client IP preservation is on or
# off". Com CIDR, a origem correta MUDA conforme o valor de `preserve_client_ip`
# — e errar produz exatamente a falha silenciosa (conecta em um modo, quebra no
# outro) que esta emenda existe para eliminar.
resource "aws_vpc_security_group_egress_rule" "eice_ssh" {
  security_group_id = aws_security_group.eice.id

  description                  = "SSH para as instancias do laboratorio (ADR-0002 §5.2)"
  referenced_security_group_id = aws_security_group.lab_access.id
  from_port                    = 22
  to_port                      = 22
  ip_protocol                  = "tcp"

  tags = {
    Name = "${var.project_name}-${var.environment}-sgr-eice-ssh"
  }
}

# Ingress TCP/22 no alvo, vindo do SG do endpoint. E a UNICA regra de ingress da
# VPC inteira, e a origem e um SG — nenhum ingress a partir de CIDR existe neste
# modulo, em nenhuma porta (ADR-0002 §9).
#
# CKV_AWS_24 ("no security groups allow ingress from 0.0.0.0:0 to port 22") FALHA
# aqui e NAO foi suprimido — nao esta na lista nominal do ADR-0002 §5.3, e §5.3 e
# explicito: achado sobre os SGs novos fora da lista e ESCALACAO, nao `skip`.
# Aguardando decisao do Arquiteto.
#
# E falso positivo, e a causa esta medida, nao suposta. O check le apenas os
# argumentos dos recursos LEGADOS — `security_groups` e `source_security_group_id`
# — e nao conhece `referenced_security_group_id`, que e o argumento do recurso
# moderno. Nao encontrando origem em nenhum dos dois, ele conclui "sem origem,
# logo aberto ao mundo" e falha (checkov 3.3.10,
# AbsSecurityGroupUnrestrictedIngress.py linhas 107-110).
#
# Teste controlado das tres variantes, com o mesmo from_port/to_port 22:
#   referenced_security_group_id  -> FAILED   <- esta regra, a forma mais restritiva
#   cidr_ipv4 = "10.0.0.0/24"     -> PASSED
#   cidr_ipv4 = "0.0.0.0/0"       -> FAILED   <- genuinamente aberto
#
# Ou seja: o check pune exatamente a decisao de seguranca do ADR-0002 §5.2 e
# aprovaria a alternativa mais frouxa. Trocar a referencia de SG por CIDR deixaria
# o relatorio verde e a conexao refem do valor de `preserve_client_ip` — que e o
# defeito que esta emenda existe para eliminar. O achado fica vermelho.
resource "aws_vpc_security_group_ingress_rule" "lab_ssh" {
  security_group_id = aws_security_group.lab_access.id

  description                  = "SSH vindo do EC2 Instance Connect Endpoint (ADR-0002 §5.2)"
  referenced_security_group_id = aws_security_group.eice.id
  from_port                    = 22
  to_port                      = 22
  ip_protocol                  = "tcp"

  tags = {
    Name = "${var.project_name}-${var.environment}-sgr-lab-ssh"
  }
}

# Egress TCP/443 do alvo. Cobre a API do ECR e as camadas de imagem que descem
# pelo Gateway Endpoint de S3 — os dois usos do §7 passo 12 (premissa P3).
#
# Escopado a 443, e nao `ip_protocol = "-1"` para 0.0.0.0/0: o `-1` seria mais
# curto de escrever e dispararia um achado de egress aberto no checkov. Trocar um
# achado por outro nao e solucao (ADR-0002 §5.2).
#
# O destino e 0.0.0.0/0 e nao a prefix list do S3 porque a API do ECR nao esta na
# prefix list — so as camadas de imagem estao. Com o NAT desligado esta regra nao
# tem por onde sair de qualquer forma; ela existe para a janela de custo ABERTA.
resource "aws_vpc_security_group_egress_rule" "lab_https" {
  security_group_id = aws_security_group.lab_access.id

  description = "HTTPS para a API do ECR e para as camadas de imagem via endpoint de S3 (ADR-0002 §5.2)"
  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 443
  to_port     = 443
  ip_protocol = "tcp"

  tags = {
    Name = "${var.project_name}-${var.environment}-sgr-lab-https"
  }
}

# As duas regras de porta 53 entram POR PRECAUCAO, sob a premissa P2 do ADR-0002,
# que esta marcada como NAO VERIFICADA: nao foi possivel confirmar na documentacao
# se regras de egress de SG se aplicam ao resolver DNS da VPC (base do CIDR + 2).
# Se NAO se aplicarem, as duas regras sao inocuas — nao ha cenario em que
# atrapalhem, e custam US$ 0,00. Se se aplicarem, sao o que faz o `docker pull`
# resolver o nome do registry.
#
# Destino e o CIDR DA VPC, lido de aws_vpc.this.cidr_block e nao de literal: o
# resolver e interno, e o criterio de aceite A7 proibe CIDR hardcoded aqui.
#
# UDP e TCP separados porque sao duas regras distintas na API. O DNS usa UDP no
# caso comum e cai para TCP quando a resposta passa de 512 bytes.
resource "aws_vpc_security_group_egress_rule" "lab_dns_udp" {
  security_group_id = aws_security_group.lab_access.id

  description = "DNS UDP para o resolver da VPC (ADR-0002 §5.2, premissa P2)"
  cidr_ipv4   = aws_vpc.this.cidr_block
  from_port   = 53
  to_port     = 53
  ip_protocol = "udp"

  tags = {
    Name = "${var.project_name}-${var.environment}-sgr-lab-dns-udp"
  }
}

resource "aws_vpc_security_group_egress_rule" "lab_dns_tcp" {
  security_group_id = aws_security_group.lab_access.id

  description = "DNS TCP para o resolver da VPC, respostas acima de 512 bytes (ADR-0002 §5.2, premissa P2)"
  cidr_ipv4   = aws_vpc.this.cidr_block
  from_port   = 53
  to_port     = 53
  ip_protocol = "tcp"

  tags = {
    Name = "${var.project_name}-${var.environment}-sgr-lab-dns-tcp"
  }
}
