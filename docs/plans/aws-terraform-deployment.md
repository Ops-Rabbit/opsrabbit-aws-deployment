# AWS Terraform deployment plan

## Goal

Provide a native Terraform deployment for the same OpsRabbit ECS Fargate
architecture as `template.yaml`. Terraform must create and manage the AWS
resources directly; it must not launch, wrap, or depend on CloudFormation.
Customers can choose either deployment method.

## Design decisions

- Keep Terraform in `terraform/` so its state and workflow are independent of
  the CloudFormation template.
- Use version-pinned `terraform-aws-modules` packages for the VPC, load
  balancer, ECS, EFS, RDS, and KMS building blocks. Use native AWS resources
  where the public modules do not express the required security or lifecycle
  behavior cleanly.
- Require Terraform 1.15.9 and pin the current AWS, Random, and Time providers,
  TFLint AWS ruleset, and public module releases. The versions were checked
  against the official Terraform Registry, upstream Git tags, and HashiCorp
  release service on 23 August 2026.
- Generate database and application secrets with ephemeral random values and
  write-only Secrets Manager and RDS arguments so plaintext values do not enter
  Terraform state or saved plans. Explicit version inputs coordinate database
  password changes with ECS task replacement.
- Keep ECS tasks in private application subnets with public IP assignment
  disabled. The public/private choice changes only the load balancer scheme.
- Support either a new two-Availability-Zone VPC or customer-supplied VPC,
  load-balancer, application, and data subnets.
- Preserve PostgreSQL data on normal destroy with a uniquely named final
  encrypted snapshot. EFS and other retained CloudFormation resources cannot
  be automatically retained by ordinary Terraform destroy while also allowing
  a complete destroy, so the Terraform guide will explain the explicit backup
  and destroy boundary.

## Prior-art review

Reviewed the Applied AI `claude-code` repository at revision
`dfb44640ca1c2b64b882a15edf73ec0374d41d9a`. It contains no Terraform, ECS,
Fargate, EFS, RDS, or reusable AWS deployment pattern. No infrastructure
structure was copied. Its interactive AWS authentication approach remains a
poor fit for workloads; this deployment uses AWS workload roles and does not
store long-lived ECR credentials.

## Behavior contract

### Independent deployment path

- Given only the files under `terraform/`, when a customer initializes and
  applies the configuration, Terraform plans AWS resources directly and does
  not contain a CloudFormation stack resource, template invocation, local
  deploy script, or shell provisioner.
- The existing CloudFormation workflow remains usable and its files retain
  their current behavior.

### New VPC and public access

- Given valid DNS, ACM, and ECR access, the public new-VPC example plans a
  dedicated VPC across two Availability Zones, an internet-facing HTTPS load
  balancer, private Fargate tasks without public IPs, isolated RDS/EFS data
  subnets, and one NAT Gateway for application egress.

### Existing VPC and private access

- Given a VPC and exactly two load-balancer, application, and data subnets in
  matching distinct Availability Zones, the private existing-VPC example plans
  no VPC or subnet ownership, creates an internal load balancer, and keeps task
  public IP assignment disabled.
- Missing or inconsistent existing-network inputs fail during planning before
  resources are created.

### Runtime and persistence

- The task contains the approved immutable backend and web images, exposes only
  the web container through the load balancer, and mounts four encrypted EFS
  access points at the standard non-root backend paths.
- PostgreSQL 16 is private and encrypted, uses an encrypted master secret,
  has automated backups, and creates a final encrypted snapshot on destroy.
- Better Auth and application encryption secrets are encrypted in Secrets
  Manager and their plaintext values are absent from Terraform state and plan
  JSON.

### Input and safety failures

- Mutable image tags, invalid Fargate CPU/memory combinations, invalid domain
  names, invalid CIDRs, and unsupported subnet counts fail Terraform validation.
- A public access choice never assigns a public IP to an ECS task or database.
- Outputs contain secret ARNs only and never secret values.

## Verification and closeout

Validated on 23 August 2026 without applying or creating AWS resources:

- confirmed Terraform 1.15.9, AWS provider 6.61.0, Random provider 3.9.0,
  Time provider 0.14.1, TFLint 0.64.0, AWS ruleset 0.48.0, and every pinned
  public module version against the official release sources
- passed Terraform formatting, initialization with the committed lock file,
  validation, TFLint, actionlint, Checkov, Trivy, and the existing
  CloudFormation validation suite
- generated a real customer-account public/new-VPC plan with 73 creates and no
  changes or destroys; it contains one NAT Gateway, an internet-facing load
  balancer, no ECS public IP, encrypted EFS with four access points, and private
  encrypted PostgreSQL with a final snapshot
- generated a real private/existing-VPC plan with 48 creates, no changes or
  destroys, zero VPC/subnet creates, an internal load balancer, and no ECS
  public IP
- confirmed saved plan JSON contains no database or application secret
  plaintext and contains no CloudFormation resource
- confirmed plans fail for a mutable or mismatched ECR image, cross-Region ACM
  certificate, invalid Fargate size, missing existing-network inputs, and
  mismatched subnet Availability Zones
- passed isolated operator-facing artifact validation against every applicable
  behavior-contract clause and the public/private anti-cheat contrast

The structured pre-commit review was run before and after the final input
validation tightening. Both runs reported no accepted or actionable P0
findings, and TruffleHog found no secret in the complete change bundle.
