variable "aws_region" {
  description = "Região da AWS para provisionamento"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Nome do Cluster EKS"
  type        = string
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
