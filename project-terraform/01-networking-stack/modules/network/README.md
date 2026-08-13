# Módulo `network`

Camada de rede do laboratório, conforme [ADR-0001 — Arquitetura de rede na AWS](../../../../docs/adr/ADR-0001-arquitetura-de-rede-aws.md).

Módulo com **um único consumidor** — a raiz `01-networking-stack/`. É uma exceção declarada em ADR-0001 §8: praticar composição raiz → módulo é objetivo do exercício, e o futuro ADR de compute vai consumir estes outputs de qualquer forma.

## Estado de implementação

O módulo é construído em etapas. **Hoje ele está incompleto** e não satisfaz sozinho a interface esperada pela raiz.

| Etapa | Componentes | Arquivos | Situação |
| --- | --- | --- | --- |
| 2 | VPC, Internet Gateway, 2 subnets públicas, 2 subnets privadas | `vpc.tf`, `vpc.internet-gateway.tf`, `vpc.public-subnets.tf`, `vpc.private-subnets.tf` | **Implementado** |
| 3 | Route table pública + 2 route tables privadas + associações | `vpc.public-route-table.tf`, `vpc.private-route-tables.tf` | Pendente |
| 3 | Gateway Endpoint S3, EC2 Instance Connect Endpoint, default SG travado | `vpc.endpoints.tf`, `vpc.security-groups.tf` | Pendente |
| 4 | Elastic IP + NAT Gateway (condicionais), VPC Flow Logs (condicionais) | `vpc.nat-gateway.tf`, `vpc.flow-logs.tf` | Pendente |

Enquanto as etapas 3 e 4 não forem concluídas, `terraform validate` **na raiz da stack falha**: `main.tf` passa `nat_gateway_az`, `enable_nat_gateway`, `enable_flow_logs` e `flow_logs_retention_in_days`, que este módulo ainda não declara, e `outputs.tf` referencia outputs de route table e NAT que ainda não existem. Valide o módulo isoladamente até lá:

```powershell
terraform -chdir=modules/network init -backend=false
terraform -chdir=modules/network validate
```

## O que este módulo cria hoje

| Recurso | Qtd | Configuração | Custo |
| --- | --- | --- | --- |
| `aws_vpc.this` | 1 | `enable_dns_support = true`, `enable_dns_hostnames = true`, tenancy `default` | US$ 0,00 |
| `aws_internet_gateway.this` | 1 | Anexado à VPC | US$ 0,00 |
| `aws_subnet.public` | 2 | Uma por AZ, `map_public_ip_on_launch = true` | US$ 0,00 |
| `aws_subnet.private` | 2 | Uma por AZ, `map_public_ip_on_launch = false` | US$ 0,00 |

**Nada aqui é tarifado.** Todo o custo desta camada mora no NAT Gateway e nos Flow Logs, que chegam na etapa 4 sob `count`, com `default = false`.

## Endereçamento

Valores fixados pela usuária em ADR-0001 §2 e passados pela raiz. O módulo não conhece nenhum deles — não há CIDR, AZ nem nome literal aqui dentro.

| Subnet | CIDR | AZ | IPs utilizáveis | `map_public_ip_on_launch` |
| --- | --- | --- | --- | --- |
| pública 1a | `10.0.0.0/26` | `us-east-1a` | 59 | `true` |
| pública 1b | `10.0.0.64/26` | `us-east-1b` | 59 | `true` |
| privada 1a | `10.0.0.128/26` | `us-east-1a` | 59 | `false` |
| privada 1b | `10.0.0.192/26` | `us-east-1b` | 59 | `false` |

