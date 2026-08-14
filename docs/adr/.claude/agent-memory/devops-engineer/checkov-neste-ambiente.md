---
name: checkov-neste-ambiente
description: Ferramentas de validacao disponiveis neste ambiente e as duas armadilhas do checkov aqui — var-file obrigatorio e leitura em cp1252
metadata:
  type: project
---

Ferramentas de validação instaladas e funcionais neste ambiente: `terraform`, `tflint` 0.64.0 (ruleset `aws` 0.48.0 + `terraform` 0.15.0-bundled), `checkov` 3.3.10. **`tfsec` não está instalado.**

Duas armadilhas do checkov aqui, ambas medidas:

**1. `--var-file` é obrigatório, não opcional.** Sem ele o checkov não resolve `count = length(var.x)` nem `count = var.flag ? 1 : 0` e **descarta o recurso silenciosamente, sem aviso**. Um scan "limpo" nessas condições é falso negativo. Recursos atrás de flag desligada exigem um segundo scan com um var-file que as ligue — a diferença entre as duas variantes chegou a 29 checks a mais.

**2. Lê os arquivos como cp1252 neste Windows.** Aborta com `UnicodeDecodeError` e exit 2 diante de emoji em comentário `.tf`, e a mensagem aponta para um offset de byte, não para o arquivo. Acentuação e `§` passam; emoji não. Mantenha comentários `.tf` sem emoji.

**Why:** as duas custam tempo de depuração e a primeira é pior, porque falha silenciosamente para o lado do "verde".

**How to apply:** todo scan deste repositório leva `--var-file` e `--skip-path .terraform`. Rode sempre as duas variantes quando houver recurso condicional. Ao ler um relatório de checkov, confira `resource_count` no summary antes de acreditar no número de passed.

`tflint --recursive` **não herda `.tflint.hcl` do diretório pai** — cada diretório precisa do seu, e `tflint --version` deve ser conferido em cada um antes de confiar no resultado, porque sem o ruleset carregado ele roda quase vazio e reporta 0 issues.

Relacionado: [[checkov-ckv-aws-24-falso-positivo]]
