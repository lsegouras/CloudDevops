# ADR-0001 — Log de implementação

Arquivo append-only. Nunca reescreva entradas anteriores.

---

## 2026-08-12 — Etapa 1 de 5: raiz Terraform e AWS Budget

**Executor:** devops-engineer · **Branch:** `feat/adr-0001-networking-stack`
**ADR:** `docs/adr/ADR-0001-arquitetura-de-rede-aws.md` — status `Aprovado` em 2026-08-12 por Laura.
**Escopo desta etapa:** passo 1 do §7 (AWS Budget) mais o esqueleto do root Terraform. Nenhum recurso de rede.

### Feito

Diretório `project-terraform/01-networking-stack/`:

| Arquivo | Conteúdo |
| --- | --- |
| `versions.tf` | `required_version = "~> 1.13"`; `hashicorp/aws ~> 6.58`. |
| `providers.tf` | `provider "aws"` com `region`, `profile` e `default_tags` com as 6 tags obrigatórias do §8. `Name` fica de fora, por recurso. |
| `backend.tf` | Backend `s3`, key `prd/network/terraform.tfstate`, `encrypt = true`, `use_lockfile = true`. Sem `dynamodb_table`. |
| `variables.tf` | 21 variáveis, todas com `description`; ordem de chaves `description, type, default, validation`; `nullable = false` em todas; plural em `list(...)`. |
| `terraform.tfvars` | Valores concretos de `prd`. Nenhum segredo. |
| `budget.tf` | `aws_budgets_budget.this` — US$ 5,00, período customizado, `cost_filter` por `TagKeyValue`, 4 notificações. |
| `main.tf` | `module "network"` apontando para `./modules/network`. |
| `outputs.tf` | Os 9 outputs exigidos pelo §14 mais `budget_name`. |
| `.terraform.lock.hcl` | `hashicorp/aws 6.59.0`, com checksums para `windows_amd64`, `linux_amd64` e `darwin_arm64`. |

Fora do diretório: `.gitignore` ganhou a exceção `!project-terraform/**/terraform.tfvars`. Ver Divergências.

**Decisões de implementação dentro do que o ADR já decidiu:**

- `budget_time_unit = "ANNUALLY"`. O AWS Budgets não tem `time_unit` "CUSTOM"; o período customizado se expressa por `time_period_start`/`time_period_end`. `MONTHLY` resetaria o teto todo mês e transformaria os US$ 5,00 num limite mensal, violando C1. Com `ANNUALLY` mais as datas, o curso inteiro cabe num único período.
- As 4 notificações foram escritas como blocos explícitos, não via `dynamic`. Os thresholds 40/60/80 `ACTUAL` e 100 `FORECASTED` são a decisão do §11.5, não configuração de ambiente; explícito é auditável linha a linha contra o ADR.
- `outputs.tf` foi escrito completo, não como esqueleto vazio. Os outputs definem o contrato que `modules/network` precisa cumprir nas etapas 2 a 4 — são a especificação do módulo, não um reflexo dele.

**Consultas ao MCP `terraform` (o ADR §16 registrou que o MCP não estava disponível quando foi escrito; nesta sessão estava):**

- `get_latest_provider_version(hashicorp/aws)` → **6.59.0**. O pin `~> 6.58` do ADR admite 6.59.0 (`>= 6.58.0, < 7.0.0`), então o ADR não precisa mudar.
- `get_provider_details(aws_budgets_budget @ 6.59.0)` → confirmados `budget_type`, `time_unit`, `limit_amount`, `limit_unit`, `time_period_start`/`_end` (formato `AAAA-MM-DD_HH:MM`), bloco `cost_filter` (`name` = `TagKeyValue`, valores no formato `TagKey$TagValue` com prefixo `user:` para tags de usuário) e bloco `notification` (`comparison_operator`, `threshold`, `threshold_type`, `notification_type`, `subscriber_email_addresses`). Nenhum argumento foi escrito de memória.

### Validado

| Validação | Resultado |
| --- | --- |
| `terraform version` | v1.15.8 — satisfaz `~> 1.13`. |
| `terraform fmt -check` | **exit 0**, limpo. |
| `terraform init -backend=false` (pasta real) | **Falha esperada:** `Unreadable module directory ... modules\network`. É a etapa 2. |
| `terraform init -backend=false` (cópia isolada, sem `main.tf`/`outputs.tf`) | **exit 0.** Provider resolvido: `hashicorp/aws v6.59.0`. |
| `terraform validate` (cópia isolada) | **exit 0** — "Success! The configuration is valid." |
| `tflint` 0.64.0 (pasta real) | **Falha esperada:** módulo `network` não encontrado. |
| `tflint` 0.64.0 (cópia isolada) | 8 `terraform_unused_declarations`. **Todos artefato do setup de validação** — as 8 variáveis são consumidas por `main.tf`, removido da cópia. Zero achado real. |
| `checkov` 3.3.10 (pasta real) | **Passed 1, Failed 0, Skipped 0.** Único check: `CKV_AWS_41` — "Ensure no hard coded AWS access key and secret key exists in provider" — **PASSED**. Nenhuma supressão foi necessária nesta etapa. |

Superfície de segurança do checkov ainda é mínima: nesta etapa só existem o provider e o budget. Os checks que o §7 passo 10 antecipa vão aparecer quando `modules/network` existir.

**Nada foi aplicado na AWS.** Nenhum `apply`, nenhum comando mutante. A única chamada à AWS foi `sts get-caller-identity`, leitura pura, para compor o nome do bucket do backend.

### Pendente

| # | Item | Bloqueia |
| --- | --- | --- |
| 1 | **Bucket de state não existe** (§7 passo 2). `terraform init` com backend vai falhar. | `init` real, e portanto o `apply` do budget. |
| 2 | **Profile `app_cloud_devops` com sessão expirada.** `aws sts get-caller-identity --profile app_cloud_devops` retorna `Your session has expired`. Pré-requisito 3 do handoff **não satisfeito**. | Qualquer `plan` ou `apply`. |
| 3 | **Datas do curso não confirmadas** (pré-requisito 6, bloqueante). Assumidos `2026-08-01_00:00` e `2026-12-03_00:00`. | Correção do `terraform.tfvars` antes do apply. |
| 4 | **Valor da tag `Owner` não confirmado** (pré-requisito 9, não bloqueante). Assumido `laura`. | Nada. Tag é trivial de corrigir. |
| 5 | **P8 e P9 sem resposta do professor** (pré-requisito 2, bloqueante pelo handoff). | Decisão de escopo, não o código. |
| 6 | **Cost Allocation Tag `CostCenter` não ativada** no console de Billing. Passo manual; leva até 24 h. | O `cost_filter` do budget fica cego até lá. |
| 7 | **Assinatura de e-mail do budget** precisa ser confirmada após o apply. | Os alertas não chegam sem isso. |
| 8 | `modules/network/` inteiro — etapas 2 a 4. | Etapas seguintes. |

### Divergências

Voltam para o `cloud-devops-architect`. Não editei o ADR.

1. **Layout de diretórios.** A usuária determinou `project-terraform/01-networking-stack/` como a raiz Terraform, substituindo `envs/prd/` do §8. A pasta numerada **é** o root; o módulo vai em `01-networking-stack/modules/network/`, não em `project-terraform/modules/network/`. Consequência: o `source` do módulo é `./modules/network`, não `../../modules/network`. Determinação da usuária, superior ao ADR. **Sugiro atualizar o §8.**

2. **`.gitignore` versus §8.** O `.gitignore` do repositório traz `*.tfvars` do template toptal, o que impediria o `terraform.tfvars` de ser versionado — e o §8 o exige commitado. Adicionei `!project-terraform/**/terraform.tfvars`, escopada: qualquer outro `.tfvars`, inclusive `*.auto.tfvars`, continua ignorado. Alteração fora de `01-networking-stack/`, registrada aqui por transparência.

3. **`time_unit` do budget.** O §11.5 pede "cost budget de período customizado" sem nomear o `time_unit`. A API não tem valor "CUSTOM". Implementado como `ANNUALLY` mais `time_period_start`/`_end`. **Sugiro que o §11.5 diga isso explicitamente**, porque `MONTHLY` é a leitura intuitiva e transformaria o teto do curso num teto mensal.

4. **Identidade da conta.** O §16 e o C4 falam do profile `app_cloud_devops`. O profile local existe mas está com sessão expirada. A identidade efetiva obtida via MCP `aws-mcp` é um **usuário IAM com nome diferente do que o ADR descreve**, na conta esperada. Não é bloqueio de código, mas o pré-requisito 3 do handoff não está satisfeito e o §9 pode estar descrevendo um principal que não é o que será usado. **Vale o arquiteto confirmar qual principal é o correto.**

5. **MCP `terraform` disponível.** O §16 declara que o MCP não estava acessível e que as versões vieram da API pública do Registry. Nesta sessão o MCP respondeu e **confirmou os dados** — `6.59.0` como última versão, dentro do pin. A ressalva do §16 pode ser removida na próxima revisão do ADR.

### Sugestões

Identificadas e **não implementadas**, por estarem fora do escopo desta etapa.

1. **`.tflint.hcl` no root do stack**, habilitando o ruleset `aws`. O ruleset bundled só cobre regras de linguagem; o plugin AWS pega argumento inválido e tipo de instância inexistente — exatamente a classe de erro mais cara nas etapas 2 a 4.
2. **`terraform.tfvars` com as datas do budget** poderia virar `budget.auto.tfvars` separado, para que a confirmação do professor mude um arquivo só. Marginal; não vale antes das datas serem conhecidas.
3. **Bucket de state via bootstrap versionado.** O §7 passo 2 o cria out-of-band, à mão. Um root `00-bootstrap/` com state local commitado deixaria o bucket rastreável. Muda a estrutura decidida no §8, portanto é decisão do arquiteto.
4. **Verificação diária do §11.5 como script versionado** em vez de comandos soltos no ADR. Reduz a chance de o passo ser pulado, que é a mitigação central de R0.

### Risco residual

1. 🔴 **As datas do budget são presunção minha, não decisão humana.** Se o curso começou antes de `2026-08-01`, o budget não enxerga o gasto anterior; se vai além de `2026-12-03`, para de vigiar antes do fim. O arquivo marca isso em maiúsculas, mas o risco só some com a resposta do professor.
2. 🟠 **A proteção de custo depende de dois passos manuais** — ativar a Cost Allocation Tag e confirmar a assinatura de e-mail. Nenhum dos dois é verificável por `terraform plan`. Um budget aplicado com os dois pendentes **parece** proteção e não é. Esse é o cenário exato que o §14 chama de "proteção ilusória".
3. 🟠 **Não há ambiente de validação anterior ao alvo.** O ADR define um único ambiente, `prd`, e eu segui o ADR. Consequência: não existe `dev` nem `staging` onde errar barato. **Toda aplicação nesta stack é aplicação em produção** e exige plan revisado e aprovação humana explícita, sem exceção.
4. 🟡 **`main.tf` e `outputs.tf` estão referenciando um módulo que não existe.** O `init` falha até a etapa 2 terminar. É intencional e foi acordado, mas deixa a branch num estado que não passa em CI, caso exista CI antes da etapa 4.
5. 🟡 **O lock file foi gerado num diretório de trabalho isolado** e copiado, porque o `init` na pasta real não completa sem o módulo. O conteúdo é função apenas do `required_providers`, que é idêntico, mas o arquivo será legitimamente regravado no primeiro `init` completo da etapa 3.

### Corpo do PR — para colar no GitHub

> `gh` **está** instalado neste ambiente (`C:\Program Files\GitHub CLI\gh.exe`), ao contrário do que a configuração do agente presume. Nenhum PR foi aberto: a entrega é 1 de 5 etapas e o PR pertence ao §7 passo 16.

```markdown
## ADR-0001 — Arquitetura de rede AWS (etapa 1 de 5)

Implementa: docs/adr/ADR-0001-arquitetura-de-rede-aws.md · Etapas: 1 de 5

### O que muda

Cria a raiz Terraform em `project-terraform/01-networking-stack/` — versions, providers
com as 6 tags obrigatórias, backend S3 com locking nativo, variáveis e tfvars de `prd` —
e o AWS Budget de US$ 5,00 com os 4 alertas do §11.5, que o §7 exige antes de qualquer
outro recurso. Nenhum recurso de rede: `modules/network/` é etapa 2. Nada foi aplicado.

### Plan

Não executado. O bucket de state não existe e `modules/network` também não, então
`terraform init` não completa. Validação possível hoje: `fmt -check` limpo,
`validate` limpo na configuração sem a chamada de módulo, `checkov` 1 passed / 0 failed.

Quando o plan for possível, o esperado é **1 to add, 0 to change, 0 to destroy**
(`aws_budgets_budget.this`). Nenhum recurso tarifado — o budget custa US$ 0,00.

### Ambientes

- [ ] production (`prd`) — único ambiente do ADR. Não aplicado.

### Critérios de aceite (ADR §14)

- [x] `terraform fmt -check` limpo — exit 0
- [x] `required_version = "~> 1.13"`; provider AWS `~> 6.58` — resolvido em 6.59.0
- [x] `.terraform.lock.hcl` commitado — windows_amd64, linux_amd64, darwin_arm64
- [x] `enable_nat_gateway` e `enable_flow_logs` com `default = false` e a tarifa na `description`
- [x] `backend "s3"` e `provider "aws"` somente no root
- [x] As 6 tags obrigatórias via `default_tags`
- [x] `checkov` executado — 1 passed, 0 failed, nenhuma supressão necessária
- [~] `terraform validate` e `tflint` — limpos na configuração sem a chamada de módulo;
      falham na pasta real por `modules/network` ausente (etapa 2)
- [ ] Budget existe na conta com as 4 notificações e assinatura confirmada — **não aplicado**
- [ ] Cost Allocation Tag `CostCenter` ativada no console — **passo manual pendente**
- [ ] Demais critérios de Infraestrutura e Validação funcional — etapas 2 a 5

### Segurança

Nenhum segredo em nenhum arquivo. `terraform.tfvars` contém apenas CIDRs, AZs, nomes,
flags de custo e o e-mail de alerta do budget — sem credencial, chave ou token.
`checkov` CKV_AWS_41 (chave de acesso hardcoded no provider) **passou**.
Nenhuma alteração de IAM, Security Group ou superfície de exposição nesta etapa.
`.gitignore` ganhou exceção escopada para versionar `terraform.tfvars`; todo outro
`.tfvars` continua ignorado.

### Rollback

Nada foi aplicado — não há infraestrutura a reverter. Para descartar o código:
`git revert <commit>` ou remover a branch. O `.gitignore` volta com o mesmo revert.
```

