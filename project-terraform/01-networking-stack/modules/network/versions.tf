# Sem bloco `provider` e sem `backend` (ADR-0001 §8): ambos vivem apenas na raiz
# da stack. Um modulo que declara provider proprio nao pode ser reutilizado com
# aliases, e backend em modulo nao existe.
#
# DIVERGENCIA DOCUMENTADA — o layout do ADR-0001 §8 anota este arquivo como
# "required_providers apenas", mas a regra terraform_required_version do tflint
# exige a restricao tambem no modulo, e o criterio de aceite do §14 pede "tflint
# limpo". O criterio de aceite prevalece sobre o comentario de layout. A
# restricao repete a da raiz, entao nao afeta a resolucao de versao.

terraform {
  required_version = "~> 1.13"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.58"
    }
  }
}
