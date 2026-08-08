data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = "fiap-repairshop2"
    key    = "network/hml.tfstate"
    region = "us-east-1"
  }
}

# Grupo de Subnets para o RDS (usando as sub-redes privadas obtidas do remote state da rede)
resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "${var.cluster_name}-rds-subnet-group"
  subnet_ids = data.terraform_remote_state.network.outputs.private_subnet_ids

  tags = {
    Name = "${var.cluster_name}-rds-subnet-group"
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
  vpc_security_group_ids = [data.terraform_remote_state.network.outputs.sg_rds_id]

  storage_encrypted   = true
  skip_final_snapshot     = var.skip_final_snapshot
  publicly_accessible     = false
  backup_retention_period = var.backup_retention_period

  tags = {
    Name = "${var.cluster_name}-postgres"
  }
}