Os quatro `/26` são contíguos e preenchem o `/24` exatamente (4 × 64 = 256). A VPC fica **100% alocada** — não cabe uma quinta subnet. É a consequência aceita em ADR-0001 **R2**; o caminho de saída, se necessário, é um CIDR secundário via `aws_vpc_ipv4_cidr_block_association` ou um ADR de redesenho.

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
}
```

## Inputs

| Nome | Tipo | Obrigatório | Descrição |
| --- | --- | --- | --- |
| `project_name` | `string` | sim | Primeiro segmento da tag `Name`. |
| `environment` | `string` | sim | Segundo segmento da tag `Name`. |
| `vpc_cidr_block` | `string` | sim | CIDR IPv4 da VPC. |
| `availability_zones` | `list(string)` | sim | AZs pinadas por nome. Define **quantas** subnets são criadas. |
| `public_subnet_cidr_blocks` | `list(string)` | sim | CIDRs públicos, na ordem de `availability_zones`. |
| `private_subnet_cidr_blocks` | `list(string)` | sim | CIDRs privados, na ordem de `availability_zones`. |

Nenhuma variável tem `default`: o contrato é que a raiz forneça tudo. As três listas precisam ter **o mesmo comprimento** — o módulo não valida isso (ver *Limitações*).

## Outputs

| Nome | Tipo | Descrição |
| --- | --- | --- |
| `vpc_id` | `string` | ID da VPC. |
| `vpc_cidr_block` | `string` | CIDR IPv4 da VPC. |
| `internet_gateway_id` | `string` | ID do Internet Gateway. |
| `public_subnet_ids` | `list(string)` | IDs das subnets públicas, na ordem de `availability_zones`. |
| `private_subnet_ids` | `list(string)` | IDs das subnets privadas, na ordem de `availability_zones`. |
| `availability_zones` | `list(string)` | AZs lidas de volta das subnets públicas, não ecoadas da variável de entrada. |

## Nomenclatura

Padrão `<projeto>-<ambiente>-<tipo>` na tag `Name` (ADR-0001 §8): `dvn-workshop-prd-vpc`, `dvn-workshop-prd-igw`, `dvn-workshop-prd-subnet-public-1a`, `dvn-workshop-prd-subnet-private-1b`.

O sufixo `1a` / `1b` sai de `substr(az, -2, -1)` — os dois últimos caracteres do nome da AZ. É derivação, não literal, porque ADR-0001 §14 proíbe AZ hardcoded dentro do módulo. **Isso pressupõe nomes de AZ no formato `<região><letra>`**, verdadeiro em `us-east-1`.

As outras 6 tags obrigatórias (`Project`, `Environment`, `ManagedBy`, `Owner`, `CostCenter`, `ADR`) vêm de `default_tags` no `provider` da raiz e **não** são declaradas aqui. `Name` não pode ir para `default_tags` porque é por recurso.

> A Cost Allocation Tag `CostCenter` precisa ser **ativada à mão** no console de Billing. O Terraform aplica a tag, não a ativa; sem isso o AWS Budget filtrado não enxerga nada.

## Limitações conhecidas

- **Sem validação de comprimento entre as listas.** Passar `availability_zones` com 2 entradas e `public_subnet_cidr_blocks` com 1 produz erro de índice, não uma mensagem clara. A raiz valida que há exatamente 2 AZs; o pareamento com os CIDRs não é validado em lugar nenhum.
- **Sem `depends_on` entre subnets e IGW.** É correto: subnet não depende do IGW. Quem depende é o NAT Gateway, e o `depends_on` explicitado em ADR-0001 §15 ponto 3 entra na etapa 4.
- **Rota de saída inexistente.** Sem as route tables da etapa 3, nenhuma subnet tem rota `0.0.0.0/0` — nem as públicas. Aplicar o módulo neste estado cria uma rede sem conectividade externa.

## Convenções

Nomenclatura, organização de arquivos e ordem de argumentos seguem [`.claude/rules/terraform-naming.md`](../../../../.claude/rules/terraform-naming.md): um arquivo por grupo de componentes no padrão `<domínio>.<componente>.tf`, `vpc.tf` contendo só o recurso raiz, `count` como primeiro argumento seguido de linha em branco, `tags` como último argumento real, `_` em identificadores HCL e `-` dentro de valores.

Módulo **não tem `main.tf`** — `vpc.tf` é a raiz do domínio.
