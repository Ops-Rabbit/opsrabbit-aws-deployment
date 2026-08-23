module "alb" {
  # terraform-aws-alb v10.5.0
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-alb.git?ref=87f1c9c18408993abe951db5bf788c676abf0731"

  name               = "${var.environment_name}-${var.public_access_enabled ? "public" : "private"}"
  load_balancer_type = "application"
  internal           = !var.public_access_enabled
  ip_address_type    = "ipv4"
  vpc_id             = local.vpc_id
  subnets            = local.load_balancer_subnet_ids

  enable_deletion_protection = false
  drop_invalid_header_fields = true

  security_group_name            = "${var.environment_name}-load-balancer"
  security_group_use_name_prefix = false
  security_group_description     = "HTTPS access to the OpsRabbit load balancer"
  security_group_ingress_rules = {
    http_redirect = {
      description = "HTTP redirect to HTTPS from the approved client network"
      from_port   = 80
      to_port     = 80
      ip_protocol = "tcp"
      cidr_ipv4   = var.allowed_ingress_cidr
    }
    https = {
      description = "HTTPS from the approved client network"
      from_port   = 443
      to_port     = 443
      ip_protocol = "tcp"
      cidr_ipv4   = var.allowed_ingress_cidr
    }
  }
  security_group_egress_rules = {
    web = {
      description                  = "Forward web traffic to OpsRabbit tasks"
      from_port                    = 8080
      to_port                      = 8080
      ip_protocol                  = "tcp"
      referenced_security_group_id = aws_security_group.task.id
    }
  }

  listeners = {
    http_redirect = {
      port     = 80
      protocol = "HTTP"
      redirect = {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
    https = {
      port            = 443
      protocol        = "HTTPS"
      certificate_arn = var.certificate_arn
      ssl_policy      = "ELBSecurityPolicy-TLS13-1-2-2021-06"
      forward = {
        target_group_key = "web"
      }
    }
  }

  target_groups = {
    web = {
      name                 = "${var.environment_name}-${var.public_access_enabled ? "public" : "private"}-web"
      port                 = 8080
      protocol             = "HTTP"
      target_type          = "ip"
      create_attachment    = false
      deregistration_delay = 120
      health_check = {
        enabled             = true
        healthy_threshold   = 2
        interval            = 30
        matcher             = "200"
        path                = "/api/health"
        port                = "traffic-port"
        protocol            = "HTTP"
        timeout             = 10
        unhealthy_threshold = 5
      }
    }
  }

  route53_records = var.hosted_zone_id == null ? {} : {
    application = {
      zone_id = var.hosted_zone_id
      name    = var.application_domain_name
      type    = "A"
    }
  }

  tags = local.tags
}
