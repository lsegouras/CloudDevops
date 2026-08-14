# ADR-0002 — Log de implementação

Arquivo append-only. Nunca reescreva entradas anteriores.

O ADR-0002 **emenda** o ADR-0001. O log daquele ADR, em `ADR-0001-log.md`, continua válido e não foi tocado — as quatro entradas dele citam §§ cujo conteúdo não mudou.

---

## 2026-08-14 — Etapas 1 a 5 de 5: security groups do caminho de acesso e supressões autorizadas

**Executor:** devops-engineer · **Branch:** `feat/adr-0001-endpoints-and-flow-logs` (a mesma da etapa 4 do ADR-0001)
**ADR:** `docs/adr/ADR-0002-security-groups-de-acesso-e-supressoes-checkov.md` — status `Aprovado` em 2026-08-14.
**Escopo:** as 5 etapas do §7, todas nesta entrada. Nenhuma delas toca a AWS.

### Pré-flight de MCP

Os dois MCPs responderam a **chamada real**, não só a carga de schema:

| MCP | Chamada | Resultado |
| --- | --- | --- |
| `terraform` | `get_latest_provider_version(hashicorp/aws)` | `6.60.0` |
| `aws-mcp` | `sts:GetCallerIdentity` (us-east-1) | conta esperada, usuário esperado |

Nenhuma fonte substituta foi usada. Todos os argumentos de recurso foram conferidos no MCP `terraform` antes de serem escritos:

| Recurso | `provider_doc_id` | O que foi confirmado nesta sessão |
| --- | --- | --- |
| `aws_security_group` | `13197168` | `name`, `description` (Forces new, não pode ser `""`), `vpc_id`, `tags`. **WARNING formal** do provider contra misturar blocos inline com recursos de regra |
| `aws_vpc_security_group_egress_rule` | `13197396` | `security_group_id` e `ip_protocol` Required; `from_port`/`to_port`/`cidr_ipv4`/`referenced_security_group_id`/`description`/`tags` Optional |
| `aws_vpc_security_group_ingress_rule` | `13197397` | Mesma forma, sentido de entrada |
| `aws_ec2_instance_connect_endpoint` | `13196330` | `security_group_ids` Optional (herda o default SG da VPC se omitido); `preserve_client_ip` — **doc do provider declara `Default: true`** |

### Feito

Três arquivos alterados no módulo, um na raiz.

| Arquivo | Mudança |
| --- | --- |
| `modules/network/vpc.security-groups.tf` | `aws_default_security_group.this` **inalterado**. Acrescentados `aws_security_group.eice` e `aws_security_group.lab_access`, mais as 5 regras: `egress.eice_ssh`, `ingress.lab_ssh`, `egress.lab_https`, `egress.lab_dns_udp`, `egress.lab_dns_tcp`. Todas como **recurso separado** — nenhum bloco inline |
| `modules/network/vpc.endpoints.tf` | `aws_ec2_instance_connect_endpoint.this` recebeu `security_group_ids = [aws_security_group.eice.id]` e `preserve_client_ip = false`. O comentário `DIVERGENCIA REGISTRADA` foi substituído por referência ao ADR-0002 |
| `modules/network/outputs.tf` | Outputs `eice_security_group_id` e `lab_access_security_group_id` |
| `outputs.tf` (raiz) | Os mesmos dois outputs, subindo do módulo |

Mais os `checkov:skip` de §5.3, aplicados em `vpc.public-subnets.tf`, `vpc.nat-gateway.tf`, `vpc.flow-logs.tf` e `vpc.security-groups.tf`.

Decisões de implementação que não são leitura direta do ADR:

- **`0.0.0.0/0` literal na regra `lab_https`.** O critério A7 proíbe CIDR literal em `modules/network`, mas o §5.2 manda esse valor explicitamente. Tratado como constante de roteamento, não como CIDR de ambiente — **com precedente já aceito no módulo**: `destination_cidr_block = "0.0.0.0/0"` existe em `vpc.public-route-table.tf` e `vpc.private-route-tables.tf` desde a etapa 2, sob o mesmo critério. Nenhum CIDR de ambiente (`10.0.0.x`), AZ, região, conta ou ARN literal entrou.
- **Destino da regra `lab_https` é `0.0.0.0/0` e não a prefix list do S3.** A API do ECR não está na prefix list — só as camadas de imagem estão. Restringir à prefix list quebraria o `curl` do passo 12.
- **UDP e TCP na porta 53 como duas regras**, porque são duas entradas distintas na API. O DNS cai para TCP quando a resposta passa de 512 bytes.
- **Nenhum `count` nos recursos desta emenda.** O caminho de acesso precisa existir no estado base, com a janela de custo **fechada** — é justamente com o NAT desligado que o EIC Endpoint é o único acesso.
- **`.terraform.lock.hcl` do módulo NÃO foi commitado.** O `terraform init -backend=false` que roda dentro de `modules/network` para permitir o `validate` gera um lock próprio, e ele resolveu para **6.60.0** enquanto a raiz está pinada em **6.59.0**. Commitá-lo criaria um segundo pin, divergente, dentro do módulo — a mesma classe de armadilha do `.tflint.hcl` duplicado. O arquivo e o `.terraform/` do módulo foram removidos após a validação. **O `.gitignore` não cobre `.terraform.lock.hcl`**, então isso depende de lembrar; ver *Sugestões*.

### Validado

Todos os comandos rodados de `project-terraform/01-networking-stack/`.

| Gate | Antes (`17f7ae1`) | Depois | Situação |
| --- | --- | --- | --- |
| `terraform fmt -recursive -check` | exit 0 | **exit 0** | limpo |
| `terraform validate` raiz | Success | **Success** | limpo |
| `terraform validate` módulo | Success | **Success** | limpo |
| `tflint --recursive` | 0 issues, exit 0 | **0 issues, exit 0** | limpo |
| `checkov` var-file padrão | Passed 19, Failed 2, Skipped 1 | **Passed 43, Failed 1, Skipped 6** | Failed 2 → 1 |
| `checkov` janela aberta | Passed 47, Failed 4, Skipped 1 | **Passed 72, Failed 1, Skipped 6** | Failed 4 → 1 |

O baseline "antes" foi **medido nesta sessão** antes de qualquer edição, não copiado do log da etapa 4.

`tflint --version` conferido **nos dois diretórios antes** de confiar no resultado, porque `--recursive` não herda `.tflint.hcl` do pai. Ambos: TFLint 0.64.0 + `ruleset.aws (0.48.0)` + `ruleset.terraform (0.15.0-bundled)`.

**As 6 supressões, todas nominais e todas apontando para ADR-0002 §5.3:**

| ID | Recurso | Origem da autorização |
| --- | --- | --- |
| `CKV_AWS_158` | `aws_cloudwatch_log_group.this[0]` | ADR-0001 §5, já suprimido na etapa 4 — **sem mudança** |
| `CKV_AWS_338` | `aws_cloudwatch_log_group.this[0]` | ADR-0002 §5.3 — era a divergência 2 da etapa 4 |
| `CKV_AWS_130` | `aws_subnet.public[0]` e `[1]` | ADR-0002 §5.3 |
| `CKV2_AWS_19` | `aws_eip.nat[0]` | ADR-0002 §5.3 — aberto desde a etapa 3 |
| `CKV2_AWS_5` | `aws_security_group.lab_access` | ADR-0002 §5.3 — **a predição do Arquiteto se confirmou por medição** |

**Os dois pontos que o ADR marcou como não verificados, agora medidos:**

1. **`CKV2_AWS_5` era o ID correto.** Disparou exatamente sobre `aws_security_group.lab_access`, como §5.3 previu. Nenhuma reatribuição de justificativa foi necessária.
2. **`CKV_AWS_23` passa: 7 passed, 0 failed.** A predição de que `description` em toda regra bastaria se confirmou.