---

## 2026-08-13 — Etapa 2 de 5: VPC, Internet Gateway e as 4 subnets

**Executor:** devops-engineer · **Branch:** `feat/adr-0001-networking-stack`
**ADR:** `docs/adr/ADR-0001-arquitetura-de-rede-aws.md` — status `Aprovado` em 2026-08-12 por Laura.
**Escopo desta etapa:** primeira metade do passo 4 do §7 — VPC, IGW e as 4 subnets. Route tables e associações ficaram para a etapa 3. Nenhum recurso tarifado, nenhum `plan` contra a AWS, nenhum `apply`.

> **Data.** O prompt desta invocação informou 2026-08-12. `date +%F` no ambiente retorna **2026-08-13**, e é a data registrada aqui, conforme a instrução de usar a data real.

### Feito

Diretório novo `project-terraform/01-networking-stack/modules/network/`:

| Arquivo | Conteúdo |
| --- | --- |
| `vpc.tf` | `aws_vpc.this` — e nada mais, conforme a regra de organização. `enable_dns_support` e `enable_dns_hostnames` em `true`, `instance_tenancy = "default"`. |
| `vpc.internet-gateway.tf` | `aws_internet_gateway.this` anexado à VPC. |
| `vpc.public-subnets.tf` | `aws_subnet.public` com `count = length(var.availability_zones)`, `map_public_ip_on_launch = true`. |
| `vpc.private-subnets.tf` | `aws_subnet.private` com `count = length(var.availability_zones)`, `map_public_ip_on_launch = false`. |
| `variables.tf` | 6 variáveis, apenas as consumidas pelos arquivos acima. Todas com `description`, todas `nullable = false`, nenhuma com `default`. |
| `outputs.tf` | 6 outputs, apenas dos recursos acima. |
| `versions.tf` | `required_providers` com `hashicorp/aws ~> 6.58`. Sem bloco `provider`, sem `backend`. Ver Divergências item 2. |
| `README.md` | Estado de implementação por etapa, tabela de endereçamento, inputs, outputs, nomenclatura e limitações conhecidas. |

**Decisões de implementação dentro do que o ADR já decidiu:**

- **`count` em vez de recursos nomeados um a um.** `length(var.availability_zones)` governa a quantidade de subnets, então acrescentar uma AZ é mudança de `terraform.tfvars`, não de código. A ordem das três listas (`availability_zones`, `public_subnet_cidr_blocks`, `private_subnet_cidr_blocks`) é o contrato de pareamento.
- **Sufixo `1a`/`1b` da tag `Name` derivado, não literal.** `substr(var.availability_zones[count.index], -2, -1)` extrai os dois últimos caracteres do nome da AZ. O §14 proíbe AZ hardcoded dentro de `modules/network`, e um literal `"1a"` seria exatamente isso. Assinatura de `substr` e o suporte a offset negativo com `length = -1` confirmados na documentação da linguagem.
- **`enable_dns_support`/`enable_dns_hostnames` fixados em `true` no código, não parametrizados.** São invariantes de arquitetura do §6 cobradas pelo §14, não valores de ambiente — não estão em `terraform.tfvars` nem são passados por `main.tf`. O padrão do provider para `enable_dns_hostnames` é `false`, então a atribuição explícita é obrigatória.
- **Nenhuma variável do módulo tem `default`.** O contrato é que a raiz forneça tudo; um `default` no módulo mascararia esquecimento na raiz.
- **`output "availability_zones"` lê de volta de `aws_subnet.public[*].availability_zone`**, em vez de ecoar `var.availability_zones`. O output passa a refletir o que foi criado, não o que foi pedido.
- **`internet_gateway_id` exposto** além dos outputs listados no §14. O IGW é um dos recursos desta etapa e o output é barato; os 9 outputs do §14 são o mínimo da raiz, não o teto do módulo.

**Fonte substituta declarada — o MCP `terraform` estava indisponível nesta sessão.** Nenhuma ferramenta desse servidor foi exposta (`ToolSearch` com `+terraform` retornou vazio); o Docker estava reiniciando. O MCP `aws-mcp` estava disponível e não foi necessário — esta etapa não consultou a conta.

Os argumentos de recurso **não foram escritos de memória**. As páginas do Terraform Registry são renderizadas por JavaScript e voltaram vazias no `WebFetch`, então a fonte usada foi a **documentação-fonte do provider no repositório oficial** (`raw.githubusercontent.com/hashicorp/terraform-provider-aws/main/website/docs/r/`), que é o markdown do qual o Registry é gerado:

| Recurso | Argumentos confirmados |
| --- | --- |
| `aws_vpc` | `cidr_block`, `instance_tenancy`, `enable_dns_support` (default `true`), `enable_dns_hostnames` (**default `false`**), `tags`. Atributos `id`, `arn`, `cidr_block`. |
| `aws_subnet` | `vpc_id` (obrigatório), `cidr_block`, `availability_zone` (nome, ex.: `us-east-1a`), `availability_zone_id` (ID, **não usado**), `map_public_ip_on_launch`, `tags`. Atributos `id`, `arn`. |
| `aws_internet_gateway` | `vpc_id`, `tags`. Atributos `id`, `arn`, `owner_id`. |
| função `substr` | `substr(string, offset, length)`; offset negativo conta do fim, `length = -1` vai até o fim. |

### Validado

| Validação | Comando | Resultado |
| --- | --- | --- |
| Formatação | `terraform fmt -check -recursive` | **exit 0**, limpo. Nenhum arquivo reformatado. |
| Init do módulo | `terraform init -backend=false` em `modules/network` | **exit 0.** Provider resolvido: `hashicorp/aws v6.59.0`, dentro do pin `~> 6.58`. |
| Validate do módulo | `terraform validate` em `modules/network` | **exit 0** — "Success! The configuration is valid." |
| Init/validate da raiz | `terraform init -backend=false` em `01-networking-stack` | **Falha esperada, exit 1.** 4 erros `Unsupported argument`: `nat_gateway_az`, `enable_nat_gateway`, `enable_flow_logs`, `flow_logs_retention_in_days`. São exatamente as variáveis das etapas 3 e 4. Ver Risco residual 1. |
| Lint | `tflint --recursive` 0.64.0 | **exit 0, 0 issues** — depois da correção descrita em Divergências item 2. Na primeira passada: 1 warning `terraform_required_version`. |
| Policy scan | `checkov -d modules/network --var-file terraform.tfvars` 3.3.10 | **2 passed, 4 failed, 0 skipped.** Detalhe abaixo. |
| Policy scan (stack) | `checkov -d . --var-file terraform.tfvars --skip-path .terraform` | **3 passed, 4 failed, 0 skipped.** Mesmos 4 achados. |

**Os 4 achados do checkov — nenhum suprimido nesta etapa.** O §7 passo 10 é o momento de suprimir, com comentário justificado apontando para o ADR; suprimir agora seria antecipar etapa e esconder achado que o passo 3 ainda vai resolver sozinho.

| ID | Recurso | Situação |
| --- | --- | --- |
| `CKV_AWS_130` | `aws_subnet.public[0]`, `aws_subnet.public[1]` | **Candidato legítimo a supressão.** `map_public_ip_on_launch = true` é exigência do §6 e do §14, e o §9 já registra que é habilitação, não exposição. As duas subnets privadas **passaram** neste mesmo check. |
| `CKV2_AWS_11` | `aws_vpc.this` | Flow logging. `vpc.flow-logs.tf` é etapa 4 e, por decisão do §5, fica condicional com `default = false`. Provavelmente continuará falhando depois da etapa 4 — é o trade-off "Flow Logs sempre ligados: sacrificado". |
| `CKV2_AWS_12` | `aws_vpc.this` | Default SG restritivo. `vpc.security-groups.tf` é etapa 3 e resolve o achado de fato, sem supressão. |

**Achado operacional sobre o checkov — vale para todas as etapas seguintes.** Rodar `checkov -d modules/network` **sem** `--var-file` reporta `Passed 0, Failed 2` e **omite as 4 subnets por completo**: sem valor para `var.availability_zones`, o checkov não resolve `count = length(...)` e **descarta o recurso silenciosamente**, sem aviso. `CKV_AWS_130` e `CKV2_AWS_1` simplesmente não aparecem. Um scan "limpo" nessas condições é falso negativo. **Todo scan deste módulo precisa de `--var-file terraform.tfvars`.**

**Nada foi aplicado na AWS.** Nenhum `plan` contra a conta, nenhum comando mutante, nenhuma chamada à AWS nesta etapa. Os artefatos de `init` do módulo (`.terraform/` e `.terraform.lock.hcl`) foram removidos após a validação — módulo filho não é root e não carrega lock próprio; o lock da raiz não foi tocado.

### Pendente

| # | Item | Bloqueia |
| --- | --- | --- |
| 1 | `vpc.public-route-table.tf` e `vpc.private-route-tables.tf` — RT pública com `0.0.0.0/0 → igw` + 2 associações, e 2 RTs privadas com associação 1:1, **sem rota default**. | Etapa 3. Também destrava o `init` da raiz. |
| 2 | `vpc.endpoints.tf` — Gateway Endpoint S3 nas 2 RTs privadas + EC2 Instance Connect Endpoint em `private-1a`. | Etapa 3. |
| 3 | `vpc.security-groups.tf` — `aws_default_security_group` sem regras. Resolve `CKV2_AWS_12`. | Etapa 3. |
| 4 | `vpc.nat-gateway.tf` e `vpc.flow-logs.tf`, condicionais. | Etapa 4. |
| 5 | Variáveis `nat_gateway_az`, `enable_nat_gateway`, `enable_flow_logs`, `flow_logs_retention_in_days` no módulo. | Etapas 3 e 4. `init` da raiz falha até lá. |
| 6 | Outputs `public_route_table_id`, `private_route_table_ids`, `nat_gateway_id`, `nat_public_ip`. | Etapas 3 e 4. |
| 7 | Todos os 8 itens pendentes da etapa 1 seguem pendentes — bucket de state, sessão do profile, datas do curso, tag `Owner`, P8/P9, Cost Allocation Tag, assinatura de e-mail. | `plan` e `apply` reais. |

### Divergências

Voltam para o `cloud-devops-architect`. Não editei o ADR.

1. **Layout de diretórios — divergência já decidida pela usuária, não reaberta.** A stack fica em `project-terraform/01-networking-stack/` como raiz Terraform, com `modules/network/` dentro dela, substituindo `envs/prd/` do §8. Determinação da usuária, superior ao ADR. Registrada por continuidade com a etapa 1; **não escalada de novo**.

2. **`required_version` no `versions.tf` do módulo — conflito interno do ADR.** O layout do §8 anota o arquivo do módulo como "required_providers apenas", mas a regra `terraform_required_version` do tflint exige a restrição também em módulo, e o §14 pede **"tflint limpo"** como critério de aceite. Os dois pontos do ADR não podem ser satisfeitos ao mesmo tempo. **Resolvi a favor do §14**: o critério de aceite é decisão normativa, o comentário de layout é descritivo, e desabilitar a regra do linter para passar é proibido. Adicionado `required_version = "~> 1.13"`, idêntico ao da raiz, o que não altera resolução de versão. Divergência documentada no próprio arquivo. **Sugiro que o §8 troque "required_providers apenas" por "sem bloco `provider` e sem `backend`".**

3. **`enable_dns_support`/`enable_dns_hostnames` não parametrizados.** O §8 diz "CIDRs, AZs, nomes e flags entram por `variables.tf`", enquanto o §14 enumera como proibido apenas "CIDR, AZ, nome ou ARN hardcoded". Interpretei "flags" como as duas variáveis de controle de custo do §8, e mantive os dois booleanos de DNS no código, com comentário. Se a intenção era literal, são duas variáveis a acrescentar — mudança trivial, mas quero a confirmação registrada e não presumida.

4. **MCP `terraform` indisponível nesta sessão**, ao contrário da etapa 1, em que respondeu. A fonte substituta está declarada acima. Isso reforça que a ressalva do §16 sobre indisponibilidade do MCP **não deve ser removida** do ADR: a disponibilidade oscila entre sessões.

### Sugestões

Identificadas e **não implementadas**, por estarem fora do escopo desta etapa.

1. **Validação de pareamento entre as três listas.** `availability_zones` com 2 entradas e `public_subnet_cidr_blocks` com 1 produz erro de índice cru, não mensagem clara. A raiz valida que há exatamente 2 AZs, mas o pareamento com os CIDRs não é validado em lugar nenhum. Terraform 1.9+ permite `validation` referenciando outra variável — a nota da regra de nomenclatura que diz o contrário está desatualizada. Não implementei por disciplina de escopo.
2. **`.tflint.hcl` com o ruleset `aws`** — já sugerido na etapa 1 e **agora com consequência medida**: o `tflint` desta etapa rodou só com o ruleset bundled `terraform` 0.15.0, que cobre linguagem, não provider. Nenhum argumento de `aws_vpc`, `aws_subnet` ou `aws_internet_gateway` foi conferido pelo linter — a conferência foi manual, contra a documentação-fonte do provider. Com o plugin AWS, essa classe de erro passaria a ser pega automaticamente nas etapas 3 e 4, que têm bem mais superfície.
3. **Fixar `--var-file terraform.tfvars` na invocação padrão do checkov** (script ou `.checkov.yaml`), pelo motivo descrito em "Achado operacional". É o tipo de pegadinha que só aparece uma vez e depois passa despercebida.

### Risco residual

