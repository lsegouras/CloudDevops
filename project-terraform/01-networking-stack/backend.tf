terraform {
  # ADR-0001 §8 "State". O bucket e criado out-of-band (etapa 2 do §7) e nao e
  # gerenciado por este root. Blocos de backend nao aceitam variaveis: os valores
  # abaixo sao literais por imposicao do Terraform, nao por descuido.
  #
  # Locking nativo do S3 via `use_lockfile`. SEM `dynamodb_table` — deprecado.
  backend "s3" {
    bucket       = "dvn-workshop-tfstate-090413359726"
    key          = "prd/network/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
