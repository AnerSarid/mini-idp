# Mini IDP — Improvements & Roadmap

This document catalogs known pain points, bugs, and improvement opportunities discovered during the initial build and end-to-end testing.

Organized by priority: **Critical** (blocks real use), **Important** (should fix soon), **Nice-to-have** (operational polish), and a final section on **Evolution Options** for growing the project.

---

## Critical (Must Fix)

### 1. CLI Destroy Command Calls Wrong Workflow

**File:** `cli/src/commands/destroy.ts:61-74`

The destroy command triggers `provision.yml` instead of `destroy.yml` and passes an `action: 'destroy'` field that doesn't exist in the provision workflow.

**Why it matters:** `idp destroy <name>` silently fails — the workflow runs a provision instead of a destroy. Users have to manually trigger destroy via `gh workflow run`.

**Fix:** Change `provision.yml` to `destroy.yml` and only pass `environment_name`.

---

### 2. IAM Role Permissions Are Over-Scoped

**Context:** During setup, we applied a custom policy (`idp-permissions.json`) that's reasonably scoped. However, the RUNBOOK.md documents using AWS-managed full-access policies (`AmazonECS_FullAccess`, `AmazonRDSFullAccess`, etc.) as an alternative. If anyone follows the RUNBOOK instructions, they'll get near-admin access.

**Why it matters:** A compromised GitHub Actions token + full-access IAM = full AWS account takeover. The blast radius should be limited to `idp-*` resources only.

**Fix:**
- Remove the full-access policy suggestions from RUNBOOK.md
- Document the scoped policy as the only supported approach
- Add IAM path `/idp/` to all created roles for finer scoping
- Add `Condition` blocks limiting resource creation to tagged resources

---

### 3. No HTTPS on ALB

**File:** `infrastructure/modules/ecs-service/main.tf:157-170`

The ALB only listens on HTTP port 80. All traffic is unencrypted.

**Why it matters:** Anyone on the network path can read all traffic. Unusable for anything involving credentials, tokens, or real data.

**Fix:** Add an optional `acm_certificate_arn` variable. When provided, create an HTTPS listener on 443 and redirect HTTP to HTTPS. When not provided, keep HTTP-only (for quick dev testing).

---

### 4. RDS Secret Has Potential Dependency Issue

**File:** `infrastructure/modules/rds-postgres/main.tf:30-41`

The Secrets Manager secret version references `aws_db_instance.this.address` — this should work because Terraform handles the implicit dependency, but the value won't be available until the RDS instance finishes creating (10-15 min). If state is interrupted mid-apply, the secret may have an empty host.

**Why it matters:** Applications reading the secret may get an empty `host` field if there's a partial apply.

**Fix:** Add explicit `depends_on = [aws_db_instance.this]` to the secret version resource for clarity.

---

## Important (Fix Soon)

### 5. CLI Output Parsing Doesn't Match Terraform Format

**File:** `cli/src/commands/create.ts:184-196` and `cli/src/lib/environments.ts`

Terraform's `-json` output format is `{"key": {"value": "actual_value", "type": "string"}}`. The CLI expects flat `{"key": "actual_value"}`.

**Why it matters:** After provisioning, users see "Outputs not yet available" even though outputs exist. They never see the ALB endpoint URL without running `idp list` or checking S3 manually.

**Fix:** When parsing `outputs.json`, extract `.value` from each nested output object.

---

### 6. TTL Cleanup Runs Only Once Daily

**File:** `.github/workflows/ttl-cleanup.yml:11-12`

Cron runs at 06:00 UTC. An environment expiring at 07:00 UTC won't be cleaned until the next day.

**Why it matters:** Up to 23 hours of extra charges per expired environment. NAT gateway alone costs ~$1/day.

**Fix:** Change cron to every 4 hours: `"0 */4 * * *"`. Consider every 1 hour for tighter cost control.

---

### 7. TTL Cleanup Race Condition

**File:** `.github/workflows/ttl-cleanup.yml:158-178`

If cleanup marks an environment as "destroying" but then fails to trigger the destroy workflow, the environment gets stuck. Future cleanup runs skip it because status is "destroying".

**Why it matters:** Stuck environments accumulate cost indefinitely with no self-healing.

