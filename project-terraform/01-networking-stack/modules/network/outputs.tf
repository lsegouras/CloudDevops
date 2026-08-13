# Interface de saida do modulo.
#
# ESCOPO — etapa 3 do plano de implementacao. Com a entrada dos quatro outputs de
# roteamento e NAT, os 9 outputs exigidos pelo criterio de aceite do ADR-0001 §14
# estao todos declarados e a raiz da stack resolve por completo.

output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "The IPv4 CIDR block of the VPC"
  value       = aws_vpc.this.cidr_block
}

output "internet_gateway_id" {
  description = "The ID of the Internet Gateway attached to the VPC"
  value       = aws_internet_gateway.this.id
}

output "public_subnet_ids" {
  description = "A list of IDs of the public subnets, in the same order as availability_zones"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "A list of IDs of the private subnets, in the same order as availability_zones"
  value       = aws_subnet.private[*].id
}

output "availability_zones" {
  description = "A list of the availability zones the subnets were created in, read back from the public subnets rather than echoed from the input variable"
  value       = aws_subnet.public[*].availability_zone
}

output "public_route_table_id" {
  description = "The ID of the shared public route table, associated with every public subnet"
  value       = aws_route_table.public.id
}

output "private_route_table_ids" {
  description = "A list of IDs of the private route tables, one per availability zone, in the same order as availability_zones"
  value       = aws_route_table.private[*].id
}

# try() em vez de element(concat(...)) por .claude/rules/terraform-naming.md, e
# string vazia em vez de null porque o criterio de aceite do ADR-0001 §14 pede
# que estes outputs venham VAZIOS no estado base — vazio aqui e a evidencia de
# que a janela de custo esta fechada, nao ausencia de informacao.
#
# DIVERGENCIA de nomenclatura, deliberada: pelo padrao {name}_{type}_{attribute}
# o segundo output se chamaria `nat_gateway_public_ip`. O ADR-0001 §14 fixa
# `nat_public_ip` na lista de outputs exigidos, e o ADR vence a regra.

output "nat_gateway_id" {
  description = "The ID of the NAT Gateway, or an empty string when enable_nat_gateway is false, which is the default and the zero-cost state"
  value       = try(aws_nat_gateway.this[0].id, "")
}

output "nat_public_ip" {
  description = "The public IP address of the NAT Gateway Elastic IP, or an empty string when enable_nat_gateway is false. Changes every time the cost window is reopened"
  value       = try(aws_nat_gateway.this[0].public_ip, "")
}
