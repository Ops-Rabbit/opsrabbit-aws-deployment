variable "aws_region" {
  description = "AWS Region in which OpsRabbit is deployed."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z]{2}(?:-gov)?-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a valid AWS Region name."
  }
}

variable "environment_name" {
  description = "Lowercase name prefix for the deployment."
  type        = string
  default     = "opsrabbit"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,19}$", var.environment_name))
    error_message = "environment_name must contain 2-20 lowercase letters, numbers, or hyphens and start with a letter."
  }
}

variable "public_access_enabled" {
  description = "Create an internet-facing load balancer when true and an internal load balancer when false."
  type        = bool
  default     = true
}

variable "application_domain_name" {
  description = "DNS name used by users and covered by the supplied ACM certificate."
  type        = string

  validation {
    condition     = length(var.application_domain_name) <= 253 && can(regex("^(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\\.)+[A-Za-z]{2,63}$", var.application_domain_name))
    error_message = "application_domain_name must be a valid DNS hostname without a scheme or path."
  }
}

variable "certificate_arn" {
  description = "ARN of an issued ACM certificate in aws_region that covers application_domain_name."
  type        = string

  validation {
    condition = (
      can(regex("^arn:(aws|aws-us-gov|aws-cn):acm:[a-z0-9-]+:[0-9]{12}:certificate/[0-9a-f-]+$", var.certificate_arn)) &&
      try(split(":", var.certificate_arn)[3] == var.aws_region, false)
    )
    error_message = "certificate_arn must be a valid ACM certificate ARN in aws_region."
  }
}

variable "hosted_zone_id" {
  description = "Optional Route 53 hosted zone ID. Leave null when DNS is managed separately."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.hosted_zone_id == null || can(regex("^Z[A-Z0-9]+$", var.hosted_zone_id))
    error_message = "hosted_zone_id must be null or a valid Route 53 hosted zone ID."
  }
}

variable "allowed_ingress_cidr" {
  description = "IPv4 CIDR allowed to reach the HTTPS and HTTP redirect listeners."
  type        = string
  default     = "0.0.0.0/0"

  validation {
    condition     = can(cidrnetmask(var.allowed_ingress_cidr)) && !strcontains(var.allowed_ingress_cidr, ":")
    error_message = "allowed_ingress_cidr must be a valid IPv4 CIDR."
  }
}

variable "create_vpc" {
  description = "Create a dedicated two-Availability-Zone VPC when true."
  type        = bool
  default     = true

  validation {
    condition = var.create_vpc || (
      var.existing_vpc_id != null &&
      length(var.existing_load_balancer_subnet_ids) == 2 &&
      length(toset(var.existing_load_balancer_subnet_ids)) == 2 &&
      length(var.existing_application_subnet_ids) == 2 &&
      length(toset(var.existing_application_subnet_ids)) == 2 &&
      length(var.existing_data_subnet_ids) == 2 &&
      length(toset(var.existing_data_subnet_ids)) == 2
    )
    error_message = "Existing-VPC mode requires one VPC ID and exactly two distinct load-balancer, application, and data subnet IDs."
  }
}

variable "vpc_cidr" {
  description = "/16 IPv4 CIDR for the dedicated VPC when create_vpc is true."
  type        = string
  default     = "10.42.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr)) && cidrnetmask(var.vpc_cidr) == "255.255.0.0"
    error_message = "vpc_cidr must be a valid IPv4 /16 CIDR."
  }
}

variable "existing_vpc_id" {
  description = "Existing VPC ID required when create_vpc is false."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.existing_vpc_id == null || can(regex("^vpc-(?:[0-9a-f]{8}|[0-9a-f]{17})$", var.existing_vpc_id))
    error_message = "existing_vpc_id must be null or a valid VPC ID."
  }
}

variable "existing_load_balancer_subnet_ids" {
  description = "Exactly two existing load-balancer subnet IDs in distinct Availability Zones."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for id in var.existing_load_balancer_subnet_ids : can(regex("^subnet-(?:[0-9a-f]{8}|[0-9a-f]{17})$", id))
    ])
    error_message = "existing_load_balancer_subnet_ids must contain valid subnet IDs."
  }
}

variable "existing_application_subnet_ids" {
  description = "Exactly two existing private ECS subnet IDs with outbound connectivity."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for id in var.existing_application_subnet_ids : can(regex("^subnet-(?:[0-9a-f]{8}|[0-9a-f]{17})$", id))
    ])
    error_message = "existing_application_subnet_ids must contain valid subnet IDs."
  }
}

variable "existing_data_subnet_ids" {
  description = "Exactly two existing private RDS and EFS subnet IDs in the application Availability Zones."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for id in var.existing_data_subnet_ids : can(regex("^subnet-(?:[0-9a-f]{8}|[0-9a-f]{17})$", id))
    ])
    error_message = "existing_data_subnet_ids must contain valid subnet IDs."
  }
}

variable "image_repository_account_id" {
  description = "AWS account that owns both OpsRabbit ECR repositories."
  type        = string
  default     = "921870554228"

  validation {
    condition     = can(regex("^[0-9]{12}$", var.image_repository_account_id))
    error_message = "image_repository_account_id must be a 12-digit AWS account ID."
  }
}

variable "image_repository_region" {
  description = "AWS Region containing both OpsRabbit ECR repositories."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z]{2}(?:-gov)?-[a-z]+-[0-9]$", var.image_repository_region))
    error_message = "image_repository_region must be a valid AWS Region name."
  }
}

