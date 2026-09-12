# Template: security_issues.md

Use this structure verbatim, translated into the user's language. Keep finding IDs stable
across runs — they are how a human refers to an item in a meeting.

Replace everything in `<angle brackets>`. Delete sections that have no content, except the
summary and the scope sections, which always stay.

---

```markdown
# Security review — <application / account name>

- Last updated: <YYYY-MM-DD>
- Reviewed by: Claude Code + Agent Toolkit for AWS (aws-serverless-security-review)
- Scope: <account ID (masked) / region(s) / repository and revision>
- Basis: AWS defense-in-depth reference architecture for serverless microservices (7 layers)

> Point-in-time assessment of the configuration visible with the access available at the
> time of the review. Not a compliance certification.

## Summary

| Priority | Open | Fixed | Accepted | Total |
|---|---|---|---|---|
| P0 (fix now) | 0 | 0 | 0 | 0 |
| P1 (this sprint) | 0 | 0 | 0 | 0 |
| P2 (planned) | 0 | 0 | 0 | 0 |
| P3 (improvement) | 0 | 0 | 0 | 0 |

**Top three to act on:** <ID — one line each>

## Layer coverage

| Layer | Controls in place | Findings | Not verified |
|---|---|---|---|
| 1 — Edge protection | <e.g. WAF with managed rules, Block mode> | <IDs> | <e.g. Shield tier> |
| 2 — Identity | | | |
| 3 — API front door | | | |
| 4 — Network isolation | | | |
| 5 — Compute security | | | |
| 6 — Credentials | | | |
| 7 — Data protection | | | |
| Continuous monitoring | | | |

## Not verified

<What could not be checked and why: missing permissions, regions not scanned, resources
outside the IaC in this repository, environments not in scope. An unknown recorded as an
unknown is useful; an unknown reported as "no findings" is misleading.>

---

## Findings

### <ID: SEC-001> — <short title>

- **Priority:** P0 | P1 | P2 | P3
- **Layer:** <1–7 / Continuous monitoring / IAM (cross-cutting)>
- **Workshop module:** <Module 1–7 of the AWS defense-in-depth workshop, or "—">
- **Status:** Open | Approved | Fixed (code) | Applied (deployed) | Accepted (risk accepted) | Deferred | Not applicable
- **Affected:** `<ARN>` / `<path/to/file.ts:84>`
- **Effort:** S | M | L

**Observed**
<The actual configuration value or code. Concrete, quotable, checkable. Secrets masked.>

**Why it matters here**
<The path from this misconfiguration to real damage in this architecture. Not the generic
risk class.>

**Recommended fix**
<The specific change and the target value. Include the snippet when it is short.>

**Blast radius of the fix**
<What breaks or changes behavior when this is applied, and who needs to know.>

**Residual risk**
<What remains open after the fix, if anything. Delete this line when nothing remains.>

---

<Repeat per finding, ordered by priority across all layers — P0 first, never layer 1 first.
Within a priority band, cheaper fixes first.>

---

## Fix history

| Date | ID | Action | Files changed | Validation | Deployed |
|---|---|---|---|---|---|
| <YYYY-MM-DD> | SEC-003 | Fixed — Cognito MFA set to REQUIRED, TOTP | `infra/lib/auth-stack.ts` | `cdk synth` passed | Pending — user deploys |

## Deployments (apply mode only)

| Date | ID | Account / Region | Plan or change set | Verification | Rollback path |
|---|---|---|---|---|---|
| <YYYY-MM-DD> | SEC-003 | 1234****9012 / us-east-1 | `cdk diff` — 1 modified, 0 replaced | `get-user-pool-mfa-config` → `ON` | Previous template, `cdk deploy` of prior commit |

Leave this section out entirely when nothing was deployed from here.

## Accepted risks and deferrals

| ID | Decision | Reason | Decided by | Review again |
|---|---|---|---|---|
| SEC-009 | Accepted | Bucket holds public marketing assets only | <user> | <YYYY-MM-DD> |

## Requires action outside code

<Steps the user must perform themselves: credential rotation, console changes, a deploy, a
dependency on another team. Name the exact command or console path.>
```

---

## Rules for maintaining the file

- **Update, never overwrite.** On a re-run, keep existing IDs, keep resolved items in the
  history table, and add new findings with new IDs. An earlier decision to accept a risk
  must survive the next review — otherwise every run re-litigates settled questions.
- **Never put secret values in this file.** Record the location and the exposure; mask the
  value. The file usually ends up in version control.
- **Mask account IDs** (`1234****9012`) unless the user says otherwise.
- **Refresh the summary counts and the "last updated" date** in the same edit as any status
  change, or the top of the file starts lying about the bottom.
- **`Fixed` means the code change is merged and validated.** If it still needs a deploy to
  take effect, say so in the Deployed column — a fix that is not deployed is not protecting
  anything yet. `Applied` is reserved for a change that was deployed and then verified
  against the live resource.
