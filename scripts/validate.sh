#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "$0")/.."

command -v uvx >/dev/null 2>&1 || {
  echo "uvx is required: https://docs.astral.sh/uv/" >&2
  exit 1
}
command -v trivy >/dev/null 2>&1 || {
  echo "trivy is required: https://trivy.dev/" >&2
  exit 1
}

# Conditional existing-resource parameters have empty defaults. cfn-lint cannot
# infer that CloudFormation Rules prevent those branches from using empty IDs.
uvx --from cfn-lint==1.55.1 cfn-lint template.yaml \
  --ignore-checks W1030 W1033 W1035

# Accepted findings:
# CKV_AWS_260 - port 80 only redirects to HTTPS.
# CKV_AWS_157 - Multi-AZ is explicit and customer-selectable.
# CKV_AWS_91  - ALB access logging is intentionally left to customer policy.
uvx --from checkov==3.2.496 checkov \
  --framework cloudformation \
  --file template.yaml \
  --quiet \
  --compact \
  --skip-check CKV_AWS_260,CKV_AWS_157,CKV_AWS_91

trivy config \
  --severity HIGH,CRITICAL \
  --exit-code 1 \
  --ignorefile .trivyignore \
  template.yaml
