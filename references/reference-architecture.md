# Reference architecture: seven layers of defense-in-depth

Source: AWS Security Blog, "Building an AI-powered defense-in-depth security architecture
for serverless microservices" — Roger Nem, 16 Feb 2026 (updated 10 Mar 2026).
https://aws.amazon.com/blogs/security/building-an-ai-powered-defense-in-depth-security-architecture-for-serverless-microservices/

This file is a condensed working summary for the review, not a substitute for the post.
Read the original when a user wants the full argument or the architecture diagram.

## The premise

A serverless microservice architecture trades a single perimeter for many small entry
points: every API route, every function invocation, every table. Defense-in-depth answers
that by layering independent controls, so one failed control does not hand over the whole
system. The post adds an AI dimension in both directions — attackers automate
reconnaissance and adaptation at machine speed, so detection has to be behavioral rather
than signature-bound.

## Layer 1 — Edge protection

The request arrives from the internet before any of your code sees it.

- **AWS Shield** — managed DDoS protection, on by default; Shield Advanced adds enhanced
  detection, the DDoS Response Team, cost protection and diagnostics.
- **AWS WAF** — managed rule groups covering OWASP Top 10 classes (SQLi, XSS, RFI),
  rate-based rules against application-layer floods and brute force, geo restrictions, and
  Bot Control for ML-based bot classification.
- **AI angle** — WAF logs analyzed by a model (e.g. via Amazon Bedrock) can surface novel
  patterns signature rules miss, summarize incidents in natural language, and propose rule
  updates. GuardDuty applies generative AI to detection, investigation and response.

## Layer 2 — Identity

- **Cognito user pools** — managed directory: registration, sign-in, MFA (SMS and TOTP),
  password policy, social login, SAML and OIDC federation.
- **Cognito identity pools** — temporary, scoped AWS credentials instead of long-lived keys.
- **Adaptive authentication** — ML risk scoring over device fingerprint, IP reputation,
  geography and sign-in velocity; step-up MFA or block on risk.
- **Compromised credential detection** — blocks sign-ins with known-breached passwords.

## Layer 3 — API front door

- **API Gateway** as the single controlled entry point: TLS via ACM with managed
  certificate renewal; throttling (burst/rate) and per-key usage quotas; API keys for
  partner access; JSON Schema request validation so malformed input never reaches Lambda;
  Cognito authorizers validating JWTs before application logic runs; access logging for audit.
- **AI angle** — GuardDuty flags anomalous API invocation patterns including credential
  exfiltration; log analysis can catch 4XX spikes that indicate probing, geographic
  anomalies, and unusual user agents.

## Layer 4 — Network isolation

- **VPC tiering** — public subnets for NAT and load balancers, private subnets for Lambda
  and application components, tightly restricted data subnets.
- Lambda in private subnets so functions have no direct inbound internet path.
- **Security groups** (stateful, least privilege) and **NACLs** (stateless, explicit deny).
- **VPC endpoints** for DynamoDB, Secrets Manager and S3, keeping that traffic off the
  public network path.
- **VPC flow logs** for traffic analysis; GuardDuty consumes flow logs, CloudTrail and DNS
  logs to detect reconnaissance, unauthorized access and compromised workloads.

The purpose of segmentation here is containment: limiting lateral movement after a
component is compromised.

## Layer 5 — Compute security

- **Execution roles** scoped to exact actions and resources (least privilege).
- **Resource-based policies** controlling who and what may invoke a function.
- **Environment variable encryption** with KMS — and genuinely sensitive values in Secrets
  Manager rather than environment variables at all.
- **Execution isolation** between invocations.
- **VPC integration** so functions inherit network controls.
- **Managed runtimes** that are patched for you — which means staying on supported versions.
- **Code signing** with AWS Signer for deployment package integrity.
- **Amazon Inspector** for continuous vulnerability scanning of functions and their
  dependencies, with ML-based prioritization.
- **Amazon Q Detector Library** describes the detectors used in code review to find
  OWASP Top 10 / CWE Top 25 issues, exposed secrets, vulnerable dependencies, and IaC
  practice problems.

## Layer 6 — Credentials

- **Secrets Manager** as the store for database passwords, API keys and OAuth tokens,
  encrypted at rest with KMS.
- **Automatic rotation**, updating both the secret and the target system without downtime.
- **Fine-grained IAM** on individual secrets.
- **CloudTrail audit trail** of secret access; **VPC endpoint** so retrieval stays inside
  the AWS network.
- Functions fetch secrets at runtime — nothing in code, nothing in config files, rotation
  without redeployment.

Hardcoded secrets in source and sensitive values in plain environment variables are the two
anti-patterns this layer exists to eliminate.

## Layer 7 — Data protection

For DynamoDB (and the equivalent controls in S3 / RDS):

- Encryption at rest (AWS-owned, AWS-managed, or customer-managed KMS keys — customer
  managed when you need key policy control and an audit trail of key use).
- Encryption in transit, TLS 1.2 or higher.
- Fine-grained IAM down to item and attribute level.
- VPC endpoints for private connectivity.
- Point-in-Time Recovery for continuous backup; Streams as an audit/event trail.
- Global Tables where multi-Region availability is required.
- GuardDuty over CloudTrail for anomalous data access — unusual query volume, unexpected
  source geography, exfiltration patterns.

## Continuous monitoring

Controls at every layer still need something watching for what gets through.

- **GuardDuty** — intelligent threat detection across accounts, workloads and data.
- **CloudTrail** — the API audit trail; the foundation for investigation and compliance.
- **CloudWatch** — metrics, log monitoring, alarms.
- **Automated response** — EventBridge plus Lambda to isolate a resource, revoke suspect
  credentials, or notify via SNS; model-generated summaries and response recommendations
  on top of findings.

## The closing point worth carrying into every review

Security here is a posture that is maintained, not a project that is finished: monitor
continuously, re-review controls, and treat security as an architectural property rather
than a phase. A report from this skill is a snapshot of one moment, and should say so.
