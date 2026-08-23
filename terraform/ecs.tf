module "ecs_cluster" {
  # terraform-aws-ecs v7.6.0
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-ecs.git//modules/cluster?ref=c83279b39a69c19cb206038a7c0e24768caa5e35"

  name                        = "${var.environment_name}-cluster"
  configuration               = null
  create_cloudwatch_log_group = false
  setting = [
    {
      name  = "containerInsights"
      value = "enabled"
    }
  ]

  tags = local.tags
}

module "ecs_service" {
  # terraform-aws-ecs v7.6.0
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-ecs.git//modules/service?ref=c83279b39a69c19cb206038a7c0e24768caa5e35"

  name        = "${var.environment_name}-service"
  family      = "${var.environment_name}-application"
  cluster_arn = module.ecs_cluster.arn

  launch_type      = "FARGATE"
  platform_version = "LATEST"
  cpu              = var.task_cpu
  memory           = var.task_memory
  ephemeral_storage = {
    size_in_gib = var.ephemeral_storage_gib
  }
  runtime_platform = {
    cpu_architecture        = "X86_64"
    operating_system_family = "LINUX"
  }

  desired_count                      = var.desired_count
  assign_public_ip                   = false
  subnet_ids                         = local.application_subnet_ids
  security_group_ids                 = [aws_security_group.task.id]
  create_security_group              = false
  health_check_grace_period_seconds  = 900
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 200
  deployment_circuit_breaker = {
    enable   = true
    rollback = true
  }
  enable_ecs_managed_tags = true
  enable_execute_command  = false
  enable_autoscaling      = false
  force_new_deployment    = false
  propagate_tags          = "SERVICE"
  track_latest            = false
  wait_for_steady_state   = true
  triggers = {
    application_secret_version = tostring(var.application_secret_version)
    database_secret_version    = tostring(var.database_secret_version)
  }

  create_iam_role = false

  create_task_exec_iam_role = false
  task_exec_iam_role_arn    = aws_iam_role.task_execution.arn
  create_tasks_iam_role     = false
  tasks_iam_role_arn        = aws_iam_role.task.arn

  load_balancer = {
    web = {
      target_group_arn = module.alb.target_groups["web"].arn
      container_name   = "web"
      container_port   = 8080
    }
  }

  container_definitions = {
    backend = {
      name                   = "backend"
      image                  = var.backend_image_uri
      essential              = true
      cpu                    = 1536
      memoryReservation      = 4096
      stopTimeout            = 120
      readonlyRootFilesystem = false

      environment = [
        { name = "NODE_ENV", value = "production" },
        { name = "OPSRABBIT_NODE_HOST", value = "0.0.0.0" },
        { name = "OPSRABBIT_NODE_PORT", value = "8384" },
        { name = "OPSRABBIT_NODE_DATA_DIR", value = "/home/opsbot/.opsrabbit" },
        { name = "OPSRABBIT_NODE_WORKSPACE_DIR", value = "/home/opsbot/git" },
        { name = "OPSRABBIT_WEB_ORIGIN", value = "https://${var.application_domain_name}" },
        { name = "OPSRABBIT_NODE_BASE_URL", value = "https://${var.application_domain_name}/api" },
        { name = "POSTGRES_HOST", value = module.rds.db_instance_address },
        { name = "POSTGRES_USER", value = "opsrabbit_admin" },
        { name = "POSTGRES_DATABASE", value = "opsrabbit_neo" },
      ]

      secrets = [
        { name = "POSTGRES_PASSWORD", valueFrom = "${aws_secretsmanager_secret.database.arn}:password::" },
        { name = "BETTER_AUTH_SECRET", valueFrom = aws_secretsmanager_secret.better_auth.arn },
        { name = "OPSRABBIT_NODE_ENCRYPTION_KEY", valueFrom = aws_secretsmanager_secret.application_encryption.arn },
      ]

      entrypoint = ["/bin/bash", "-lc"]
      command = [
        "export OPSRABBIT_NODE_DATABASE_URL=\"postgresql://$${POSTGRES_USER}:$${POSTGRES_PASSWORD}@$${POSTGRES_HOST}:5432/$${POSTGRES_DATABASE}?sslmode=require\"; exec node /opt/opsrabbit/apps/backend/dist/index.js"
      ]

      healthCheck = {
        command = [
          "CMD-SHELL",
          "node -e \"fetch('http://127.0.0.1:8384/health').then((response) => { if (!response.ok) process.exit(1); }).catch(() => process.exit(1))\"",
        ]
        interval    = 30
        timeout     = 10
        retries     = 5
        startPeriod = 300
      }

      enable_cloudwatch_logging = false
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.application.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "backend"
        }
      }

