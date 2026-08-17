# Interface de saida do modulo.
#
# ESCOPO — etapa 4 do plano de implementacao. Os 9 outputs exigidos pelo criterio
# de aceite do ADR-0001 §14 entraram na etapa 3 e seguem intactos abaixo. Esta
# etapa acrescenta os outputs dos endpoints, do default SG e dos flow logs, que o
# §14 nao lista mas sao a evidencia verificavel de que esses recursos existem (ou,
# no caso dos flow logs, de que NAO existem com a janela de custo fechada).
#
# Os acrescimos da etapa 4 nao sobem para a raiz da stack: outputs.tf da raiz
# declara exatamente os 9 do criterio de aceite mais o budget, e mexer naquele
# contrato nao era escopo daquela etapa.
#
# EXCECAO, por ADR-0002 §7 etapa 3: os dois outputs de security group do caminho
# de acesso sobem para a raiz. Nao e simetria — e necessidade operacional. O
# `lab_access_security_group_id` precisa ser legivel por `terraform output` na
# raiz, porque quem lanca a instancia descartavel do §7 passo 12 le dali, e nao
# de dentro do modulo.

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

# try() em vez de element(concat(...)) por .claude/skills/terraform-naming/SKILL.md, e
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

# --- Endpoints e default SG — permanentes, custo US$ 0,00 --------------------

output "s3_vpc_endpoint_id" {
  description = "The ID of the S3 Gateway VPC Endpoint associated with every private route table"
  value       = aws_vpc_endpoint.s3.id
}

# O consumidor mais provavel deste output e o ADR de compute: uma regra de egress
# de security group para S3 usa a prefix list como destino, em vez de abrir
# 0.0.0.0/0. Exposto agora porque e barato expor e caro descobrir depois.
output "s3_vpc_endpoint_prefix_list_id" {
  description = "The prefix list ID of the S3 Gateway VPC Endpoint, for use as a destination in security group egress rules"
  value       = aws_vpc_endpoint.s3.prefix_list_id
}

output "ec2_instance_connect_endpoint_id" {
  description = "The ID of the EC2 Instance Connect Endpoint, the only access path to instances in private subnets and the one that works with the NAT Gateway turned off"
  value       = aws_ec2_instance_connect_endpoint.this.id
}

# Exposto para ser evitado, nao para ser usado. O SG default nao tem regra alguma
# (ADR-0001 §9), entao qualquer recurso que caia nele por omissao fica sem
# comunicacao — este output existe para que o ADR de compute possa conferir que
# nao esta usando este ID.
output "default_security_group_id" {
  description = "The ID of the VPC default security group, managed with no ingress or egress rules at all and therefore unusable by design"
  value       = aws_default_security_group.this.id
}

# --- SGs do caminho de acesso (ADR-0002 §5.2) — custo US$ 0,00 ---------------

output "eice_security_group_id" {
  description = "The ID of the security group attached to the EC2 Instance Connect Endpoint, which allows egress on TCP/22 towards the lab access security group"
  value       = aws_security_group.eice.id
}

# ESTE OUTPUT E OPERACIONAL, NAO DECORATIVO. A instancia descartavel do §7 passo
# 12 nasce fora do Terraform e precisa receber este SG explicitamente no
# lancamento (`--security-group-ids`). Sem isso ela cai no default SG vazio e o
# teste de acesso falha do mesmo jeito que falhava antes desta emenda — e o risco
# R14 do ADR-0002, e este output e a mitigacao dele.
output "lab_access_security_group_id" {
  description = "The ID of the lab access security group. Pass it explicitly when launching the disposable instance of ADR-0001 section 7 step 12, otherwise the instance lands in the empty default security group and is unreachable"
  value       = aws_security_group.lab_access.id
}

# --- Flow logs — vazios no estado base, que e o de custo ZERO ----------------
#
# Mesma convencao dos outputs de NAT: string vazia em vez de null, porque vazio
# aqui e a evidencia de que a janela de custo esta fechada, nao ausencia de dado.
#
# DIVERGENCIA menor e deliberada da regra {name}_{type}_{attribute}: como o nome
# dos recursos e `this`, o padrao estrito produziria `cloudwatch_log_group_name`,
# que nao diz de que log group se trata para quem le do lado de fora. O prefixo
# `flow_log_` foi mantido pela mesma razao que os recursos ficaram com `this` — o
# modulo tem um unico log group, e ele existe so para os flow logs.

output "flow_log_id" {
  description = "The ID of the VPC Flow Log, or an empty string when enable_flow_logs is false, which is the default and the zero-cost state"
  value       = try(aws_flow_log.this[0].id, "")
}

output "flow_log_cloudwatch_log_group_name" {
  description = "The name of the CloudWatch log group receiving the VPC Flow Logs, or an empty string when enable_flow_logs is false. Use it as the Logs Insights target when the cost window is open"
  value       = try(aws_cloudwatch_log_group.this[0].name, "")
}
