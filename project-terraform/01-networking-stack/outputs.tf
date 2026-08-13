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
