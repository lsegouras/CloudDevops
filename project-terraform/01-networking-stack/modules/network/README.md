# Módulo `network`

Camada de rede do laboratório, conforme [ADR-0001 — Arquitetura de rede na AWS](../../../../docs/adr/ADR-0001-arquitetura-de-rede-aws.md).

Módulo com **um único consumidor** — a raiz `01-networking-stack/`. É uma exceção declarada em ADR-0001 §8: praticar composição raiz → módulo é objetivo do exercício, e o futuro ADR de compute vai consumir estes outputs de qualquer forma.

## Estado de implementação

**O código do módulo está completo.** Todos os recursos de rede previstos em ADR-0001 §6 estão escritos; não sobra recurso do ADR por implementar.

| Etapa | Componentes | Arquivos | Situação |
| --- | --- | --- | --- |
| 2 | VPC, Internet Gateway, 2 subnets públicas, 2 subnets privadas | `vpc.tf`, `vpc.internet-gateway.tf`, `vpc.public-subnets.tf`, `vpc.private-subnets.tf` | **Implementado** |
| 3 | Route table pública + 2 route tables privadas + associações; Elastic IP + NAT Gateway + rotas default (condicionais) | `vpc.public-route-table.tf`, `vpc.private-route-tables.tf`, `vpc.nat-gateway.tf` | **Implementado** |
| 4 | Gateway Endpoint S3, EC2 Instance Connect Endpoint, default SG travado, VPC Flow Logs (condicionais) | `vpc.endpoints.tf`, `vpc.security-groups.tf`, `vpc.flow-logs.tf` | **Implementado** |

O que **não** foi feito ainda: nenhum `terraform plan` contra a AWS e nenhum `apply`. O bucket de state do backend S3 ainda não existe (ADR-0001 §7, passo 2), então a stack nunca foi resolvida contra a conta. A evidência dos critérios de aceite de §14 é a etapa 5.

Validação local sem tocar na AWS:

```powershell
terraform fmt -recursive -check
terraform init -backend=false ; terraform validate
terraform -chdir=modules/network init -backend=false ; terraform -chdir=modules/network validate
tflint --recursive
```

> `terraform -chdir=modules/network init` cria `.terraform/` e `.terraform.lock.hcl` **dentro do módulo**. Remova os dois depois — módulo filho não carrega lock próprio e eles não devem ser commitados.

## O que este módulo cria

### Permanente — custo US$ 0,00

| Recurso | Qtd | Configuração | Custo |
| --- | --- | --- | --- |
| `aws_vpc.this` | 1 | `enable_dns_support = true`, `enable_dns_hostnames = true`, tenancy `default` | US$ 0,00 |
| `aws_internet_gateway.this` | 1 | Anexado à VPC | US$ 0,00 |
| `aws_subnet.public` | 2 | Uma por AZ, `map_public_ip_on_launch = true` | US$ 0,00 |
| `aws_subnet.private` | 2 | Uma por AZ, `map_public_ip_on_launch = false` | US$ 0,00 |
| `aws_route_table.public` + rota + associações | 1 + 1 + 2 | `0.0.0.0/0 → igw`, compartilhada pelas 2 subnets públicas | US$ 0,00 |
| `aws_route_table.private` + associações | 2 + 2 | Uma por AZ, **sem rota default** no estado base | US$ 0,00 |
| `aws_vpc_endpoint.s3` | 1 | Tipo `Gateway`, `com.amazonaws.<região>.s3` | US$ 0,00 |
| `aws_vpc_endpoint_route_table_association.s3_private` | 2 | Uma por route table privada | US$ 0,00 |
| `aws_ec2_instance_connect_endpoint.this` | 1 | Na subnet privada da **primeira** AZ | US$ 0,00 |
| `aws_default_security_group.this` | 1 | Adotado **sem nenhuma regra** de ingress ou egress | US$ 0,00 |

### Condicional — é onde mora 100% do custo

Nada abaixo existe com os defaults. Os dois grupos são governados por `count` sobre uma flag `bool` com `default = false`.

