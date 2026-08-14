# Default Security Group da VPC, esvaziado (ADR-0001 §9). Custo US$ 0,00.
#
# Este e o UNICO security group tocado por este modulo. Nenhum SG de aplicacao e
# criado aqui: eles pertencem ao ADR de compute, e criar um "so para adiantar"
# seria decidir arquitetura que nao me cabe.
#
# `aws_default_security_group` nao CRIA nada — ele adota o SG que a AWS ja criou
# junto com a VPC. Ao adotar, o provider remove imediatamente TODAS as regras de
# ingress e egress e recria apenas as declaradas aqui. Como nao ha nenhum bloco
# declarado, o SG fica sem regra alguma e se torna inutilizavel por acidente: um
# recurso que caia nele por omissao nao conversa com ninguem, em nenhuma direcao.
# E o comportamento desejado, e o que resolve o CKV2_AWS_12 do checkov.
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
