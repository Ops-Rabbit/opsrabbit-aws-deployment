module "vpc" {
  # terraform-aws-vpc v6.7.0
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-vpc.git?ref=6b147b1ef0e83c74402b984a5c8e55f95c88cf36"

  create_vpc = var.create_vpc
  name       = var.environment_name
  cidr       = var.vpc_cidr
  azs        = local.selected_azs

  public_subnets   = [for index in range(2) : cidrsubnet(var.vpc_cidr, 8, index)]
  private_subnets  = [for index in range(2) : cidrsubnet(var.vpc_cidr, 8, index + 10)]
  database_subnets = [for index in range(2) : cidrsubnet(var.vpc_cidr, 8, index + 20)]

  enable_dns_support   = true
  enable_dns_hostnames = true

  enable_nat_gateway     = true
  single_nat_gateway     = true
  one_nat_gateway_per_az = false

  map_public_ip_on_launch                = false
  create_database_subnet_group           = false
  create_database_subnet_route_table     = true
  create_database_nat_gateway_route      = false
  create_database_internet_gateway_route = false

  public_subnet_names   = [for az in local.selected_azs : "${var.environment_name}-load-balancer-${az}"]
  private_subnet_names  = [for az in local.selected_azs : "${var.environment_name}-application-${az}"]
  database_subnet_names = [for az in local.selected_azs : "${var.environment_name}-data-${az}"]

  tags = local.tags
}
