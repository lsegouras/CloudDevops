---
name: checkov-ckv-aws-24-falso-positivo
description: CKV_AWS_24 falha em aws_vpc_security_group_ingress_rule que usa referenced_security_group_id, tratando referencia de SG como 0.0.0.0/0
metadata:
  type: project
---

`CKV_AWS_24` ("no security groups allow ingress from 0.0.0.0:0 to port 22") **falha por falso positivo** em toda regra `aws_vpc_security_group_ingress_rule` que define a origem por `referenced_security_group_id` na porta 22.

Causa, medida no fonte do checkov 3.3.10 — `checkov/terraform/checks/resource/aws/AbsSecurityGroupUnrestrictedIngress.py`, linhas 107-110: o check só consulta `security_groups` e `source_security_group_id`, que são os argumentos dos recursos **legados** (`aws_security_group` inline e `aws_security_group_rule`). Ele não conhece `referenced_security_group_id`, do recurso moderno. Não achando origem nos dois campos que conhece, conclui "sem origem, logo aberto ao mundo".

Comportamento verificado com teste controlado, mesmo `from_port`/`to_port` 22:

| Origem | Resultado |
| --- | --- |
| `referenced_security_group_id` | **FAILED** |
| `cidr_ipv4 = "10.0.0.0/24"` | PASSED |
| `cidr_ipv4 = "0.0.0.0/0"` | **FAILED** |

O check pune a forma mais restritiva e aprova a mais permissiva.

**Why:** a referência SG↔SG é a prática recomendada pelo provider AWS desde 2023 e é o que torna regras de EC2 Instance Connect Endpoint imunes ao valor de `preserve_client_ip`. A "correção" óbvia — trocar para `cidr_ipv4` — deixa o relatório verde e o código pior.

**How to apply:** ao ver `CKV_AWS_24` sobre uma regra que usa `referenced_security_group_id`, confirme a origem no código antes de tratar como achado real. **Nunca troque a referência de SG por CIDR para silenciar o check.** Se houver ADR, a supressão precisa de autorização nominal; sem ela, escale. Vale para qualquer `AbsSecurityGroupUnrestrictedIngress` — `CKV_AWS_260` (porta 80) tem a mesma classe-base e o mesmo defeito.

Relacionado: [[checkov-neste-ambiente]]
