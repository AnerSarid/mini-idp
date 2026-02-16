# Mini IDP — Improvements v2

Status update and forward-looking roadmap. Last updated: Feb 2026.
Supersedes the original `IMPROVEMENTS.md` which tracked the initial build's issues.

---

## What's been done since v1

For context, here's what was implemented across the sessions that followed the original improvements doc:

| v1 Item | Status | Notes |
|---------|--------|-------|
| #1 CLI destroy calls wrong workflow | Fixed | `destroy.ts` now calls `destroy.yml` correctly |
| #2 IAM over-scoped | Fixed | Scoped inline policy with `idp-*` resource patterns |
| #3 No HTTPS on ALB | Done | Conditional HTTPS listener + HTTP→HTTPS redirect |
| #4 RDS secret dependency | Done | Explicit `depends_on` added |
| #5 CLI output parsing | Fixed | `flattenTerraformOutputs()` extracts `.value` |
| #6 TTL cleanup runs once daily | Fixed | Changed to every 4 hours |
| #7 TTL cleanup race condition | Fixed | "destroying" timestamp + 2h retry logic |
| #10 Workflow timeout too short | Improved | Raised to 30 minutes |
| #B Custom DNS | Done | `*.preview.anersarid.com` via Route 53 + ACM wildcard |
| #D GitOps integration | Done | Full preview-env.yml: push → provision, PR close → destroy |
| #G Secrets injection | Done | `environment` + `secrets` maps in config.yml → ECS container |

**New features not in v1:**
- Container build pipeline (ECR + Dockerfile auto-detect)
- Environments dashboard (auto-generated `ENVIRONMENTS.md`)
- Extend redesign (code changes on push actually redeploy, not just TTL bump)
- Concurrency fix for dual destroy triggers (PR close + branch delete)

---

## Remaining items from v1 (still valid)

### CLI housekeeping