1. 🟠 **A branch está num estado que não faz `terraform init` na raiz.** É intencional e acordado — as variáveis que faltam chegam nas etapas 3 e 4 —, mas qualquer CI que rode `init` ou `validate` na raiz falha até a etapa 4 terminar. A validação hoje só é possível no módulo isolado.
2. 🟠 **O `tflint` não conferiu nenhum argumento de provider** (item 2 das Sugestões). O código foi conferido à mão contra a documentação-fonte, o que é bom mas não é automatizado, e `terraform validate` valida schema — não pega argumento válido com semântica errada.
3. 🟡 **Rede sem conectividade externa neste estado.** Sem as route tables da etapa 3, nem as subnets públicas têm rota `0.0.0.0/0`. Aplicar o módulo hoje criaria uma VPC funcional porém isolada. Não é defeito: é etapa intermediária, e não há intenção de aplicar antes da etapa 4.
4. 🟡 **O sufixo `1a`/`1b` pressupõe nome de AZ no formato `<região><letra>`.** Verdadeiro em `us-east-1` e em toda região comercial da AWS, mas é uma suposição do código, não uma garantia da API. Se o nome mudar de forma, a tag `Name` sai errada — sem quebrar nada funcional.
5. 🔴 **Não há ambiente de validação anterior ao alvo.** O ADR define um único ambiente, `prd`, e eu segui o ADR. **Toda aplicação nesta stack é aplicação em produção** e exige plan revisado e aprovação humana explícita, sem exceção. Repetido da etapa 1 porque continua valendo.

### Corpo do PR — para colar no GitHub

> `gh` está instalado neste ambiente (`C:\Program Files\GitHub CLI\gh.exe`). Nenhum PR foi aberto: a entrega é 2 de 5 etapas e o PR pertence ao §7 passo 16.

~~~markdown
## ADR-0001 — Arquitetura de rede AWS (etapas 1 e 2 de 5)

Implementa: docs/adr/ADR-0001-arquitetura-de-rede-aws.md · Etapas: 1 e 2 de 5

### O que muda

Etapa 1 criou a raiz Terraform e o AWS Budget de US$ 5,00. Etapa 2 cria
`modules/network/` com VPC 10.0.0.0/24, Internet Gateway e as 4 subnets /26 em
us-east-1a e us-east-1b. Route tables, endpoints, default SG travado, NAT Gateway e
Flow Logs são as etapas 3 e 4. Nenhum recurso tarifado. Nada foi aplicado na AWS.

### Plan

Não executado. `terraform init` na raiz ainda não completa: `main.tf` passa 4
variáveis que o módulo só declara nas etapas 3 e 4. Validação possível hoje, no
módulo isolado: `fmt -check` exit 0, `validate` exit 0, `tflint` exit 0 / 0 issues,
`checkov` 2 passed / 4 failed / 0 skipped.

Quando o plan for possível, o esperado é 0 to change, 0 to destroy.

### Ambientes

- [ ] production (`prd`) — único ambiente do ADR. Não aplicado.

### Critérios de aceite (ADR §14)

- [x] `terraform fmt -check` limpo — exit 0 na stack inteira
- [x] `terraform validate` limpo — exit 0 no módulo
- [x] `tflint` limpo — exit 0, 0 issues (ruleset bundled `terraform` apenas)
- [x] `checkov` executado — 4 achados reportados, **nenhuma supressão** (é o §7 passo 10)
- [x] VPC com `enable_dns_support` e `enable_dns_hostnames` habilitados
- [x] 4 subnets nos CIDRs e AZs exatos do §14; públicas `map_public_ip_on_launch = true`,
      privadas `false`; IGW anexado
- [x] Nenhum CIDR, AZ, nome ou ARN hardcoded em `modules/network`
- [x] `backend "s3"` e `provider "aws"` somente na raiz
- [ ] Route tables, VPC Endpoints, EIC Endpoint, default SG travado — etapa 3
- [ ] NAT Gateway e Flow Logs condicionais, e os planos de contagem exata do §14 — etapa 4
- [ ] Validação funcional de egress — etapa 5

### Segurança

Nenhum segredo em nenhum arquivo. Nenhuma alteração de IAM, Security Group, NACL ou
superfície de exposição nesta etapa — o único SG tocado pelo ADR é o default da VPC, e
isso é etapa 3. `map_public_ip_on_launch = true` nas subnets públicas é habilitação,
não exposição (§9): nenhum recurso com IP público é criado por este módulo.
`CKV_AWS_130` falha nas 2 subnets públicas por esse motivo e é candidato a supressão
justificada no §7 passo 10.

### Rollback

Nada foi aplicado — não há infraestrutura a reverter. Para descartar o código:
`git revert <commit>` ou remover a branch.
~~~

---

## 2026-08-13 — Revisão da etapa 2: reverificação contra o MCP `terraform`

**Executor:** devops-engineer · **Branch:** `feat/adr-0001-networking-stack`
**ADR:** `docs/adr/ADR-0001-arquitetura-de-rede-aws.md` — status `Aprovado` em 2026-08-12 por Laura.
**Escopo:** revisão, não etapa nova. Nenhum recurso novo, nenhum avanço para route tables, NAT, endpoints, flow logs ou security groups.

> **Por que esta revisão existe.** Na etapa 2 o MCP `terraform` estava fora e a sessão caiu para o markdown-fonte do provider no GitHub, declarando a substituição. A definição do agente foi alterada desde então: MCP fora é **parada total** e substituir a fonte é **proibido**. Esta revisão reverifica, contra o MCP, tudo o que foi escrito sob a fonte substituta.

### Pré-flight de MCP

| MCP | Verificação | Resultado |
| --- | --- | --- |
| `terraform` | `ToolSearch` + chamada real `get_latest_provider_version(hashicorp/aws)` | **No ar** — retornou `6.60.0` |
| `aws-mcp` | `ToolSearch` + chamada real `ec2:DescribeAvailabilityZones` em `us-east-1` | **No ar** — retornou as 6 AZs |

Schema carregado não prova servidor no ar, por isso cada MCP levou uma chamada real antes de eu prosseguir.

### Feito

**Reverificação de cada recurso e cada argumento contra o MCP `terraform`, na versão pinada no lock (`6.59.0`), não na `latest`.** O lock resolve `~> 6.58` em 6.59.0, e é essa a versão que `validate` e `plan` usam.

| Recurso | `provider_doc_id` @ 6.59.0 | Argumentos e atributos conferidos |
| --- | --- | --- |
| `aws_vpc` | `13197359` | `cidr_block`, `instance_tenancy`, `enable_dns_support` (default **true**), `enable_dns_hostnames` (default **false**), `tags`. Atributos `id`, `cidr_block`. |
| `aws_internet_gateway` | `13196589` | `vpc_id` (Optional), `tags`. Atributo `id`. |
| `aws_subnet` | `13197319` | `vpc_id` (**Required**), `cidr_block`, `availability_zone`, `map_public_ip_on_launch` (default `false`), `tags`. Atributo `id`; `availability_zone` legível como atributo. |
| `aws_budgets_budget` | `13195997` | `budget_type`, `time_unit` (**Required**; valores `MONTHLY`/`QUARTERLY`/`ANNUALLY`/`DAILY`), `limit_amount`, `limit_unit`, `time_period_start`/`_end` (formato `AAAA-MM-DD_HH:MM`), `cost_filter` (`name` = `TagKeyValue`, valor `user:<Tag>$<Valor>`), `notification` (`comparison_operator`, `threshold`, `threshold_type`, `notification_type`, `subscriber_email_addresses`), `tags`. |

### Validado

| Validação | Comando | Resultado |
| --- | --- | --- |
| Formatação | `terraform fmt -check -recursive` | **exit 0**, limpo |
| Init do módulo | `terraform -chdir=modules/network init -backend=false` | **exit 0** — resolveu `hashicorp/aws v6.60.0` |
| Validate do módulo | `terraform -chdir=modules/network validate` | **exit 0** — "Success! The configuration is valid." |
| Lint | `tflint --recursive` 0.64.0 | **exit 0, 0 issues** |
| Policy scan (módulo) | `checkov -d modules/network --var-file terraform.tfvars` | **2 passed, 4 failed, 0 skipped** |
| Policy scan (stack) | `checkov -d . --var-file terraform.tfvars --skip-path .terraform` | **3 passed, 4 failed, 0 skipped** |

Os 4 achados do checkov são **os mesmos da etapa 2**, com os mesmos IDs — `CKV_AWS_130` nas 2 subnets públicas, `CKV2_AWS_11` e `CKV2_AWS_12` no `aws_vpc`. Nenhuma supressão: continua sendo o §7 passo 10. O `exit 1` do checkov é o código de "há check falhando", não erro de execução.

**Cobertura dupla e complementar:** o MCP confirma os argumentos contra a versão **pinada** (6.59.0); o `terraform validate` confirma contra o **schema real** do provider que o `init` resolveu (6.60.0, porque módulo filho não carrega lock próprio). Todo argumento escrito passou nas duas.

**Nada foi aplicado na AWS.** Nenhum `plan` contra a conta, nenhum comando mutante. A única chamada à AWS foi `ec2:DescribeAvailabilityZones`, leitura pura, no pré-flight. Os artefatos de `init` (`.terraform/` e `.terraform.lock.hcl`) foram removidos de `modules/network/` após a validação; o lock da raiz segue em 6.59.0, intocado.

### Divergências entre a fonte substituta e o MCP

**Nenhuma. Zero correções em arquivo `.tf`.**

Os 8 arquivos do módulo e o `budget.tf` da etapa 1 estão corretos: todo argumento existe, todo nome está certo, todo tipo é válido e todo atributo referenciado por output é exportado. Nada deprecado, nada faltando, nada renomeado.

Vale registrar os dois pontos de maior risco, porque ambos passaram:

1. **`enable_dns_hostnames` default `false`** — o comentário do `vpc.tf` afirma isso e o MCP confirma. Era o candidato número um a erro de memória, e está certo.
2. **`time_unit = "ANNUALLY"` no budget** — o MCP confirma que `MONTHLY`, `QUARTERLY`, `ANNUALLY` e `DAILY` são os únicos valores válidos e que **não existe "CUSTOM"**. A escolha da etapa 1 está certa, e o bloco `validation` de `variables.tf` lista exatamente esses 4 valores.

**O resultado bom não valida o método.** A fonte substituta lia `raw.githubusercontent.com/.../terraform-provider-aws/main/website/docs/r/` — a branch de desenvolvimento, ou seja, documentação da versão **não lançada**, não da 6.59.0 do lock. Um argumento adicionado em `main` e ainda não publicado teria passado por verificado e quebrado só no `apply`. Aqui não quebrou porque os quatro recursos usam argumentos antigos e estáveis. Com superfície maior — NAT Gateway, flow logs, IAM — a chance de acerto cairia.

### Feito fora do Terraform

**Memória do agente estava em local errado e teria sido commitada.** Os arquivos viviam em `project-terraform/01-networking-stack/.claude/agent-memory/devops-engineer/`. O `.gitignore` ignora `.claude/agent-memory/` **ancorado na raiz**, então a cópia aninhada **não** era ignorada — `git check-ignore` confirmou. Movida para `.claude/agent-memory/devops-engineer/`, que é o caminho correto e é ignorado.

**Conteúdo corrigido, não só movido.** A memória `validation-tooling-scope` recomendava explicitamente o markdown do provider no GitHub como "fonte substituta declarável quando o MCP `terraform` estiver fora" — orientação que a definição atual do agente **proíbe**. Mantida essa recomendação, a próxima sessão repetiria o problema exatamente por seguir a memória. Reescrita para apontar o fluxo `search_providers` → `get_provider_details` com `provider_version` igual à do lock. Adicionada `feedback_mcp-parada-total.md` registrando a regra e o motivo.

Nenhum valor sensível foi gravado: sem credencial, ARN, ID de conta, endpoint ou conteúdo de state.

### Pendente

Inalterado em relação à etapa 2. Nada foi resolvido nesta revisão e nada novo entrou.

| # | Item | Bloqueia |
| --- | --- | --- |
| 1 | `vpc.public-route-table.tf` e `vpc.private-route-tables.tf` | Etapa 3. Também destrava o `init` da raiz. |
| 2 | `vpc.endpoints.tf` — Gateway Endpoint S3 + EIC Endpoint | Etapa 3. |
| 3 | `vpc.security-groups.tf` — `aws_default_security_group` sem regras. Resolve `CKV2_AWS_12`. | Etapa 3. |
| 4 | `vpc.nat-gateway.tf` e `vpc.flow-logs.tf`, condicionais | Etapa 4. |
| 5 | Variáveis `nat_gateway_az`, `enable_nat_gateway`, `enable_flow_logs`, `flow_logs_retention_in_days` no módulo | Etapas 3 e 4. `init` da raiz falha até lá. |
| 6 | Outputs `public_route_table_id`, `private_route_table_ids`, `nat_gateway_id`, `nat_public_ip` | Etapas 3 e 4. |
| 7 | Os 8 pendentes da etapa 1 — bucket de state, sessão do profile, datas do curso, tag `Owner`, P8/P9, Cost Allocation Tag, assinatura de e-mail | `plan` e `apply` reais. |

### Divergências para o Arquiteto

As 5 divergências da etapa 2 e as 5 da etapa 1 **seguem abertas** — nenhuma foi resolvida aqui, e não as reabro. Uma se atualiza e uma é nova:

1. **Etapa 1, divergência 5 e etapa 2, divergência 4 — ressalva do §16 sobre o MCP `terraform`.** O §16 do ADR declara a indisponibilidade do MCP e lista dados vindos da API pública do Registry. **Reverificado agora via MCP:** `hashicorp/aws` mais recente é **6.60.0**, não 6.58.0 como o §16 registrou. O pin `~> 6.58` continua válido e o lock em 6.59.0 continua dentro dele — nenhuma mudança de código —, mas **o número no §16 está desatualizado**. Sugiro que o §16 passe a citar a versão do lock em vez da "última publicada", que envelhece sozinha.