variable "backend_image_uri" {
  description = "Immutable ECR URI and SHA-256 digest for the standard non-root backend image."
  type        = string
  default     = "921870554228.dkr.ecr.us-east-1.amazonaws.com/opsrabbit/backend@sha256:00e6611e5f6e34bc8d8a7c21fde567db2e7f545cc5a7cc2845468ac5c3213925"

  validation {
    condition = can(regex(
      "^${var.image_repository_account_id}\\.dkr\\.ecr\\.${var.image_repository_region}\\.amazonaws\\.com(?:\\.cn)?/opsrabbit/backend@sha256:[0-9a-f]{64}$",
      var.backend_image_uri,
    ))
    error_message = "backend_image_uri must be the opsrabbit/backend ECR URI in image_repository_account_id and image_repository_region, pinned to a SHA-256 digest."
  }
}

variable "web_image_uri" {
  description = "Immutable ECR URI and SHA-256 digest for the web image."
  type        = string
  default     = "921870554228.dkr.ecr.us-east-1.amazonaws.com/opsrabbit/web@sha256:a7ae3c12b8e5a2a64cb3c14e395559c0a9b4aa0a25a1fcf4085d69c923c8f48a"

  validation {
    condition = can(regex(
      "^${var.image_repository_account_id}\\.dkr\\.ecr\\.${var.image_repository_region}\\.amazonaws\\.com(?:\\.cn)?/opsrabbit/web@sha256:[0-9a-f]{64}$",
      var.web_image_uri,
    ))
    error_message = "web_image_uri must be the opsrabbit/web ECR URI in image_repository_account_id and image_repository_region, pinned to a SHA-256 digest."
  }
}

variable "task_cpu" {
  description = "Fargate task CPU units shared by the backend and web containers."
  type        = number
  default     = 2048

  validation {
    condition = (
      contains([2048, 4096], var.task_cpu) &&
      (var.task_cpu == 2048 || var.task_memory == 8192)
    )
    error_message = "task_cpu must be 2048 or 4096; task_cpu 4096 requires task_memory 8192."
  }
}

variable "task_memory" {
  description = "Fargate task memory in MiB."
  type        = number
  default     = 5120

  validation {
    condition     = contains([5120, 6144, 7168, 8192], var.task_memory)
    error_message = "task_memory must be 5120, 6144, 7168, or 8192 MiB."
  }
}

variable "ephemeral_storage_gib" {
  description = "Fargate ephemeral storage in GiB for images and temporary runtime files."
  type        = number
  default     = 40

  validation {
    condition     = var.ephemeral_storage_gib >= 21 && var.ephemeral_storage_gib <= 200
    error_message = "ephemeral_storage_gib must be between 21 and 200."
  }
}

variable "desired_count" {
  description = "Number of OpsRabbit tasks. The initial deployment supports one task."
  type        = number
  default     = 1

  validation {
    condition     = var.desired_count == 1
    error_message = "desired_count must be 1 for this release."
  }
}

variable "database_engine_version" {
  description = "Amazon RDS for PostgreSQL 16 engine version."
  type        = string
  default     = "16"

  validation {
    condition     = can(regex("^16(?:\\.[0-9]+)?$", var.database_engine_version))
    error_message = "database_engine_version must be PostgreSQL 16."
  }
}

variable "database_instance_class" {
  description = "RDS database instance class."
  type        = string
  default     = "db.t4g.medium"

  validation {
    condition     = can(regex("^db\\.[a-z0-9.]+$", var.database_instance_class))
    error_message = "database_instance_class must be a valid RDS instance class."
  }
}

variable "database_allocated_storage" {
  description = "Initial gp3 database storage in GiB."
  type        = number
  default     = 50

  validation {
    condition     = var.database_allocated_storage >= 20 && var.database_allocated_storage <= 180
    error_message = "database_allocated_storage must be between 20 and 180 GiB."
  }
}

variable "database_backup_retention_days" {
  description = "Number of days to retain automated database backups."
  type        = number
  default     = 7

  validation {
    condition     = var.database_backup_retention_days >= 1 && var.database_backup_retention_days <= 35
    error_message = "database_backup_retention_days must be between 1 and 35."
  }
}

variable "database_multi_az" {
  description = "Create a synchronous standby database in another Availability Zone."
  type        = bool
  default     = false
}

variable "database_deletion_protection" {
  description = "Enable RDS deletion protection after the initial deployment is healthy."
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "CloudWatch application log retention period."
  type        = number
  default     = 30

  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731,
      1096, 1827, 2192, 2557, 2922, 3288, 3653
    ], var.log_retention_days)
    error_message = "log_retention_days must be a CloudWatch Logs supported retention value."
  }
}

variable "application_secret_version" {
  description = "Increment to rotate the generated Better Auth and application encryption secrets."
  type        = number
  default     = 1

  validation {
    condition     = var.application_secret_version >= 1 && floor(var.application_secret_version) == var.application_secret_version
    error_message = "application_secret_version must be a positive whole number."
  }
}

variable "database_secret_version" {
  description = "Increment to rotate the generated PostgreSQL administrator password and replace the ECS task."
  type        = number
  default     = 1

  validation {
    condition     = var.database_secret_version >= 1 && floor(var.database_secret_version) == var.database_secret_version
    error_message = "database_secret_version must be a positive whole number."
  }
}

variable "additional_tags" {
  description = "Additional tags to add to resources."
  type        = map(string)
  default     = {}
}
