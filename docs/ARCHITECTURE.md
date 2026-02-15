# Architecture

## Overview

Mini IDP follows a three-layer architecture:

1. **Interface layer** — CLI tool on the developer's laptop
2. **Orchestration layer** — GitHub Actions workflows (reusable cross-repo)
3. **Infrastructure layer** — OpenTofu modules deployed to AWS

## Data Flow

### GitOps Preview Environments (Primary Path)

```
1. Developer pushes to branch feature/payment-api
2. preview-env.yml triggers automatically (push to non-main branch)
3. Branch name is sanitized: feature/payment-api → preview-payment-api
4. Workflow reads .idp/config.yml from repo root (or uses defaults)
5. If Dockerfile exists:
   a. Builds Docker image with branch-specific tag
   b. Pushes to ECR (shared mini-idp-preview repository)
6. If environment doesn't exist:
   a. Calls provision.yml as a reusable workflow
   b. Posts PR comment with HTTPS endpoint and logs link
7. If environment already exists and is active:
   a. Extends expires_at timestamp in S3 metadata
   b. Redeploys with the new container image (ECS force-new-deployment)
   c. Updates PR comment
8. On PR merge or branch delete:
   a. preview-env.yml triggers (pull_request closed / delete event)
   b. Calls destroy.yml as a reusable workflow
   c. Cleans up ECR images, S3 state artifacts, and DynamoDB locks
```

### Cross-Repo Workflow Pattern

Consumer repos reference mini-idp's reusable workflows without duplicating infrastructure code:

```
Consumer repo (e.g. mini-idp-demo-app)          mini-idp (platform repo)
┌─────────────────────────────────┐    ┌──────────────────────────────────┐
│ .github/workflows/              │    │ .github/workflows/               │
│   preview-env.yml               │    │   provision.yml  (workflow_call) │
│     - setup (branch name, config)│───→│   destroy.yml    (workflow_call) │
│     - build-image (ECR push)    │    │   update-dashboard.yml           │
│     - provision/extend/destroy  │    │                                  │
│                                 │    │ infrastructure/                  │
│ .idp/config.yml                 │    │   templates/                     │
│ Dockerfile                      │    │   modules/                       │
│ (application code)              │    │   shared/                        │
└─────────────────────────────────┘    └──────────────────────────────────┘
```

**Key design decisions:**

- `preview-env.yml` must live in each consumer repo because it triggers on `push`/`delete`/`pull_request` events and needs to checkout the consumer's code (for Dockerfile and config).
- `provision.yml`, `destroy.yml`, and `update-dashboard.yml` are reusable workflows (`on: workflow_call`) that live in mini-idp and are called cross-repo via absolute refs: `uses: YOUR-ORG/mini-idp/.github/workflows/provision.yml@main`.
- When a reusable workflow runs cross-repo, `actions/checkout@v4` defaults to the **caller's** repo. The reusable workflows explicitly checkout `repository: YOUR-ORG/mini-idp` to access Terraform templates.
- `${{ vars.* }}` in reusable workflows resolve to the **called** workflow's repository variables (mini-idp), which is the correct behavior for platform-level configuration.

### CLI-Triggered Provisioning

```
1. Developer runs `idp create --template api-database --name foo --ttl 7d`
2. CLI validates inputs, shows cost estimate, confirms with user
3. CLI triggers GitHub Actions `provision.yml` via workflow_dispatch API
4. Workflow:
   a. Authenticates to AWS via OIDC (no stored credentials)
   b. Generates tfvars from inputs + computed timestamps
   c. Runs `tofu init` with -backend-config flags for bucket/region/table/key
   d. Runs `tofu plan` + `tofu apply`
   e. Uploads outputs.json and metadata.json to S3
5. CLI polls workflow status, displays results
```

### Destruction

```
1. Developer runs `idp destroy foo` or deletes the feature branch
2. Workflow reads metadata.json from S3 to determine template
3. Runs `tofu init` with same -backend-config flags
4. Runs `tofu destroy` against the correct template
5. Cleans up: S3 artifacts, ECR images tagged with environment prefix, DynamoDB locks
```

### TTL Cleanup

```
1. ttl-cleanup.yml runs every 4 hours via cron
2. Lists all environments in S3
3. Checks each metadata.json for expiry
4. Triggers destroy workflow for any expired environments
5. Handles stuck "destroying" states (retries after 2 hours)
```

### Per-Repo Configuration

Each repository includes `.idp/config.yml` to customize preview environments:

```yaml
template: api-service          # api-service | api-database | scheduled-worker
container_port: 3000           # Port the container listens on
ttl: 7d                        # Auto-extended on every push
cpu: 256                       # Fargate CPU units
memory: 512                    # Fargate memory in MiB
log_retention_days: 3          # CloudWatch log retention

# Docker build config (auto-detected)
dockerfile: Dockerfile
build_context: .

# Environment variables
environment:
  NODE_ENV: preview
  LOG_LEVEL: debug

# Secrets (AWS Secrets Manager ARN references)
secrets:
  API_KEY: "arn:aws:secretsmanager:REGION:ACCOUNT:secret:NAME:KEY::"
```

If `.idp/config.yml` is absent, defaults apply: `api-service`, `nginx:alpine`, port `80`, `7d` TTL, 256 CPU, 512 MiB memory.

