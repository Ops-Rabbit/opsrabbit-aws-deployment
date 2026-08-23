#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "Usage: $0 <aws-profile> <aws-region> <stack-name> <parameter-file>" >&2
  exit 2
fi

profile=$1
region=$2
stack_name=$3
parameter_file=$4
script_dir=$(cd "$(dirname "$0")" && pwd)
template_file=$(cd "$script_dir/.." && pwd)/template.yaml

command -v aws >/dev/null 2>&1 || {
  echo "AWS CLI v2 is required." >&2
  exit 1
}
command -v jq >/dev/null 2>&1 || {
  echo "jq is required." >&2
  exit 1
}
[[ -f "$parameter_file" ]] || {
  echo "Parameter file not found: $parameter_file" >&2
  exit 1
}

parameter_json=$(jq -ce '
  if type != "array" or length == 0 then
    error("parameter file must be a non-empty JSON array")
  elif any(.[]; type != "object"
    or (.ParameterKey | type != "string" or length == 0 or (explode | any(.[]; . < 32 or (. >= 127 and . <= 159))))
    or (.ParameterValue | type != "string" or (explode | any(.[]; . < 32 or (. >= 127 and . <= 159))))) then
    error("every parameter requires control-character-free string ParameterKey and ParameterValue fields")
  elif ([.[].ParameterKey] | length) != ([.[].ParameterKey] | unique | length) then
    error("parameter keys must be unique")
  else
    .
  end
' "$parameter_file")

parameter_value() {
  jq -r --arg key "$1" \
    'first(.[] | select(.ParameterKey == $key) | .ParameterValue) // empty' \
    <<<"$parameter_json"
}

create_vpc=$(parameter_value CreateVpc)
create_vpc=${create_vpc:-true}

if [[ "$create_vpc" == "false" ]]; then
  existing_vpc_id=$(parameter_value ExistingVpcId)
  load_balancer_subnets=$(parameter_value ExistingLoadBalancerSubnetIds)
  application_subnets=$(parameter_value ExistingApplicationSubnetIds)
  data_subnets=$(parameter_value ExistingDataSubnetIds)

  [[ -n "$existing_vpc_id" && -n "$load_balancer_subnets" && -n "$application_subnets" && -n "$data_subnets" ]] || {
    echo "Existing-VPC mode requires the VPC ID and all three subnet lists." >&2
    exit 1
  }

  subnet_pattern='^subnet-([0-9a-f]{8}|[0-9a-f]{17}),subnet-([0-9a-f]{8}|[0-9a-f]{17})$'
  for subnet_list in "$load_balancer_subnets" "$application_subnets" "$data_subnets"; do
    [[ "$subnet_list" =~ $subnet_pattern ]] || {
      echo "Each existing subnet list must contain exactly two comma-separated subnet IDs." >&2
      exit 1
    }
  done

  IFS=',' read -r load_balancer_subnet_a load_balancer_subnet_b <<<"$load_balancer_subnets"
  IFS=',' read -r application_subnet_a application_subnet_b <<<"$application_subnets"
  IFS=',' read -r data_subnet_a data_subnet_b <<<"$data_subnets"
  all_subnets=(
    "$load_balancer_subnet_a" "$load_balancer_subnet_b"
    "$application_subnet_a" "$application_subnet_b"
    "$data_subnet_a" "$data_subnet_b"
  )

  subnet_details=$(aws ec2 describe-subnets \
    --profile "$profile" \
    --region "$region" \
    --subnet-ids "${all_subnets[@]}" \
    --output json)

  for subnet_id in "${all_subnets[@]}"; do
    jq -e --arg subnet_id "$subnet_id" \
      'any(.Subnets[]; .SubnetId == $subnet_id)' \
      <<<"$subnet_details" >/dev/null || {
      echo "Subnet was not returned by AWS: $subnet_id" >&2
      exit 1
    }
  done

  jq -e --arg vpc_id "$existing_vpc_id" \
    'all(.Subnets[]; .VpcId == $vpc_id)' \
    <<<"$subnet_details" >/dev/null || {
    echo "Every supplied subnet must belong to ExistingVpcId." >&2
    exit 1
  }

  availability_zones() {
    local first_subnet=$1
    local second_subnet=$2
    jq -r --arg first "$first_subnet" --arg second "$second_subnet" \
      '[.Subnets[] | select(.SubnetId == $first or .SubnetId == $second) | .AvailabilityZone] | unique | sort | join(",")' \
      <<<"$subnet_details"
  }

  load_balancer_azs=$(availability_zones "$load_balancer_subnet_a" "$load_balancer_subnet_b")
  application_azs=$(availability_zones "$application_subnet_a" "$application_subnet_b")
  data_azs=$(availability_zones "$data_subnet_a" "$data_subnet_b")

  [[ "$load_balancer_azs" == *,* && "$load_balancer_azs" == "$application_azs" && "$application_azs" == "$data_azs" ]] || {
    echo "All existing subnet lists must use the same two distinct Availability Zones." >&2
    exit 1
  }

  dns_support=$(aws ec2 describe-vpc-attribute \
    --profile "$profile" \
    --region "$region" \
    --vpc-id "$existing_vpc_id" \
    --attribute enableDnsSupport \
    --query 'EnableDnsSupport.Value' \
    --output text)
  dns_hostnames=$(aws ec2 describe-vpc-attribute \
    --profile "$profile" \
    --region "$region" \
    --vpc-id "$existing_vpc_id" \
    --attribute enableDnsHostnames \
    --query 'EnableDnsHostnames.Value' \
    --output text)
  [[ "$dns_support" == "True" && "$dns_hostnames" == "True" ]] || {
    echo "ExistingVpcId must have DNS support and DNS hostnames enabled." >&2
    exit 1
  }
fi

parameters=()
parameter_lines=$(jq -er '.[] | "\(.ParameterKey)=\(.ParameterValue)"' <<<"$parameter_json")
while IFS= read -r parameter; do
  parameters+=("$parameter")
done <<<"$parameter_lines"

aws cloudformation deploy \
  --profile "$profile" \
  --region "$region" \
  --stack-name "$stack_name" \
  --template-file "$template_file" \
  --capabilities CAPABILITY_NAMED_IAM \
  --no-fail-on-empty-changeset \
  --parameter-overrides "${parameters[@]}" \
  --tags application=opsrabbit

aws cloudformation describe-stacks \
  --profile "$profile" \
  --region "$region" \
  --stack-name "$stack_name" \
  --query 'Stacks[0].Outputs' \
  --output table
