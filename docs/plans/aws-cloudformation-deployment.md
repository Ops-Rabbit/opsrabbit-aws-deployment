# AWS CloudFormation deployment plan

## Goal

Provide a customer-deployed CloudFormation stack for OpsRabbit on ECS Fargate,
with EFS persistence, RDS PostgreSQL with pgvector, new or existing VPC support,
and public or private application access.

## Design decisions

- Run backend and web in one Fargate task so the web proxy can reach the backend
  over localhost and releases remain atomic.
- Keep ECS tasks in private subnets with `AssignPublicIp=DISABLED` in both modes.
- Express public/private access through the Application Load Balancer scheme.
- Use four EFS access points with UID/GID 1000 for the standard non-root backend.
- Use RDS PostgreSQL 16; the backend startup migration enables pgvector.
- Use immutable image digests and a narrowly scoped cross-account ECR pull role.
- Retain customer data stores and secrets on stack deletion.

## Existing-network contract

The customer supplies one VPC and three two-subnet lists using the same two
Availability Zones. Load-balancer subnets match the selected public/private
mode, application subnets have AWS API and registry egress, and data subnets
remain private. DNS support and DNS hostnames must be enabled. The deployment
helper validates these facts without changing the customer network. The stack
owns only the resources it creates.

## Prior-art review

Reviewed the Applied AI `claude-code` repository at revision
`dfb446fc65c92c3efb1d98e52402dc0c12fd0724`. Its AWS material is limited to
interactive STS/authentication utilities and does not define an ECS,
CloudFormation, EFS, or RDS deployment pattern. No infrastructure structure was
copied. Interactive credential handling was explicitly rejected because ECS
must use workload roles and CloudFormation must not receive long-lived image
credentials.

## Behavior contract

### New VPC and public access

- Given valid DNS, ACM, and ECR access, when the public new-VPC example is
  deployed, then the stack completes, the ALB is internet-facing, the URL serves
  OpsRabbit over HTTPS, and the ECS task has no public IP.

### Existing VPC and private access

- Given valid existing subnet lists, when the private existing-VPC example is
  deployed, then the stack does not create or modify the VPC/subnets, the ALB is
  internal, the targets become healthy, and the ECS task has no public IP.

### Persistence

- Given a marker written to an EFS-mounted backend directory, when the task is
  replaced, then a later task can read the same marker.
- Given an initialized application, when the task is replaced, then PostgreSQL
  data and the first-admin state remain present.

### Input and safety failures

- Existing-VPC mode without every required subnet list fails before resources
  are created.
- Invalid Fargate CPU/memory combinations fail validation.
- Image values without immutable SHA-256 digests fail validation.
- Stack outputs never expose secret values.

## Verification and closeout

Record static validation, public deployment proof, private/existing-VPC proof,
EFS restart proof, application state proof, and complete test-resource cleanup
before the initial release is considered ready.

### Pre-commit review

The structured review found seven actionable issues. All were accepted and
fixed: parameter parsing now fails closed; existing subnet and DNS assumptions
are preflighted; retained resources clean up on failed first creation; database
deletion protection defaults off for safe rollback; the load balancer can be
replaced when its access mode changes; database storage limits are consistent;
and the existing-VPC requirements are documented. No review finding was
rejected or deferred.

The final review found five additional valid issues. The design was simplified
to leave ALB access logging to customer policy, use generated retained log-group
names, preserve RDS data through a final snapshot and its retained encryption key,
cap allocated storage below the fixed autoscaling ceiling, and reject every
control character before Bash conversion. Behavior validation also found and
fixed that the deployment helper originally depended on the caller's working
directory. No finding was waived. A failed initial creation that reaches RDS
can leave a recoverable final snapshot and KMS key; this limitation is explicitly
documented because CloudFormation cannot apply different snapshot behavior to
rollback and normal deletion without a custom lifecycle provider.

The frozen-tree review found and fixed two final release blockers: mode-specific
target-group names now allow safe public/private load-balancer replacement, and
parameter validation rejects both C0 and C1 Unicode control ranges before raw
Bash conversion.

### Live verification

Validated in a disposable AWS account in `us-east-1` on 23 August 2026:

- created a public stack with a new VPC and confirmed valid HTTPS, HTTP redirect,
  healthy targets, immutable image digests, private task addressing, encrypted
  EFS, and private encrypted PostgreSQL
- created a second private stack in the first stack's existing VPC, confirmed
  that no VPC or subnet resources were adopted, and reached the internal HTTPS
  endpoint from a temporary task inside the VPC
- replaced the public service task and confirmed that both a PostgreSQL user
  record and an EFS marker survived
- updated the public stack to the final generated-log-group and lifecycle
  design and confirmed healthy service plus persisted database state
- ran source-blind positive and negative contract checks, including malformed
  parameters, missing network inputs, invalid Fargate sizing, a mutable image
  tag, and a NUL-bearing parameter
- deleted both stacks, removed retained test data, manual snapshots, secrets,
  logs, buckets, EFS file systems, and the temporary ECR pull grant; the two KMS
  keys entered AWS's mandatory seven-day pending-deletion window, no EFS recovery
  points remained, and AWS retained one non-deletable automated RDS snapshot for
  service-managed expiry
