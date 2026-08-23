# OpsRabbit AWS deployment

This repository offers two independent ways to deploy a fresh OpsRabbit
installation on AWS:

| Choice | Use |
|---|---|
| CloudFormation | `template.yaml` and the included deployment helper |
| Terraform | Native code under `terraform/`; it does not execute CloudFormation |

Both choices create:

- one Amazon ECS Fargate task containing the OpsRabbit backend and web containers
- one encrypted Amazon EFS file system for OpsRabbit data, Git workspaces,
  browser state, and Codex state
- one private Amazon RDS for PostgreSQL 16 database with `pgvector`
- one HTTPS Application Load Balancer
- encrypted secrets and application logs

OpsRabbit builds and publishes the container images. Customers deploy their
chosen configuration in their own AWS account; they do not build or modify the
images.

## Network choices

Both deployment choices support either a new dedicated VPC or an existing
customer VPC, with public or private application access.

| CloudFormation setting / Terraform variable | Result |
|---|---|
| `CreateVpc=true` / `create_vpc=true` | Creates public load-balancer subnets, private application subnets, isolated data subnets, and one NAT Gateway. |
| `CreateVpc=false` / `create_vpc=false` | Uses the supplied VPC and subnet lists without taking ownership of them. |
| `PublicAccessEnabled=true` / `public_access_enabled=true` | Creates an internet-facing Application Load Balancer. |
| `PublicAccessEnabled=false` / `public_access_enabled=false` | Creates an internal Application Load Balancer reachable only through the customer network. |

ECS `AssignPublicIp` is always disabled. The backend, web container, EFS, and
PostgreSQL database are never assigned public IP addresses. The public/private
choice controls only the load balancer.

Changing `PublicAccessEnabled` on an existing stack replaces both the load
balancer and its target group. When CloudFormation manages the Route 53 alias,
it updates the record automatically; externally managed DNS must be updated to
the new `LoadBalancerDnsName` output.

## Prerequisites

- an AWS account and permission to create the resources in `template.yaml` or
  `terraform/`
- AWS CLI v2 authenticated to the target account
- an issued ACM certificate in the deployment Region for the application DNS name
- a Route 53 public or private hosted zone, or another way to create the DNS record
- `jq` when using the CloudFormation deployment helper
- pull access to the private OpsRabbit ECR repositories

### OpsRabbit ECR access

Before deployment, give OpsRabbit the customer's 12-digit AWS account ID.
OpsRabbit must grant that account read access to both image repositories. The
template creates a narrowly scoped ECS task execution role that pulls the
approved image digests; no ECR password or long-lived AWS access key is stored
in CloudFormation.

The customer deployment identity does not need credentials for the OpsRabbit
AWS account. It needs permission to create the task execution role in the
customer account and pass it to ECS.

## Validate

The validation script checks both deployment choices with pinned releases of
the relevant tools:

```bash
./scripts/validate.sh
```

The Checkov exceptions are intentional: HTTP port 80 performs only an HTTPS
redirect, Multi-AZ and log retention remain customer-controlled choices,
load-balancer access logging is left to the customer's central logging policy,
module-attached security groups are not visible to Checkov's static graph, and
secret rotation is explicitly coordinated with ECS replacement. Trivy's
accepted public-mode and required task-egress findings are documented in
`.trivyignore`.

To also ask AWS to validate the template:

```bash
aws cloudformation validate-template \
  --region us-east-1 \
  --template-body file://template.yaml
```

## Deploy with Terraform

Follow the [Terraform deployment guide](terraform/README.md). Terraform creates
the AWS resources directly and maintains separate state; it does not create or
call a CloudFormation stack.

## Deploy with CloudFormation into a new VPC

Copy the example to an ignored local file and replace its placeholders:

```bash
cp parameters/public-new-vpc.json parameters/customer.local.json
```

Deploy:

```bash
./scripts/deploy.sh \
  <aws-profile> \
  <aws-region> \
  opsrabbit \
  parameters/customer.local.json
```

The example is public. Set `PublicAccessEnabled` to `false` to create an
internal load balancer in the new VPC instead.

