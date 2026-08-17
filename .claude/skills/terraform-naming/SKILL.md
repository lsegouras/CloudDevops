---
name: terraform-naming
description: Convenções de nomenclatura e ordenação para código Terraform. Obrigatória ao escrever ou revisar .tf neste repositório.
source: https://www.terraform-best-practices.com/naming
---

# Nomenclatura Terraform

Regras obrigatórias para todo `.tf` deste repositório. Fonte: [terraform-best-practices.com/naming](https://www.terraform-best-practices.com/naming).

## Geral

- Use `_` (underscore), nunca `-` (dash), em nomes de recurso, data source, variável, output e módulo.
- Use letras minúsculas e números. UTF-8 é suportado, mas não use.
- Use `-` **dentro de valores** de argumento e em qualquer lugar exposto a humano — nome de DNS, tag `Name`, identificador de RDS.

```hcl
# nome do recurso com _, valor com -
resource "aws_subnet" "public_1a" {
  tags = { Name = "dvn-workshop-prd-public-1a" }
}
```

## Organização de arquivos

Um arquivo por grupo de componentes, nomeado **`<domínio>.<componente>.tf`**. Nunca concentre um domínio inteiro em `main.tf`.

```text
modules/network/
├── vpc.tf                        # o recurso raiz do domínio
├── vpc.internet-gateway.tf
├── vpc.public-subnets.tf
├── vpc.private-subnets.tf
├── vpc.public-route-table.tf
├── vpc.private-route-tables.tf
├── vpc.nat-gateway.tf
├── vpc.endpoints.tf
├── vpc.flow-logs.tf
├── vpc.security-groups.tf
├── variables.tf
├── outputs.tf
└── versions.tf
```

Regras:

- **`<domínio>.tf`** contém o recurso raiz — `vpc.tf` tem o `aws_vpc`, e nada mais.
- **Separador entre segmentos:** `.` (ponto). **Dentro de um segmento:** `-` (dash).
- **Singular ou plural conforme a quantidade** de recursos no arquivo: `vpc.public-route-table.tf` (uma route table pública) e `vpc.private-route-tables.tf` (uma por AZ).
- Recurso e tudo que existe só para ele ficam **no mesmo arquivo**: rotas e associações moram junto da sua route table; o Elastic IP mora junto do NAT Gateway; log group, IAM role e policy moram junto do flow log.
- Recurso condicional fica no arquivo do seu componente, com o `count` nele — não crie um `conditional.tf`.
- **Nomes fixos, fora do padrão:** `variables.tf`, `outputs.tf`, `versions.tf`, `providers.tf`, `backend.tf`, `terraform.tfvars`. Não os renomeie.
- `main.tf` só existe na **raiz de ambiente** (`envs/<ambiente>/`), onde contém as chamadas de `module`. Módulo não tem `main.tf`.
- Outro domínio, outro prefixo: `ecs.tf`, `ecs.task-definitions.tf`, `rds.tf`, `rds.parameter-group.tf`.

> O `-` em **nome de arquivo** é intencional e não contradiz a regra do `_`. Aquela regra vale para identificadores dentro do HCL — nome de recurso, variável e output. Nome de arquivo não é identificador.

## Recursos e data sources

**Não repita o tipo no nome.** O tipo já está na primeira string.

```hcl
resource "aws_route_table" "public" {}              # certo
resource "aws_route_table" "public_route_table" {}  # errado
```

**Use `this`** quando não houver nome mais descritivo, ou quando o módulo cria um único recurso daquele tipo.

**Sempre substantivo no singular.** `aws_subnet.public`, não `aws_subnet.publics`.

### Ordem dos argumentos

1. `count` / `for_each` — primeiro, seguido de linha em branco
2. argumentos reais
3. `tags` — último argumento real
4. `depends_on`
5. `lifecycle`

```hcl
resource "aws_nat_gateway" "this" {
  count = 2

  allocation_id = "..."
  subnet_id     = "..."

  tags = {
    Name = "..."
  }

  depends_on = [aws_internet_gateway.this]

  lifecycle {
    create_before_destroy = true
  }
}
```

### Condições em count / for_each

Prefira booleano a `length()` ou outras expressões.

```hcl
count = var.create_public_subnets ? 1 : 0        # melhor
count = length(var.public_subnets) > 0 ? 1 : 0   # aceitável
```

## Variáveis

- **Forma plural** quando o tipo for `list(...)` ou `map(...)`.
- **Ordem das chaves:** `description`, `type`, `default`, `validation`.
- `description` é **obrigatória** em toda variável, mesmo quando parecer óbvia.
- Reaproveite `name`, `description` e `default` da seção *Argument Reference* do recurso. Não reinvente.
- Prefira tipos simples (`number`, `string`, `list(...)`, `map(...)`, `any`) a `object()`, salvo necessidade real de restrição.
- Use `map(map(string))` quando todos os elementos tiverem o mesmo tipo.
- Use `any` para desligar validação a partir de certa profundidade ou quando múltiplos tipos forem válidos.
- **Evite dupla negativa.** `encryption_enabled`, nunca `encryption_disabled`.
- Para variáveis que nunca devem ser `null`, defina `nullable = false` — assim passar `null` usa o default.
- `{}` às vezes é map, às vezes object. Use `tomap(...)` quando precisar garantir map.

```hcl
variable "private_subnets" {
  description = "Lista de CIDRs das subnets privadas"
  type        = list(string)
  default     = []
  nullable    = false
}
```

## Outputs

Padrão de nome: **`{name}_{type}_{attribute}`**

- `{name}` — nome do recurso ou data source
- `{type}` — tipo sem o prefixo do provider (`aws_security_group` → `security_group`)
- `{attribute}` — atributo retornado

Regras:

- Quando o valor vem de interpolação sobre múltiplos recursos, `{name}` e `{type}` devem ser genéricos. **Omita o prefixo `this`.**
- Valor que é lista recebe **nome plural**.
- `description` é obrigatória em todo output.
- Não use `sensitive` a menos que você controle todo o uso daquele output em todos os módulos.
- Prefira `try()` a `element(concat(...))`.

```hcl
# certo
output "security_group_id" {
  description = "The ID of the security group"
  value       = try(aws_security_group.this[0].id, aws_security_group.name_prefix[0].id, "")
}

# errado — prefixo this, element(concat(...))
output "this_security_group_id" {
  description = "The ID of the security group"
  value       = element(concat(coalescelist(aws_security_group.this.*.id, aws_security_group.web.*.id), [""]), 0)
}

# lista recebe nome plural
output "rds_cluster_instance_endpoints" {
  description = "A list of all cluster instance endpoints"
  value       = aws_rds_cluster_instance.this.*.endpoint
}
```

## Observação sobre `validation`

O suporte a `validation` em variáveis é limitado — não referencia outras variáveis nem valores conhecidos só em runtime. Planeje sem contar com ele para validação complexa.
