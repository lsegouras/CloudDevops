# Interface de entrada do modulo. Como regra, nenhuma variavel tem default: o
# contrato e que a raiz da stack forneca todos os valores, que vivem em
# terraform.tfvars. As duas excecoes estao no fim do arquivo, com a justificativa.
#
# ESCOPO — etapa 3 do plano de implementacao. As quatro variaveis de egress e
# custo entram todas aqui, inclusive enable_flow_logs e
# flow_logs_retention_in_days, cujos recursos so chegam na etapa 4. O motivo e
# pratico: a raiz ja repassa as quatro em main.tf, entao ate que estejam
# declaradas o `terraform init` da raiz falha com 4 "Unsupported argument" e a
# stack nao valida de ponta a ponta. Variavel declarada e ainda nao usada e HCL
# valido — o custo e um aviso de tflint, resolvido na etapa 4.

# -----------------------------------------------------------------------------
# Nomenclatura (ADR-0001 §8)
#
# As 6 tags obrigatorias vem de default_tags no provider da raiz. Aqui so entra o
# que compoe a tag `Name`, que e por recurso e nao pode ficar em default_tags.
# -----------------------------------------------------------------------------

variable "project_name" {
  description = "Nome do projeto. Primeiro segmento do padrao de nomenclatura <projeto>-<ambiente>-<tipo> aplicado a tag Name de cada recurso."
  type        = string
  nullable    = false
}

variable "environment" {
  description = "Nome do ambiente. Segundo segmento do padrao de nomenclatura <projeto>-<ambiente>-<tipo>."
  type        = string
  nullable    = false
}

# -----------------------------------------------------------------------------
# Enderecamento (ADR-0001 §2 — entradas fixadas pela usuaria)
# -----------------------------------------------------------------------------

variable "vpc_cidr_block" {
  description = "Bloco CIDR IPv4 da VPC. As quatro subnets /26 preenchem este bloco por completo."
  type        = string
  nullable    = false
}

variable "availability_zones" {
  description = "Availability Zones da stack, pinadas por nome e na ordem em que as subnets sao criadas. Define a quantidade de subnets publicas e privadas e os dois ultimos caracteres de cada nome de AZ viram o sufixo da tag Name."
  type        = list(string)
  nullable    = false
}

variable "public_subnet_cidr_blocks" {
  description = "Blocos CIDR das subnets publicas, na mesma ordem de availability_zones. Precisa ter o mesmo comprimento que availability_zones."
  type        = list(string)
  nullable    = false
}

variable "private_subnet_cidr_blocks" {
  description = "Blocos CIDR das subnets privadas, na mesma ordem de availability_zones. Precisa ter o mesmo comprimento que availability_zones."
  type        = list(string)
  nullable    = false
}

# -----------------------------------------------------------------------------
# Egress (ADR-0001 §6)
# -----------------------------------------------------------------------------

variable "nat_gateway_az" {
  description = "Nome da AZ que hospeda o NAT Gateway unico; ele e criado na subnet publica dessa AZ. Precisa ser um dos valores de availability_zones. Trocar de AZ e a recuperacao prevista em ADR-0001 R1 para queda da AZ do NAT."
  type        = string
  nullable    = false
}

# -----------------------------------------------------------------------------
# Controle de custo — o contrato central do ADR-0001 §8
#
# Estas duas sao as UNICAS variaveis do modulo com `default`, rompendo de
# proposito a regra do topo do arquivo. O criterio de aceite do ADR-0001 §14
# exige `default = false` nas duas, e a razao e defesa em profundidade: se a raiz
# um dia deixar de repassa-las, o modulo cai no estado de custo ZERO em vez de
# cair no estado tarifado. O default seguro precisa morar na camada mais interna,
# nao so na de fora.
#
# Os defaults `false` sao a DECISAO do ADR-0001 §5, nao placeholder. Nao promover
# a `true` para facilitar teste: se o plan sem variaveis mostrar recurso
# tarifado, o criterio de aceite falhou.
# -----------------------------------------------------------------------------

variable "enable_nat_gateway" {
  description = "Cria o Elastic IP, o NAT Gateway e as duas rotas 0.0.0.0/0 das route tables privadas. CUSTO QUANDO true: US$ 0,050/h (NAT US$ 0,045 + IPv4 publico US$ 0,005) mais US$ 0,045/GB processado. Default false por decisao do ADR-0001 §5."
  type        = bool
  default     = false
  nullable    = false
}

variable "enable_flow_logs" {
  description = "Cria o log group, a IAM role, a IAM role policy e o aws_flow_log de nivel VPC. CUSTO QUANDO true: US$ 0,50/GB de ingestao no CloudWatch Logs. Default false por decisao do ADR-0001 §5. Recursos implementados na etapa 4."
  type        = bool
  default     = false
  nullable    = false
}

variable "flow_logs_retention_in_days" {
  description = "Retencao do log group dos VPC Flow Logs, em dias. ADR-0001 §10 usa 7; o custo relevante e o de ingestao, nao o de retencao. Consumida pelos recursos da etapa 4."
  type        = number
  nullable    = false
}
