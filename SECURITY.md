# Security policy

## Supported version

Security fixes are made on the default `main` branch. Use the latest revision
when reporting or validating a potential issue.

## Reporting a vulnerability

Use GitHub private vulnerability reporting from the repository Security page.
Do not open a public issue for a suspected vulnerability.

Include the affected revision, selected network mode, impact, and reproducible
steps using placeholders. Never include AWS credentials, secret values,
customer identifiers, private image-access details, database snapshots, or logs
containing sensitive data.

## Deployment responsibility

This repository provisions customer-owned AWS resources. Deployment owners
remain responsible for IAM policy, network access, DNS, certificate renewal,
backup retention, secret rotation, monitoring, regional resilience, and their
organization's security requirements.

