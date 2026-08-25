variable "aws_region" {
  description = "Região da AWS para provisionamento"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Ambiente de deploy (dev, hml, prd)"
  type        = string
  default     = "prd"
}

variable "cluster_name" {
  description = "Nome do Cluster EKS"
  type        = string
  default     = "repairshop-eks"
}

variable "db_name" {
  description = "Nome do banco de dados no RDS"
  type        = string
  default     = "repairshop"
}

variable "db_username" {
  description = "Usuário master do banco de dados RDS"
  type        = string
  default     = "repairshop"
}

variable "db_password" {
  description = "Senha master do banco de dados RDS (passada de forma segura)"
  type        = string
  sensitive   = true
  default     = "repairshop"
}

variable "db_instance_class" {
  description = "Tipo de instância do RDS"
  type        = string
  default     = "db.t3.micro"
}

variable "skip_final_snapshot" {
  description = "Indica se pula o snapshot final ao destruir a instância"
  type        = bool
  default     = true
}

variable "backup_retention_period" {
  description = "Período de retenção de backup em dias"
  type        = number
  default     = 7
}

variable "s3_tfstate_bucket" {
  description = "Nome do bucket S3 onde está armazenado o tfstate de rede"
  type        = string
  default     = "fiap-repairshop2"
}

variable "remote_state_network_key" {
  description = "Chave do S3 onde está o tfstate da infraestrutura de rede"
  type        = string
  default     = ""
}

# Busca dinâmica do ID da conta AWS
data "aws_caller_identity" "current" {}

locals {
  # Constrói o ARN da role dinamicamente utilizando a conta atual logada
  lab_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/LabRole"
}