      mountPoints = [
        { sourceVolume = "application-data", containerPath = "/home/opsbot/.opsrabbit", readOnly = false },
        { sourceVolume = "git-workspace", containerPath = "/home/opsbot/git", readOnly = false },
        { sourceVolume = "agent-browser", containerPath = "/home/opsbot/.agent-browser", readOnly = false },
        { sourceVolume = "codex", containerPath = "/home/opsbot/.codex", readOnly = false },
      ]

      linuxParameters = {
        initProcessEnabled = true
      }
    }

    web = {
      name                   = "web"
      image                  = var.web_image_uri
      essential              = true
      cpu                    = 512
      memoryReservation      = 1024
      readonlyRootFilesystem = false

      dependsOn = [
        { containerName = "backend", condition = "HEALTHY" }
      ]

      portMappings = [
        {
          name          = "web-http"
          containerPort = 8080
          hostPort      = 8080
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "VITE_API_URL", value = "/api" },
        { name = "WEB_API_UPSTREAM", value = "http://127.0.0.1:8384" },
        { name = "WEB_TLS_MODE", value = "http" },
        { name = "WEB_SERVER_NAME", value = var.application_domain_name },
      ]

      entrypoint = ["/bin/sh", "-c"]
      command = [
        "sed -i 's/listen 80;/listen 8080;/g; s/listen \\[::\\]:80;/listen [::]:8080;/g' /etc/nginx/templates/http.conf.template; exec /docker-entrypoint.sh nginx -g 'daemon off;'"
      ]

      healthCheck = {
        command     = ["CMD-SHELL", "wget --quiet --output-document=/dev/null http://127.0.0.1:8080/ || exit 1"]
        interval    = 30
        timeout     = 10
        retries     = 5
        startPeriod = 60
      }

      enable_cloudwatch_logging = false
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.application.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "web"
        }
      }
    }
  }

  volume = {
    application-data = {
      efs_volume_configuration = {
        file_system_id     = module.efs.id
        transit_encryption = "ENABLED"
        authorization_config = {
          access_point_id = module.efs.access_points["application-data"].id
          iam             = "ENABLED"
        }
      }
    }
    git-workspace = {
      efs_volume_configuration = {
        file_system_id     = module.efs.id
        transit_encryption = "ENABLED"
        authorization_config = {
          access_point_id = module.efs.access_points["git-workspace"].id
          iam             = "ENABLED"
        }
      }
    }
    agent-browser = {
      efs_volume_configuration = {
        file_system_id     = module.efs.id
        transit_encryption = "ENABLED"
        authorization_config = {
          access_point_id = module.efs.access_points["agent-browser"].id
          iam             = "ENABLED"
        }
      }
    }
    codex = {
      efs_volume_configuration = {
        file_system_id     = module.efs.id
        transit_encryption = "ENABLED"
        authorization_config = {
          access_point_id = module.efs.access_points["codex"].id
          iam             = "ENABLED"
        }
      }
    }
  }

  tags = local.tags

  depends_on = [
    module.alb,
    module.efs,
    aws_secretsmanager_secret_version.application_encryption,
    aws_secretsmanager_secret_version.better_auth,
    aws_secretsmanager_secret_version.database,
  ]
}