| Flag | Recursos criados | Custo quando `true` |
| --- | --- | --- |
| `enable_nat_gateway` | `aws_eip.nat`, `aws_nat_gateway.this`, `aws_route.private` ×2 — **4 recursos** | **US$ 0,050/h** (NAT 0,045 + IPv4 público 0,005) + US$ 0,045/GB |
| `enable_flow_logs` | `aws_cloudwatch_log_group.this`, `aws_iam_role.this`, `aws_iam_role_policy.this`, `aws_flow_log.this` — **4 recursos** | **US$ 0,50/GB** de ingestão no CloudWatch Logs |

O EIP e o NAT compartilham a **mesma** flag de propósito: um EIP alocado e não anexado custa os mesmos US$ 0,005/h de um EIP em uso, então separá-los criaria a falha silenciosa de ADR-0001 **R6**.

Fechar a janela de custo é `terraform apply` **sem** `-var`, nunca `destroy` — desligar não é destruir (ADR-0001 §13). A VPC, as subnets, o IGW e as route tables permanecem, a US$ 0,00.

## Endereçamento

Valores fixados pela usuária em ADR-0001 §2 e passados pela raiz. O módulo não conhece nenhum deles — não há CIDR, AZ, região nem ARN literal aqui dentro.

| Subnet | CIDR | AZ | IPs utilizáveis | `map_public_ip_on_launch` |
| --- | --- | --- | --- | --- |
| pública 1a | `10.0.0.0/26` | `us-east-1a` | 59 | `true` |
| pública 1b | `10.0.0.64/26` | `us-east-1b` | 59 | `true` |
| privada 1a | `10.0.0.128/26` | `us-east-1a` | 59 | `false` |
| privada 1b | `10.0.0.192/26` | `us-east-1b` | 59 | `false` |

Os quatro `/26` são contíguos e preenchem o `/24` exatamente (4 × 64 = 256). A VPC fica **100% alocada** — não cabe uma quinta subnet. É a consequência aceita em ADR-0001 **R2**; o caminho de saída, se necessário, é um CIDR secundário via `aws_vpc_ipv4_cidr_block_association` ou um ADR de redesenho.

A região não é variável: sai de `data.aws_region.current.region`, herdada do `provider` da raiz.

## Uso

```hcl
module "network" {
  source = "./modules/network"

  project_name = var.project_name
  environment  = var.environment

  vpc_cidr_block             = var.vpc_cidr_block
  availability_zones         = var.availability_zones
  public_subnet_cidr_blocks  = var.public_subnet_cidr_blocks
  private_subnet_cidr_blocks = var.private_subnet_cidr_blocks

  nat_gateway_az              = var.nat_gateway_az
  enable_nat_gateway          = var.enable_nat_gateway
  enable_flow_logs            = var.enable_flow_logs
  flow_logs_retention_in_days = var.flow_logs_retention_in_days
}
```

## Inputs

| Nome | Tipo | Default | Descrição |
| --- | --- | --- | --- |
| `project_name` | `string` | — | Primeiro segmento da tag `Name`. |
| `environment` | `string` | — | Segundo segmento da tag `Name`. |
| `vpc_cidr_block` | `string` | — | CIDR IPv4 da VPC. |
| `availability_zones` | `list(string)` | — | AZs pinadas por nome. Define **quantas** subnets e route tables privadas são criadas. |
| `public_subnet_cidr_blocks` | `list(string)` | — | CIDRs públicos, na ordem de `availability_zones`. |
| `private_subnet_cidr_blocks` | `list(string)` | — | CIDRs privados, na ordem de `availability_zones`. |
| `nat_gateway_az` | `string` | — | AZ que hospeda o NAT Gateway. Precisa estar em `availability_zones`. |
| `enable_nat_gateway` | `bool` | **`false`** | Liga EIP + NAT Gateway + rotas default privadas. |
| `enable_flow_logs` | `bool` | **`false`** | Liga log group + role + policy + flow log. |
| `flow_logs_retention_in_days` | `number` | — | Retenção do log group. ADR-0001 §10 usa `7`. |

