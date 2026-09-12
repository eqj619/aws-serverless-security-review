# Prioritization rubric

The user reads the top of the list first. Ranking is therefore the part of the review that
carries the most weight — more than the count of findings, more than the wording of any
single one.

## Three inputs

**Impact** — what an attacker gets if this is used.

| Score | Meaning |
|---|---|
| 4 | Personal data, credentials, or financial data disclosed; full account or data-store takeover |
| 3 | Privilege escalation, lateral movement, or write access to production data |
| 2 | Limited data disclosure, availability loss, or integrity damage in one component |
| 1 | Information leakage of low value; hardening gap with no direct consequence |

**Exposure** — who can reach it.

| Score | Meaning |
|---|---|
| 4 | Anonymous, from the public internet |
| 3 | Any authenticated user of the application |
| 2 | Requires a compromised component, or a position inside the VPC/account |
| 1 | Requires privileged access that an attacker would already have to hold |

**Exploitability** — what it takes.

| Score | Meaning |
|---|---|
| 3 | A single request, a public tool, or simply reading a value that is already visible |
| 2 | Requires chaining with another weakness, or non-trivial effort |
| 1 | Theoretical, needs conditions that are unlikely to line up |

## Mapping to priority

Multiply impact × exposure × exploitability, then apply judgment — the number starts the
conversation, it does not end it.

| Score | Priority | Meaning |
|---|---|---|
| 32–48 | **P0** | Fix now. Treat as a live incident risk |
| 16–31 | **P1** | Fix this sprint |
| 6–15 | **P2** | Plan it into the next cycle |
| 1–5 | **P3** | Improvement / hardening backlog |

### Overrides that ignore the arithmetic

Promote to **P0** regardless of score:

- A live, unrotated credential in source control or in a log.
- A storage location holding personal or business data that is publicly readable.
- A public entry point that reaches data with no authentication (Lambda Function URL with
  `AuthType: NONE`, an API method with `authorizationType: NONE`, a public database).

Demote by one level when:

- The exposed component holds only synthetic or public data, confirmed with the user.
- A compensating control genuinely blocks the path (a WAF rule in Block mode, an SCP, a
  network boundary). Record the compensating control in the finding, so the priority can be
  re-evaluated if that control is ever removed.

**Never** adjust priority for how hard the fix is. Effort belongs in its own field, and it
decides the order within a priority band, not the band itself.

## Ordering the report

1. Sort by priority across all layers — P0 first, never layer 1 first.
2. Within a band, cheaper fixes first, so the user can clear ground quickly.
3. Group items that share a single fix, and say so: one IAM policy rewrite that closes four
   findings should read as one piece of work.

## Worked examples

**Lambda Function URL with `AuthType: NONE` returning customer records**
Impact 4 × exposure 4 × exploitability 3 = 48 → **P0**, and the public-entry-point override
would have said P0 anyway.

**`dynamodb:*` on `*` in a Lambda execution role**
Impact 3 × exposure 2 (needs the function compromised first) × exploitability 2 = 12 →
P2 by arithmetic, but promote to **P1**: the function is reachable from the internet
through API Gateway, which makes "the function is compromised" the realistic case rather
than the hypothetical one. Write that reasoning into the finding.

**No VPC flow logs on a production VPC**
Impact 1 (no direct consequence; it is a detection gap) × exposure 2 × exploitability 1 = 2
→ **P3**. Raise it to P2 if the workload is in scope for PCI-DSS, where flow logging is
expected.

**Cognito pool with MFA off, admin users included**
Impact 4 × exposure 4 × exploitability 2 (needs credential theft first) = 32 → **P1** in
practice: phishing and credential stuffing make this a matter of when. If compromised
credential detection is also off, it is P0 territory.

**API Gateway with no WAF, behind a Cognito authorizer, internal users only**
Impact 2 × exposure 3 × exploitability 1 = 6 → **P2**. Recommend it as defense in depth;
do not present it as urgent.

## Writing the finding

Whatever the priority, the finding is only useful if the reader can act without asking a
follow-up question:

- **Observed** — the actual value, ARN, or `file:line`. Not "IAM is too permissive" but
  `Action: "dynamodb:*"`, `Resource: "*"` in `infra/lib/api-stack.ts:84`.
- **Why it matters here** — the path from this misconfiguration to real damage in *this*
  architecture, not a generic description of the risk class.
- **Fix** — the specific change, with the target value.
- **Effort** — S (under an hour) / M (under a day) / L (more than a day or cross-team).
- **Residual risk** — what is still open after the fix, when anything is.
