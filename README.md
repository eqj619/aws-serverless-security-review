# aws-serverless-security-review

A Claude Code skill for reviewing the security of an application built on AWS, designed for
**Claude Code with the Agent Toolkit for AWS**.

It reviews a workload against a seven-layer defense-in-depth model, ranks the findings by
priority, records them in `security_issues.md`, and applies the fixes **only after you
approve each one** — to IaC and application code by default, and to the AWS account itself
when you switch on apply mode.

The layer model follows the AWS Security Blog post
[Building an AI-powered defense-in-depth security architecture for serverless microservices](https://aws.amazon.com/blogs/security/building-an-ai-powered-defense-in-depth-security-architecture-for-serverless-microservices/)
(Roger Nem, 16 Feb 2026), and findings are mapped to the modules of the companion workshop
[AI-powered defense-in-depth: securing serverless application on AWS](https://catalog.us-east-1.prod.workshops.aws/workshops/9508bf03-a457-4c7b-9883-4374dc883dbb/en-US/)
so each one points at a control with a known target configuration.

## What it does

1. Establishes scope — live account, IaC repository, or both.
2. Collects evidence **read-only** (AWS MCP tools, `aws` CLI, static reading of IaC and code).
3. Evaluates the seven layers plus continuous monitoring and cross-cutting IAM.
4. Ranks findings P0–P3 by impact × exposure × exploitability.
5. Writes `security_issues.md`.
6. Presents the ranked list and asks which items to fix.
7. Applies approved fixes to IaC/application code, then validates them (7a) — and deploys
   them, plan first and one approval per plan, when apply mode is on (7b).
8. Updates `security_issues.md` with status, files changed, what was deployed and verified,
   and what still needs a deploy.

Reports are written in your language — Japanese input gets a Japanese report — while AWS
service names, IAM actions, ARNs and CLI commands stay in their original form.

## Safety boundaries

- Analysis never mutates. No `create` / `update` / `put` / `delete` / `deploy` / `apply`
  during the review.
- Remediation is opt-in per finding. No blanket "fix everything".
- Deployment is off by default. The skill stops at the code boundary unless you turn on
  apply mode in that conversation; apply mode never carries over to another session.
- In apply mode, every deployment is preceded by a plan or change set you see, and approved
  per plan — resources being removed or replaced are called out before anything runs.
- Never, in any mode: deleting or destroying resources, disabling a security control,
  creating IAM users or access keys, handling secret values, rotating credentials, or
  touching root/organization settings.
- Secrets are never printed into the report or committed. A found credential is reported by
  location, with the value masked, and must be rotated by you.
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

If you intend to use apply mode, switch to a deployment role at that point rather than
starting the review with one — and prefer a non-production account for the first run.

## Layout

```
aws-serverless-security-review/
├── SKILL.md                            the workflow Claude follows
├── references/
│   ├── reference-architecture.md       the seven layers and their controls
│   ├── layer-checklist.md              per-layer checks and how to run them
│   ├── prioritization.md               P0–P3 scoring rubric with worked examples
│   ├── remediation-patterns.md         fix snippets for CDK / Terraform / SAM
│   └── workshop-modules.md             workshop module mapping, rollout order, costs
├── assets/
│   └── security_issues_template.md     the report structure
├── scripts/
│   └── collect_aws_evidence.sh         read-only inventory script
└── docs/
    └── github-setup.md                 how to publish and version this skill
```

## License

MIT — see [LICENSE](LICENSE).
