output "rds_endpoint" {
  description = "Endpoint do banco de dados RDS"
  value       = aws_db_instance.postgres.endpoint
}

output "rds_address" {
  description = "Endereco (host) do banco de dados RDS"
  value       = aws_db_instance.postgres.address
}

output "rds_port" {
  description = "Porta de conexao do banco de dados RDS"
  value       = aws_db_instance.postgres.port
}

output "rds_db_name" {
  description = "Nome do banco de dados"
  value       = aws_db_instance.postgres.db_name
}

output "rds_security_group_id" {
  description = "ID do Security Group do RDS PostgreSQL"
  value       = aws_security_group.rds.id
}