Só as duas flags de custo têm `default`, e é deliberado: se a raiz um dia deixar de repassá-las, o módulo cai no estado de **custo zero** em vez do estado tarifado. O default seguro precisa morar na camada mais interna.

> Os defaults `false` são a **decisão** de ADR-0001 §5, não um placeholder. Não os promova a `true` para facilitar teste. Se o `plan` sem variáveis mostrar qualquer recurso tarifado, o critério de aceite falhou.

## Outputs

| Nome | Tipo | Descrição |
| --- | --- | --- |
| `vpc_id` | `string` | ID da VPC. |
| `vpc_cidr_block` | `string` | CIDR IPv4 da VPC. |
| `internet_gateway_id` | `string` | ID do Internet Gateway. |
| `public_subnet_ids` | `list(string)` | IDs das subnets públicas, na ordem de `availability_zones`. |
| `private_subnet_ids` | `list(string)` | IDs das subnets privadas, na ordem de `availability_zones`. |
| `availability_zones` | `list(string)` | AZs lidas de volta das subnets públicas, não ecoadas da variável de entrada. |
| `public_route_table_id` | `string` | ID da route table pública compartilhada. |
| `private_route_table_ids` | `list(string)` | IDs das route tables privadas, uma por AZ. |
| `nat_gateway_id` | `string` | ID do NAT Gateway, ou **`""`** com a janela de custo fechada. |
| `nat_public_ip` | `string` | IP público do EIP do NAT, ou **`""`**. Muda a cada reabertura da janela. |
| `s3_vpc_endpoint_id` | `string` | ID do Gateway Endpoint de S3. |
| `s3_vpc_endpoint_prefix_list_id` | `string` | Prefix list do endpoint, para usar como destino em regra de egress de SG. |
| `ec2_instance_connect_endpoint_id` | `string` | ID do EIC Endpoint. |
| `default_security_group_id` | `string` | ID do SG default travado — exposto **para ser evitado**, não usado. |
| `flow_log_id` | `string` | ID do flow log, ou **`""`** com a janela fechada. |
| `flow_log_cloudwatch_log_group_name` | `string` | Nome do log group, ou **`""`**. Alvo das queries do Logs Insights. |

Os outputs condicionais retornam **string vazia**, não `null`: vazio aqui é a evidência de que a janela de custo está fechada, não ausência de informação. A raiz expõe apenas os 9 nomes exigidos por ADR-0001 §14 mais `budget_name`.

## Segurança

- **Default SG sem nenhuma regra.** `aws_default_security_group` adota o SG que a AWS criou com a VPC e remove todas as regras. Recurso que caia nele por omissão não se comunica com ninguém — é o objetivo, e resolve `CKV2_AWS_12`.
- **NACL default deliberadamente fora do Terraform** (ADR-0001 §9 e **R5**). Nome parecido, comportamento oposto: declarar `aws_default_network_acl` sem blocos remove as regras 100 allow-all e **derruba todo o tráfego da VPC**.
- **IAM least privilege.** A única role criada é a de flow logs, e só com a flag ligada. Nenhum `Action: "*"`, nenhum `Resource: "*"`. As três ações de escrita ficam presas ao ARN daquele log group com sufixo `:*`; `logs:CreateLogGroup` é omitida porque o Terraform já cria o grupo. Só `logs:DescribeLogGroups` fica em `log-group:*`, limitação da API do CloudWatch Logs.
- **Trust policy com proteção contra confused deputy:** `aws:SourceAccount` e `aws:SourceArn` prendem a role a flow logs desta conta e desta região.
- **Zero segredo.** Não há credencial, chave ou token neste módulo, nem valor sensível em output.

### Limitação conhecida do EIC Endpoint

`aws_ec2_instance_connect_endpoint.this` é criado **sem** `security_group_ids`. A AWS então associa o **default security group da VPC** ao endpoint — e esse SG está vazio por decisão de ADR-0001 §9.

