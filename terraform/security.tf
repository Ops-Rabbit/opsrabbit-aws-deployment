resource "aws_security_group" "task" {
  name        = "${var.environment_name}-tasks"
  description = "OpsRabbit ECS task network access"
  vpc_id      = local.vpc_id

  revoke_rules_on_delete = true

  lifecycle {
    precondition {
      condition     = length(data.aws_availability_zones.available.names) >= 2
      error_message = "The selected AWS Region must have at least two standard Availability Zones."
    }

    precondition {
      condition = var.create_vpc ? true : (
        data.aws_vpc.existing[0].enable_dns_support &&
        data.aws_vpc.existing[0].enable_dns_hostnames
      )
      error_message = "The existing VPC must have DNS support and DNS hostnames enabled."
    }

    precondition {
      condition = var.create_vpc ? true : alltrue([
        for subnet in data.aws_subnet.existing : subnet.vpc_id == var.existing_vpc_id
      ])
      error_message = "Every supplied subnet must belong to existing_vpc_id."
    }

    precondition {
      condition = var.create_vpc ? true : (
        length(local.existing_load_balancer_azs) == 2 &&
        local.existing_load_balancer_azs == local.existing_application_azs &&
        local.existing_application_azs == local.existing_data_azs
      )
      error_message = "Each existing subnet list must cover the same two distinct Availability Zones."
    }
  }

  tags = merge(local.tags, {
    Name = "${var.environment_name}-tasks"
  })
}

resource "aws_vpc_security_group_ingress_rule" "task_from_load_balancer" {
  security_group_id            = aws_security_group.task.id
  referenced_security_group_id = module.alb.security_group_id
  description                  = "Web traffic only from the load balancer"
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
}

resource "aws_vpc_security_group_egress_rule" "task_all_ipv4" {
  security_group_id = aws_security_group.task.id
  description       = "Outbound access for AWS APIs, ECR, updates, and configured integrations"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_security_group" "database" {
  name        = "${var.environment_name}-database"
  description = "PostgreSQL access only from OpsRabbit tasks"
  vpc_id      = local.vpc_id

  revoke_rules_on_delete = true

  tags = merge(local.tags, {
    Name = "${var.environment_name}-database"
  })
}

resource "aws_vpc_security_group_ingress_rule" "database_from_tasks" {
  security_group_id            = aws_security_group.database.id
  referenced_security_group_id = aws_security_group.task.id
  description                  = "PostgreSQL from ECS tasks"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}
