# VPC Flow Logs — log group, IAM role, IAM role policy e o proprio flow log
# (ADR-0001 §10). CONDICIONAIS: os QUATRO recursos usam o mesmo
# `var.enable_flow_logs`, cujo default e false.
#
# ATENCAO — CUSTO. US$ 0,50 por GB entregue no CloudWatch Logs. Um unico GB
# consome 10% do teto de US$ 5,00 do curso INTEIRO (ADR-0001 R9). O que se paga
# aqui e a INGESTAO, nao a retencao: 100 MB guardados por 7 dias custam US$
# 0,0007. Por isso a retencao de 7 dias e barata e ligar o recurso nao e.
#
# Os quatro sob a MESMA condicao, e nao so o `aws_flow_log`: um log group criado
# com a flag desligada nao custaria nada por existir vazio, mas o criterio de
# aceite do ADR-0001 §14 e literal — `plan` sem variaveis nao cria "nem log group,
# nem role". Estado desligado significa que estes recursos nao existem, ponto.
#
# Consequencia aceita e nao obvia: com a flag em false nao ha historico para
# investigar um problema DEPOIS que ele aconteceu. O fluxo previsto e reproduzir o
# problema com os logs ligados, nao consultar o passado.
#
# Estes sao os 4 recursos que o criterio de aceite espera ver em
# `plan -var="enable_flow_logs=true"` — exatamente 4, nem mais nem menos.

# Usados so para montar ARNs de escopo da policy. `data.aws_region` esta declarado
# em vpc.endpoints.tf, onde e indispensavel para o service_name do endpoint; aqui
# ele e reaproveitado em vez de redeclarado.
#
# `partition` em vez de "aws" literal e `account_id` em vez do numero da conta:
# nenhum ARN entra hardcoded em modules/network, por criterio de aceite do §14.
data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

# Retencao vem de variavel (ADR-0001 §10 usa 7 dias). Sem KMS CMK: e um trade-off
# aceito e escrito em ADR-0001 §5 — custo de chave mais key policy para proteger
# metadados de trafego sintetico de laboratorio. A criptografia gerenciada pela
# AWS continua ativa no log group; o que se abre mao e da chave propria.
#
# O nome foge do padrao <projeto>-<ambiente>-<tipo> de proposito, por decisao do
# ADR-0001 §8: log group segue a convencao de caminho do CloudWatch.
#
# CKV_AWS_338 ("retains logs for at least 1 year") era o achado escalado na etapa 4:
# a retencao de 7 dias e decisao explicita do ADR-0001 §10, mas a tabela de §5
# nao a listava, e so o §5 autorizava supressao. O ADR-0002 §5.3 fechou a lacuna
# com uma lista nominal, e a supressao esta autorizada abaixo.
resource "aws_cloudwatch_log_group" "this" {
  #checkov:skip=CKV_AWS_158: CMK do KMS no log group e trade-off aceito e escrito em ADR-0001 §5 — custo de chave mais key policy para proteger metadados de trafego sintetico de laboratorio. A criptografia gerenciada pela AWS permanece ativa.
  #checkov:skip=CKV_AWS_338: o log group e destruido ao fechar a janela de custo (ADR-0001 §13) e seu tempo de vida e de HORAS — 7 dias de retencao ja excedem a existencia do recurso, e reter 1 ano descreveria um ciclo de dados que nao ocorre. O custo dos flow logs e de ingestao, nao de retencao (§11.2). Supressao autorizada nominalmente por ADR-0002 §5.3.
  count = var.enable_flow_logs ? 1 : 0

  name              = "/aws/vpc/${var.project_name}-${var.environment}/flow-logs"
  retention_in_days = var.flow_logs_retention_in_days

  tags = {
    Name = "/aws/vpc/${var.project_name}-${var.environment}/flow-logs"
  }
}

# Trust policy (ADR-0001 §9). As duas condicoes nao sao decorativas: sem elas,
# qualquer conta que consiga fazer o servico de flow logs assumir esta role
# poderia usa-la — e o problema do confused deputy. `aws:SourceAccount` prende a
# role a esta conta e `aws:SourceArn` a prende a flow logs desta conta e regiao.
data "aws_iam_policy_document" "assume_role" {
  count = var.enable_flow_logs ? 1 : 0

  statement {
    sid     = "AllowVpcFlowLogsToAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:vpc-flow-log/*"]
    }
  }
}

