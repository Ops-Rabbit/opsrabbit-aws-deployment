data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "zone-type"
    values = ["availability-zone"]
  }
}

data "aws_vpc" "existing" {
  count = var.create_vpc ? 0 : 1
  id    = var.existing_vpc_id
}

data "aws_subnet" "existing" {
  for_each = var.create_vpc ? toset([]) : toset(concat(
    var.existing_load_balancer_subnet_ids,
    var.existing_application_subnet_ids,
    var.existing_data_subnet_ids,
  ))

  id = each.value
}

locals {
  selected_azs = slice(data.aws_availability_zones.available.names, 0, 2)

  tags = merge({
    application = "opsrabbit"
    environment = var.environment_name
    managed-by  = "terraform"
  }, var.additional_tags)

  vpc_id = var.create_vpc ? module.vpc.vpc_id : var.existing_vpc_id

  load_balancer_subnet_ids = var.create_vpc ? (
    var.public_access_enabled ? module.vpc.public_subnets : module.vpc.private_subnets
  ) : var.existing_load_balancer_subnet_ids
  application_subnet_ids = var.create_vpc ? module.vpc.private_subnets : var.existing_application_subnet_ids
  data_subnet_ids        = var.create_vpc ? module.vpc.database_subnets : var.existing_data_subnet_ids

  existing_load_balancer_azs = var.create_vpc ? toset([]) : toset([
    for id in var.existing_load_balancer_subnet_ids : data.aws_subnet.existing[id].availability_zone
  ])
  existing_application_azs = var.create_vpc ? toset([]) : toset([
    for id in var.existing_application_subnet_ids : data.aws_subnet.existing[id].availability_zone
  ])
  existing_data_azs = var.create_vpc ? toset([]) : toset([
    for id in var.existing_data_subnet_ids : data.aws_subnet.existing[id].availability_zone
  ])

  backend_repository_arn = "arn:${data.aws_partition.current.partition}:ecr:${var.image_repository_region}:${var.image_repository_account_id}:repository/opsrabbit/backend"
  web_repository_arn     = "arn:${data.aws_partition.current.partition}:ecr:${var.image_repository_region}:${var.image_repository_account_id}:repository/opsrabbit/web"
}
