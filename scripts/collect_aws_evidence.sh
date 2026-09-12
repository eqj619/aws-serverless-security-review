#!/usr/bin/env bash
#
# collect_aws_evidence.sh — read-only AWS inventory for the seven-layer security review.
#
# Every call in this script is a Describe/Get/List operation. Nothing here creates,
# modifies or deletes anything in the account. Read it before you run it.
#
# Usage:
#   ./collect_aws_evidence.sh --out ./evidence [--profile PROFILE] [--region REGION]
#                             [--layers 1,2,3,4,5,6,7,m]
#
# Output: one JSON file per check under --out, plus a manifest listing which checks
# succeeded, which returned nothing, and which failed (usually a permissions gap — record
# those as "not verified" in the report rather than as "no findings").

set -uo pipefail

OUT_DIR="./evidence"
PROFILE=""
REGION=""
LAYERS="1,2,3,4,5,6,7,m"

usage() { sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out)     OUT_DIR="$2"; shift 2 ;;
    --profile) PROFILE="$2"; shift 2 ;;
    --region)  REGION="$2"; shift 2 ;;
    --layers)  LAYERS="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

command -v aws >/dev/null || { echo "aws CLI not found" >&2; exit 1; }

AWS_ARGS=()
[[ -n "$PROFILE" ]] && AWS_ARGS+=(--profile "$PROFILE")
[[ -n "$REGION" ]]  && AWS_ARGS+=(--region "$REGION")

mkdir -p "$OUT_DIR"
MANIFEST="$OUT_DIR/_manifest.txt"
: > "$MANIFEST"

want() { [[ ",$LAYERS," == *",$1,"* ]]; }

# run <name> <aws args...> — writes $OUT_DIR/<name>.json, records the outcome.
run() {
  local name="$1"; shift
  local file="$OUT_DIR/$name.json"
  if aws "${AWS_ARGS[@]}" "$@" > "$file" 2> "$file.err"; then
    if [[ -s "$file" ]] && ! grep -q '^\s*{\s*}\s*$' "$file"; then
      echo "OK        $name" | tee -a "$MANIFEST"
    else
      echo "EMPTY     $name" | tee -a "$MANIFEST"
    fi
    rm -f "$file.err"
  else
    echo "FAILED    $name -- $(head -c 200 "$file.err" | tr '\n' ' ')" | tee -a "$MANIFEST"
    rm -f "$file"
  fi
}

echo "== identity ==" | tee -a "$MANIFEST"
run caller-identity sts get-caller-identity

if want 1; then
  echo "== layer 1: edge ==" | tee -a "$MANIFEST"
  run waf-acls-regional   wafv2 list-web-acls --scope REGIONAL
  run waf-acls-cloudfront wafv2 list-web-acls --scope CLOUDFRONT --region us-east-1
  run shield-subscription shield get-subscription-state
  run cloudfront-distributions cloudfront list-distributions
fi

if want 2; then
  echo "== layer 2: identity ==" | tee -a "$MANIFEST"
  run cognito-user-pools cognito-idp list-user-pools --max-results 60
  run cognito-identity-pools cognito-identity list-identity-pools --max-results 60
  # Per-pool detail needs the pool id; the reviewer follows up with:
  #   aws cognito-idp describe-user-pool --user-pool-id <id>
  #   aws cognito-idp get-user-pool-mfa-config --user-pool-id <id>
  #   aws cognito-idp list-user-pool-clients --user-pool-id <id>
fi

if want 3; then
  echo "== layer 3: api ==" | tee -a "$MANIFEST"
  run apigw-rest-apis apigateway get-rest-apis
  run apigw-http-apis apigatewayv2 get-apis
  run apigw-domain-names apigateway get-domain-names
  run apigw-usage-plans apigateway get-usage-plans
fi

if want 4; then
  echo "== layer 4: network ==" | tee -a "$MANIFEST"
  run vpcs ec2 describe-vpcs
  run subnets ec2 describe-subnets
  run security-groups ec2 describe-security-groups
  run network-acls ec2 describe-network-acls
  run route-tables ec2 describe-route-tables
  run vpc-endpoints ec2 describe-vpc-endpoints
  run flow-logs ec2 describe-flow-logs
fi

if want 5; then
  echo "== layer 5: compute ==" | tee -a "$MANIFEST"
  run lambda-functions lambda list-functions
  run iam-roles iam list-roles
  run iam-users iam list-users
  run iam-account-summary iam get-account-summary
  run inspector-coverage inspector2 list-coverage
  # Per-function detail:
  #   aws lambda get-function-configuration --function-name <name>
  #   aws lambda get-policy --function-name <name>
  #   aws lambda get-function-url-config --function-name <name>
fi

if want 6; then
  echo "== layer 6: credentials ==" | tee -a "$MANIFEST"
  run secrets secretsmanager list-secrets
  run kms-keys kms list-keys
  run kms-aliases kms list-aliases
fi

if want 7; then
  echo "== layer 7: data ==" | tee -a "$MANIFEST"
  run dynamodb-tables dynamodb list-tables
  run s3-buckets s3api list-buckets
  run rds-instances rds describe-db-instances
  run rds-clusters rds describe-db-clusters
  # Per-resource detail:
  #   aws dynamodb describe-table --table-name <name>
  #   aws dynamodb describe-continuous-backups --table-name <name>
  #   aws s3api get-public-access-block --bucket <name>
  #   aws s3api get-bucket-encryption --bucket <name>
  #   aws s3api get-bucket-policy --bucket <name>
fi

if want m; then
  echo "== continuous monitoring ==" | tee -a "$MANIFEST"
  run cloudtrail-trails cloudtrail describe-trails
  run guardduty-detectors guardduty list-detectors
  run securityhub-standards securityhub get-enabled-standards
  run config-recorders configservice describe-configuration-recorders
  run log-groups logs describe-log-groups
fi

echo
echo "Evidence written to $OUT_DIR"
echo "Review $MANIFEST: FAILED entries are usually missing permissions --"
echo "record them as 'not verified' in the report, not as 'no findings'."
