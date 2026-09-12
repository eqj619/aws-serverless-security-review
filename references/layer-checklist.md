# Layer checklist

One section per layer. Each check gives: what to look at, how to get it (read-only), and
what separates a real finding from a theoretical one.

Contents:

1. [Layer 1 — Edge protection](#layer-1--edge-protection)
2. [Layer 2 — Identity](#layer-2--identity)
3. [Layer 3 — API front door](#layer-3--api-front-door)
4. [Layer 4 — Network isolation](#layer-4--network-isolation)
5. [Layer 5 — Compute security](#layer-5--compute-security)
6. [Layer 6 — Credentials](#layer-6--credentials)
7. [Layer 7 — Data protection](#layer-7--data-protection)
8. [Continuous monitoring](#continuous-monitoring)
9. [Cross-cutting: IAM](#cross-cutting-iam)
10. [Static code and IaC signals](#static-code-and-iac-signals)

Every CLI example below is read-only. When AWS MCP tools from the Agent Toolkit are
available, prefer them and keep to `Describe*` / `Get*` / `List*` / `Search*`.

---

## Layer 1 — Edge protection

| Check | How to look | Real finding when |
|---|---|---|
| WAF in front of public entry points | `aws wafv2 list-web-acls --scope REGIONAL` and `--scope CLOUDFRONT`; `aws wafv2 get-web-acl-for-resource --resource-arn <api/alb arn>` | A public, unauthenticated endpoint has no Web ACL associated at all |
| Managed rule groups enabled | `aws wafv2 get-web-acl` → `Rules[].Statement.ManagedRuleGroupStatement` | No AWSManagedRulesCommonRuleSet / KnownBadInputs on an API accepting user input |
| Rules in Block, not Count | same output → `OverrideAction` / `Action` | Every rule is in Count mode — the WAF is observing, not protecting |
| Rate-based rule | `Statement.RateBasedStatement` | A login or token endpoint with no rate limit anywhere in the stack |
| WAF logging | `aws wafv2 get-logging-configuration` | Blocked requests are invisible, so nobody can investigate an attack |
| Shield Advanced (if the workload warrants it) | `aws shield get-subscription-state` | Only worth raising for a revenue-critical or targeted public workload; otherwise P3 |
| CloudFront in front of static/public content | `aws cloudfront list-distributions` | An S3 website bucket is publicly reachable directly |

Do not raise "no WAF" as a high priority for an internal API behind a Cognito authorizer in
a private VPC. Exposure decides the priority, not the absence of the service.

---

## Layer 2 — Identity

| Check | How to look | Real finding when |
|---|---|---|
| MFA configuration | `aws cognito-idp get-user-pool-mfa-config --user-pool-id <id>` | `MfaConfiguration: OFF` on a pool with administrative or privileged users |
| Password policy | `aws cognito-idp describe-user-pool` → `Policies.PasswordPolicy` | Minimum length below 8, or no complexity requirement, on an internet-facing pool |
| Advanced security / adaptive auth | `describe-user-pool` → `UserPoolAddOns.AdvancedSecurityMode` | `OFF` while the pool is public and password-based — compromised-credential detection is not running |
| Self sign-up | `AdminCreateUserConfig.AllowAdminCreateUserOnly` | Open self sign-up on an internal application |
| Token lifetimes | `aws cognito-idp describe-user-pool-client` → token validity | Refresh tokens valid for years with no rotation, on a high-value app |
| App client secrets and flows | `describe-user-pool-client` → `ExplicitAuthFlows` | `ALLOW_USER_PASSWORD_AUTH` enabled unnecessarily; implicit grant still enabled |
| Callback URLs | `describe-user-pool-client` → `CallbackURLs` | Wildcards, `http://` (non-localhost), or stale domains that could be re-registered |
| Identity pool unauthenticated role | `aws cognito-identity describe-identity-pool`; then the role's policy | Unauthenticated identities allowed, and their role can read data |

The unauthenticated identity pool role is the one people forget. Anything it can do, the
whole internet can do.

---

## Layer 3 — API front door

| Check | How to look | Real finding when |
|---|---|---|
| Authorizer on every route | `aws apigateway get-resources --rest-api-id <id>` / `aws apigatewayv2 get-routes`; check `authorizationType` per method | Any method is `NONE` and returns or mutates data. A deliberately public health check is fine — name it as reviewed, not as a finding |
| Throttling | `aws apigateway get-stage` → `methodSettings`; usage plans via `get-usage-plans` | No account-level or stage-level limit on an endpoint that triggers expensive work |
| Request validation | `aws apigateway get-request-validators`, models per method | User input reaches Lambda with no schema validation on a public API |
| Access logging + execution logging | `get-stage` → `accessLogSettings`, `methodSettings.loggingLevel` | No access logs at all: an incident cannot be reconstructed |
| TLS policy and custom domain | `aws apigateway get-domain-names` → `securityPolicy` | `TLS_1_0` security policy |
| Private vs regional/edge endpoint | `get-rest-apis` → `endpointConfiguration.types` | An internal-only API deployed as a public regional endpoint |
| Data in URLs | route definitions, log samples | Tokens, emails or IDs passed as query strings and then written into logs |
| CORS | `get-cors-configuration` / method responses | `Access-Control-Allow-Origin: *` together with credentials on an authenticated API |
| WAF association | see Layer 1 | — |

---

## Layer 4 — Network isolation

| Check | How to look | Real finding when |
|---|---|---|
| Security group ingress | `aws ec2 describe-security-groups` | `0.0.0.0/0` on 22, 3389, 3306, 5432, 6379, 27017, or any admin port |
| Security group egress | same | Unrestricted egress from a component that handles sensitive data — this is the exfiltration path; usually P2 unless the workload is regulated |
| Lambda VPC placement | `aws lambda get-function-configuration` → `VpcConfig` | A function that reaches private data sits outside the VPC, or sits in a public subnet with a route to an IGW |
| Subnet tiering | `aws ec2 describe-subnets`, `describe-route-tables` | Data-tier resources in a subnet with a default route to an internet gateway |
| NACLs | `aws ec2 describe-network-acls` | Fully permissive NACLs on a data subnet in a regulated workload (P2/P3 — defense in depth) |
| VPC endpoints | `aws ec2 describe-vpc-endpoints` | DynamoDB / S3 / Secrets Manager traffic traverses a NAT gateway instead of an endpoint |
| Flow logs | `aws ec2 describe-flow-logs` | No flow logs on a VPC holding production data |
| Public IP assignment | `describe-subnets` → `MapPublicIpOnLaunch` | Workload subnets auto-assign public IPs |

---

## Layer 5 — Compute security

| Check | How to look | Real finding when |
|---|---|---|
| Execution role scope | `aws lambda get-function-configuration` → `Role`; then `aws iam get-role-policy` / `list-attached-role-policies` | `Action: "*"` or `Resource: "*"` on a data service; `AdministratorAccess` attached to a function role |
| Shared roles | compare role ARNs across functions | One role shared by many functions, so each inherits the union of all their permissions |
| Runtime version | `get-function-configuration` → `Runtime` | A deprecated runtime (no longer receiving patches) |
| Dependency vulnerabilities | `aws inspector2 list-findings` if enabled; otherwise `npm audit` / `pip-audit` in the repo | Critical/high with a known exploit path in a reachable code path |
| Resource-based policy | `aws lambda get-policy` | `Principal: "*"` without a `SourceArn`/`SourceAccount` condition |
| Environment variables | `get-function-configuration` → `Environment.Variables` (mask values in the report) | Anything that looks like a password, token or private key |
| KMS key for env vars | `KMSKeyArn` | Sensitive config encrypted only with the default key in a workload that requires key separation (P3 unless required by policy) |
| Function URLs | `aws lambda get-function-url-config` | `AuthType: NONE` — a public, unauthenticated entry point that bypasses API Gateway and WAF entirely |
| Code signing | `aws lambda get-function-code-signing-config` | Absent in an environment with a supply-chain requirement (P3 otherwise) |
| Dead letter / error handling | `DeadLetterConfig`, `on-failure` destinations | Silent failure on a security-relevant path |
| Timeouts and concurrency | `Timeout`, `ReservedConcurrentExecutions` | No reserved concurrency on an internet-triggered function — a cost/availability DoS |

---

## Layer 6 — Credentials

| Check | How to look | Real finding when |
|---|---|---|
| Hardcoded secrets in the repo | `rg -n "(aws_secret_access_key\|AKIA[0-9A-Z]{16}\|-----BEGIN [A-Z ]*PRIVATE KEY\|password\s*=\s*[\"'][^\"']{6,}\|token\s*=\s*[\"'][^\"']{12,})"` over the repo and its git history | Any live credential in source. **P0. Report location only, mask the value, tell the user to rotate first and remove second** |
| Secrets in environment variables | Layer 5 env var check | Database passwords or API keys as plain Lambda env vars instead of Secrets Manager |
| Rotation | `aws secretsmanager describe-secret` → `RotationEnabled`, `LastRotatedDate` | Long-lived database credentials with rotation never enabled |
| Secret resource policies | `aws secretsmanager get-resource-policy` | Broad principals with access to a production secret |
| KMS key policies and rotation | `aws kms get-key-policy`, `get-key-rotation-status` | A key policy allowing `kms:*` to the whole account root for a sensitive data key; rotation disabled on a long-lived CMK |
| Long-lived IAM users | `aws iam list-users`, `list-access-keys`, `get-access-key-last-used` | Access keys older than 90 days, or keys never used, still active — especially with console access and no MFA |
| Secrets in CloudFormation/Terraform | search IaC for literal values and `terraform.tfstate` in version control | State files with plaintext secrets committed |

Secrets found in git history are still exposed after the file is deleted. Say that plainly:
the credential must be rotated, and removing the file is not remediation.

---

## Layer 7 — Data protection

| Check | How to look | Real finding when |
|---|---|---|
| DynamoDB encryption | `aws dynamodb describe-table` → `SSEDescription` | Customer-managed key required by policy but AWS-owned key in use; note that DynamoDB is always encrypted at rest |
| Point-in-Time Recovery | `aws dynamodb describe-continuous-backups` | PITR off on a production table |
| Deletion protection | `describe-table` → `DeletionProtectionEnabled` | Off on a production table |
| Fine-grained access | the IAM policies from Layer 5 | `dynamodb:*` on `*` from an application role |
| S3 public access | `aws s3api get-public-access-block`, `get-bucket-policy`, `get-bucket-acl` | Public read or write on a bucket holding non-public data — **P0 if it contains personal or business data** |
| S3 encryption and TLS | `get-bucket-encryption`, bucket policy `aws:SecureTransport` | No default encryption; no policy denying non-TLS access |
| S3 versioning and lifecycle | `get-bucket-versioning` | No versioning on a bucket where ransomware or accidental deletion would be material |
| RDS exposure | `aws rds describe-db-instances` → `PubliclyAccessible`, `StorageEncrypted` | Publicly accessible production database; storage unencrypted |
| Backups | RDS `BackupRetentionPeriod`, AWS Backup plans | Retention of 0–1 days on production data |
| PII handling | code and schema reading | Personal data stored unencrypted at the field level where the compliance framework in scope requires it |

---

## Continuous monitoring

| Check | How to look | Real finding when |
|---|---|---|
| CloudTrail | `aws cloudtrail describe-trails`, `get-trail-status` | No multi-Region trail; trail not logging; log file validation disabled |
| CloudTrail log integrity | `describe-trails` → `LogFileValidationEnabled`; bucket policy | Logs writable by the same roles being audited |
| GuardDuty | `aws guardduty list-detectors`, `get-detector` | Not enabled, or enabled in one Region only while workloads run in several |
| GuardDuty findings backlog | `aws guardduty list-findings` | High-severity findings open for weeks — the detection exists but nobody acts on it |
| Security Hub / Config | `aws securityhub get-enabled-standards`, `aws configservice describe-configuration-recorders` | No continuous compliance baseline in a regulated workload |
| Alarms and routing | `aws cloudwatch describe-alarms`, `aws sns list-topics` | Findings go to a mailbox nobody reads, or nowhere |
| Log retention | `aws logs describe-log-groups` → `retentionInDays` | `null` (never expires — a cost problem) or shorter than the compliance requirement |
| Automated response | EventBridge rules | Worth recommending, rarely a finding on its own |

---

## Cross-cutting: IAM

Check across every layer, because this is where a small misconfiguration becomes lateral
movement:

- Wildcard `Action` or `Resource` in any policy attached to a runtime role.
- `iam:PassRole` with `Resource: "*"` — privilege escalation.
- `sts:AssumeRole` trust policies with `Principal: {"AWS": "*"}` or a third-party account
  with no `ExternalId` condition.
- Missing `Condition` keys (`aws:SourceArn`, `aws:SourceAccount`) on service trust policies
  — the confused deputy problem.
- Roles unused for 90+ days (`aws iam get-role` → `RoleLastUsed`).
- Root account: access keys present, MFA absent (`aws iam get-account-summary`).

## Static code and IaC signals

Worth grepping for even when account access is available, because code is what gets
redeployed:

- `verify=False`, `rejectUnauthorized: false`, disabled certificate validation.
- String-concatenated SQL or NoSQL filter expressions built from request input.
- `eval`, `exec`, `child_process` with user-controlled input.
- `console.log`/`print` of tokens, authorization headers, or full request bodies.
- `Principal: "*"`, `Action: "*"`, `Resource: "*"` in IaC policy documents.
- `cidr_blocks = ["0.0.0.0/0"]`, `AnyPrincipal()`, `publicReadAccess: true`.
- `authorizationType: NONE`, `authType: NONE` on routes and function URLs.
- Terraform state, `.env`, `*.pem` in the repo or missing from `.gitignore`.
- Pinned but long-outdated dependencies in `package.json` / `requirements.txt`.