2. **Nova, de método:** a etapa 2 declarou fonte substituta no log, e o §16 do ADR faz o mesmo. Agora que a substituição é proibida na implementação, sugiro que o Arquiteto trate "MCP indisponível" como bloqueio de escrita do ADR também, e não como ressalva declarável — pelo mesmo motivo: a ressalva é honesta, mas o leitor da revisão não distingue o que foi verificado do que não foi.

### Sugestões

Repetidas das etapas 1 e 2 porque continuam valendo e continuam não implementadas.

1. **`.tflint.hcl` com o ruleset `aws`.** Segue sendo a lacuna mais cara: o `tflint` desta revisão rodou de novo só com o bundled `terraform` 0.15.0 e **não conferiu um único argumento de provider**. A conferência foi o MCP, manual. Com o plugin AWS, a classe de erro que motivou esta revisão passaria a ser pega automaticamente — e as etapas 3 e 4 têm muito mais superfície que estas.
2. **`--var-file terraform.tfvars` fixado num `.checkov.yaml`**, pelo motivo já medido.
3. **Validação de pareamento entre as três listas** de AZ e CIDRs.

### Risco residual

1. 🟠 **O `tflint` continua sem conferir provider.** Reduzido pela reverificação via MCP, não eliminado: a conferência é manual e depende de eu executá-la, enquanto um linter rodaria sozinho em toda etapa e em qualquer CI.
2. 🟠 **A branch continua sem fazer `terraform init` na raiz** até a etapa 4. Inalterado e intencional.
3. 🟡 **O sufixo `1a`/`1b` pressupõe nome de AZ no formato `<região><letra>`.** Inalterado.
4. 🔴 **Não há ambiente de validação anterior ao alvo.** O ADR define um único ambiente, `prd`. **Toda aplicação nesta stack é aplicação em produção** e exige plan revisado e aprovação humana explícita. Repetido das etapas 1 e 2 porque continua valendo.

---

## 2026-08-13 — Etapa 3 de 5: caminho de egress (route tables, NAT Gateway) e `.tflint.hcl`

### Pré-flight de MCP

Regra nova da definição do agente, motivada pela etapa 2. Confirmado com **chamada real**, não só carregamento de schema:

| MCP | Chamada | Resultado |
| --- | --- | --- |
| `terraform` | `search_providers` (`aws`, `provider_version = 6.59.0`, `route_table`) | 14 documentos retornados |
| `aws-mcp` | `ec2:DescribeAvailabilityZones` em `us-east-1` | `us-east-1a` e `us-east-1b` `available` |

**Achado do pré-flight:** `get_latest_provider_version(hashicorp/aws)` respondeu `provider not found: hashicorp/aws`. O servidor está **no ar** — `search_providers` e `get_provider_details` funcionam normalmente na mesma sessão. É uma falha daquele endpoint específico, não indisponibilidade do MCP, então não configura parada total. Consequência prática: nenhuma, porque a versão que importa é a do lock (6.59.0), não a latest.

### Feito

**Passo 0 — `.tflint.hcl` com o ruleset `aws`** (a sugestão repetida nas etapas 1, 2 e na revisão).

- `project-terraform/01-networking-stack/.tflint.hcl` — plugin `aws` **pinado em 0.48.0**, mais o bundled `terraform` com preset `recommended` declarado explicitamente.
- `project-terraform/01-networking-stack/modules/network/.tflint.hcl` — **cópia intencional**, ver a armadilha abaixo.

**Armadilha encontrada e corrigida — `tflint --recursive` não herda configuração.** A primeira execução saiu limpa e era **falso-limpo**. `--recursive` executa em cada diretório como se fosse o cwd e procura um `.tflint.hcl` local; ele não propaga o do diretório pai. Medido com `tflint --version` em cada diretório:

| Diretório | Rulesets carregados |
| --- | --- |
| raiz da stack | `ruleset.aws (0.48.0)` + `ruleset.terraform (0.15.0-bundled)` |
| `modules/network` (antes da cópia) | **só** `ruleset.terraform (0.15.0-bundled)` |

Ou seja: o único diretório que contém recursos `aws_*` era exatamente o que rodava sem o ruleset `aws`. `TFLINT_CONFIG_FILE` apontando para a raiz resolve e foi verificado, mas faz o gate depender de alguém lembrar de exportar uma variável de ambiente — e esquecer produz falso-limpo silencioso. Optei pela duplicação de 10 linhas, que torna `tflint --recursive` correto por padrão. As duas cópias têm comentário apontando uma para a outra.

**Controle positivo do ruleset.** "Limpo" só vale se a ferramenta for capaz de acusar. Em `scratchpad/tflint-probe/`, com a mesma configuração:

- `instance_type = "t4g.nao-existe"` → **acusou** `aws_instance_invalid_type`.
- `availability_mode = "zonalzinho"` em `aws_nat_gateway` → **não acusou**.

**Escopo real do plugin, medido:** ele cobre um conjunto **curado** de regras por recurso, não validação de enum contra o schema do provider. O MCP `terraform` continua sendo a fonte primária para escrever argumento; o plugin é rede de segurança parcial, não substituto.

**O ruleset `aws` não encontrou nada nos arquivos das etapas 1 e 2.** Nenhuma correção retroativa foi necessária.

**Recursos da etapa 3.** Todo argumento verificado no MCP `terraform` contra a versão do lock (**6.59.0**), não a latest.

| Arquivo | Recursos |
| --- | --- |
| `modules/network/vpc.public-route-table.tf` | `aws_route_table.public`, `aws_route.public` (`0.0.0.0/0` → IGW), `aws_route_table_association.public` (count 2) |
| `modules/network/vpc.private-route-tables.tf` | `aws_route_table.private` (count 2), `aws_route_table_association.private` (count 2), `aws_route.private` (**condicional**, count 2 quando ligado) |
| `modules/network/vpc.nat-gateway.tf` | `aws_eip.nat` (**condicional**), `aws_nat_gateway.this` (**condicional**) |

Decisões de implementação e o porquê:

- **`aws_route` separado em vez de bloco `route` inline.** O provider proíbe misturar os dois no mesmo route table ("will cause a conflict of rule settings and will overwrite rules"), e o critério de aceite do §14 exige que as 2 rotas privadas apareçam como **recursos** no plan — bloco inline seria alteração do route table, não recurso novo. A RT pública usa a mesma forma por simetria, para que ninguém acrescente um bloco inline depois e sobrescreva a rota sem perceber.
- **EIP e NAT compartilham a mesma variável de `count`**, nunca duas. É o que impede o EIP órfão de R6 — EIP alocado e não anexado custa os mesmos US$ 0,005/h de um EIP em uso.
- **`subnet_id` do NAT resolvido por `index(var.availability_zones, var.nat_gateway_az)`**, não `[0]` fixo. Trocar a AZ do NAT (recuperação prevista em R1) passa a não exigir edição de código.
- **`availability_mode = "zonal"` e `connectivity_type = "public"` explícitos**, apesar de serem os defaults do provider — ADR §4 (Opção A) e §6 os especificam nominalmente, e explicitar deixa a Opção C visível como troca de uma linha.
- **`depends_on = [aws_internet_gateway.this]` no NAT**, exigido por §15 ponto 3. **Não** no EIP: a nota do provider sobre EIP precisar do IGW vale para EIP associado a `instance`/`network_interface`; aqui ele é só alocação, e quem associa é o NAT, que já depende.
- **`count` como primeiro argumento seguido de linha em branco**, e `tags` como último argumento real, conforme `.claude/rules/terraform-naming.md`.

**Destravado o `init` da raiz.** As 4 variáveis foram declaradas em `modules/network/variables.tf` — `nat_gateway_az`, `enable_nat_gateway`, `enable_flow_logs`, `flow_logs_retention_in_days` — incluindo as duas de flow logs, cujos recursos só chegam na etapa 4. Os 4 `Unsupported argument` sumiram e a raiz volta a validar de ponta a ponta.

`enable_nat_gateway` e `enable_flow_logs` são as **únicas** variáveis do módulo com `default`, rompendo de propósito a regra "nenhuma variável tem default" do topo do arquivo. Motivo: o critério de aceite do §14 exige `default = false` nas duas, e a razão é defesa em profundidade — se a raiz um dia deixar de repassá-las, o módulo cai no estado de custo **zero**, não no tarifado. O default seguro precisa morar na camada mais interna.

**Outputs.** Entraram `public_route_table_id`, `private_route_table_ids`, `nat_gateway_id` e `nat_public_ip`. Com eles, os **9 outputs** exigidos pelo §14 estão declarados e a raiz resolve por completo. Os dois de NAT usam `try(..., "")` — string vazia é a evidência de que a janela de custo está fechada.

### Validado

| Validação | Comando | Resultado |
| --- | --- | --- |
| Formatação | `terraform fmt -recursive -check -diff` | exit 0, nenhum arquivo reformatado |
| `init` da raiz | `terraform init -backend=false` | **exit 0** — antes falhava com 4 `Unsupported argument` |
| `validate` da raiz | `terraform validate` | `Success! The configuration is valid.` |
| `validate` do módulo | `terraform -chdir=modules/network` idem | `Success! The configuration is valid.` |
| tflint | `tflint --recursive` **com ruleset `aws` nos 2 diretórios** | **2 warnings**, ambos esperados — ver Pendente |
| checkov | `checkov -d . --var-file terraform.tfvars --skip-path .terraform` | **Passed 14, Failed 4** |

Evolução do checkov: etapa 2 fechou em `Passed 3, Failed 4`. Os 4 failed são **os mesmos**, nenhum novo veio da etapa 3.

**O scan default não cobre os recursos desta etapa.** Com `enable_nat_gateway = false` o `count` resolve para 0 e o checkov descarta o recurso sem avisar — a armadilha já medida na etapa 2. Reescaneei com um `--var-file` adicional em scratchpad (`enable_nat_gateway = true`), scan **estático**, sem tocar a AWS e sem alterar nada no repositório:

| Invocação | Resultado |
| --- | --- |
| `--var-file terraform.tfvars` | `Passed 14, Failed 4` |
| idem + `--var-file <scratch>/natwindow.tfvars` | `Passed 15, Failed 5` |

O 5º achado é **`CKV2_AWS_19`** — "Ensure that all EIP addresses allocated to a VPC are attached to EC2 instances" — em `aws_eip.nat[0]`. Sem o override ele ficaria invisível até o dia em que a janela de custo abrisse.

`terraform fmt`, `validate` e `tflint` foram executados; **nenhuma validação foi pulada**. `tfsec` não está instalado neste ambiente e não foi executado — o ADR §14 pede `checkov`, não `tfsec`.

### Pendente

| # | Item | Motivo |
| --- | --- | --- |
| 1 | **2 warnings de `terraform_unused_declarations`** — `enable_flow_logs` e `flow_logs_retention_in_days` | Consequência direta e prevista de declarar as 4 variáveis agora para destravar o `init`. Resolvem sozinhos na etapa 4, quando `vpc.flow-logs.tf` passar a consumi-las. **Não desabilitei a regra** — desligar linter para "fazer passar" é proibido, e o §14 pede tflint limpo, o que só é honesto depois da etapa 4. |
| 2 | Evidência do §14 — `plan` sem variáveis com 0 recursos tarifados, e `plan -var="enable_nat_gateway=true"` com exatamente 4 | `terraform plan` contra a AWS estava **fora do escopo desta etapa por instrução explícita**. A contagem esperada está correta por leitura do código (1 EIP + 1 NAT + 2 rotas), mas **não foi verificada por execução**. |
| 3 | `vpc.endpoints.tf`, `vpc.security-groups.tf`, `vpc.flow-logs.tf` | Etapa 4. Resolvem `CKV2_AWS_12` e condicionam `CKV2_AWS_11`. |
| 4 | Os 8 pendentes da etapa 1 — bucket de state, sessão do profile, datas do curso, tag `Owner`, P8/P9, Cost Allocation Tag, assinatura de e-mail | `plan` e `apply` reais. |

### Divergências para o Arquiteto

As divergências abertas das etapas 1 e 2 **seguem abertas** e não as reabro. Duas novas:

1. **`CKV2_AWS_19` no EIP do NAT — decisão de supressão não é minha.** O check exige EIP anexado a **instância EC2**; o nosso está anexado a um **NAT Gateway**, via `allocation_id`. É limitação do checkov, que não reconhece esse vínculo — não é exposição real. Mas o ADR §7 etapa 10 autoriza suprimir **apenas** o que está listado como trade-off aceito em §5, e este não está. **Não adicionei `checkov:skip` por conta própria.** Peço ao Arquiteto que decida: (a) incluir `CKV2_AWS_19` na lista de supressões justificadas de §5, ou (b) aceitar o finding no relatório. Recomendo (a), com a justificativa "EIP anexado a NAT Gateway, não a instância; o check não modela essa associação".

2. **Nomenclatura do output `nat_public_ip`.** Pelo padrão `{name}_{type}_{attribute}` de `.claude/rules/terraform-naming.md`, o nome seria `nat_gateway_public_ip`. O §14 fixa `nat_public_ip` na lista de outputs exigidos e o `outputs.tf` da raiz já o referencia assim. **Segui o ADR**, como manda a regra de precedência, e registro aqui. Sugestão de baixa prioridade: alinhar §14 ao padrão, ou anotar a exceção no ADR.

### Sugestões

1. **Fixar `--var-file terraform.tfvars` num `.checkov.yaml`.** Sugestão repetida das etapas 1 e 2, e esta etapa mostrou o custo de não tê-la: o scan default escondeu `CKV2_AWS_19`. Um `.checkov.yaml` que fixasse o `--var-file` e o `--skip-path` eliminaria metade do problema. A outra metade — recursos condicionais nunca escaneados no estado default — só se resolve escaneando também com a janela aberta. Vale virar dois alvos no que quer que sirva de task runner: `scan` e `scan:natwindow`.
2. **Um wrapper de validação** (Makefile, `justfile` ou script) encadeando `fmt` → `validate` (raiz e módulo) → `tflint --recursive` → `checkov` nas duas variantes. Hoje são 6 comandos com pegadinhas de diretório e de env var; cada uma delas é uma chance de falso-limpo.
3. **Validação de pareamento entre as três listas** de AZ e CIDRs. Repetida da etapa 2, continua não implementada.

### Risco residual

