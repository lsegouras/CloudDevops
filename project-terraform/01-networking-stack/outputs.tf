# Os 9 outputs exigidos pelo criterio de aceite do ADR-0001 §14 ("Codigo").
# Todos derivam do module "network", implementado nas etapas 2 a 4 — ate la estas
# referencias nao resolvem. Ficam declarados desde ja porque definem o contrato
# que o module precisa cumprir: sao a especificacao dos outputs do module, nao um
# reflexo dele.

output "vpc_id" {
  description = "The ID of the VPC"
  value       = module.network.vpc_id
}

output "vpc_cidr_block" {
  description = "The CIDR block of the VPC"
  value       = module.network.vpc_cidr_block
}

output "public_subnet_ids" {
  description = "A list of IDs of the public subnets, in the same order as availability_zones"
  value       = module.network.public_subnet_ids
}

output "private_subnet_ids" {
  description = "A list of IDs of the private subnets, in the same order as availability_zones"
  value       = module.network.private_subnet_ids
}

output "public_route_table_id" {
  description = "The ID of the shared public route table"
  value       = module.network.public_route_table_id
}

output "private_route_table_ids" {
  description = "A list of IDs of the private route tables, one per availability zone"
  value       = module.network.private_route_table_ids
}

output "nat_gateway_id" {
  description = "The ID of the NAT Gateway. Empty when enable_nat_gateway is false, which is the default and the zero-cost state"
  value       = module.network.nat_gateway_id
}

output "nat_public_ip" {
  description = "The public IP of the NAT Gateway Elastic IP. Empty when enable_nat_gateway is false. Changes every time the cost window is reopened"
  value       = module.network.nat_public_ip
}

output "availability_zones" {
  description = "A list of the availability zones the stack is pinned to"
  value       = module.network.availability_zones
}

output "budget_name" {
  description = "The name of the AWS Budget guarding the US$ 5.00 hard limit"
  value       = aws_budgets_budget.this.name
}

# --- SGs do caminho de acesso (ADR-0002 §7 etapa 3) — custo US$ 0,00 ---------
#
# Acrescimo ao contrato dos 9 outputs do ADR-0001 §14, autorizado pelo ADR-0002.
# Sobem ate a raiz porque sao lidos por quem opera a stack de fora, com
# `terraform output`, e nao por outro modulo.

output "eice_security_group_id" {
  description = "The ID of the security group attached to the EC2 Instance Connect Endpoint"
  value       = module.network.eice_security_group_id
}

# O output mais importante desta emenda na pratica. A instancia descartavel do
# ADR-0001 §7 passo 12 e lancada FORA do Terraform e precisa deste SG explicito
# no comando de lancamento:
#
#   aws ec2 run-instances ... --security-group-ids $(terraform output -raw lab_access_security_group_id)
#
# Sem isso ela cai no default SG vazio, sem ingress e sem egress, e fica
# inalcancavel — ADR-0002 R14 e criterio de aceite A10.
output "lab_access_security_group_id" {
  description = "The ID of the lab access security group. Pass it explicitly when launching the disposable instance of ADR-0001 section 7 step 12"
  value       = module.network.lab_access_security_group_id
}
