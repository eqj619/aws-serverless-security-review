# Workshop module mapping

Maps findings from this review to the AWS workshop
**"AI-powered defense-in-depth: securing serverless application on AWS"**
(catalog.us-east-1.prod.workshops.aws, workshop `9508bf03-a457-4c7b-9883-4374dc883dbb`),
so a finding points at a concrete, practiced control with a known target configuration.

Read this file when the user asks for workshop alignment, when writing the
`Workshop module` field of a finding, or before planning a staged rollout.

Two things to keep straight:

- The workshop hardens **its own** starter application through numbered CloudFormation
  stacks. In a real environment, the *controls* transfer; the stack names and templates do
  not. Apply the equivalent control to the user's own IaC — never tell a user to deploy a
  workshop template into their production account.
- The workshop is a sequential build: each module depends on the previous one. That
  dependency order is also the sane rollout order for a real workload, which is why it is
  recorded below.

## The seven starter weaknesses

The workshop's starter app ships with seven deliberate weaknesses. They are a good
checklist of what this review should never miss, because they are the defaults that real
serverless applications also drift into:

| # | Weakness | Fixed in |
|---|---|---|
| 1 | No authentication — every endpoint accepts anonymous requests | Module 2 |
| 2 | No edge protection — nothing filtering malicious traffic | Module 2 |
| 3 | No VPC isolation — Lambda runs in the public AWS network | Module 3 |
| 4 | Log injection and a hardcoded placeholder in code | Module 4 |
| 5 | Lambda execution role with broad DynamoDB permissions | Module 4 |
| 6 | Hardcoded secret in an environment variable | Module 5 |
| 7 | DynamoDB not encrypted with a customer-managed KMS key | Module 6 |

## Module 1 — Identity verification (Amazon Cognito)

**Controls practiced**

- User pool with email sign-in, password policy of 12+ characters with all four character
  classes, account recovery by verified email only.
- `SOFTWARE_TOKEN_MFA` (TOTP). `MfaConfiguration: OPTIONAL` deliberately: it lets adaptive
  authentication escalate to MFA on risk without forcing every user to enrol on day one.
- Threat protection (adaptive authentication) — device fingerprint, IP reputation,
  geography and velocity. `AUDIT` mode observes and publishes CloudWatch metrics;
  `ENFORCED` / Full-function mode is what actually blocks and what exposes the compromised
  credential settings in the console.
- App client: `GenerateSecret: false` only because the CLI needs it — the workshop says
  production should use `ALLOW_USER_SRP_AUTH`. `PreventUserExistenceErrors: ENABLED` against
  user enumeration. ID/access tokens 1 hour, refresh 30 days.
- Identity pool with `AllowUnauthenticatedIdentities: false`, and an authenticated role
  whose trust policy is conditioned on `cognito-identity.amazonaws.com:aud` (this pool) and
  `amr: authenticated`.

**Maps to** layer-checklist Layer 2 findings, plus the identity-pool unauthenticated role check.

**Watch out**: moving MFA to required on an existing pool blocks users who have not
enrolled. Audit → enforced is the safe sequence. Threat protection in full-function mode
bills per monthly active user.

## Module 2 — API security + edge protection (API Gateway + WAF)

**Controls practiced**

- Cognito user pool authorizer on the API, `AuthorizationType: COGNITO_USER_POOLS` per
  method. Unauthenticated calls get 401 before Lambda is ever invoked. One health endpoint
  stays `NONE` deliberately — a reviewed exception, not a finding.
- Stage throttling: 10 req/s rate, 20 burst, applied with the `/*` wildcard.
- WAF Web ACL with default action Allow and rules evaluated in priority order:

| Priority | Rule | Blocks |
|---|---|---|
| 0 | Manual IP set | IPs you add yourself |
| 1 | `AWSManagedRulesAmazonIpReputationList` | Known malicious IPs |
| 2 | `AWSManagedRulesCommonRuleSet` | OWASP Top 10 — SQLi, XSS, traversal |
| 3 | `AWSManagedRulesKnownBadInputs` | SSRF, Log4j, known exploit payloads |
| 4 | Rate-based | 100 requests per 5-minute window per IP |

- `AWS::WAFv2::WebACLAssociation` binding the Web ACL to the stage — **the association is
  what activates protection**; an unassociated Web ACL protects nothing.
