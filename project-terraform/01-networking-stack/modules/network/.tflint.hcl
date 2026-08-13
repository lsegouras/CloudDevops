# Configuracao do TFLint para o modulo `network` (ADR-0001).
#
# COPIA INTENCIONAL de `../../.tflint.hcl`. Nao e redundancia por descuido:
# `tflint --recursive` executa em cada diretorio como se fosse o cwd e procura um
# `.tflint.hcl` local — ele NAO herda a configuracao do diretorio pai. Sem este
# arquivo, o modulo (que e onde vivem TODOS os recursos `aws_*` da stack) roda so
# com o ruleset bundled `terraform` e sai limpo sem ter conferido um unico
# argumento de provider.
#
# A alternativa seria exportar TFLINT_CONFIG_FILE a cada execucao, o que faz o
# gate depender de alguem lembrar de uma variavel de ambiente. Esquecer produz
# falso-limpo silencioso, entao a duplicacao de 10 linhas e a opcao segura.
#
# As versoes aqui e na raiz da stack precisam ser alteradas juntas.

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "aws" {
  enabled = true
  version = "0.48.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}