A [documentação da AWS](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/eice-security-groups.html) exige que o SG do endpoint permita **saída na porta 22** em direção às instâncias-alvo. O endpoint é criado sem erro, mas a conexão do passo 12 de ADR-0001 §7 não vai completar.

Nenhum SG é criado aqui para resolver: ADR-0001 §9 determina que SG de aplicação pertence ao ADR de compute. **Item aberto para o Arquiteto** — ver `docs/implementation/ADR-0001-log.md`.

## Nomenclatura

Padrão `<projeto>-<ambiente>-<tipo>` na tag `Name` (ADR-0001 §8): `dvn-workshop-prd-vpc`, `dvn-workshop-prd-vpce-s3`, `dvn-workshop-prd-eice-private-1a`, `dvn-workshop-prd-sg-default-locked`, `dvn-workshop-prd-role-flowlogs`.

Fora do padrão por decisão do ADR: o log group é `/aws/vpc/dvn-workshop-prd/flow-logs`, seguindo a convenção de caminho do CloudWatch.

O sufixo `1a` / `1b` sai de `substr(az, -2, -1)` — os dois últimos caracteres do nome da AZ. É derivação, não literal, porque ADR-0001 §14 proíbe AZ hardcoded dentro do módulo. **Isso pressupõe nomes de AZ no formato `<região><letra>`**, verdadeiro em `us-east-1`.

As outras 6 tags obrigatórias (`Project`, `Environment`, `ManagedBy`, `Owner`, `CostCenter`, `ADR`) vêm de `default_tags` no `provider` da raiz e **não** são declaradas aqui. `Name` não pode ir para `default_tags` porque é por recurso.

> A Cost Allocation Tag `CostCenter` precisa ser **ativada à mão** no console de Billing. O Terraform aplica a tag, não a ativa; sem isso o AWS Budget filtrado não enxerga nada.

## Limitações conhecidas

- **EIC Endpoint sem SG utilizável** — ver *Segurança* acima. É a lacuna mais consequente do módulo hoje.
- **Sem validação de comprimento entre as listas.** Passar `availability_zones` com 2 entradas e `public_subnet_cidr_blocks` com 1 produz erro de índice, não uma mensagem clara. A raiz valida que há exatamente 2 AZs; o pareamento com os CIDRs não é validado em lugar nenhum.
- **NAT Gateway único = SPOF de AZ.** As duas route tables privadas apontam para o mesmo NAT. É o risco **R1**, aceito; a recuperação é trocar `nat_gateway_az` e aplicar.
- **`CKV_AWS_338` falha e não foi suprimido.** O checkov quer 1 ano de retenção; ADR-0001 §10 fixa 7 dias. A decisão é consciente, mas não está na tabela de trade-offs aceitos de §5 — e só §5 autoriza supressão. Falha visível de propósito, aguardando o Arquiteto.
- **`CKV_AWS_130` falha nas 2 subnets públicas.** `map_public_ip_on_launch = true` é habilitação, não exposição (ADR-0001 §9). Pré-existente da etapa 2.
- **`CKV2_AWS_19` falha no EIP do NAT** quando a janela está aberta. Sem decisão humana, não suprimido.

## Convenções

Nomenclatura, organização de arquivos e ordem de argumentos seguem [`.claude/rules/terraform-naming.md`](../../../../.claude/rules/terraform-naming.md): um arquivo por grupo de componentes no padrão `<domínio>.<componente>.tf`, `vpc.tf` contendo só o recurso raiz, `count` como primeiro argumento seguido de linha em branco, `tags` como último argumento real, `_` em identificadores HCL e `-` dentro de valores.

Módulo **não tem `main.tf`** — `vpc.tf` é a raiz do domínio.

> **Comentários em `.tf` devem ficar em ASCII.** O checkov 3.3.10 neste ambiente Windows lê os arquivos como cp1252 e aborta com `UnicodeDecodeError` diante de emoji (o byte `0x8f` de `⚠️`, por exemplo). Acentuação e `§` passam; emoji não.
