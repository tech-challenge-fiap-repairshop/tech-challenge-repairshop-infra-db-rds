# Referência ao estado remoto da Infraestrutura de Rede Base (infra-network)
data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = var.s3_tfstate_bucket
    key    = var.remote_state_network_key != "" ? var.remote_state_network_key : "network/${var.environment}.tfstate"
    region = var.aws_region
  }
}

# Grupo de Subnets para o RDS (usando as sub-redes privadas obtidas do remote state da rede)
resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "${var.cluster_name}-rds-subnet-group"
  subnet_ids = try(data.terraform_remote_state.network.outputs.private_subnet_ids, [])

  tags = {
    Name = "${var.cluster_name}-rds-subnet-group"
  }
}

# Security Group dedicado ao RDS PostgreSQL (Gerenciado diretamente pelo módulo de banco)
resource "aws_security_group" "rds" {
  name        = "${var.cluster_name}-rds-sg"
  description = "Security Group para RDS PostgreSQL (${var.environment})"
  vpc_id      = try(data.terraform_remote_state.network.outputs.vpc_id, null)

  ingress {
    description = "Conexao PostgreSQL vinda das subnets privadas da VPC"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = try(
      data.terraform_remote_state.network.outputs.private_subnet_cidr_blocks,
      [try(data.terraform_remote_state.network.outputs.vpc_cidr_block, "10.0.0.0/16")]
    )
  }

  egress {
    description = "Regra de saida padrao"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-rds-sg"
  }
}

# Instância de Banco de Dados RDS PostgreSQL
resource "aws_db_instance" "postgres" {
  identifier             = "${var.cluster_name}-postgres"
  engine                 = "postgres"
  engine_version         = "16"
  instance_class         = var.db_instance_class
  allocated_storage      = 20
  storage_type           = "gp3"
  db_name                = var.db_name
  username               = var.db_username
  password               = var.db_password
  port                   = 5432
  db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  storage_encrypted       = true
  skip_final_snapshot     = var.skip_final_snapshot
  deletion_protection     = false
  publicly_accessible     = false
  backup_retention_period = var.backup_retention_period

  tags = {
    Name = "${var.cluster_name}-postgres"
  }
}