**1. Duplicate TTL parsing** (v1 #17) — **Done**
Extracted to shared utility `cli/src/lib/ttl.ts` with `validateTtl()` and `parseTtl()`. Both `create.ts` and `extend.ts` import from the shared module.

**2. GitHub PAT in plain text** (v1 #9)
`Conf` stores tokens to `%APPDATA%` as JSON. Use `keytar` or native OS credential store.
Effort: 1-2 hours.

**3. Extend command metadata** (v1 #8) — **Partially fixed**
The extend command now computes `ttl` as the total lifetime from `created_at` to new `expires_at`, rather than blindly overwriting with the extension amount. Still writes the `ttl` field (which could be dropped entirely since `created_at` + `expires_at` are the source of truth).

### Infrastructure polish

**4. Container Insights inconsistency** (v1 #15) — **Done**
Both `ecs-service` and `scheduled-task` modules now have a `container_insights` variable defaulting to `"enabled"`.

**5. Workflow input validation** (v1 #19) — **Done**
Input validation step added to provision.yml: environment names, TTL formats, template names, port numbers, and schedule expressions are all validated before Terraform runs.

**6. Terraform state lock cleanup** (v1 #20) — **Done**
`-lock-timeout=5m` added to all tofu commands. `idp unlock <name>` CLI command implemented for manual recovery.

---

## New improvements

### High priority

**7. Shared networking** — **Done**
Optional shared VPC toggle (`use_shared_networking`) implemented across all templates. When enabled, environments skip per-env VPC/NAT/IGW creation and look up a pre-deployed shared VPC via `terraform_remote_state`. Default is `false` — existing per-env behavior preserved.

Implementation:
- Shared VPC module: `infrastructure/shared/preview-networking/` (deploy once, reuse across envs)
- Templates use `count` on networking module + `locals` to abstract over both per-env and shared sources
- Toggle controlled via `.idp/config.yml`, repo variable `USE_SHARED_NETWORKING`, or workflow input
- Tested E2E: provision (30 resources, no networking), extend, destroy — shared VPC untouched

Impact: provision time drops from ~4 min to ~90 seconds (dominated by RDS for api-database; api-service would be faster). Per-env NAT cost ($1.10/day) eliminated. Shared VPC costs ~$1.10/day regardless of environment count — only worth deploying when running multiple concurrent environments.

**8. Health check configuration**
Health check path is hardcoded to `/` in the ALB target group. Any app without a root handler (e.g. an API on `/api/health`) gets constant 404s and never becomes healthy.

Fix: add `health_check_path` to `.idp/config.yml` and flow it through the same chain as `container_port`. Default: `/`.

Effort: low (1 hour across all layers).

**9. Deploy a real application test** — **Done**
Validated with two real apps:
- `api-service` template: Node.js Express API with /health, /env, /echo endpoints. Full provision → extend → destroy cycle tested.
- `api-database` template: Node.js Express API with PostgreSQL (CRUD on /notes). Tested cross-repo from separate `mini-idp-demo-app` repo. Validated DB connectivity, credential injection, SSL, and full lifecycle.

**10. `idp logs <env-name>`** — **Done**
Implemented in `cli/src/commands/logs.ts`. Wraps `aws logs tail` with `--since` and `--follow` options. Log group pattern: `/ecs/idp-{name}`.

### Medium priority

**11. Resource sizing in config** — **Done**
`cpu` and `memory` fields added to `.idp/config.yml`. Parsed by preview-env.yml, passed through to provision.yml, and written into tfvars. Defaults: 256 CPU, 512 MiB memory.

**12. ALB access logs**
No request logging. Useful for debugging and required by most compliance frameworks.

Fix: create an S3 bucket for ALB logs in shared infrastructure, enable access logging on the ALB resource. Auto-delete logs when the environment is destroyed.

Effort: medium (2 hours).

**13. Log retention matching TTL** — **Done**
`log_retention_days` field added to `.idp/config.yml`. Default changed from 7 to 3 days. Parsed and passed through the full config → workflow → tfvars → CloudWatch chain.

**14. ECR pull-through cache** — **Done**
Implemented in `infrastructure/shared/ecr-preview/main.tf`. Docker Hub pull-through cache with Secrets Manager credential storage. Conditional on `dockerhub_username`/`dockerhub_access_token` variables. Images cached at `{account}.dkr.ecr.{region}.amazonaws.com/docker-hub/{image}`.

### Low priority

**15. ECS deployment circuit breaker** — **Done**
Added `deployment_circuit_breaker { enable = true, rollback = true }` to `aws_ecs_service` in `infrastructure/modules/ecs-service/main.tf`.

**16. Parameterize hardcoded values** — **Done**
All hardcoded values replaced across 15 files:
- Workflows: `${{ vars.AWS_REGION }}`, `${{ vars.STATE_BUCKET }}`, `${{ vars.LOCK_TABLE }}`, `${{ vars.ECR_REPO }}`
- Terraform: Partial backend configuration via `-backend-config` flags + `infrastructure/backend.conf`
- CLI: `config.ts` gains `lockTable` and `ecrRepo` fields; `unlock.ts` reads from config
- ECR: Repository name extracted to `var.ecr_repo_name`

**17. NAT gateway HA option**
Single NAT gateway in AZ-a means AZ failure kills all private networking. Add a `high_availability` variable that creates one NAT per AZ when enabled.

For ephemeral dev environments this doesn't matter. Flag it for future staging/production use.

Effort: low (30 minutes in networking module).

**18. VPC flow logs**
No network traffic visibility. Fails AWS CIS Benchmark 2.9.

Add as an optional feature in the networking module. Log to CloudWatch with retention matching environment TTL.

Effort: low (30 minutes).

---

## Evolutions

Larger directional bets for growing mini-idp beyond its current scope. These are not bugs or polish — they're strategic choices about what the platform becomes.

### I. Shared EKS cluster + namespace-per-environment

**What:** Instead of ECS Fargate per environment, run a shared EKS cluster. Each preview environment is a Kubernetes namespace with an ArgoCD Application CR for GitOps sync.

**Why:**
- Provision time drops from ~4 min to ~15 seconds (just namespace + manifests)
- Cost is shared (cluster + node group is fixed, environments only consume pod resources)
- Aligns with how most production teams actually deploy (Kubernetes, not ECS)
- ArgoCD gives real-time sync status, self-healing, and drift detection

**Trade-offs:**
- Shared cluster is a bigger blast radius than isolated ECS per env
- EKS cluster is expensive (~$75/month for control plane alone) — only makes sense with 5+ concurrent environments
- Operational complexity: you're now running a Kubernetes cluster

**Architecture:** Terraform creates namespace + ResourceQuota + ArgoCD Application. ArgoCD syncs the branch's `k8s/` directory into the namespace. DNS points to the shared ingress controller's ALB. The mini-idp workflow structure stays the same (setup → provision → destroy).

**Effort:** High. Shared EKS cluster setup is 1-2 days. Template itself is ~half a day. Total: 2-3 days.

### II. Template ecosystem

**What:** Let teams define their own infrastructure templates beyond the three built-in ones (api-service, api-database, scheduled-worker). Templates are Terraform modules in a `templates/` directory, discovered dynamically.

**Examples of new templates:**
- `static-site` — S3 + CloudFront for frontend SPAs
- `lambda-api` — API Gateway + Lambda (serverless, no ECS)
- `kafka-consumer` — MSK topic + consumer ECS service
- `ml-training` — SageMaker training job + S3 I/O

**Why:** The current templates cover 80% of use cases. The remaining 20% either don't fit (serverless, ML) or require awkward workarounds. Letting teams add templates means the platform grows with adoption.

**Architecture:** Each template is a self-contained Terraform root module with a standard interface (variables: `environment_name`, `owner`, `ttl`, `created_at`, `expires_at`, plus template-specific vars). The workflow already routes by template name. Add a `template.json` manifest in each template directory for CLI discovery (description, required config fields, expected outputs).

**Effort:** Low-medium. The mechanism already works. The work is documenting the interface contract and building 1-2 example community templates.

### III. Multi-region

**What:** Allow environments to be provisioned in any AWS region, not just `us-east-1`.

**Why:** Global teams need low-latency environments. EU teams may have data residency requirements. Disaster recovery testing needs multi-region.

**What it requires:**
- Parameterize region everywhere (workflows, backends, provider blocks)
- State key includes region: `environments/{name}/{region}/terraform.tfstate`
- OIDC trust policy must allow the same role in all regions (already works — OIDC is global)
- ACM certs are region-specific — either one wildcard per region, or use CloudFront (global cert)
- DNS delegation works across regions (Route 53 is global)

**Effort:** Medium. Mostly a search-and-replace + testing exercise. The architecture doesn't change.

### IV. Cost controls

**What:** Per-user or per-team spending guardrails. Budget alerts, automatic shutdown when limits are hit, cost attribution.

**Layers:**
1. **Visibility** — `idp cost [name]` CLI command using AWS Cost Explorer filtered by `idp:environment` tag. Shows daily burn rate and projected monthly cost.
2. **Alerts** — AWS Budgets integration. SNS notification when team spending crosses threshold.
3. **Guardrails** — Pre-provision budget check. Block new environments if team budget is exhausted.
4. **Chargeback** — Monthly cost report per team/owner, exported to S3 for finance.

Start with layer 1 (visibility). Don't build layers 3-4 until there's real multi-team usage.

**Effort:** Layer 1 is low (2 hours). Layer 2 is medium (half day). Layers 3-4 are high and premature.

### V. Web dashboard (replacing ENVIRONMENTS.md)

**What:** A lightweight web UI that shows active environments, their status, logs, and actions (extend, destroy). Not a full admin portal — just a read-heavy dashboard with a few action buttons.

**Why `ENVIRONMENTS.md` is good enough for now:**
- It's zero-infrastructure (just a file in the repo)
- It updates automatically via GitHub Actions
- Anyone with repo access can see it
- It's searchable, linkable, and version-controlled

**When to upgrade:**
- More than ~10 concurrent environments (markdown table gets unwieldy)
- Non-technical stakeholders need access (PMs, QA leads)
- You want real-time status instead of last-commit-time freshness

**Architecture if you build it:** Static site (React or even plain HTML) hosted on S3/CloudFront. Reads environment data from S3 metadata (same bucket the workflows already write to). GitHub OAuth for authentication. No backend server needed.

**Effort:** Medium. 2-3 days for a useful MVP. But don't build it yet.

### VI. `idp` CLI v2

**What:** The CLI exists but is secondary to the GitOps workflow. If you invest in CLI improvements, focus on operations rather than provisioning (GitOps handles that):

- `idp logs <env-name>` — tail CloudWatch logs (highest priority)
- `idp status [env-name]` — show environment health (ECS task status, ALB health, last deploy)
- `idp exec <env-name> -- <command>` — ECS Exec into the running container
- `idp cost [env-name]` — show cost breakdown
- `idp unlock <env-name>` — break a stuck Terraform state lock

**Why not `idp create`/`idp destroy`:** GitOps (push a branch / close a PR) is a better UX than running CLI commands. The CLI should be for observability and troubleshooting, not for lifecycle management.

**Effort:** Each command is 1-2 hours. `idp logs` is the clear winner for effort-to-value ratio.

---

## Status Summary

### Completed
- #1 Duplicate TTL parsing — shared `cli/src/lib/ttl.ts` utility ✅
- #4 Container Insights — both modules default to `"enabled"` ✅
- #5 Workflow input validation ✅
- #6 Terraform state lock cleanup (`idp unlock`) ✅
- #9 Real application E2E test (api-service + api-database cross-repo) ✅
- #10 `idp logs` CLI command ✅
- #11 Resource sizing in config (cpu/memory) ✅
- #13 Log retention matching TTL ✅
- #14 ECR pull-through cache ✅
- #15 ECS deployment circuit breaker ✅
- #16 Parameterize hardcoded values ✅
- #7 Shared networking (optional toggle, `terraform_remote_state` lookup) ✅

### Remaining
- #2 GitHub PAT in plain text — use OS credential store
- #3 Extend command metadata — partially fixed (computes total lifetime, but still writes `ttl` field)
- #8 **Health check path** — unblocks non-root-handler apps
- #12 ALB access logs
- #17 NAT gateway HA option
- #18 VPC flow logs

### Recommended next priorities
1. **Health check path** (#8) — quick win, unblocks real-world apps
2. **Template ecosystem** (Evolution II) — enable team self-service
3. **Cost visibility** (Evolution IV) — `idp cost` command
