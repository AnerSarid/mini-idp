# Architecture

## Overview

Mini IDP follows a three-layer architecture:

1. **Interface layer** — CLI tool on the developer's laptop
2. **Orchestration layer** — GitHub Actions workflows
3. **Infrastructure layer** — OpenTofu modules deployed to AWS

## Data Flow

### Provisioning

```
1. Developer runs `idp create --template api-database --name foo --ttl 7d`
2. CLI validates inputs, shows cost estimate, confirms with user
3. CLI triggers GitHub Actions `provision.yml` via workflow_dispatch API
4. Workflow:
   a. Authenticates to AWS via OIDC (no stored credentials)
   b. Generates tfvars from inputs + computed timestamps
   c. Runs `tofu init` with per-environment backend key
   d. Runs `tofu plan` + `tofu apply`
   e. Uploads outputs.json and metadata.json to S3
5. CLI polls workflow status, displays results
```

### Destruction

```
1. Developer runs `idp destroy foo`
2. CLI triggers `destroy.yml` workflow
3. Workflow reads metadata.json from S3 to determine template
4. Runs `tofu destroy` against the correct template
5. Cleans up S3 artifacts
```

### TTL Cleanup

```
1. `ttl-cleanup.yml` runs every 4 hours via cron
2. Lists all environments in S3
3. Checks each metadata.json for expiry
4. Triggers destroy workflow for any expired environments
```

### GitOps Preview Environments

```
1. Developer pushes to branch feature/payment-api
2. preview-env.yml triggers automatically (push to non-main branch)
3. Branch name is sanitized: feature/payment-api → preview-payment-api
4. Workflow reads .idp/config.yml from repo root (or uses defaults)
5. If environment already exists and is active:
   a. Extends expires_at timestamp in S3 metadata
   b. Posts/updates PR comment with environment details
6. If environment doesn't exist:
   a. Calls provision.yml as a reusable workflow
   b. Posts PR comment with ALB endpoint and logs link
7. On PR merge or branch delete:
   a. preview-env.yml triggers (pull_request closed / delete event)
   b. Calls destroy.yml as a reusable workflow
```

### Per-Repo Configuration

Each repository can include `.idp/config.yml` to customize preview environments:

```yaml
template: api-service          # api-service | api-database | scheduled-worker
container_image: myorg/app     # Docker image to deploy
container_port: 3000           # Port the container listens on
ttl: 7d                        # Auto-extended on every push
```

If `.idp/config.yml` is absent, defaults apply: `api-service`, `nginx:alpine`, port `80`, `7d` TTL.

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
s3://mini-idp-terraform-state/environments/{name}/terraform.tfstate
```

Environment metadata and outputs are stored alongside:
```
s3://mini-idp-terraform-state/environments/{name}/metadata.json
s3://mini-idp-terraform-state/environments/{name}/outputs.json
```

DynamoDB provides state locking to prevent concurrent modifications.

## Module Composition

Templates compose reusable modules:

```
api-service    = networking + common + ecs-service
api-database   = networking + common + ecs-service + rds-postgres
scheduled-worker = networking + common + scheduled-task
```

Each module is independently testable and versioned. Adding a new template means composing existing modules in a new combination.

## Workflow Composition

Workflows follow a reusable pattern to avoid duplication:

```
preview-env.yml (GitOps automation)
  ├── calls provision.yml (for new environments)
  └── calls destroy.yml (on branch delete / PR merge)

CLI (manual / scripted use)
  ├── triggers provision.yml via workflow_dispatch
  └── triggers destroy.yml via workflow_dispatch

ttl-cleanup.yml (scheduled cleanup)
  └── triggers destroy.yml via gh CLI
```

Both `provision.yml` and `destroy.yml` support two trigger types:
- `workflow_dispatch` — for manual/API invocation (CLI, `gh workflow run`)
- `workflow_call` — for composition by other workflows (preview-env)

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
| AWS auth | GitHub OIDC → IAM role assumption |
| IAM | Separate execution role (ECS agent) and task role (container) |
| Network | Private subnets for compute/data, public only for ALB |
| Secrets | AWS Secrets Manager, never in env vars or logs |
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