1. 🟠 **`nat_gateway_az` inválida só falha quando a janela abre.** Se o valor não estiver em `availability_zones`, `index()` aborta — mas com `count = 0` o Terraform não avalia o corpo do recurso, então `validate` e o `plan` do estado base passam limpos. O erro aparece só no `apply -var="enable_nat_gateway=true"`, que é exatamente o momento de maior pressa. `validation` de variável não resolve (não referencia outra variável) e `precondition` também não (mesma avaliação preguiçosa). Mitigação real seria uma checagem na raiz; não implementada por escopo fechado.
2. 🟠 **A duplicação do `.tflint.hcl` pode divergir.** Duas cópias do pin `0.48.0`. Se alguém atualizar só uma, o módulo volta silenciosamente a rodar sem o ruleset `aws` — a mesma falha que esta etapa corrigiu, mas de volta pela porta dos fundos. Os comentários avisam; nada impõe.
3. 🟡 **O plugin `aws` não valida enum do schema.** Medido no controle positivo: `availability_mode = "zonalzinho"` passou. A cobertura é um conjunto curado de regras. O MCP segue obrigatório para escrever argumento — o plugin reduziu o risco, não o eliminou.
4. 🟡 **O sufixo `1a`/`1b` pressupõe nome de AZ no formato `<região><letra>`.** Inalterado das etapas anteriores; agora também nas tags das route tables e do NAT.
5. 🔴 **Não há ambiente de validação anterior ao alvo.** O ADR define um único ambiente, `prd`. **Toda aplicação nesta stack é aplicação em produção** e exige plan revisado e aprovação humana explícita. Repetido das etapas 1 e 2 porque continua valendo.

---

## Etapa 4 — Endpoints, default SG travado e VPC Flow Logs

**Data:** 2026-08-14 · **Branch:** `feat/adr-0001-endpoints-and-flow-logs` (a partir de `main`, após o merge `095fd16` das etapas 1–3) · **ADR-0001 §7, passos 5, 6 e 8**

Esta etapa **completa o código do módulo `network`**. Não sobra recurso do ADR-0001 §6 por escrever.

### Pré-flight de MCP

Os dois MCPs responderam com chamada real antes de qualquer arquivo ser escrito.

| MCP | Sonda | Resultado |
| --- | --- | --- |
| `terraform` | `search_providers(hashicorp/aws, 6.59.0, vpc_endpoint, resources)` | 16 documentos retornados |
| `aws-mcp` | `sts:GetCallerIdentity` | conta e usuário esperados |

`get_latest_provider_version(hashicorp/aws)` segue respondendo `provider not found`, como já registrado na etapa 3. É falha daquele endpoint, **não** MCP fora do ar: `search_providers` e `get_provider_details` funcionaram normalmente na mesma sessão. Nenhuma fonte substituta foi usada.

**Todo argumento verificado contra a versão 6.59.0**, a mesma do `.terraform.lock.hcl`, nunca `latest`:

| Recurso / data source | O que a consulta decidiu |
| --- | --- |
| `aws_vpc_endpoint` | `vpc_endpoint_type` aceita `Gateway`; default é `Gateway`; a doc adverte que `route_table_ids` **conflita** com o recurso de associação separado |
| `aws_vpc_endpoint_route_table_association` | `route_table_id` + `vpc_endpoint_id`, ambos obrigatórios |
| `aws_ec2_instance_connect_endpoint` | `subnet_id` é o único argumento obrigatório; **sem `security_group_ids` a AWS associa o SG default da VPC** |
| `aws_default_security_group` | adota o SG existente e remove **todas** as regras ao assumir a gestão |
| `aws_cloudwatch_log_group` | `retention_in_days` aceita `7`; o atributo `arn` **já vem sem o sufixo `:*`** |
| `aws_flow_log` | `log_destination_type` aceita `cloud-watch-logs`; `max_aggregation_interval` aceita `600` |
| `aws_iam_role` / `aws_iam_role_policy` | `role` recebe o **name** da role; `inline_policy` está deprecado — usado o recurso separado |
| `data.aws_iam_policy_document` | blocos `condition` com `test` / `variable` / `values`; `ArnLike` é `test` válido |
| `data.aws_region` | **`region` é o atributo correto no provider 6.x — `name` e `id` estão deprecados** |
| `data.aws_partition`, `data.aws_caller_identity` | `partition` e `account_id` |

Uma consulta ao `aws-mcp` mudou o código: `ec2:DescribeVpcEndpointServices` mostrou que `com.amazonaws.us-east-1.s3` é oferecido nos **dois** tipos, `Gateway` **e** `Interface`. Omitir `vpc_endpoint_type` não daria erro de sintaxe — daria a fatura errada, US$ 0,01/h por AZ. O argumento foi escrito explícito por isso.

Uma segunda consulta ao `aws-mcp` produziu a divergência principal desta etapa: a página *Security groups for EC2 Instance Connect Endpoint* exige regra de **saída na porta 22** no SG do endpoint. Ver *Divergências*.

### Feito

Três arquivos novos em `project-terraform/01-networking-stack/modules/network/`:

| Arquivo | Recursos |
| --- | --- |
| `vpc.endpoints.tf` | `data.aws_region.current`, `aws_vpc_endpoint.s3` (Gateway), `aws_vpc_endpoint_route_table_association.s3_private` ×2, `aws_ec2_instance_connect_endpoint.this` |
| `vpc.security-groups.tf` | `aws_default_security_group.this`, sem nenhum bloco `ingress`/`egress` |
| `vpc.flow-logs.tf` | `data.aws_caller_identity.current`, `data.aws_partition.current`, `data.aws_iam_policy_document.assume_role`, `data.aws_iam_policy_document.this`, `aws_cloudwatch_log_group.this`, `aws_iam_role.this`, `aws_iam_role_policy.this`, `aws_flow_log.this` — **os 4 recursos sob o mesmo `count = var.enable_flow_logs ? 1 : 0`** |

Mais `outputs.tf` do módulo (6 outputs novos) e `README.md` reescrito, que ainda descrevia o estado da etapa 2.

Decisões de implementação que não são leitura direta do ADR:

- **Gateway Endpoint associado pelo recurso separado**, não pelo argumento `route_table_ids` do `aws_vpc_endpoint`. A documentação do provider adverte que usar os dois caminhos gera conflito de associação, com uma sobrescrevendo a outra. ADR-0001 §15 ponto 4 nomeia o recurso separado.
- **Nenhum Interface Endpoint de ECR**, conforme ADR-0001 §6 — os dois em 2 AZs custariam US$ 0,04/h, ou US$ 29,20/mês.
- **EIC Endpoint na subnet privada de índice `[0]`, não em `var.nat_gateway_az`.** Hoje as duas apontam para a mesma AZ, mas são decisões independentes: trocar a AZ do NAT é a recuperação de **R1**, e não há razão para essa troca recriar também o endpoint de acesso, que nada tem a ver com egress.
- **Os 4 recursos de flow log sob a mesma condição, não só o `aws_flow_log`.** Um log group vazio não custaria nada por existir, mas o critério de aceite de §14 é literal: `plan` sem variáveis não cria "nem log group, nem role".
- **`logs:CreateLogGroup` omitida da policy.** O log group é criado pelo Terraform; conceder ao serviço o poder de criar log group seria permissão para algo que ele nunca faz. As três ações de escrita ficam presas a `"${log_group.arn}:*"` — o sufixo precisa ser concatenado à mão porque o provider já o remove do atributo `arn`.
- **Região por `data.aws_region`, ARNs por `data.aws_partition` + `data.aws_caller_identity`.** Nenhum literal de região, conta ou ARN entrou no módulo, por §14.

### Validado

Todos os comandos rodados de `project-terraform/01-networking-stack/`.

| Gate | Antes (HEAD `095fd16`) | Depois | Situação |
| --- | --- | --- | --- |
| `terraform fmt -recursive -check` | exit 0 | **exit 0** | limpo |
| `terraform validate` raiz | Success | **Success** | limpo |
| `terraform validate` módulo | Success | **Success** | limpo |
| `tflint --recursive` | **2 issues**, exit 2 | **0 issues, exit 0** | **zerou** |
| `checkov` var-file padrão | Passed 14, Failed 4, Skipped 0 | **Passed 19, Failed 2, Skipped 1** | 2 checks a menos falhando |
| `checkov` com a janela aberta | Passed 15, Failed 5, Skipped 0 | **Passed 47, Failed 4, Skipped 1** | +32 passed |

O baseline "antes" foi medido num `git worktree` descartável apontando para `095fd16`, não estimado.

**Os 2 warnings do tflint zeraram**, que era o primeiro resultado esperado desta etapa:

```
terraform_unused_declarations · variable "enable_flow_logs"            -> resolvido
terraform_unused_declarations · variable "flow_logs_retention_in_days" -> resolvido
```

`tflint --version` foi conferido **nos dois diretórios antes** de confiar no resultado, porque `--recursive` não herda `.tflint.hcl` do pai. Ambos carregaram `ruleset.aws (0.48.0)` + `ruleset.terraform (0.15.0-bundled)`. A cópia do `.tflint.hcl` dentro do módulo continua sendo carregada.

**`CKV2_AWS_11` e `CKV2_AWS_12` passaram**, o segundo resultado esperado:

```
CKV2_AWS_11 "Ensure VPC flow logging is enabled in all VPCs"                    PASSED
CKV2_AWS_12 "Ensure the default security group of every VPC restricts all traffic" PASSED
```

Detalhe que contraria a expectativa e vale registrar: **`CKV2_AWS_11` passou mesmo com `enable_flow_logs = false`**. Esperava-se que o `count = 0` fizesse o checkov descartar o `aws_flow_log` e manter o check vermelho. Não é o que acontece: os dois são checks de **grafo** ancorados no `aws_vpc`, e o grafo é montado sobre a configuração, não sobre a contagem resolvida. Ou seja, eles atestam que o código **prevê** flow logging e SG default travado — não que os recursos existam na conta. A prova de que existem é o `plan` da etapa 5.

Achados restantes, nenhum introduzido por descuido:

| Check | Onde | Situação |
| --- | --- | --- |
| `CKV_AWS_158` — log group sem CMK do KMS | `aws_cloudwatch_log_group.this` | **Suprimido.** É o único `checkov:skip` desta etapa. ADR-0001 §5 lista "CMK do KMS no log group" como trade-off aceito, e §7 etapa 10 autoriza suprimir exatamente o que §5 lista. Comentário no código aponta para o ADR. |
| `CKV_AWS_338` — retenção mínima de 1 ano | `aws_cloudwatch_log_group.this` | **NÃO suprimido.** Ver *Divergências*. |
| `CKV_AWS_130` ×2 — subnet atribui IP público | `aws_subnet.public` | Pré-existente da etapa 2, fora do escopo desta. |
| `CKV2_AWS_19` — EIP não anexado a instância | `aws_eip.nat` | **NÃO suprimido**, continua aguardando decisão humana desde a etapa 3. |

Cobertura real do checkov, medida e não presumida: nem no scan padrão nem no scan com a janela aberta aparecem `aws_vpc_endpoint`, `aws_vpc_endpoint_route_table_association`, `aws_ec2_instance_connect_endpoint`, `aws_default_security_group` ou `aws_flow_log` como recursos avaliados. **Não há check direto do checkov sobre nenhum dos cinco.** O que existe é a cobertura indireta de `CKV2_AWS_11` e `CKV2_AWS_12`, ancorados no `aws_vpc`. Três dos cinco recursos escritos nesta etapa não têm gate automático algum — a revisão humana do PR é a única barreira sobre eles.

**Nenhum `terraform plan` foi executado contra a AWS e nenhum recurso foi criado**, conforme instrução da etapa. O bucket do backend S3 ainda não existe.

### Pendente

1. **Todos os critérios de aceite que exigem contato com a AWS** — os dois `plan` de contagem (4 recursos por flag), o `apply` do estado base, o segundo `plan` com "No changes", os outputs preenchidos e a validação funcional de egress. São a etapa 5, e dependem do bucket de state (ADR-0001 §7 passo 2), que segue inexistente.
2. **Pré-requisitos 2, 5 e 6 do handoff** — resposta do professor a P8/P9, confirmação da assinatura de e-mail do budget e datas reais do curso. Continuam abertos desde a etapa 1; os valores assumidos em `terraform.tfvars` seguem marcados como pendentes no próprio arquivo.
3. **Cost Allocation Tag `CostCenter` não ativada** no console de Billing. Sem isso o budget filtrado não enxerga nada.

### Divergências

As divergências abertas nas etapas 1, 2 e 3 **seguem abertas** e não as reabro. Três novas:

1. 🔴 **O EIC Endpoint não vai conseguir conectar, e a causa são duas decisões do ADR que colidem.** ADR-0001 §6 pede um EC2 Instance Connect Endpoint em `private-1a`; §9 manda esvaziar o default security group da VPC; e §9 também determina que nenhum SG de aplicação seja criado nesta camada. Só que `aws_ec2_instance_connect_endpoint` sem `security_group_ids` recebe **o default SG da VPC** — o mesmo que acabou de ser esvaziado. A documentação da AWS (*Security groups for EC2 Instance Connect Endpoint*, consultada via `aws-mcp`) é explícita: o SG do endpoint **precisa** de regra de saída na porta 22 em direção às instâncias-alvo. O `apply` vai criar o endpoint sem erro nenhum; o que falha é o passo 12 de §7 — "acesso por EIC Endpoint" — e com ele o critério de aceite "o acesso a ela foi via EC2 Instance Connect Endpoint, sem IP público e sem bastion". **Não criei SG para resolver:** seria decidir arquitetura, e §9 diz que SG pertence ao ADR de compute. Implementei o ADR como escrito e trago a colisão. Três saídas possíveis, todas do Arquiteto: (a) autorizar um SG mínimo nesta camada, só para o endpoint, com egress TCP/22 para o CIDR da VPC; (b) manter o default SG esvaziado e mover o EIC Endpoint inteiro para o ADR de compute, junto com o SG dele; (c) deixar `map`ado como limitação conhecida e trocar o passo 12 por outro método de acesso. **Recomendo (a)** — é o menor delta, custa US$ 0,00, mantém o passo 12 executável e não antecipa nenhuma decisão de compute.

