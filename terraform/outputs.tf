output "opsrabbit_url" {
  description = "Customer-facing OpsRabbit HTTPS URL."
  value       = "https://${var.application_domain_name}"
}

output "access_mode" {
  description = "Application load balancer access mode."
  value       = var.public_access_enabled ? "public" : "private"
}

output "load_balancer_dns_name" {
  description = "AWS load balancer hostname."
  value       = module.alb.dns_name
}

output "vpc_id" {
  description = "Created or supplied VPC ID."
  value       = local.vpc_id
}

output "ecs_cluster_name" {
  description = "OpsRabbit ECS cluster name."
  value       = module.ecs_cluster.name
}

output "ecs_service_name" {
  description = "OpsRabbit ECS service name."
  value       = module.ecs_service.name
}

output "task_execution_role_arn" {
  description = "ECS task execution role ARN."
  value       = aws_iam_role.task_execution.arn
}

output "database_endpoint" {
  description = "Private PostgreSQL endpoint."
  value       = module.rds.db_instance_endpoint
}

output "file_system_id" {
  description = "Encrypted EFS file system ID."
  value       = module.efs.id
}

output "application_log_group_name" {
  description = "CloudWatch application log group name."
  value       = aws_cloudwatch_log_group.application.name
}

output "data_encryption_key_arn" {
  description = "Customer-managed KMS key ARN."
  value       = module.kms.key_arn
}

output "database_secret_arn" {
  description = "Database credential secret ARN. The secret value is never output."
  value       = aws_secretsmanager_secret.database.arn
}

output "better_auth_secret_arn" {
  description = "Better Auth secret ARN. The secret value is never output."
  value       = aws_secretsmanager_secret.better_auth.arn
}

output "application_encryption_secret_arn" {
  description = "Application encryption secret ARN. The secret value is never output."
  value       = aws_secretsmanager_secret.application_encryption.arn
}
