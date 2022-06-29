
output "endpoint" {
  value = aws_rds_cluster.rds.endpoint
}

output "port" {
  value = aws_rds_cluster.rds.port
}

output "version" {
  value = aws_rds_cluster.rds.engine_version_actual
}

output "name" {
  value = aws_rds_cluster.rds.database_name
}

output "username" {
  value     = aws_rds_cluster.rds.master_username
  sensitive = true
}

output "password" {
  value     = aws_rds_cluster.rds.master_password
  sensitive = true
}

output "xz" {
  value = aws_security_group.rds.id
}
