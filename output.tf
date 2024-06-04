output "database_username" {
  value = local.database_username
}

output "database_password" {
  value = random_password.database_password.result

  sensitive = true
}

output "connection_secret_name" {
  value = kubernetes_secret.cnpg_connection.metadata[0].name
}

output "connection_host_rw" {
  value = "${var.name}-${var.suffix}-rw"
}

output "connection_port" {
  value = "5432"
}