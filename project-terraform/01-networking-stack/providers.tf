provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  # ADR-0001 §8 — as 6 tags obrigatorias. `Name` NAO entra aqui: e por recurso.
  # `CostCenter` e a Cost Allocation Tag que filtra o AWS Budget (budget.tf) e
  # precisa ser ativada a mao no console de Billing -> Cost allocation tags.
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = var.owner
      CostCenter  = var.cost_center
      ADR         = var.adr_id
    }
  }
}