**Contradição do `preserve_client_ip` — confirmada por medição direta nesta sessão, nas duas fontes:**

| Fonte | Lida via | Default declarado |
| --- | --- | --- |
| Provider Terraform `hashicorp/aws`, doc `13196330` | MCP `terraform` | **`true`** |
| CDK / CloudFormation `CfnInstanceConnectEndpointProps` | MCP `aws-mcp` | **`false`** |

As duas se contradizem, como o ADR-0002 R18 registrou. O valor foi escrito explicitamente (`false`), e a referência SG↔SG torna a conectividade imune a ele de qualquer forma.

**Nenhum `terraform plan` foi executado contra a AWS e nenhum recurso foi criado.** O bucket do backend S3 continua inexistente.

### Pendente

1. **`CKV_AWS_24` continua vermelho**, por decisão consciente. Ver *Divergências*.
2. **Critérios de aceite funcionais A10 e A11** — instância descartável lançada com o SG `lab-access`, acesso via EIC Endpoint, `curl` e `docker pull`. São a etapa 5 do ADR-0001 e dependem do bucket de state.
3. **Critérios A8 e A9** — as duas contagens de `plan`. Exigem contato com a AWS.
4. **Pendentes herdados do ADR-0001**, todos ainda bloqueando o `apply`: bucket de state, P8/P9, datas do curso, Cost Allocation Tag, assinatura de e-mail do budget. O §15 pré-requisito 4 do ADR-0002 é explícito: esta emenda **não** desbloqueia nenhum.
5. ~~Referência cruzada no ADR-0001.~~ **Já resolvida antes desta etapa começar, e não por mim.** O campo *Relacionados* do ADR-0001 já dizia `Emendado por ADR-0002` na working tree quando li o repositório. **Risco R17 fechado.** ADRs continuam somente leitura para mim; apenas versionei a alteração no commit dos ADRs.

### Divergências

As divergências das etapas 1 a 4 do ADR-0001 que o ADR-0002 **não** endereça seguem abertas. As duas que ele endereçava — EIC Endpoint sem SG e `CKV_AWS_338` — estão **fechadas**. Uma nova:

1. 🟠 **`CKV_AWS_24` falha sobre `aws_vpc_security_group_ingress_rule.lab_ssh`, e é falso positivo do checkov.** Não está na lista nominal de §5.3, e §5.3 é explícito — "qualquer outro achado sobre os SGs novos é escalação". **Não suprimi.**

   A causa está **medida, não suposta**: `AbsSecurityGroupUnrestrictedIngress.py` (checkov 3.3.10), linhas 107-110, lê apenas `security_groups` e `source_security_group_id` — os argumentos dos recursos **legados**. Ele não conhece `referenced_security_group_id`, que é o argumento do recurso moderno. Não achando origem em nenhum dos dois campos que conhece, conclui "sem origem, logo aberto ao mundo" e falha.

   Teste controlado das três variantes, mesmo `from_port`/`to_port` 22, em diretório isolado:

   | Variante | Origem | Resultado |
   | --- | --- | --- |
   | `by_sg_ref` | `referenced_security_group_id` | **FAILED** ← a forma que o ADR exige |
   | `by_private_cidr` | `cidr_ipv4 = "10.0.0.0/24"` | PASSED |
   | `by_world` | `cidr_ipv4 = "0.0.0.0/0"` | **FAILED** ← genuinamente aberto |

   **O check trata a referência de SG exatamente como trata `0.0.0.0/0`, e aprova o `/24` que é estritamente mais permissivo.** Ele pune a decisão de segurança de §5.2 e recompensaria a alternativa que o ADR rejeitou.

   Existe uma "correção" que deixaria o relatório verde: trocar `referenced_security_group_id` por `cidr_ipv4 = <CIDR da VPC>`. **Não a fiz**, e recomendo que não seja feita — é exatamente a forma sensível a `preserve_client_ip` que §5.2 rejeitou, e o resultado seria verde no relatório e frágil em runtime. Trocar corretude por cor de relatório é o defeito que esta emenda existe para eliminar.

   Três saídas, todas do Arquiteto: **(a)** acrescentar `CKV_AWS_24` sobre `aws_vpc_security_group_ingress_rule.lab_ssh` à lista de §5.3, com a justificativa do falso positivo medido; **(b)** manter o achado vermelho e documentado; **(c)** trocar para CIDR. **Recomendo (a)** — é o mesmo raciocínio que já autorizou `CKV2_AWS_19`: check que não modela a associação real. **(c) é a única que eu desaconselho ativamente.**

