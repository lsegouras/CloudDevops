# Valores concretos do ambiente prd. NAO-SECRETOS — este arquivo e commitado.
# Nenhuma credencial, chave ou token entra aqui.

aws_region  = "us-east-1"
aws_profile = "app_cloud_devops"

# --- Nomenclatura e tags obrigatorias (ADR-0001 §8) --------------------------
project_name = "dvn-workshop"
environment  = "prd"
cost_center  = "workshop-devops-ia"
adr_id       = "ADR-0001"

# PENDENTE DE CONFIRMACAO — handoff do ADR-0001, pre-requisito 9 (nao bloqueante).
# O valor da tag Owner nao foi informado. Assumido a partir do decisor do ADR.
owner = "laura"

# --- Rede (ADR-0001 §2, entradas fixadas pela usuaria) -----------------------
vpc_cidr_block             = "10.0.0.0/24"
availability_zones         = ["us-east-1a", "us-east-1b"]
public_subnet_cidr_blocks  = ["10.0.0.0/26", "10.0.0.64/26"]
private_subnet_cidr_blocks = ["10.0.0.128/26", "10.0.0.192/26"]
nat_gateway_az             = "us-east-1a"

# --- Controle de custo -------------------------------------------------------
# NAO altere para true aqui. A janela de custo se abre por linha de comando:
#   terraform apply -var="enable_nat_gateway=true"
# e se fecha com `terraform apply` sem -var (ADR-0001 §13).
enable_nat_gateway          = false
enable_flow_logs            = false
flow_logs_retention_in_days = 7

# --- AWS Budget (ADR-0001 §11.5) --------------------------------------------
budget_limit_amount = "5"
budget_limit_unit   = "USD"
budget_time_unit    = "ANNUALLY"

# PENDENTE DE CONFIRMACAO — handoff do ADR-0001, pre-requisito 6 (BLOQUEANTE).
# A data de inicio e de fim do curso nao foram informadas. Valores assumidos:
#   inicio = 2026-08-01, mes em que o projeto comecou;
#   fim    = 2026-12-03, data de expiracao do plano Free da conta (ADR-0001 §11.6
#            e R12) — o laboratorio nao pode passar disso de qualquer forma.
# Confirmar com o professor ANTES do apply. Corrigir aqui, nao no codigo.
budget_time_period_start = "2026-08-01_00:00"
budget_time_period_end   = "2026-12-03_00:00"

# PENDENTE DE CONFIRMACAO — handoff do ADR-0001, pre-requisito 5 (BLOQUEANTE).
# A assinatura precisa ser confirmada por e-mail apos o apply, senao os alertas
# nunca chegam e a protecao de custo e ilusoria.
budget_notification_emails = ["laura.segouras@g2tecnologia.com.br"]