- WAF logging to S3 with a 30-day lifecycle, and a CloudWatch alarm on blocked-request count.

**Maps to** Layer 1 and Layer 3 findings. Satisfies the Security Hub control
`api-gw-associated-with-waf`.

**Watch out**: attaching an authorizer to a route that was open breaks every existing
caller that cannot present a token. API Gateway also needs a new **deployment** for method,
authorizer and throttling changes to take effect — a config change alone does nothing.
WAF integrates with REST APIs, not HTTP APIs.

## Module 3 — Network isolation (VPC)

**Controls practiced**

- VPC `10.0.0.0/16` with DNS hostnames and DNS resolution enabled (Interface endpoints in
  later modules depend on this).
- Two private subnets in separate AZs, `MapPublicIpOnLaunch: false`, no NAT gateway, no IGW.
- Lambda security group with **no inbound rules** — functions are invoked through the
  Lambda service API, not over the network — and outbound HTTPS only.
- DynamoDB **Gateway** VPC endpoint (free, route-table based) with an endpoint policy
  scoped to the table ARN.
- Lambda `VpcConfig` attaching the functions to the private subnets.

**Maps to** Layer 4 findings.

**Watch out**: the endpoint policy is an authorization layer of its own, evaluated
independently of IAM — a new table that IAM allows is still denied until the endpoint policy
covers it. Gateway endpoints are same-VPC/same-Region only. And if a function needs the
internet or an AWS service with no endpoint, moving it into private subnets breaks it;
enumerate its outbound dependencies first.

## Module 4 — Compute security (code, IAM, Inspector)

**Controls practiced**