**Fix:** Add a timestamp to the "destroying" status. In cleanup, treat any environment that's been "destroying" for >2 hours as failed and retry.

---

### 8. Extend Command Overwrites TTL Metadata

**File:** `cli/src/commands/extend.ts:53-58`

When extending by 7d, the metadata's `ttl` field becomes "7d" (the extension) instead of the total elapsed TTL. This makes the field misleading.

**Why it matters:** Audit logs and cost tracking reference `ttl` — if it says "2h" but the environment runs for 26h (original 24h + 2h extension), reports are wrong.

**Fix:** Drop the `ttl` field from metadata updates during extend. The `created_at` and `expires_at` fields are the source of truth.

---

### 9. GitHub PAT Stored in Plain Text

**File:** `cli/src/lib/config.ts`

The Conf library writes tokens to `%APPDATA%\mini-idp-nodejs\Config\config.json` in clear text.

**Why it matters:** Any process running as the user can read the token and trigger infrastructure provisioning.

**Fix:** Use `keytar` or the native OS credential store (Windows Credential Manager, macOS Keychain, Linux Secret Service).

---

### 10. Workflow Timeout Too Short for RDS

**File:** `cli/src/lib/github.ts:63`

CLI waits 15 minutes for workflow completion. RDS provisioning alone takes 10-15 minutes. The `api-database` template will almost certainly time out.

**Why it matters:** Users see a timeout error but resources continue creating in the background. They might re-trigger, creating duplicates.

**Fix:** Increase to 30 minutes, or make it template-aware (15 min for `api-service`, 30 min for `api-database`).

---

## Nice-to-Have (Operational Polish)

### 11. Single NAT Gateway = Single AZ Failure

**File:** `infrastructure/modules/networking/main.tf:88-107`

One NAT gateway serves both private subnets. If that AZ goes down, all private networking fails.

**Why it matters:** Acceptable for dev/test. Problematic if someone uses this for staging with uptime expectations.

**Fix:** Add a `high_availability` variable. When true, create one NAT gateway per AZ. Default to false (cost-optimized).

---

### 12. No Monitoring or Alerting on Provisioned Resources

No CloudWatch alarms are created for ECS task failures, ALB 5xx rates, RDS CPU/storage, or NAT bandwidth.

**Why it matters:** Users have zero visibility into their environments' health without manual CloudWatch setup.

**Fix:** Add a `monitoring` submodule that creates baseline alarms (task crash count, 5xx rate > 5%, CPU > 80%) with an SNS topic output.

---

### 13. No Environment Update Capability

Users can create and destroy but cannot update a running environment (new image version, different CPU/memory, new env vars). Updating requires destroy + recreate.

**Why it matters:** Zero-downtime deployments are impossible. Developers lose their environment state on every update.

**Fix:** Add `idp update <name> --image <new-image>` that triggers a targeted `tofu apply` with updated variables.

---

### 14. No VPC Flow Logs

**File:** `infrastructure/modules/networking/main.tf`

VPCs have no flow logs enabled.

**Why it matters:** No network traffic visibility for security investigations. Fails AWS CIS Benchmark 2.9.

**Fix:** Add VPC flow logs to CloudWatch Logs with retention matching the environment TTL.

---

### 15. Container Insights Inconsistency

`ecs-service` enables Container Insights; `scheduled-task` disables it.

**Why it matters:** Inconsistent observability. Scheduled task failures are harder to debug.

**Fix:** Enable for both, or make it a configurable variable defaulting to `enabled`.

---

### 16. No Cost Visibility for Users

Users have no way to see how much their environments cost.

**Why it matters:** No accountability, no awareness of cost impact.

**Fix:** Add `idp cost [name]` command that queries AWS Cost Explorer with `idp:environment` tag filter.

---

### 17. Duplicate TTL Parsing Logic

TTL parsing (`"7d"` → seconds) is duplicated in:
- `cli/src/commands/create.ts:52-65`
- `cli/src/commands/extend.ts:10-14`
- `.github/workflows/provision.yml:74-84`

**Fix:** Extract to a shared `parseTTL()` utility in the CLI. The workflow copy is unavoidable (bash vs TypeScript) but the CLI copies should share code.

---

### 18. Log Retention Outlives Environments

Default log retention is 7 days. A 2-hour TTL environment's logs persist for 7 days after the environment is gone.