### Sugestões

1. **`.checkov.yaml` fixando `--var-file` e `--skip-path`.** Quinta vez que aparece. O §15 do ADR-0002 já reconhece que é melhoria de tooling e não precisa de ADR — falta só decidir fazer.
2. **Um segundo `--var-file` versionado para a variante de janela aberta.** Hoje ele é recriado à mão em scratchpad a cada rodada, e a diferença entre Passed 43 e Passed 72 mostra quanto fica invisível sem ele. Um `envs/open-window.tfvars` commitado tornaria o segundo scan reprodutível por qualquer pessoa.
3. **Wrapper de validação** encadeando os 7 comandos. Repetida das etapas 3 e 4.
4. **Ignorar `modules/**/.terraform.lock.hcl` no `.gitignore`.** O `validate` do módulo exige um `init` que gera esse arquivo, e ele resolve para uma versão diferente da pinada na raiz. Hoje só não é commitado porque alguém lembra de apagar — e uma vez commitado vira pin fantasma que ninguém procura.
5. **Reportar o falso positivo do `CKV_AWS_24` upstream.** O recurso `aws_vpc_security_group_ingress_rule` é a prática recomendada pelo provider desde 2023, e o check ainda não o modela. Qualquer projeto que siga a recomendação do provider e use referência de SG vai bater nisso.

### Risco residual

1. 🔴 **Não há ambiente de validação anterior ao alvo.** O ADR define um único ambiente, `prd`. **Toda aplicação nesta stack é aplicação em produção** e exige plan revisado e aprovação humana explícita. Repetido de todas as etapas anteriores porque continua valendo.
2. 🔴 **R14 do ADR-0002 não tem gate automático.** Se a instância descartável for lançada sem `--security-group-ids`, ela cai no default SG vazio e a falha reaparece — idêntica à original. O output `lab_access_security_group_id` e o comentário no código são a mitigação, e ambos dependem de alguém **ler**. Nenhuma ferramenta verifica isso.
3. 🟠 **A premissa P2 continua não verificada.** Não foi possível confirmar se egress de SG se aplica ao resolver DNS da VPC. As duas regras de porta 53 entram por precaução, custam US$ 0,00 e não há cenário em que atrapalhem — mas se P2 for falsa **e** algo mais estiver errado no DNS, essas regras não serão o problema nem a solução, e podem induzir a diagnóstico errado.
4. 🟠 **`CKV_AWS_24` vermelho reintroduz o problema que §5.3 queria resolver.** A tabela de §4.2 argumenta que vermelho permanente treina a ignorar o relatório. Agora há exatamente um vermelho, bem documentado — mas ele é o começo de uma fila se não for decidido.
5. 🟡 **Nenhum dos SGs novos tem cobertura de `terraform validate` quanto à semântica de conectividade.** `validate` confere schema; o MCP conferiu argumentos; o checkov erra o único check que incide. **A prova de que o caminho funciona é o passo 12**, na etapa 5, e não existe antes disso.
6. 🟡 **A duplicação do `.tflint.hcl` pode divergir.** Inalterado das etapas 3 e 4.