2. 🟠 **`CKV_AWS_338` falha e não tenho autorização para suprimir.** O check exige retenção de no mínimo 1 ano; ADR-0001 §10 fixa **7 dias**, e §11.2 justifica bem — o custo dos flow logs é de ingestão, não de retenção (100 MB por 7 dias custam US$ 0,0007). A decisão é consciente e correta para este laboratório. O problema é formal: a tabela de trade-offs aceitos de §5 **não lista** a retenção curta, e §7 etapa 10 autoriza suprimir apenas o que está em §5. Deixei o check **falhando de propósito**, com comentário no código explicando por quê. Peço ao Arquiteto que decida: (a) acrescentar "retenção de 7 dias no log group de flow logs" à tabela de §5, o que me autoriza o `skip`; ou (b) manter o finding visível no relatório. **Recomendo (a)**, pelo mesmo raciocínio de `CKV2_AWS_19`.

3. 🟡 **Nome do output `flow_log_cloudwatch_log_group_name`.** Pelo padrão `{name}_{type}_{attribute}` de `.claude/rules/terraform-naming.md`, com o recurso chamado `this` o prefixo cai e o nome seria `cloudwatch_log_group_name` — que não diz de qual log group se trata para quem lê de fora do módulo. Mantive o qualificador `flow_log_`. Divergência menor, registrada por completude; não pede ação.

### Sugestões

1. **`.checkov.yaml` fixando `--var-file` e `--skip-path`.** Terceira vez que aparece neste log. Esta etapa reforçou o custo: sem `--var-file` o scan não enxerga metade dos recursos, e a diferença entre Passed 19 e Passed 47 mostra quanto fica invisível quando as flags estão desligadas.
2. **Um `.editorconfig` ou hook restringindo comentários `.tf` a ASCII.** O checkov 3.3.10 lê os arquivos como cp1252 neste Windows e **aborta com `UnicodeDecodeError`** diante do byte `0x8f`, que é parte do emoji `⚠️`. Custou uma rodada de depuração nesta etapa: o scan falhou inteiro, com exit 2, e a mensagem apontava para um offset de byte, não para o arquivo. Acentuação e `§` passam; emoji não.
3. **Wrapper de validação** (Makefile/`justfile`/script) encadeando `fmt` → `validate` raiz → `validate` módulo → `tflint --recursive` → `checkov` nas duas variantes. Repetida da etapa 3; agora são 7 comandos.
4. **Considerar um `aws_vpc_endpoint_policy` no Gateway Endpoint de S3.** Hoje o endpoint tem acesso total ao S3 por default. Restringi-lo aos buckets do ECR reduziria a superfície sem custo. Fora do escopo do ADR-0001; sugestão para o ADR de compute.

### Risco residual

1. 🔴 **A lacuna do EIC Endpoint é a mais consequente e não tem gate automático.** Não existe check de checkov nem regra de tflint sobre `aws_ec2_instance_connect_endpoint`. Nada além da divergência acima vai lembrar alguém disso antes do passo 12 falhar na prática.
2. 🔴 **Não há ambiente de validação anterior ao alvo.** O ADR define um único ambiente, `prd`. **Toda aplicação nesta stack é aplicação em produção** e exige plan revisado e aprovação humana explícita. Repetido das etapas 1, 2 e 3 porque continua valendo.
3. 🟠 **Três dos cinco tipos de recurso escritos nesta etapa não têm cobertura de ferramenta.** Endpoints, EIC Endpoint e flow log passaram por `validate` (schema) e pelo MCP (argumentos), mas nenhum gate de segurança os avalia. A revisão humana do PR é a única barreira.
4. 🟠 **`nat_gateway_az` inválida só falha quando a janela abre.** Inalterado da etapa 3. `count = 0` impede a avaliação do corpo do recurso, então `validate` e o `plan` do estado base passam limpos e o erro aparece no `apply -var="enable_nat_gateway=true"`.
5. 🟠 **A duplicação do `.tflint.hcl` pode divergir.** Inalterado da etapa 3. Duas cópias do pin `0.48.0`; atualizar só uma devolve o módulo ao estado de falso-limpo.
6. 🟡 **`CKV2_AWS_11` verde não significa flow logs ativos.** É check de grafo sobre a configuração. Com `enable_flow_logs = false` — o estado permanente do laboratório — **não há flow log nenhum na conta**, e o check continua verde. Quem ler o relatório do checkov sem esta nota vai concluir o contrário.
7. 🟡 **O sufixo `1a`/`1b` pressupõe nome de AZ no formato `<região><letra>`.** Inalterado; agora também na tag do EIC Endpoint.

---

## 2026-08-19 — Etapa 5a: bootstrap da conta (§7 passos 1 e 2) e `plan` bloqueado

Primeira etapa deste ADR que toca a AWS. Escopo autorizado pela usuária: **apenas** os passos 1 e 2 de §7. `terraform apply` explicitamente **não** autorizado — a contagem do `plan` seria revisada antes.

**Pré-flight de MCP:** os dois responderam com chamada real antes de qualquer escrita. `terraform` → `get_latest_provider_version(hashicorp/aws)` = `6.60.0`. `aws-mcp` → `sts get-caller-identity` = conta `090413359726`. Nenhuma fonte substituta foi usada em nenhum ponto desta etapa.

### Feito

1. **§7 passo 1 — AWS Budget criado.** `budgets:CreateBudget` via `aws-mcp`, out-of-band, com os valores exatos de `budget.tf` + `terraform.tfvars`: teto US$ 5,00, `COST`, `ANNUALLY`, período 2026-08-01 → 2026-12-03, filtro `TagKeyValue = user:CostCenter$workshop-devops-ia`, as 4 notificações (40/60/80% `ACTUAL` e 100% `FORECASTED`) e as 7 tags via `ResourceTags`, para que um `import` futuro não gere diff.
2. **§7 passo 2 — bucket de state criado.** Nome conforme §8. Quatro operações separadas: `create-bucket`, `put-bucket-versioning` (`Enabled`), `put-bucket-encryption` (SSE-S3 `AES256` com `BucketKeyEnabled`) e `put-public-access-block` (as 4 flags `true`). Acrescentei `put-bucket-tagging` com as 6 tags obrigatórias mais `Name` — sem a tag `CostCenter` o custo do bucket ficaria **fora** do filtro do budget que acabara de ser criado, e o critério de §14 pede as tags em todo recurso que as suporte.
3. **Correção em `backend.tf`:** acrescentado `profile = "app_cloud_devops"`. Ver *Divergências* 2 — é defeito de implementação, não mudança de arquitetura.

### Validado

**Budget**, por leitura da API e não por presunção:

| Verificação | Resultado |
| --- | --- |
| `describe-budget` | `BudgetLimit 5.0 USD`, `TimeUnit ANNUALLY`, período 2026-08-01 → 2026-12-03, `CostFilters` correto, `HealthStatus: HEALTHY` |
| `describe-notifications-for-budget` | **4** notificações, todas `NotificationState: OK` |
| `describe-subscribers-for-notification` (100% FORECASTED) | `EMAIL` → o endereço configurado em `terraform.tfvars` |

**Bucket**, idem:

| Verificação | Resultado |
| --- | --- |
| `get-bucket-versioning` | `Status: Enabled` |
| `get-bucket-encryption` | `AES256`, `BucketKeyEnabled: true` |
| `get-public-access-block` | as 4 flags `true` |

**Gates estáticos**, todos reexecutados após a alteração do `backend.tf`:

| Gate | Resultado |
| --- | --- |
| `terraform fmt -check -recursive` | exit 0 |
| `terraform validate` | `Success! The configuration is valid.` |
| `tflint` raiz | 0 issues — `ruleset.aws (0.48.0)` confirmado carregado |
| `tflint` `modules/network` | 0 issues — `ruleset.aws (0.48.0)` confirmado carregado |
| `checkov -d . --var-file terraform.tfvars --skip-path .terraform` | **Passed 43, Failed 0, Skipped 7** |

**Confirmação de custo do estado base**, pedida explicitamente pela usuária. Item a item, contra fonte consultada via `aws-mcp` nesta data:

| Recurso | Custo | Fonte |
| --- | --- | --- |
| VPC, subnets, IGW, route tables, security groups | **US$ 0,00** | Amazon VPC Pricing lista **o que é cobrado** numa VPC: NAT Gateway, IPAM, Network Analysis, IPv4 público, bloco IPv4 contíguo, Route Server, VPC Peering, ODB Peering e Encryption Controls. Nenhum dos recursos do estado base aparece. |
| Gateway Endpoint de S3 | **US$ 0,00** | *Gateway endpoints*: "There is no additional charge for using gateway endpoints." |
| EC2 Instance Connect Endpoint | **US$ 0,00** | *Connect using EC2 Instance Connect Endpoint*: "There is no additional cost for using EC2 Instance Connect Endpoints." **Com ressalva** — ver *Divergências* 4. |
| AWS Budget (o 3º da conta) | **US$ 0,00** | AWS Budgets Pricing: "You can monitor and receive notifications on your budgets free of charge." A cobrança recai só sobre budgets **com ações** acima de 2 (US$ 0,10/dia) e sobre Budgets **Reports** (US$ 0,01 cada). Este budget não tem `aws_budgets_budget_action` e não é um report. |
| Bucket de state | **< US$ 0,01 no curso** | Bucket vazio. As 5 requisições `PUT` desta etapa custam ~US$ 0,000025. |

**Custo real incorrido nesta etapa: US$ 0,00** (arredondamento à casa do centavo). Nenhuma chamada ao Cost Explorer foi feita — só `describe-*`, `get-*` e `pricing get-products`, todas gratuitas.

### Pendente

1. 🔴 **`terraform init` com backend S3 e os três `plan` — BLOQUEADOS.** Não foi possível executá-los: a sessão do profile `app_cloud_devops` está **expirada**. `aws sts get-caller-identity --profile app_cloud_devops` retorna `Your session has expired. Please reauthenticate`. Este é o pré-requisito 3 do handoff de §15, e ele deixou de ser atendido. O comando de renovação é **interativo** — abre o console e não pode ser executado por um agente. Os três `plan` que eram o entregável desta etapa (critérios A8 e A9) **não foram produzidos e não há contagem para reportar**. Não estimei os números: contagem de `plan` que não rodou é invenção.
2. 🔴 **`terraform import` do budget** antes do primeiro `apply` — ver *Divergências* 1.
3. 🟠 **Assinatura de e-mail do budget.** As 4 notificações estão `OK` e o subscriber está registrado, mas a AWS cria uma assinatura SNS por trás e ela precisa ser aceita no e-mail. Enquanto não for, o alerta não chega. Verificável em SNS → Subscriptions, filtro `budget`, procurando `PendingConfirmation`.
4. 🟠 **Cost Allocation Tag `CostCenter` não ativada.** Sem a ativação manual no console de Billing o filtro do budget não enxerga nada e o teto fica cego. Leva até 24 h para valer. Pendente desde a etapa 1.
5. 🟡 Pré-requisitos 2 e 6 do handoff (P8/P9 com o professor; datas reais do curso) seguem abertos. O budget foi criado com as datas **assumidas** já registradas em `terraform.tfvars`.

### Divergências

As divergências abertas nas etapas anteriores seguem abertas. Cinco novas:

1. 🔴 **§7 passo 1 e `budget.tf` gerenciam o mesmo recurso, e a ordem de §7 torna o conflito inevitável.** O passo 1 manda criar o budget "antes de qualquer recurso", sem depender de nada; o `terraform init` só acontece no passo 3 e o `apply` no passo 9. Logo o passo 1 **só pode** ser out-of-band — foi como o executei, e foi o que a usuária autorizou. Mas `budget.tf` declara `aws_budgets_budget.this`, então o primeiro `apply` vai tentar **criar de novo** um budget que já existe e falhar com `DuplicateRecordException`. A correção é um `terraform import` antes do apply, e import está na lista de operações que exigem aprovação humana explícita. O comando, com o formato `AccountID:BudgetName` confirmado no MCP:

   `terraform import aws_budgets_budget.this 090413359726:dvn-workshop-budget-curso`

   Criei o recurso com nome, valores e tags idênticos aos do código justamente para que esse import não produza diff. **Ao Arquiteto:** ou §7 passa a dizer que o passo 1 é out-of-band e inclui o import como passo explícito, ou o budget sai de `budget.tf` e vira infraestrutura de bootstrap junto do bucket. Recomendo a primeira — mantém o budget versionado.
