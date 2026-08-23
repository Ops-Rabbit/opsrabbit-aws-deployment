# OpsRabbit Terraform deployment

This directory is a native Terraform alternative to the repository's
CloudFormation template. It creates the AWS resources directly and does not
invoke CloudFormation, a shell deployment helper, or another provisioning
system.

## Prerequisites

- Terraform 1.15.9
- AWS credentials for the customer account, normally through AWS SSO or another
  short-lived identity
- permission to create the resources described in the root `README.md`
- an issued ACM certificate in the deployment Region for the application DNS name
- a Route 53 hosted zone, or another way to create the DNS record
- pull access from the customer account to the private OpsRabbit ECR repositories

OpsRabbit must grant the customer's 12-digit AWS account ID read access to both
image repositories before the first apply. Terraform creates the customer-side
ECS execution role; it does not store an ECR password or an access key.

## Pinned versions

The configuration pins the releases that were current on 23 August 2026:

| Component | Version |
|---|---:|
| Terraform | 1.15.9 |
| HashiCorp AWS provider | 6.61.0 |
| HashiCorp Random provider | 3.9.0 |
| HashiCorp Time provider | 0.14.1 |
| TFLint | 0.64.0 |
| TFLint AWS ruleset | 0.48.0 |
| AWS VPC module | 6.7.0 |
| AWS ECS module | 7.6.0 |
| AWS ALB module | 10.5.0 |
| AWS RDS module | 7.2.1 |
| AWS EFS module | 2.2.0 |
| AWS KMS module | 4.2.1 |

Provider selections and their checksums are committed in
`.terraform.lock.hcl`. Module release tags are pinned by their exact upstream
Git commit in the configuration. Check
the official [Terraform Registry](https://registry.terraform.io/) and test a
plan before intentionally upgrading them.

## State

Terraform uses local state unless the customer configures a backend. For a
shared or long-lived deployment, use the customer's normal protected remote
state service. `backend-s3.tf.example` shows an S3 backend with native state
locking; the bucket must exist before `terraform init`, so this deployment
cannot safely create its own backend.

The generated database and application secret values use ephemeral and
write-only arguments. Their plaintext values are omitted from Terraform state
and saved plans. State still contains infrastructure identifiers and must be
protected.

## Deploy into a new VPC

From this directory, copy and edit the public example:

```bash
cp examples/public-new-vpc.tfvars terraform.tfvars
terraform init
terraform validate
terraform plan -out=opsrabbit.tfplan
terraform apply opsrabbit.tfplan
```

The example creates public load-balancer subnets, private application subnets,
isolated data subnets, and one NAT Gateway across two Availability Zones. Set
`public_access_enabled = false` to create an internal load balancer in the new
VPC instead.

## Deploy into an existing VPC

Copy and edit the private example:

```bash
cp examples/private-existing-vpc.tfvars terraform.tfvars
terraform init
terraform validate
terraform plan -out=opsrabbit.tfplan
terraform apply opsrabbit.tfplan
```

The customer supplies exactly two subnet IDs per list. All three lists must use
the same two distinct Availability Zones:

- load-balancer subnets: public for public access, or private and reachable
  from the customer network for private access
- application subnets: private ECS subnets with NAT or suitable VPC endpoints
  for ECR, Secrets Manager, CloudWatch Logs, and required AWS APIs
- data subnets: private RDS and EFS subnets with no required internet route

Terraform reads the supplied network and fails the plan if the subnets do not
belong to the VPC, the Availability Zones do not match, or VPC DNS support and
DNS hostnames are disabled. It does not create, modify, import, or delete the
customer's VPC and subnets.

ECS public IP assignment is always disabled. `public_access_enabled` controls
only whether the load balancer is internet-facing or internal. A private
deployment requires a customer-managed path such as VPN, Direct Connect,
Transit Gateway, or VPC peering.

## DNS and TLS

`application_domain_name` and `certificate_arn` are required. Set
`hosted_zone_id` to let Terraform create the Route 53 alias. Leave it `null`
when DNS is managed elsewhere, then point the customer record to the
`load_balancer_dns_name` output.

The ACM certificate must be issued in the same Region and cover the application
DNS name.

## Images and updates

The defaults are immutable image digests from the approved OpsRabbit release.
Update `backend_image_uri` and `web_image_uri` together to the two digests in a
new release manifest, review the plan, and apply it.

If images are mirrored into another account or Region, also change
`image_repository_account_id` and `image_repository_region` so the execution
role remains limited to the correct repositories.

To rotate application secrets, increment `application_secret_version`. To
rotate the database password, increment `database_secret_version`. Each change
updates the encrypted secret and replaces the ECS task so the new value is
loaded. Secret plaintext is not shown in outputs.

## Persistence and destroy

PostgreSQL stores application records. EFS stores OpsRabbit application data,
Git workspaces, browser state, and Codex state through four access points. EFS
automatic backups and RDS automated backups are enabled.

Terraform destroy has different semantics from the retained CloudFormation
resources: it removes the active EFS file system, application log group, and
managed secrets, schedules the customer KMS key for deletion after 30 days,
and creates a final encrypted RDS snapshot. Verify an independent recovery
point before destroy. If the final snapshot must remain recoverable, cancel the
KMS key deletion during its 30-day window and retain the key; otherwise delete
the snapshot when it is no longer required.

`database_deletion_protection` defaults to `false` so a failed first deployment
can roll back. If it is enabled later, set it back to `false` and apply that
change before destroy.

## Main outputs

- `opsrabbit_url`
- `access_mode`
- `load_balancer_dns_name`
- `vpc_id`
- `ecs_cluster_name` and `ecs_service_name`
- `database_endpoint`
- `file_system_id`
- `application_log_group_name`
- `data_encryption_key_arn`
- database and application secret ARNs; values are never outputs
