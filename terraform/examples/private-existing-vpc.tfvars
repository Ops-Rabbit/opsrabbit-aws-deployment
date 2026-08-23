aws_region       = "us-east-1"
environment_name = "opsrabbit"

create_vpc                        = false
existing_vpc_id                   = "vpc-00000000000000000"
existing_load_balancer_subnet_ids = ["subnet-00000000000000001", "subnet-00000000000000002"]
existing_application_subnet_ids   = ["subnet-00000000000000003", "subnet-00000000000000004"]
existing_data_subnet_ids          = ["subnet-00000000000000005", "subnet-00000000000000006"]
public_access_enabled             = false
allowed_ingress_cidr              = "10.0.0.0/8"
application_domain_name           = "opsrabbit.internal.example.com"
certificate_arn                   = "arn:aws:acm:us-east-1:111122223333:certificate/00000000-0000-0000-0000-000000000000"