2. 🟠 **`backend.tf` não tinha `profile`, e por isso nunca funcionaria.** Bloco de backend **não herda** credencial do bloco `provider "aws"`. Sem `profile`, o backend cai na cadeia default do SDK; como `~/.aws/config` só define `[profile app_cloud_devops]` e não há profile `default`, a cadeia ia até o IMDS e falhava com `No valid credential sources found` / `no EC2 IMDS role found`. Medido: acrescentar o profile ao backend mudou a mensagem para `create oauth2 token: login session has expired` — prova de que o argumento é aceito e de que o profile passou a ser usado. Corrigi no código em vez de depender de um flag na linha de comando, pela mesma razão que levou à cópia do `.tflint.hcl`: gate que depende de alguém lembrar de um flag não é gate. §8 define bucket, key, região e locking, mas não menciona credencial do backend.
3. 🟡 **§11.6 trata "2 budgets ativos" como limite de free tier; a página de pricing atual não impõe esse limite.** A conta já tinha **2 budgets** pré-existentes, criados fora deste ADR (um cost budget mensal e um zero-spend budget) — não constavam do inventário "conta vazia". O nosso é o **3º**. Há divergência entre as fontes da própria AWS: um blog de Cloud Financial Management afirma "60 free budget days per month... $0.02 per day" para budgets adicionais, enquanto a **página de pricing do produto** afirma que o monitoramento é gratuito e cobra apenas budgets **com ações**. Adotei a página de pricing, que é a fonte do produto. Se o blog valesse, o 3º budget custaria US$ 0,02/dia × ~106 dias até 2026-12-03 = **US$ 2,12**, ou 42% do teto — por isso a discrepância está registrada em vez de silenciada. Sugiro ao Arquiteto reconciliar §11.6.
4. 🟡 **§11 não lista transferência de dados cross-AZ, e o passo 12 depende dela por construção.** VPC FAQ oficial: "If the instances reside in subnets in different Availability Zones, you will be charged **$0.01 per GB**" — e a documentação de CUR esclarece que se cobra **as duas pontas**, logo ~US$ 0,02/GB efetivo. O passo 12 põe a instância de teste em `private-1b` e acessa por um EIC Endpoint em `private-1a`, saindo por um NAT em `us-east-1a`: as duas pernas são cross-AZ, **de propósito**, para provar o roteamento. A documentação do EIC Endpoint diz isso na mesma frase em que declara o serviço gratuito. Magnitude real: tráfego SSH é de KBs e um `docker pull` de 100 MB custaria ~US$ 0,002. **Não é bloqueante nem muda a decisão** — é a tabela de §11.2 que está incompleta.
5. 🟡 **A conta não está em US$ 0,00 de consumo.** `freetier get-account-plan-state` retorna `139.99` de crédito restante, contra os `140.00` registrados em §16 em 2026-08-12. O budget pré-existente que exclui créditos mostra `ActualSpend: 0.01`. O valor bate exatamente com **uma** requisição do Cost Explorer a US$ 0,01 — e §16 registra `ce:GetCostAndUsage` chamado na redação do ADR. Ou seja: o único gasto da conta até agora foi a ferramenta de medir gasto. Não afeta o teto de forma relevante; registrado porque o ADR afirma US$ 0,00 e isso deixou de ser exato.

### Sugestões

1. **Documentar a renovação de sessão como pré-requisito operacional recorrente.** O pré-requisito 3 de §15 trata o profile como algo que se verifica uma vez. Na prática é sessão de curta duração que expira sozinha e cuja renovação é interativa — ou seja, **bloqueia qualquer agente** de forma recorrente e silenciosa. Vale um passo "renovar sessão" no início de toda etapa que toque a AWS.
2. **Decidir o destino dos dois budgets pré-existentes** se forem redundantes com o do ADR. Não toquei neles — estão fora do escopo autorizado e um deles é uma proteção ativa da conta.
3. Repetidas das etapas anteriores e ainda válidas: `.checkov.yaml` fixando `--var-file`/`--skip-path`, hook de ASCII em comentário `.tf`, e wrapper de validação encadeando os gates (agora são 7 comandos).

### Risco residual

1. 🔴 **Há dois recursos na AWS que o Terraform não conhece.** Budget e bucket existem e nenhum dos dois está em state — o bucket por decisão de §8 (out-of-band é o correto: o backend não pode gerenciar o próprio storage), o budget por acidente de ordenação. Enquanto o import não acontecer, o primeiro `apply` **falha**. É a próxima coisa que quebra.
2. 🔴 **A proteção de custo do budget é hoje nominal.** Duas condições faltam para ela funcionar: a Cost Allocation Tag `CostCenter` não está ativada — e sem ela o filtro `TagKeyValue` não casa com nada, deixando o budget medindo zero para sempre — e a assinatura de e-mail não está confirmada. **Um budget que mede zero nunca dispara.** As duas são ações manuais no console, e nenhuma delas tem gate automático.
3. 🔴 **Não há ambiente de validação anterior ao alvo.** O ADR define um único ambiente, `prd`. Toda aplicação nesta stack é aplicação em produção. Repetido de todas as etapas anteriores porque continua valendo.
4. 🟠 **Os critérios A8 e A9 seguem inteiramente não verificados contra a AWS.** O código está verde em `validate`, `tflint` e `checkov`, mas nenhum deles conta recurso de `plan`. A afirmação "o estado base cria zero recursos tarifados" continua sendo leitura de código, não medição — e só o `plan` a converte em evidência.
5. 🟠 **O budget entrou em produção sem nunca ter passado por `plan`.** Foi criado por chamada de API direta, com os valores transcritos à mão do código para o JSON da CLI. Conferi campo a campo com `describe-budget`, mas a transcrição não teve gate automático nenhum; um erro de digitação no filtro de tag teria produzido exatamente o mesmo `HEALTHY`.

---

## 2026-08-22 — Etapa 5b: `import` do budget e os três `plan` (critérios A8 e A9)

Continuação direta da 5a. Três bloqueios da etapa anterior foram removidos antes desta sessão começar: a sessão do profile `app_cloud_devops` foi renovada, o `terraform init -reconfigure` com backend S3 passou, e a Cost Allocation Tag `CostCenter` foi ativada.

### Pré-flight

| MCP | Chamada real | Resultado |
| --- | --- | --- |
| `terraform` | `get_latest_provider_version(hashicorp/aws)` | `6.61.0` |
| `aws-mcp` | `sts get-caller-identity` | `arn:aws:iam::090413359726:user/lauraclouddevops` |

Ambos no ar. **Isto encerra a "fonte substituta declarada" registrada em §16 do ADR** — naquela sessão o MCP `terraform` não existia e o Arquiteto anotou a substituição por transparência. Nesta ele responde, e a versão publicada do provider avançou de `6.58.0` (registrada em §16) para `6.61.0`. O pin `~> 6.58` continua correto e o `.terraform.lock.hcl` mantém a stack em **6.59.0** — nada a fazer, registrado só para que a diferença não seja lida como deriva.

Ambiente: Terraform **1.15.8** (satisfaz `~> 1.13`), provider `hashicorp/aws` **6.59.0** vindo do lock.

### Feito

**1. `terraform import` do budget — executado, com autorização humana explícita.**

```
terraform import aws_budgets_budget.this 090413359726:dvn-workshop-budget-curso
→ Import successful!
```

Este era o item 1 de *Divergências* e o item 1 de *Risco residual* da etapa 5a: o budget existia na AWS mas não em state, e o primeiro `apply` falharia com `DuplicateRecordException`. Antes do import confirmei por `budgets:describe-budget` que o recurso estava lá com os valores esperados (`5.0 USD`, `ANNUALLY`, período 2026-08-01 → 2026-12-03, filtro `TagKeyValue`, `HealthStatus: HEALTHY`).

State depois do import — quatro entradas, nenhuma delas de rede:

```
aws_budgets_budget.this
module.network.data.aws_caller_identity.current
module.network.data.aws_partition.current
module.network.data.aws_region.current
```

**2. Os três `plan`, salvos em `docs/implementation/plans/`.**

| Arquivo | Comando |
| --- | --- |
| `ADR-0001-plan-base.txt` | `terraform plan` |
| `ADR-0001-plan-nat.txt` | `terraform plan -var="enable_nat_gateway=true"` |
| `ADR-0001-plan-flowlogs.txt` | `terraform plan -var="enable_flow_logs=true"` |

### Validado

**O import não gerou diff.** É a verificação que dá sentido ao import: se os valores criados à mão na etapa 5a divergissem do código, o plan mostraria `~ update`. No plan base o budget aparece **uma única vez**, e como refresh:

```
aws_budgets_budget.this: Refreshing state... [id=090413359726:dvn-workshop-budget-curso]
```

Não há bloco `~ aws_budgets_budget.this`. Os três plans fecham em **`0 to change, 0 to destroy`**, e uma busca por `must be replaced`, `will be destroyed` e `will be updated` nos três arquivos retorna **vazio**. Isto encerra o item 5 de *Risco residual* da 5a — a transcrição manual campo a campo para o JSON da CLI está agora conferida por uma ferramenta, não por leitura minha.

**Critério A8 — `plan` sem variáveis não cria nenhum recurso tarifado. ATENDIDO.**

```
Plan: 26 to add, 0 to change, 0 to destroy.
```

Os 26, na íntegra:

| # | Recurso | Custo |
| --- | --- | --- |
| 1 | `module.network.aws_vpc.this` | US$ 0,00 |
| 2 | `module.network.aws_internet_gateway.this` | US$ 0,00 |
| 3–4 | `aws_subnet.public[0]`, `aws_subnet.public[1]` | US$ 0,00 |
| 5–6 | `aws_subnet.private[0]`, `aws_subnet.private[1]` | US$ 0,00 |
| 7 | `aws_route_table.public` | US$ 0,00 |
| 8–9 | `aws_route_table.private[0]`, `aws_route_table.private[1]` | US$ 0,00 |
| 10 | `aws_route.public` (`0.0.0.0/0 → igw`) | US$ 0,00 |
| 11–12 | `aws_route_table_association.public[0]`, `[1]` | US$ 0,00 |
| 13–14 | `aws_route_table_association.private[0]`, `[1]` | US$ 0,00 |
| 15 | `aws_vpc_endpoint.s3` — `vpc_endpoint_type = "Gateway"` | US$ 0,00 |
| 16–17 | `aws_vpc_endpoint_route_table_association.s3_private[0]`, `[1]` | US$ 0,00 |
| 18 | `aws_ec2_instance_connect_endpoint.this` | US$ 0,00 |
| 19 | `aws_default_security_group.this` | US$ 0,00 |
| 20 | `aws_security_group.eice` (ADR-0002) | US$ 0,00 |
| 21 | `aws_security_group.lab_access` (ADR-0002) | US$ 0,00 |
| 22 | `aws_vpc_security_group_egress_rule.eice_ssh` | US$ 0,00 |
| 23–24 | `aws_vpc_security_group_egress_rule.lab_dns_tcp`, `lab_dns_udp` | US$ 0,00 |
| 25 | `aws_vpc_security_group_egress_rule.lab_https` | US$ 0,00 |
| 26 | `aws_vpc_security_group_ingress_rule.lab_ssh` | US$ 0,00 |

Nenhum `aws_nat_gateway`, nenhum `aws_eip`, nenhum `aws_cloudwatch_log_group`, nenhum `aws_iam_role`, nenhum `aws_flow_log`. Confirmado também que `aws_vpc_endpoint.s3` é do tipo **Gateway** — o tipo é o que separa US$ 0,00 de US$ 0,01/h por AZ, e o plan mostra `vpc_endpoint_type = "Gateway"` literalmente.

**Nota sobre a contagem.** §6 do ADR previa ~10 recursos e o plan traz 26. A diferença não é escopo extra: são as 2 route table associations públicas, as 2 privadas, as 2 do endpoint S3, e sobretudo os **7 recursos de Security Group do ADR-0002** (2 SGs + 5 regras), que emenda este ADR. §4 conta "recursos" em granularidade de componente; o Terraform conta em granularidade de recurso. Nenhum recurso fora dos dois ADRs aparece no plan.

Evidências de §14 "Infraestrutura" colhidas do mesmo plan, agora contra a máquina e não contra o código:

| Critério | Valor no plan |
| --- | --- |
| VPC `10.0.0.0/24` com DNS | `cidr_block = "10.0.0.0/24"`, `enable_dns_support = true`, `enable_dns_hostnames = true` |
| `public-1a` | `10.0.0.0/26`, `us-east-1a`, `map_public_ip_on_launch = true` |
| `public-1b` | `10.0.0.64/26`, `us-east-1b`, `map_public_ip_on_launch = true` |
| `private-1a` | `10.0.0.128/26`, `us-east-1a`, `map_public_ip_on_launch = false` |
| `private-1b` | `10.0.0.192/26`, `us-east-1b`, `map_public_ip_on_launch = false` |
| NACL default ausente do state (R5) | busca por `aws_default_network_acl` nos 3 plans: **vazio** |
| RTs privadas sem rota default no estado base | `aws_route.private[*]` **não** aparece no plan base |
| Outputs | `nat_gateway_id = ""` e `nat_public_ip = ""`; `availability_zones = ["us-east-1a","us-east-1b"]` |

**Critério A9 — `-var="enable_nat_gateway=true"` cria exatamente 4. ATENDIDO.**

```
Plan: 30 to add, 0 to change, 0 to destroy.
```

30 − 26 = **4**, obtidos por diff da lista de recursos contra o plan base:

1. `module.network.aws_eip.nat[0]`
2. `module.network.aws_nat_gateway.this[0]`
3. `module.network.aws_route.private[0]`
4. `module.network.aws_route.private[1]`

Exatamente os quatro que §14 nomeia. O diff inverso (recursos que sumiriam) é **vazio**: ligar o NAT só acrescenta. Confirma o ponto de atenção 1 de §15 — `enable_nat_gateway` condiciona três coisas (EIP, NAT e as duas rotas), e o EIP está sob a mesma variável, que é a mitigação de R6.

**Terceiro plan — `-var="enable_flow_logs=true"` cria exatamente 4. ATENDIDO.**

```
Plan: 30 to add, 0 to change, 0 to destroy.
```

30 − 26 = **4**:

1. `module.network.aws_cloudwatch_log_group.this[0]`
2. `module.network.aws_iam_role.this[0]`
3. `module.network.aws_iam_role_policy.this[0]`
4. `module.network.aws_flow_log.this[0]`

Exatamente os quatro de §14. O diff bruto de linhas `#` mostra 32 contra 26, não 30 contra 26 — as duas linhas a mais são `module.network.data.aws_iam_policy_document.this[0] will be read during apply` e sua linha de continuação `(config refers to values not yet known)`. **Data source não é recurso criado, não entra no `to add` e não custa nada**; o `Plan:` do próprio Terraform é a contagem que vale, e ela diz 30. Registro a discrepância porque quem contar linhas `#` a olho vai achar 6 e concluir que o critério falhou.

**Cost Allocation Tag `CostCenter` — ATIVA.** Verificada por leitura própria, não por relato:

```
aws ce list-cost-allocation-tags --tag-keys CostCenter
→ {"TagKey":"CostCenter","Type":"UserDefined","Status":"Active","LastUpdatedDate":"2026-08-22T15:07:37Z"}
```

Encerra o pendente 4 da etapa 5a. Metade do item 2 de *Risco residual* da 5a cai com isso; a outra metade — a assinatura de e-mail — virou uma divergência, abaixo.

### Pendente