- SAST / secrets / IaC scanning against the Amazon Q Detector Library (the workshop uses
  Kiro's code review; the detector set is the same one Amazon Q uses), producing
  severity-rated, CWE- and OWASP-referenced, line-level findings.
- Log injection fix — sanitize before logging:

  ```python
  safe_customer_id = str(body.get('customerId', 'anonymous')).replace('\n', ' ').replace('\r', ' ')
  print(f"Creating order for customer: {safe_customer_id}")
  ```

  CWE-117, OWASP A03:2021. The point is audit-trail integrity: forged log lines let an
  attacker cover tracks and trigger false alerts.
- Remove the hardcoded secret placeholder from the template (CWE-798) — removal here,
  proper replacement in Module 5.
- Least privilege on the execution role: the functions use only `PutItem` and `GetItem`, so
  `DeleteItem`, `UpdateItem`, `Query` and `Scan` come out. Production guidance is a separate
  role per function.
- Amazon Inspector enabled for continuous Lambda scanning (standard scan covers
  dependencies; code scan is a separate option).

**Maps to** Layer 5 findings, the cross-cutting IAM section, and the static code signals.

**Watch out**: Inspector bills per function per month after the trial. IAM policy changes
take up to 60 seconds to propagate — an `AccessDeniedException` immediately after a change
is usually propagation, not a broken policy.

## Module 5 — Secrets management (Secrets Manager + KMS)

**Controls practiced**

- Customer-managed KMS key with `EnableKeyRotation: true`; key policy granting the account
  root, the Secrets Manager service, and the execution role — nothing else.
- Secret holding the value as JSON, `KmsKeyId` pointing at the customer-managed key rather
  than `aws/secretsmanager`, named on an `{environment}/app-secret` convention so IAM can be
  scoped per environment.
- Secrets Manager **Interface** VPC endpoint with `PrivateDnsEnabled: true`, plus a
  dedicated security group allowing inbound 443 from the Lambda security group — the Lambda
  SG has no inbound rules, and endpoint ENIs receive connections.
- Function keeps only `SECRET_NAME` as an environment variable and calls `GetSecretValue` at
  runtime, caching the value in a module-level variable so the call happens once per cold
  start.
- IAM scoped to the one secret ARN and the one key ARN — `GetSecretValue` plus `kms:Decrypt`.
  Two permissions are now needed to read the secret: defense in depth at the credential layer.
- CloudTrail records every `GetSecretValue` and `kms:Decrypt`.

**Maps to** Layer 6 findings.

**Watch out**: Interface endpoints bill hourly per AZ plus data processing. Without the
endpoint, `GetSecretValue` from a private subnet times out rather than failing clearly. And
the actual secret value is the user's to set — a template should ship a placeholder, never
a real credential.

## Module 6 — Data protection (DynamoDB + KMS)

**Controls practiced**

- Customer-managed KMS key with rotation, key policy granting the account root, the
  DynamoDB service and the execution role.
- Table with `SSESpecification` `SSEType: KMS` and the customer-managed key, PITR enabled,
  and Streams with `NEW_AND_OLD_IMAGES` as a change-data audit trail.
- KMS **Interface** VPC endpoint — DynamoDB calls `kms:GenerateDataKey` and `kms:Decrypt` on
  the caller's behalf, so the function needs both the permissions and a network path.
- Gateway endpoint policy widened to cover the new table.
- Attribute-level access control with the `dynamodb:Attributes` condition key and
  `ForAllValues:StringEquals`.

**Maps to** Layer 7 findings.

**Watch out — the big one**: DynamoDB **cannot change the encryption key of an existing
table**. The workshop creates a new table and repoints the functions; existing data stays
behind. In a real workload that means a planned migration (export/import or a migration
script) before the cutover, and this is exactly the class of change that must be flagged as
replacement before anyone approves it.

## Module 7 — AI monitoring and automated response

**Controls practiced**

- GuardDuty detector with `LAMBDA_NETWORK_LOGS`, `S3_DATA_EVENTS` and `RDS_LOGIN_EVENTS`,
  publishing every 15 minutes (the shortest interval available).
- Severity bands: Low 1.0–3.9, Medium 4.0–6.9, High 7.0–8.9, Critical 9.0–10.0.
- EventBridge rule matching `aws.guardduty` findings with `severity >= 7.0` → an incident
  response Lambda. The threshold is deliberate: automated action for real threats, console
  review for the rest, no alert fatigue.
- The response function calls Amazon Bedrock (Amazon Nova 2 Lite) to turn the finding JSON
  into a two-or-three sentence analyst summary, disables a compromised access key with
  `iam:UpdateAccessKey … Status: Inactive` where the finding is a key compromise, and
  publishes a structured alert to SNS. Bedrock failure falls back to a static message —
  the alert still goes out.
- Response function IAM split into five narrow policies (logs, key disable, SNS publish,
  GuardDuty read, Bedrock invoke), each scoped to specific resources, so the security
  automation is not itself an escalation path.
- The response function runs **outside** the VPC — it only calls AWS service APIs, so VPC
  placement would only add endpoints, cost and cold-start latency.

**Maps to** the Continuous monitoring section of the checklist.

**Watch out**: automated containment acts on production credentials. Recommend it, but let
the user decide the blast radius — a containment action fired on a false positive is an
outage. GuardDuty bills on analyzed volume; S3 data events in particular.

## Rollout order for a real workload

The workshop's module order is a dependency chain, and the same order works as a staged
rollout — each stage leaves the application working and adds one layer:

1. **Identity** (Module 1) — deploy the pool, but do not enforce anything yet. Nothing breaks.
2. **API + edge** (Module 2) — attach the authorizer (breaking for token-less clients) and
   put WAF managed rules in **Count** first, then Block once sampled requests look clean.
3. **Network** (Module 3) — private subnets and endpoints. Transparent to callers when the
   outbound dependencies were enumerated correctly.
4. **Compute** (Module 4) — code fixes and IAM tightening. Lowest risk, highest ratio of
   value to blast radius; often worth doing first in practice when nothing is internet-open.
5. **Secrets** (Module 5) — rotate first, store second, change code third.
6. **Data** (Module 6) — encryption and backups. Plan the migration if a key change forces a
   new table.
7. **Monitoring** (Module 7) — detection and response last, because it is most useful once
   the preventive layers are in place and the noise floor is low.

Priority still overrides this order. A P0 in Module 6 territory — a public bucket of customer
data — is fixed before a P2 in Module 1 territory. The chain is for sequencing work of equal
urgency, not for deferring an emergency.

## Cost note

Several of these controls are not free: Shield Advanced, Cognito threat protection in full
function mode, Inspector, Interface VPC endpoints (hourly per AZ), GuardDuty (especially S3
data events), Bedrock invocations, and CloudTrail data events. When recommending any of
them, say so in the finding — a security recommendation that arrives as a surprise on the
invoice does not get adopted twice.