## Deploy with CloudFormation into an existing VPC

Copy `parameters/private-existing-vpc.json` and replace its placeholders. The
customer must supply exactly two subnet IDs per list. All three lists must use
the same two distinct Availability Zones:

- load-balancer subnets: public subnets for public access, or private subnets
  reachable from the customer network for private access
- application subnets: private ECS subnets with outbound access to ECR,
  Secrets Manager, CloudWatch Logs, and AWS APIs through NAT or suitable VPC endpoints
- data subnets: private subnets for RDS and EFS; no internet route is required

All supplied subnets must belong to `ExistingVpcId`. The template creates its
own security groups and does not modify or delete the customer VPC or subnets.
The existing VPC must have both DNS support and DNS hostnames enabled so ECS can
resolve the private RDS and EFS endpoints. The deployment helper verifies the
VPC, subnet ownership, Availability Zones, and DNS settings before deployment.

For a private deployment, users need an approved network path such as VPN,
Direct Connect, Transit Gateway, or VPC peering. A public DNS record does not
make an internal load balancer internet-accessible.

## DNS and TLS

`ApplicationDomainName` and `CertificateArn` are required. If `HostedZoneId` is
provided, CloudFormation creates an alias record for the load balancer. Leave
it empty when DNS is managed elsewhere, then create the record after deployment
using the `LoadBalancerDnsName` output.

The ACM certificate must be issued in the same Region as the load balancer and
must cover `ApplicationDomainName`.

## Images and updates

The template defaults to immutable SHA-256 image digests from the approved
OpsRabbit release. To update OpsRabbit, change `BackendImageUri` and
`WebImageUri` together to the digests in the new release manifest, then run the
deployment helper again with the same stack name and parameter file.

If the images are mirrored into a different ECR account or Region, also update
`ImageRepositoryAccountId` and `ImageRepositoryRegion` so the ECS execution
role points to the correct repositories.

## Persistence and recovery

PostgreSQL stores application records. EFS stores the four backend directories
that are persistent in the standard OpsRabbit container deployment. The
backend runs database migrations, including enabling `pgvector`, during startup.

The database uses automated backups, and EFS automatic backups are enabled.

### CloudFormation retention

EFS, secrets, the encryption key, and application logs use retention
protection. Database replacement or stack deletion creates a final encrypted
snapshot. This means deleting a successfully created CloudFormation stack
intentionally does not erase customer data. A failed initial creation that
reaches the database may also leave a final snapshot and its retained
encryption key; review and remove failed-deployment snapshots and keys when
they are not needed.

Database deletion protection defaults to `false` so CloudFormation can safely
roll back an unsuccessful first deployment. After the stack is healthy, enable
`DatabaseDeletionProtection` if customer policy requires it. Disable it before
deleting the stack or applying an update that replaces the database. Retained
file data, secrets, logs, keys, and database snapshots must be reviewed and
removed separately by an authorized customer administrator if permanent
deletion is required.

### Terraform destroy behavior

Terraform destroy removes the resources it manages, schedules the KMS key for
deletion, and creates a final RDS snapshot. Review the different backup and key
handling requirements in the
[Terraform persistence guide](terraform/README.md#persistence-and-destroy)
before destroying a Terraform deployment.

## Main outputs

- `OpsRabbitUrl`: customer-facing HTTPS URL
- `AccessMode`: `public` or `private`
- `LoadBalancerDnsName`: AWS load-balancer hostname
- `VpcId`: created or supplied VPC
- `EcsClusterName` and `EcsServiceName`: runtime identifiers
- `FileSystemId`: retained EFS file system
- `ApplicationLogGroupName`: retained CloudWatch application log group
- `DataEncryptionKeyArn`: retained customer-managed encryption key
- secret ARNs: references only; secret values are never outputs

Terraform provides the same information with lowercase output names documented
in its deployment guide.

## License and security

This project is licensed under Apache License 2.0. Report suspected
vulnerabilities through GitHub private vulnerability reporting as described in
`SECURITY.md`.
