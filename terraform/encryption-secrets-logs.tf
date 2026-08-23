module "kms" {
  # terraform-aws-kms v4.2.1
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-kms.git?ref=af1d45558a6073c017a732d2273efcc733b34d0f"

  description             = "Customer-managed encryption key for ${var.environment_name}"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  enable_default_policy   = true
  aliases                 = ["${var.environment_name}-data"]

  key_statements = [
    {
      sid = "AllowCloudWatchLogsEncryption"
      actions = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey",
      ]
      resources = ["*"]
      principals = [
        {
          type        = "Service"
          identifiers = ["logs.${var.aws_region}.${data.aws_partition.current.dns_suffix}"]
        }
      ]
      condition = [
        {
          test     = "ArnLike"
          variable = "kms:EncryptionContext:aws:logs:arn"
          values   = ["arn:${data.aws_partition.current.partition}:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"]
        }
      ]
    }
  ]

  tags = local.tags
}

ephemeral "random_password" "better_auth" {
  length  = 64
  special = false
}

ephemeral "random_password" "application_encryption" {
  length  = 64
  special = false
}

ephemeral "random_password" "database" {
  length  = 40
  special = false
}

resource "aws_secretsmanager_secret" "database" {
  name_prefix             = "${var.environment_name}-database-"
  description             = "${var.environment_name} RDS administrator credentials"
  kms_key_id              = module.kms.key_arn
  recovery_window_in_days = 30
}

resource "aws_secretsmanager_secret_version" "database" {
  secret_id = aws_secretsmanager_secret.database.id
  secret_string_wo = jsonencode({
    username = "opsrabbit_admin"
    password = ephemeral.random_password.database.result
  })
  secret_string_wo_version = var.database_secret_version
}

resource "aws_secretsmanager_secret" "better_auth" {
  name_prefix             = "${var.environment_name}-better-auth-"
  description             = "${var.environment_name} Better Auth signing secret"
  kms_key_id              = module.kms.key_arn
  recovery_window_in_days = 30
}

resource "aws_secretsmanager_secret_version" "better_auth" {
  secret_id                = aws_secretsmanager_secret.better_auth.id
  secret_string_wo         = ephemeral.random_password.better_auth.result
  secret_string_wo_version = var.application_secret_version
}

resource "aws_secretsmanager_secret" "application_encryption" {
  name_prefix             = "${var.environment_name}-encryption-"
  description             = "${var.environment_name} application encryption key"
  kms_key_id              = module.kms.key_arn
  recovery_window_in_days = 30
}

resource "aws_secretsmanager_secret_version" "application_encryption" {
  secret_id                = aws_secretsmanager_secret.application_encryption.id
  secret_string_wo         = ephemeral.random_password.application_encryption.result
  secret_string_wo_version = var.application_secret_version
}

resource "aws_cloudwatch_log_group" "application" {
  name              = "/opsrabbit/${var.environment_name}/application"
  retention_in_days = var.log_retention_days
  kms_key_id        = module.kms.key_arn

  tags = local.tags
}