### Branch Name Sanitization

Branch names are mapped to valid AWS resource names:

```
feature/payment-api     → preview-payment-api
bugfix/auth-token       → preview-auth-token
HOTFIX/Critical_Issue   → preview-critical-issue
release/v2.0            → preview-v2-0
```

The `preview-` prefix distinguishes GitOps environments from CLI-created ones.

## State Management

Each environment gets its own Terraform state file at:
```
s3://{STATE_BUCKET}/environments/{name}/terraform.tfstate
```

Environment metadata and outputs are stored alongside:
```
s3://{STATE_BUCKET}/environments/{name}/metadata.json
s3://{STATE_BUCKET}/environments/{name}/outputs.json
```

DynamoDB provides state locking to prevent concurrent modifications.

### Parameterized Backend

All Terraform backend blocks use **partial configuration** — no hardcoded bucket, region, or table names in `.tf` files. Values are provided at init time:

- **In CI**: `-backend-config` flags populated from GitHub repo variables (`${{ vars.STATE_BUCKET }}`, etc.)
- **Locally**: A shared `infrastructure/backend.conf` file containing bucket/region/table values

This makes the platform portable across teams and AWS accounts.

## Container Build Pipeline

When a Dockerfile is found in the repository:

```
1. preview-env.yml detects Dockerfile (configurable path via config.yml)
2. Logs into ECR using aws-actions/amazon-ecr-login
3. Builds image with tag: {environment_name}-{short_sha}
4. Pushes to shared ECR repository (configurable via vars.ECR_REPO)
5. Passes full image URI to provision/extend workflow
6. On destroy: batch-deletes all ECR images matching environment prefix
```

ECR lifecycle policies automatically expire:
- Untagged images after 1 day
- Old tagged images beyond 50 per prefix

### ECR Pull-Through Cache

An optional Docker Hub pull-through cache avoids rate limits during concurrent builds. When configured (via `dockerhub_username` and `dockerhub_access_token` variables in the ecr-preview module), Docker Hub images are cached in ECR at `{account}.dkr.ecr.{region}.amazonaws.com/docker-hub/{image}`.

## Module Composition

Templates compose reusable modules:

```
api-service      = networking + common + ecs-service
api-database     = networking + common + ecs-service + rds-postgres
scheduled-worker = networking + common + scheduled-task
```

Each module is independently testable and versioned. Adding a new template means composing existing modules in a new combination. See [ADDING_TEMPLATES.md](ADDING_TEMPLATES.md).

## Workflow Composition

```
preview-env.yml (GitOps automation — lives in consumer repo)
  ├── calls provision.yml (for new environments)          ← cross-repo
  ├── calls provision.yml (for extend + redeploy)         ← cross-repo
  ├── calls destroy.yml (on branch delete / PR merge)     ← cross-repo
  └── calls update-dashboard.yml (after any change)       ← cross-repo

CLI (manual / scripted use)
  ├── triggers provision.yml via workflow_dispatch
  └── triggers destroy.yml via workflow_dispatch

ttl-cleanup.yml (scheduled cleanup)
  └── triggers destroy.yml via gh CLI
```

Both `provision.yml` and `destroy.yml` support two trigger types:
- `workflow_dispatch` — for manual/API invocation (CLI, `gh workflow run`)
- `workflow_call` — for composition by other workflows (preview-env, cross-repo)

## Networking

Each environment gets its own VPC with:
- 2 public subnets (ALB) across 2 AZs
- 2 private subnets (ECS, RDS) across 2 AZs
- 1 NAT gateway (cost-optimized, not HA)
- Internet gateway for public subnets

This provides full network isolation between environments.

## Security Model

| Concern | Approach |
|---------|----------|
| AWS auth | GitHub OIDC → IAM role assumption (no stored credentials) |
| IAM | Scoped to `idp-*` resources; separate execution role and task role |
| Network | Private subnets for compute/data, public only for ALB |
| HTTPS | ACM wildcard certificate, HTTP → HTTPS redirect |
| Secrets | AWS Secrets Manager, injected via ECS `valueFrom` |
| Deployment | Circuit breaker with automatic rollback on consecutive failures |
| Audit | GitHub Actions history as complete audit trail |

## Tagging Strategy

All resources carry these tags for cost attribution and lifecycle management:

```
idp:managed     = true
idp:environment = {name}
idp:template    = {template}
idp:owner       = {email}
idp:created-at  = {ISO 8601}
idp:ttl         = {duration}
idp:expires-at  = {ISO 8601}
cost-center     = engineering
```

## Adopting for a New Team

To deploy mini-idp for a different team or AWS account:

1. Set 4 GitHub repo variables: `AWS_REGION`, `STATE_BUCKET`, `LOCK_TABLE`, `ECR_REPO`
2. Set 3 preview-specific variables: `PREVIEW_DOMAIN`, `PREVIEW_ZONE_ID`, `PREVIEW_ACM_CERT_ARN`
3. Set the `AWS_ROLE_ARN` secret with your IAM role ARN
4. Update `infrastructure/backend.conf` with your bucket/region/table values
5. Optionally configure CLI: `idp config set aws.stateBucket your-bucket`