**Why it matters:** Minor cost leak. CloudWatch Logs pricing is per GB ingested + stored.

**Fix:** Match log retention to TTL, or default to 1 day for ephemeral environments.

---

### 19. No Input Validation in Workflows

GitHub Actions workflows trust all inputs. Environment names with special characters, malformed schedule expressions, or invalid ARNs are passed straight to Terraform.

**Fix:** Add a validation step early in each workflow that checks:
- Environment name matches `^[a-z0-9-]+$`
- TTL matches `^\d+[dh]$`
- Schedule expression is valid cron/rate

---

### 20. No Terraform State Lock Cleanup

If a workflow is cancelled mid-apply, the DynamoDB lock persists forever. Subsequent provisions fail with "state locked".

**Fix:** Add lock timeout to backend config. Add `idp unlock <name>` CLI command for manual recovery.

---

## Evolution Options

These are directions to grow the project beyond its current scope.

### A. Self-Service Portal (Web UI)

Replace or supplement the CLI with a web dashboard. Stack: Next.js or plain React, backed by the same GitHub Actions API.

**What it enables:**
- Non-technical users can provision environments
- Visual environment management (status, TTL countdown, costs)
- Approval workflows with manager sign-off
- Team-wide environment visibility

**Effort:** Medium. The API layer (GitHub Actions + S3 metadata) already exists. The UI is additive.

---

### B. Custom Domain Names via Route 53

Add automatic DNS record creation so environments get friendly URLs like `test-app.dev.yourcompany.com` instead of `test-app-alb-1143789646.us-east-1.elb.amazonaws.com`.

**What it enables:**
- Shareable, memorable URLs
- HTTPS via ACM DNS validation
- Easier integration testing with real domain names

**Effort:** Low. Add a Route 53 hosted zone data source + `aws_route53_record` to the ECS service module.

---

### C. Multi-Region Support

Currently hardcoded to `us-east-1`. Add region as a CLI parameter.

**What it enables:**
- Latency-optimized environments for global teams
- Region-specific compliance (EU data residency)
- Disaster recovery testing

**Effort:** Medium. Requires parameterizing region throughout, ensuring OIDC trust policy covers all regions, and separate state prefixes per region.

---

### D. GitOps Integration

Instead of CLI-triggered workflows, provision environments automatically from branch pushes. A PR branch `feature/payment-api` auto-creates an environment; merging destroys it.

**What it enables:**
- True ephemeral preview environments
- No manual CLI interaction needed
- Environments tied to feature branch lifecycle

**Effort:** Medium. Add a `push` trigger to provision.yml with branch-to-environment-name mapping.

---

### E. Template Marketplace

Allow teams to define and publish their own templates beyond the three built-in ones. Templates live in a `templates/` directory and are discovered dynamically.

**What it enables:**
- Lambda + API Gateway template
- Static site (S3 + CloudFront) template
- Kafka/MSK template
- Teams own their infrastructure patterns

**Effort:** Low-Medium. The template system is already modular. Add template discovery to the CLI and a template manifest format.

---

### F. Cost Budgets and Guardrails

Integrate with AWS Budgets to enforce per-user or per-team spending limits. Block new provisions when budget is exceeded.

**What it enables:**
- Financial accountability
- Prevent runaway costs from forgotten environments
- Per-team chargeback

**Effort:** Medium. Requires AWS Budgets API integration, user/team mapping, and pre-provision budget checks.

---

### G. Secrets Injection Pipeline

Add a secure way to inject application secrets into environments without manual Secrets Manager edits. Use the CLI to set key-value pairs that flow into ECS task environment variables.

**What it enables:**
- `idp secrets set test-app DATABASE_URL=postgres://...`
- Secrets populated before first task starts
- Rotation support

**Effort:** Low-Medium. The Secrets Manager secret already exists. Add CLI commands and a small workflow step.

---

### H. Observability Stack

Bundle Grafana + Prometheus (or CloudWatch dashboards) as an optional add-on. Auto-create dashboards per environment.

**What it enables:**
- One-click observability for any environment
- Pre-built dashboards for ECS, ALB, RDS metrics
- Log aggregation and search

**Effort:** Medium-High. Consider using AWS-managed Grafana or a shared observability account.
