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