1. 🔴 **`terraform apply` do estado base (§7 passo 9) — não autorizado nesta invocação.** É o próximo passo e precisa de aprovação humana sobre as contagens acima. O plan está revisado e as três contagens batem com §14; falta a decisão.
2. 🟠 **Critério "um segundo `plan` logo após o `apply` retorna *No changes*"** — só verificável depois do apply.
3. 🟠 **Toda a "Validação funcional" de §14** (§7 passos 11–15: instância descartável em `private-1b`, EIC Endpoint, `docker pull`, Logs Insights, fechamento da janela e custo real) — depende do apply. Nenhuma instância EC2 foi criada nesta etapa, conforme instrução.
4. 🟠 **Assinatura de e-mail do budget** — ver *Divergências* 1. Mudou de natureza: não é mais "confirmar no e-mail", é "descobrir se há o que confirmar".
5. 🟡 Pré-requisitos 2 e 6 do handoff (P8/P9 com o professor; datas reais do curso) seguem abertos desde a etapa 1. O budget opera com as datas assumidas.

### Divergências

As divergências abertas nas etapas anteriores seguem abertas, **exceto a nº 1 da etapa 5a** (budget fora do state), que o import desta etapa resolve na prática. A recomendação daquele item continua valendo para o Arquiteto: §7 deveria dizer que o passo 1 é out-of-band e incluir o import como passo explícito, senão a próxima pessoa que executar este ADR do zero repete o mesmo tropeço. Uma divergência nova:

1. 🟠 **O pendente 3 da etapa 5a — "assinatura SNS do budget em `PendingConfirmation`" — não se sustenta na observação.** `aws sns list-subscriptions` na conta retorna `{"Subscriptions":[]}`: **nenhuma** assinatura, em nenhum estado. Na etapa 5a assumi que a AWS criaria uma assinatura SNS visível por trás de `subscriber_email_addresses` e a registrei como pendente a confirmar. A conta não mostra isso. A leitura mais provável é que subscriber do tipo `EMAIL` em AWS Budgets é entregue por mecanismo interno da AWS, sem tópico SNS na conta do cliente — o fluxo de confirmação por SNS valeria para subscriber do tipo `SNS`, que não é o nosso caso. ⚠️ **NÃO VERIFICADO:** não confirmei isso na documentação e, principalmente, **não tenho prova de que o e-mail chega** — a única prova seria um alerta real disparando. Corrijo aqui o que afirmei na 5a, em vez de deixar um pendente que aponta para algo inexistente. **Ao Arquiteto:** o critério de §14 pede assinatura de e-mail "confirmada"; se não há o que confirmar, o critério precisa virar outra coisa — sugiro "alerta de teste recebido" ou a remoção do requisito com justificativa.

### Sugestões

1. **§16 do ADR merece uma nota de que o MCP `terraform` voltou.** A seção declara a fonte substituta com um aviso forte e permanente; agora que o MCP responde, os quatro itens de Terraform listados ali podem ser reverificados e o aviso retirado. Não fiz porque `docs/adr/` é somente leitura para mim.
2. **Salvar os plans em `docs/implementation/plans/` deveria virar convenção.** Criei o diretório nesta etapa porque §7 passo 16 pede "plan salvo" no PR e não havia lugar definido. Vale registrar em §8 se o Arquiteto concordar.
3. Repetidas e ainda válidas: `.checkov.yaml` fixando `--var-file`/`--skip-path`, hook de ASCII em comentário `.tf`, e wrapper encadeando os gates de validação.

### Risco residual

1. 🔴 **Não há ambiente de validação anterior ao alvo.** O ADR define um único ambiente, `prd`. Toda aplicação nesta stack é aplicação em produção. Repetido de todas as etapas anteriores porque continua valendo, e é o que torna a aprovação do próximo `apply` uma decisão de produção.
2. 🟠 **A proteção de custo do budget ainda não foi vista funcionar.** A tag está ativa e o filtro agora casa, mas `CalculatedSpend.ActualSpend` segue `0.0` e os dados de Budgets levam de 8 a 12 h para refletir (§11.5). Só o primeiro ciclo com gasto real prova que a corrente inteira — tag aplicada → tag ativada → filtro → notificação → e-mail — está fechada. Até lá é presunção razoável, não evidência.
3. 🟠 **O bucket de state continua fora do Terraform**, por decisão de §8. Correto, e registrado para que a assimetria com o budget não confunda: o budget entrou no state nesta etapa, o bucket não entra por design.
4. 🟡 **As contagens valem para este código nesta data.** Qualquer alteração no módulo muda os números, e os três plans precisam ser refeitos antes do apply se houver commit no meio. O apply deve reconfirmar que o plan bate com o que foi aprovado.

### Custo desta etapa

**US$ 0,00.** O `import` não cria recurso. Os três `plan` são leitura. Todas as chamadas de AWS foram `sts get-caller-identity`, `budgets describe-budget`, `ce list-cost-allocation-tags` e `sns list-subscriptions` — todas gratuitas. **Nenhuma chamada a `ce get-cost-and-usage`** (US$ 0,01 cada); `list-cost-allocation-tags` pertence ao namespace `ce` mas não é operação tarifada do Cost Explorer, que cobra por requisição de `GetCostAndUsage` e afins.

---

## Etapa 5c — `apply` do estado base (§7 passo 9) — 2026-08-22

**Resultado: parcial. 21 dos 26 recursos criados; 5 falharam pela mesma causa. O state ficou consistente e nada tarifado existe na conta.**

### Feito

**Pré-flight de MCP, com chamada real.** `mcp__terraform__get_latest_provider_version` (hashicorp/aws) devolveu `6.61.0`; `mcp__aws-mcp__aws___call_aws` com `sts get-caller-identity` devolveu a conta. Os dois no ar. Sessão local do profile `app_cloud_devops` verificada **antes** de investir trabalho, conforme a armadilha registrada — válida.

**Reconfirmação do plan antes de mutar.** Não bastou conferir a contagem. Comparei o plan novo com `docs/implementation/plans/ADR-0001-plan-base.txt`, aprovado na 5b, em três níveis: a linha `Plan:` (`26 to add, 0 to change, 0 to destroy` nos dois), os 26 endereços de recurso (`diff` vazio) e o corpo inteiro das linhas 1-614. As **únicas** diferenças do corpo foram um BOM de encoding no arquivo salvo e a ordem de duas linhas de log de leituras concorrentes de data source — zero diferença de atributo. Só então apliquei.

**Apply.** Executado sobre um plan salvo com `-out`, para que a mutação fosse exatamente o conjunto verificado e nada além. Sem `-var`: `enable_nat_gateway` e `enable_flow_logs` permaneceram nos defaults `false`.

Entraram **21 recursos**: a VPC, o IGW, as 4 subnets, as 3 route tables, as 4 associações, a rota pública, o Gateway Endpoint de S3 e suas 2 associações, o EIC Endpoint, o default SG esvaziado e os 2 SGs de acesso.

### A falha, e a causa

As 5 regras de security group falharam, todas com o mesmo erro da EC2 API:

```
InvalidParameterValue: Invalid rule description. Valid descriptions are
strings less than 256 characters from the following set:  a-zA-Z0-9._-:/()#,@[]+=&;{}!$*
```

**Causa: o caractere `§` no valor de `description`.** Confirmada na documentação da AWS via `aws-mcp` (`IpRange.description` / `Ipv6Range.description`: "Allowed characters are a-z, A-Z, 0-9, spaces, and `._-:/()#,@[]+=&;{}!$*`"), não suposta de memória. O `§` não pertence ao conjunto.

A correlação é exata e explica por que a falha foi seletiva: as 5 regras tinham `(ADR-0002 §5.2)` na descrição e as 5 falharam; os 2 `aws_security_group` nunca tiveram `§` e os 2 passaram. O texto não foi invenção da implementação — **é cópia literal do exemplo de código do ADR-0002 §5.2, linha 224**, que prescreve uma string que a API rejeita.

**Correção aplicada:** `§5.2` passou a `secao 5.2` nos 5 valores de `description`. Nada mais mudou — nem porta, nem protocolo, nem origem, nem CIDR, nem referência de SG. A semântica de segurança das 5 regras é idêntica à aprovada, e o critério A3 do ADR-0002 ("toda regra com `description`") segue atendido. Acrescentei ao arquivo um bloco de comentário explicando a restrição e o motivo da forma por extenso, para que ninguém "conserte" o texto de volta e reproduza a falha. Nos comentários o `§` continua livre: comentário não chega na AWS.

**Varredura de escopo.** Verifiquei todos os valores de `description` do stack, não só os 5 que quebraram: os `§` restantes estão exclusivamente em `variables.tf`, que são descrições de **variável do Terraform** — metadado local que nunca vai à API da AWS. Deliberadamente não alterados.

### Validado

| Critério | Evidência |
| --- | --- |
| `fmt -check -recursive` | limpo |
| `validate` | `Success! The configuration is valid.` |
| `tflint` raiz e módulo | exit 0 nos dois, com `ruleset.aws (0.48.0)` confirmado por `--version` **em cada diretório** antes de confiar no resultado (ADR-0002 A4) |
| `checkov --var-file terraform.tfvars` | **43 passed, 0 failed, 7 skipped** (ADR-0002 A5) |
| VPC | `10.0.0.0/24`; `EnableDnsSupport` e `EnableDnsHostnames` = `true` |
| 4 subnets | `10.0.0.0/26` pub 1a · `10.0.0.64/26` pub 1b · `10.0.0.128/26` priv 1a · `10.0.0.192/26` priv 1b — CIDR e AZ exatos |
| `map_public_ip_on_launch` | `true` nas 2 públicas, `false` nas 2 privadas |
| RT pública | `0.0.0.0/0 → igw-0d7e60324d1822e50`, associada às 2 subnets públicas |
| RTs privadas | 2, associadas 1:1 às privadas, **sem rota default** — estado base correto |
| Gateway Endpoint S3 | 1, `available`, associado às 2 RTs privadas; **nenhum** Interface Endpoint |
| EIC Endpoint | `create-complete` em `private-1a`, com `sg-eice` e `preserve_client_ip = false` (ADR-0002 A2) |
| Default SG | sem nenhuma regra, ingress e egress vazios |
| NACL default | ausente do state |
| Tags | 7 em cada recurso tagueável: as 6 de `default_tags` mais `Name` |
| Nada tarifado | `describe-nat-gateways`, `describe-addresses`, `describe-flow-logs`, `describe-log-groups --prefix /aws/vpc` e `describe-instances`: **todos vazios** |

**Custo do estado resultante: US$ 0,00/hora.** VPC, subnets, route tables, IGW, security groups, Gateway Endpoint de S3 e EIC Endpoint não são recursos tarifados por hora.

### Pendente

1. 🔴 **As 5 regras de SG não foram aplicadas, e o `apply` está PARADO aguardando aprovação humana.** O plan corrigido é `5 to add, 0 to change, 0 to destroy`, exatamente os 5 endereços que falharam. Não apliquei por regra própria: o plan que a usuária revisou era `26 to add`, e o que existe agora é um plan cujo texto **eu** alterei depois da aprovação. Aplicar a própria edição não revisada é o que o gate existe para impedir. Não há urgência que justifique contornar — o estado parcial é gratuito, fechado e estável.
2. 🟠 **O critério `terraform plan` retorna "No changes"** só pode ser fechado depois do apply dos 5. Hoje retorna `5 to add`.
3. Pendentes herdados das etapas anteriores seguem abertos, inclusive o item 5 do handoff (P8/P9 com o professor).

### Divergências

1. 🔴 **O exemplo de código do ADR-0002 §5.2, linha 224, não é aplicável como está escrito.** A `description` prescrita — `"SSH para as instancias do laboratorio (ADR-0002 §5.2)"` — é rejeitada pela EC2 API por causa do `§`. Não é detalhe de estilo: é o que fez 5 de 26 recursos falharem num apply aprovado. **Ao Arquiteto:** corrigir a linha 224 do ADR-0002 e, de preferência, acrescentar ao §8 do ADR-0001 (Nomenclatura) uma regra explícita de que valor de `description` de recurso AWS é ASCII restrito ao conjunto da API, distinguindo-o de `description` de variável do Terraform, que é livre. O código já diverge do ADR neste ponto, deliberadamente e por impossibilidade técnica.

As divergências abertas nas etapas anteriores seguem abertas.

### Sugestões

1. **Um gate de lint que rejeite não-ASCII em valor de `description` de recurso** fecharia esta classe inteira antes do apply. Nem `validate`, nem `tflint`, nem `checkov` pegaram — os três passaram limpos sobre o código quebrado, porque nenhum deles conhece a restrição de charset da EC2 API. O único detector foi a própria AWS, no meio da mutação. Note que o gate precisa distinguir `description` de recurso da de variável, senão dá falso positivo em `variables.tf`.
2. Repetidas e ainda válidas: `.checkov.yaml` fixando `--var-file`, e wrapper encadeando os gates de validação.

### Risco residual

1. 🔴 **Não há ambiente de validação anterior ao alvo.** O ADR define um único ambiente, `prd`. Toda aplicação nesta stack é aplicação em produção — e esta etapa mostrou o custo prático disso: a falha de charset foi descoberta em produção porque não existe lugar mais barato para descobri-la.
2. 🟠 **Os 2 SGs existem sem nenhuma regra.** É fail-closed e seguro — o provider revogou o egress allow-all default, verificado na conta — mas o caminho de acesso do §7 passo 12 **não funciona** neste estado. Quem tentar a etapa 5d antes de aplicar os 5 vai falhar no SSH pelo EIC Endpoint.
3. 🟠 **A proteção de custo do budget ainda não foi vista funcionar** (herdado da 5b).
4. 🟡 **O apply parcial não deixou recurso órfão.** `terraform state list` traz 25 entradas — 21 recursos desta etapa, o budget importado na 5b e 3 data sources — e o plan seguinte acusa `0 to change, 0 to destroy`, o que prova que nada do que entrou ficou divergente do código. Não houve necessidade de manipular state.

### Custo desta etapa

**US$ 0,00.** Os 21 recursos criados são todos não tarifados por hora. Nenhuma chamada a `ce get-cost-and-usage`. Todas as verificações de conta foram `describe-*`, gratuitas.
