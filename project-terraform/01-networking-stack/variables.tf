# -----------------------------------------------------------------------------
# Provider e identidade da conta
# -----------------------------------------------------------------------------

variable "aws_region" {
  description = "Regiao AWS onde toda a stack e provisionada. ADR-0001 §2 fixa us-east-1."
  type        = string
  default     = "us-east-1"
  nullable    = false
}

variable "aws_profile" {
  description = "Nome do profile local do AWS CLI usado pelo provider. ADR-0001 C4 fixa app_cloud_devops. Nao e credencial: apenas o nome do profile."
  type        = string
  default     = "app_cloud_devops"
  nullable    = false
}

# -----------------------------------------------------------------------------
# Nomenclatura e tags obrigatorias (ADR-0001 §8)
# -----------------------------------------------------------------------------

variable "project_name" {
  description = "Nome do projeto. Primeiro segmento do padrao <projeto>-<ambiente>-<tipo> e valor da tag Project."
  type        = string
  default     = "dvn-workshop"
  nullable    = false
}

variable "environment" {
  description = "Nome do ambiente. Segundo segmento do padrao de nomenclatura e valor da tag Environment."
  type        = string
  default     = "prd"
  nullable    = false
}

variable "owner" {
  description = "Responsavel pela stack. Valor da tag Owner."
  type        = string
  nullable    = false
}

variable "cost_center" {
  description = "Centro de custo. Valor da tag CostCenter, que e a Cost Allocation Tag usada como filtro do AWS Budget."
  type        = string
  default     = "workshop-devops-ia"
  nullable    = false
}

variable "adr_id" {
  description = "Identificador do ADR que decidiu esta arquitetura. Valor da tag ADR, para rastrear recurso ate a decisao."
  type        = string
  default     = "ADR-0001"
  nullable    = false
}

# -----------------------------------------------------------------------------
# Rede (ADR-0001 §2 e §6) — repassado ao module "network"
# -----------------------------------------------------------------------------

variable "vpc_cidr_block" {
  description = "Bloco CIDR IPv4 da VPC. ADR-0001 §2 fixa 10.0.0.0/24, 100% alocado pelas 4 subnets /26."
  type        = string
  default     = "10.0.0.0/24"
  nullable    = false

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block precisa ser um bloco CIDR IPv4 valido."
  }
}

variable "availability_zones" {
  description = "Availability Zones usadas pela stack, pinadas por nome. ADR-0001 §6 escolhe us-east-1a e us-east-1b; o mapeamento nome -> Zone ID e por conta, por isso nao se usa data.aws_availability_zones."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
  nullable    = false

  validation {
    condition     = length(var.availability_zones) == 2
    error_message = "ADR-0001 §2 fixa exatamente 2 AZs."
  }
}

variable "public_subnet_cidr_blocks" {
  description = "Blocos CIDR das subnets publicas, na mesma ordem de availability_zones. ADR-0001 §2 fixa 10.0.0.0/26 e 10.0.0.64/26."
  type        = list(string)
  default     = ["10.0.0.0/26", "10.0.0.64/26"]
  nullable    = false
}

variable "private_subnet_cidr_blocks" {
  description = "Blocos CIDR das subnets privadas, na mesma ordem de availability_zones. ADR-0001 §2 fixa 10.0.0.128/26 e 10.0.0.192/26."
  type        = list(string)
  default     = ["10.0.0.128/26", "10.0.0.192/26"]
  nullable    = false
}

variable "nat_gateway_az" {
  description = "AZ que hospeda o NAT Gateway unico, na subnet publica correspondente. ADR-0001 §6 usa us-east-1a; trocar para us-east-1b e a recuperacao prevista em R1."
  type        = string
  default     = "us-east-1a"
  nullable    = false
}

# -----------------------------------------------------------------------------
# Controle de custo — o contrato central do ADR-0001 §8
#
# Os defaults `false` sao a DECISAO, nao placeholder. Nao promover a `true` para
# facilitar teste. Se o plan sem variaveis mostrar recurso tarifado, o criterio
# de aceite do §14 falhou.
# -----------------------------------------------------------------------------

variable "enable_nat_gateway" {
  description = "Cria Elastic IP, NAT Gateway e as duas rotas 0.0.0.0/0 privadas. CUSTO QUANDO true: US$ 0,050/h (NAT US$ 0,045 + IPv4 publico US$ 0,005) mais US$ 0,045/GB processado. Default false por decisao do ADR-0001 §5."
  type        = bool
  default     = false
  nullable    = false
}

variable "enable_flow_logs" {
  description = "Cria log group, IAM role, IAM role policy e o aws_flow_log de nivel VPC. CUSTO QUANDO true: US$ 0,50/GB de ingestao no CloudWatch Logs. Default false por decisao do ADR-0001 §5."
  type        = bool
  default     = false
  nullable    = false
}

variable "flow_logs_retention_in_days" {
  description = "Retencao do log group dos VPC Flow Logs, em dias. ADR-0001 §10 usa 7; o custo relevante e o de ingestao, nao o de retencao."
  type        = number
  default     = 7
  nullable    = false

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.flow_logs_retention_in_days)
    error_message = "flow_logs_retention_in_days precisa ser um dos valores aceitos pelo CloudWatch Logs."
  }
}

# -----------------------------------------------------------------------------
# AWS Budget (ADR-0001 §7 etapa 1 e §11.5)
# -----------------------------------------------------------------------------

variable "budget_limit_amount" {
  description = "Teto do AWS Budget que cobre o laboratorio inteiro. ADR-0001 C1 fixa 5,00 como limite rigido, nao como meta."
  type        = string
  default     = "5"
  nullable    = false
}

variable "budget_limit_unit" {
  description = "Unidade de medida do teto do budget."
  type        = string
  default     = "USD"
  nullable    = false
}

variable "budget_time_unit" {
  description = "Periodo de reset do budget. ANNUALLY combinado com budget_time_period_start/end produz um unico periodo cobrindo o curso inteiro; MONTHLY resetaria o teto todo mes e violaria C1."
  type        = string
  default     = "ANNUALLY"
  nullable    = false

  validation {
    condition     = contains(["MONTHLY", "QUARTERLY", "ANNUALLY", "DAILY"], var.budget_time_unit)
    error_message = "budget_time_unit precisa ser MONTHLY, QUARTERLY, ANNUALLY ou DAILY."
  }
}

variable "budget_time_period_start" {
  description = "Inicio do periodo coberto pelo budget, no formato AAAA-MM-DD_HH:MM. Sem default: e o pre-requisito 6 do handoff do ADR-0001 e exige confirmacao humana."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}:[0-9]{2}$", var.budget_time_period_start))
    error_message = "budget_time_period_start precisa estar no formato AAAA-MM-DD_HH:MM."
  }
}

variable "budget_time_period_end" {
  description = "Fim do periodo coberto pelo budget, no formato AAAA-MM-DD_HH:MM. Sem default: e o pre-requisito 6 do handoff do ADR-0001 e exige confirmacao humana."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}:[0-9]{2}$", var.budget_time_period_end))
    error_message = "budget_time_period_end precisa estar no formato AAAA-MM-DD_HH:MM."
  }
}

variable "budget_notification_emails" {
  description = "Enderecos de e-mail que recebem os alertas do budget. A assinatura precisa ser confirmada no e-mail, senao a protecao de custo e ilusoria. Nao e segredo."
  type        = list(string)
  nullable    = false

  validation {
    condition     = length(var.budget_notification_emails) > 0
    error_message = "Pelo menos um e-mail precisa receber os alertas do budget."
  }
}
