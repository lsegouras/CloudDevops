terraform {
  # ADR-0001 §8 "State". O bucket e criado out-of-band (etapa 2 do §7) e nao e
  # gerenciado por este root. Blocos de backend nao aceitam variaveis: os valores
  # abaixo sao literais por imposicao do Terraform, nao por descuido.
  #
  # Locking nativo do S3 via `use_lockfile`. SEM `dynamodb_table` — deprecado.
  #
  # `profile` e obrigatorio aqui: o bloco de backend NAO herda credencial do
  # bloco `provider "aws"`. Sem ele o backend cai na cadeia default do SDK e,
  # como nao existe profile `default` em ~/.aws/config, vai ate o IMDS e falha
  # com "No valid credential sources found". Medido na etapa 5a: acrescentar
  # este argumento mudou o erro de "no EC2 IMDS role found" para a expiracao
  # real da sessao, provando que o profile passou a ser usado.
  backend "s3" {
    bucket       = "dvn-workshop-tfstate-090413359726"
    key          = "prd/network/terraform.tfstate"
    region       = "us-east-1"
    profile      = "app_cloud_devops"
    encrypt      = true
    use_lockfile = true
  }
}
