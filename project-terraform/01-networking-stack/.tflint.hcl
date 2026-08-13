# Configuracao do TFLint para a stack de rede (ADR-0001).
#
# POR QUE O PLUGIN `aws`: o ruleset bundled `terraform` cobre apenas linguagem —
# ele nao confere se um argumento de `aws_*` existe, nem se o valor cabe no enum
# aceito. Ate a etapa 2 essa conferencia era 100% manual, via MCP `terraform`, e
# uma conferencia manual so acontece se alguem lembrar de faze-la. O plugin `aws`
# transforma essa classe de erro em falha automatica de lint.
#
# O MCP continua sendo a fonte para escrever o argumento; o plugin e a rede de
# seguranca que pega o que passou. Sao complementares, nao substitutos.
#
# VERSAO PINADA: coerente com o pin do provider (`~> 6.58`) e do Terraform
# (`~> 1.13`). Sem `latest` — um gate de qualidade cujo criterio muda sozinho
# entre execucoes nao e um gate.

# ATENCAO — `tflint --recursive` NAO propaga esta configuracao para
# subdiretorios: ele executa em cada diretorio como se fosse o cwd e procura um
# `.tflint.hcl` local. Sem um arquivo proprio, `modules/network/` roda apenas com
# o ruleset bundled e o resultado sai limpo sem ter conferido nada de provider —
# falso-limpo, a pior saida possivel para um gate. Por isso existe uma copia
# deste bloco de plugins em `modules/network/.tflint.hcl`.
#
# As duas versoes precisam ser alteradas juntas.

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "aws" {
  enabled = true
  version = "0.48.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}
