# ADR-0001 §7 etapa 1 — o Budget vem ANTES de qualquer outro recurso.
# ADR-0001 §8 — budget e preocupacao de conta, nao de rede: mora no root, nao no module.
#
# Custo do proprio recurso: US$ 0,00. Budgets sem action sao gratuitos e o free
# tier cobre 2 budgets ativos (ADR-0001 §11.6).
#
# ATENCAO (ADR-0001 §11.5): os dados do AWS Budgets sao atualizados ate 3x por dia,
# com defasagem tipica de 8 a 12 h. Isto e rede de seguranca, nao sensor em tempo real.

resource "aws_budgets_budget" "this" {
  name         = "${var.project_name}-budget-curso"
  budget_type  = "COST"
  limit_amount = var.budget_limit_amount
  limit_unit   = var.budget_limit_unit

  # Periodo customizado: um unico periodo do inicio ao fim do curso.
  time_unit         = var.budget_time_unit
  time_period_start = var.budget_time_period_start
  time_period_end   = var.budget_time_period_end

  # Filtro pela Cost Allocation Tag CostCenter, aplicada via default_tags em providers.tf.
  # PASSO MANUAL OBRIGATORIO (ADR-0001 §8): a tag precisa ser ATIVADA no console de
  # Billing -> Cost allocation tags. O Terraform aplica a tag, nao a ativa. Sem
  # ativacao este filtro nao enxerga nada e o budget fica cego. Leva ate 24 h.
  cost_filter {
    name   = "TagKeyValue"
    values = [format("user:CostCenter$%s", var.cost_center)]
  }

  # ADR-0001 §11.5 — 40 / 60 / 80% do ACTUAL e 100% do FORECASTED.
  # O alerta de FORECASTED e o unico que dispara ANTES do estouro: e ele que pega
  # um destroy esquecido (R0).
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 40
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = var.budget_notification_emails
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 60
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = var.budget_notification_emails
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = var.budget_notification_emails
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = var.budget_notification_emails
  }

  tags = {
    Name = "${var.project_name}-budget-curso"
  }
}