# Permission policy (ADR-0001 §9). Least privilege de verdade: nenhum
# `Resource: "*"` e nenhum `Action: "*"`.
#
# As tres acoes de escrita ficam presas ao ARN DESTE log group com o sufixo `:*`,
# que cobre os log streams dentro dele. O sufixo precisa ser concatenado a mao
# porque o atributo `arn` do aws_cloudwatch_log_group ja vem com ele removido pelo
# provider — sem o `:*` a role enxerga o grupo e nao consegue escrever stream
# nenhum. Verificado na documentacao do recurso via MCP terraform.
#
# `logs:CreateLogGroup` esta deliberadamente FORA: o log group e criado pelo
# Terraform, logo acima. Conceder ao servico o poder de criar log group seria dar
# permissao para algo que ele nunca precisa fazer.
#
# `logs:DescribeLogGroups` e o unico ponto que nao aceita escopo mais fino que
# `log-group:*` — e limitacao da API do CloudWatch Logs, nao relaxamento
# deliberado. Ainda assim segue preso a esta conta e a esta regiao, e a acao e de
# leitura de metadados.
data "aws_iam_policy_document" "this" {
  count = var.enable_flow_logs ? 1 : 0

  statement {
    sid    = "AllowWriteToFlowLogGroup"
    effect = "Allow"

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]

    resources = ["${aws_cloudwatch_log_group.this[0].arn}:*"]
  }

  statement {
    sid       = "AllowDescribeLogGroups"
    effect    = "Allow"
    actions   = ["logs:DescribeLogGroups"]
    resources = ["arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:*"]
  }
}

# Unica IAM role criada por este modulo, e so quando a flag esta ligada.
resource "aws_iam_role" "this" {
  count = var.enable_flow_logs ? 1 : 0

  name               = "${var.project_name}-${var.environment}-role-flowlogs"
  description        = "Permite ao servico de VPC Flow Logs escrever no log group da VPC ${var.project_name}-${var.environment}. Criada por ADR-0001."
  assume_role_policy = data.aws_iam_policy_document.assume_role[0].json

  tags = {
    Name = "${var.project_name}-${var.environment}-role-flowlogs"
  }
}

# Policy inline, e nao gerenciada: ela existe exclusivamente para esta role e nao
# faz sentido sozinha. Inline garante que morre junto com a role, sem deixar
# policy orfa na conta quando a janela de custo fecha.
#
# `role` recebe o `name` da role, que e o que o argumento espera.
resource "aws_iam_role_policy" "this" {
  count = var.enable_flow_logs ? 1 : 0

  name   = "${var.project_name}-${var.environment}-policy-flowlogs"
  role   = aws_iam_role.this[0].name
  policy = data.aws_iam_policy_document.this[0].json
}

# O flow log em si, no nivel da VPC (ADR-0001 §10).
#
# Nivel VPC, e nao subnet ou ENI: cobre todas as subnets e todas as ENIs, as que
# existem hoje e as que o ADR de compute criar depois, sem precisar voltar aqui.
#
# `traffic_type = "ALL"` captura ACCEPT e REJECT — troubleshooting de
# conectividade quase sempre precisa do REJECT, que e onde aparece o pacote que o
# security group derrubou.
#
# `log_destination_type = "cloud-watch-logs"` e o default do provider, mas vai
# explicito porque a escolha e economica e nao obvia: S3 custaria metade na
# entrega (US$ 0,25/GB contra US$ 0,50/GB) e foi recusado no ADR-0001 §11.2 porque
# obrigaria a usar Athena para consultar. Com logs ligados por horas a diferenca e
# de centavos, e o Logs Insights resolve direto.
#
# `max_aggregation_interval = 600` (10 min) e o default e o valor do ADR. O outro
# valor valido, 60, geraria mais registros e mais GB ingeridos — e GB ingerido e
# exatamente onde mora o custo aqui.
resource "aws_flow_log" "this" {
  count = var.enable_flow_logs ? 1 : 0

  vpc_id                   = aws_vpc.this.id
  traffic_type             = "ALL"
  log_destination_type     = "cloud-watch-logs"
  log_destination          = aws_cloudwatch_log_group.this[0].arn
  iam_role_arn             = aws_iam_role.this[0].arn
  max_aggregation_interval = 600

  tags = {
    Name = "${var.project_name}-${var.environment}-flowlogs"
  }
}
