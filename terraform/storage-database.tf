module "efs" {
  # terraform-aws-efs v2.2.0
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-efs.git?ref=d9be6bf012c847df6d0f33b578a816a1d10c0df2"

  name             = "${var.environment_name}-data"
  creation_token   = "${var.environment_name}-data"
  encrypted        = true
  kms_key_arn      = module.kms.key_arn
  performance_mode = "generalPurpose"
  throughput_mode  = "elastic"

  attach_policy                             = true
  deny_nonsecure_transport                  = true
  deny_nonsecure_transport_via_mount_target = false

  mount_targets = {
    for index, subnet_id in local.data_subnet_ids : tostring(index) => {
      subnet_id = subnet_id
    }
  }

  security_group_name        = "${var.environment_name}-efs"
  security_group_description = "NFS access only from OpsRabbit tasks"
  security_group_vpc_id      = local.vpc_id
  security_group_ingress_rules = {
    tasks = {
      description                  = "Encrypted NFS from ECS tasks"
      referenced_security_group_id = aws_security_group.task.id
    }
  }

  access_points = {
    application-data = {
      name = "${var.environment_name}-application-data"
      posix_user = {
        uid = 1000
        gid = 1000
      }
      root_directory = {
        path = "/opsrabbit-data"
        creation_info = {
          owner_uid   = 1000
          owner_gid   = 1000
          permissions = "0700"
        }
      }
    }
    git-workspace = {
      name = "${var.environment_name}-git-workspace"
      posix_user = {
        uid = 1000
        gid = 1000
      }
      root_directory = {
        path = "/git-workspace"
        creation_info = {
          owner_uid   = 1000
          owner_gid   = 1000
          permissions = "0700"
        }
      }
    }
    agent-browser = {
      name = "${var.environment_name}-agent-browser"
      posix_user = {
        uid = 1000
        gid = 1000
      }
      root_directory = {
        path = "/agent-browser"
        creation_info = {
          owner_uid   = 1000
          owner_gid   = 1000
          permissions = "0700"
        }
      }
    }
    codex = {
      name = "${var.environment_name}-codex"
      posix_user = {
        uid = 1000
        gid = 1000
      }
      root_directory = {
        path = "/codex"
        creation_info = {
          owner_uid   = 1000
          owner_gid   = 1000
          permissions = "0700"
        }
      }
    }
  }

  create_backup_policy = true
  enable_backup_policy = true

  tags = local.tags
}

module "rds" {
  # terraform-aws-rds v7.2.1
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-rds.git?ref=9920097a40175c084c46fee1c306fa61cdbaf823"

  identifier = "${var.environment_name}-postgresql"

  engine                   = "postgres"
  engine_version           = var.database_engine_version
  engine_lifecycle_support = "open-source-rds-extended-support-disabled"
  family                   = "postgres16"
  create_db_option_group   = false
  instance_class           = var.database_instance_class

  allocated_storage     = var.database_allocated_storage
  max_allocated_storage = 200
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = module.kms.key_arn

  db_name  = "opsrabbit_neo"
  username = "opsrabbit_admin"
  port     = 5432

  manage_master_user_password = false
  password_wo                 = ephemeral.random_password.database.result
  password_wo_version         = var.database_secret_version

  create_db_subnet_group = true
  subnet_ids             = local.data_subnet_ids
  vpc_security_group_ids = [aws_security_group.database.id]
  publicly_accessible    = false
  multi_az               = var.database_multi_az

  iam_database_authentication_enabled = true
  auto_minor_version_upgrade          = true
  allow_major_version_upgrade         = false

  backup_retention_period          = var.database_backup_retention_days
  copy_tags_to_snapshot            = true
  skip_final_snapshot              = false
  final_snapshot_identifier_prefix = "${var.environment_name}-final"
  delete_automated_backups         = true
  deletion_protection              = var.database_deletion_protection

  create_monitoring_role          = true
  monitoring_interval             = 60
  monitoring_role_name            = "${var.environment_name}-rds-monitoring"
  monitoring_role_use_name_prefix = false

  tags = local.tags
}
