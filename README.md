# aws-serverless-security-review

A Claude Code skill for reviewing the security of an application built on AWS, designed for
**Claude Code with the Agent Toolkit for AWS**.

It reviews a workload against a seven-layer defense-in-depth model, ranks the findings by
priority, records them in `security_issues.md`, and applies fixes to IaC/application code
**only after you approve each one**.

The layer model follows the AWS Security Blog post
[Building an AI-powered defense-in-depth security architecture for serverless microservices](https://aws.amazon.com/blogs/security/building-an-ai-powered-defense-in-depth-security-architecture-for-serverless-microservices/)
(Roger Nem, 16 Feb 2026).

## What it does

1. Establishes scope — live account, IaC repository, or both.
2. Collects evidence **read-only** (AWS MCP tools, `aws` CLI, static reading of IaC and code).
3. Evaluates the seven layers plus continuous monitoring and cross-cutting IAM.
4. Ranks findings P0–P3 by impact × exposure × exploitability.
5. Writes `security_issues.md`.
6. Presents the ranked list and asks which items to fix.
7. Applies approved fixes **to code only**, then validates them.
8. Updates `security_issues.md` with status, files changed, and what still needs a deploy.

Reports are written in your language — Japanese input gets a Japanese report — while AWS
service names, IAM actions, ARNs and CLI commands stay in their original form.

## Safety boundaries

- Analysis never mutates. No `create` / `update` / `put` / `delete` / `deploy` / `apply`
  during the review.
- Remediation is opt-in per finding. No blanket "fix everything".
- Remediation edits IaC and application code only. It never changes AWS directly, and it
  never deploys — that stays with you.
- Secrets are never printed into the report or committed. A found credential is reported by
  location, with the value masked, and must be rotated.
- No penetration testing, no exploitation, no host scanning. This reads configuration.

## Install

Clone into your skills directory:

```bash
# Personal, available in every project
git clone <this-repo-url> ~/.claude/skills/aws-serverless-security-review

# Or per project, committed with the repository
git clone <this-repo-url> .claude/skills/aws-serverless-security-review
```

Then start Claude Code in the project and ask for a security review. The skill triggers on
requests about AWS security, hardening, misconfiguration, risk analysis or a security audit.

## Recommended AWS access

Run the review with read-only credentials. The AWS managed policies `SecurityAudit` and
`ViewOnlyAccess` together cover almost everything the checklist reads. Using a role that
cannot write is the strongest guarantee that the review will not change anything.

## Layout

```
aws-serverless-security-review/
├── SKILL.md                            the workflow Claude follows
├── references/
│   ├── reference-architecture.md       the seven layers and their controls
│   ├── layer-checklist.md              per-layer checks and how to run them
│   ├── prioritization.md               P0–P3 scoring rubric with worked examples
│   └── remediation-patterns.md         fix snippets for CDK / Terraform / SAM
├── assets/
│   └── security_issues_template.md     the report structure
├── scripts/
│   └── collect_aws_evidence.sh         read-only inventory script
└── docs/
    └── github-setup.md                 how to publish and version this skill
```

## License

MIT — see [LICENSE](LICENSE).
