data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    sid     = "AllowEcsTasks"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${data.aws_partition.current.partition}:ecs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"]
    }
  }
}

resource "aws_iam_role" "task_execution" {
  name               = "${var.environment_name}-ecs-execution-${var.aws_region}"
  description        = "Pulls OpsRabbit images and injects runtime secrets into ECS tasks"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json

  tags = local.tags
}

data "aws_iam_policy_document" "task_execution" {
  statement {
    sid       = "EcrAuthorization"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "PullOpsRabbitImages"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = [
      local.backend_repository_arn,
      local.web_repository_arn,
    ]
  }

  statement {
    sid = "WriteContainerLogs"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["${aws_cloudwatch_log_group.application.arn}:*"]
  }

  statement {
    sid     = "ReadRuntimeSecrets"
    actions = ["secretsmanager:GetSecretValue"]
    resources = [
      aws_secretsmanager_secret.database.arn,
      aws_secretsmanager_secret.better_auth.arn,
      aws_secretsmanager_secret.application_encryption.arn,
    ]
  }

  statement {
    sid       = "DecryptRuntimeSecrets"
    actions   = ["kms:Decrypt"]
    resources = [module.kms.key_arn]
  }
}

resource "aws_iam_role_policy" "task_execution" {
  name   = "OpsRabbitTaskExecution"
  role   = aws_iam_role.task_execution.id
  policy = data.aws_iam_policy_document.task_execution.json
}

resource "aws_iam_role" "task" {
  name               = "${var.environment_name}-ecs-task-${var.aws_region}"
  description        = "Runtime role for OpsRabbit ECS tasks"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json

  tags = local.tags
}

data "aws_iam_policy_document" "task" {
  statement {
    sid = "MountApplicationFileSystem"
    actions = [
      "elasticfilesystem:ClientMount",
      "elasticfilesystem:ClientWrite",
    ]
    resources = [module.efs.arn]

    condition {
      test     = "StringEquals"
      variable = "elasticfilesystem:AccessPointArn"
      values = [
        module.efs.access_points["application-data"].arn,
        module.efs.access_points["git-workspace"].arn,
        module.efs.access_points["agent-browser"].arn,
        module.efs.access_points["codex"].arn,
      ]
    }
  }
}

resource "aws_iam_role_policy" "task" {
  name   = "OpsRabbitEfsAccess"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task.json
}
