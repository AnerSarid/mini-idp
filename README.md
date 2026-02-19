# Mini IDP - Internal Developer Platform

A lightweight, self-service Internal Developer Platform that provisions fully-configured AWS preview environments on every feature branch push — no Terraform knowledge required.

## How It Works

Push a branch, get an environment. Merge or delete the branch, it's destroyed automatically.

```
1. Developer pushes to feature/payment-api
2. GitHub Actions builds the Docker image, provisions AWS infrastructure
3. Environment is live at https://preview-payment-api.preview.yourdomain.com
4. Every subsequent push redeploys the app and extends the TTL
5. PR merge or branch delete triggers full teardown
```

All configuration lives in a single `.idp/config.yml` file in your repository.

## Templates

| Template | What You Get |
|----------|-------------|
| `api-service` | VPC + ECS Fargate + ALB + HTTPS + CloudWatch + Secrets Manager |
| `api-database` | Everything above + RDS PostgreSQL (credentials auto-injected) |
| `scheduled-worker` | VPC + ECS Scheduled Task + CloudWatch + optional S3 access |

## Architecture

```
Developer pushes branch
        ↓
GitHub Actions (preview-env.yml)
   ├── Build Docker image → ECR
   └── Provision / Extend / Destroy
        ↓
Reusable workflows (provision.yml / destroy.yml)
        ↓
OpenTofu → AWS (VPC, ECS, ALB, RDS, Route 53, ACM, Secrets Manager)
        ↓
S3 (state + metadata + tfvars + outputs)
```

- **GitOps**: Automatic preview environments tied to branch lifecycle
- **Cross-repo**: Consumer repos reference mini-idp's reusable workflows — no copy-paste
- **CLI**: TypeScript tool for observability (`idp logs`, `idp list`) and troubleshooting (`idp unlock`)
- **State**: S3 + DynamoDB backend with per-environment isolation
- **Parameterized**: All infrastructure values (region, bucket, ECR repo) configurable via GitHub repo variables

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full design.

## Quick Start

### 1. AWS Bootstrap

```bash
# Create S3 bucket for Terraform state
aws s3api create-bucket --bucket YOUR-STATE-BUCKET --region YOUR-REGION
aws s3api put-bucket-versioning --bucket YOUR-STATE-BUCKET \
  --versioning-configuration Status=Enabled

# Create DynamoDB table for state locking
aws dynamodb create-table \
  --table-name YOUR-LOCK-TABLE \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST

# Set up GitHub OIDC provider (see docs/RUNBOOK.md for full IAM setup)
```

### 2. Configure GitHub Repo Variables

In your repository Settings > Variables, set:

| Variable | Example | Description |
|----------|---------|-------------|
| `AWS_REGION` | `us-east-1` | AWS region for all resources |
| `STATE_BUCKET` | `mini-idp-terraform-state` | S3 bucket for Terraform state |
| `LOCK_TABLE` | `mini-idp-terraform-locks` | DynamoDB table for state locking |
| `ECR_REPO` | `mini-idp-preview` | ECR repository name for Docker images |
| `PREVIEW_DOMAIN` | `preview.yourdomain.com` | Base domain for environment URLs |
| `PREVIEW_ZONE_ID` | `Z01234...` | Route 53 hosted zone ID |
| `PREVIEW_ACM_CERT_ARN` | `arn:aws:acm:...` | ACM wildcard certificate ARN |

And one secret:
- `AWS_ROLE_ARN`: IAM role ARN for GitHub OIDC authentication

### 3. Set Up Shared Infrastructure

```bash
# Update infrastructure/backend.conf with your values
# Then init and apply shared resources:

cd infrastructure/shared/preview-dns
tofu init -backend-config=../../backend.conf
tofu apply

cd ../ecr-preview
tofu init -backend-config=../../backend.conf
tofu apply
```

### 4. Add Configuration to Your Repo

Create `.idp/config.yml`:

```yaml
template: api-service          # api-service | api-database | scheduled-worker
container_port: 3000
ttl: 7d

environment:
  NODE_ENV: preview
  LOG_LEVEL: debug
```

Push a feature branch and the preview environment provisions automatically.

## Cross-Repo Usage

Consumer repos reference mini-idp's reusable workflows without copy-pasting infrastructure code:

```yaml
# In your app repo: .github/workflows/preview-env.yml
provision:
  uses: YOUR-ORG/mini-idp/.github/workflows/provision.yml@main
  with:
    template: ${{ needs.setup.outputs.template }}
    environment_name: ${{ needs.setup.outputs.environment_name }}
    # ... other inputs
  secrets: inherit
```

The consumer repo needs:
1. A `.github/workflows/preview-env.yml` (template provided by mini-idp)
2. A `.idp/config.yml` with template and environment config
3. The same GitHub variables/secrets as above

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full cross-repo workflow pattern.

## CLI

The CLI provides observability and troubleshooting for preview environments:

```bash
cd cli && npm install && npm run build && npm link

idp auth login              # Authenticate with GitHub
idp list                    # List active environments
idp list --all              # Include expired/destroyed
idp logs my-env             # Tail container logs
idp logs my-env --follow    # Stream logs in real-time
idp unlock my-env           # Force-unlock stuck Terraform state
idp templates               # Show available templates
idp create --template api-service --name my-app --owner me@example.com --ttl 7d
idp extend my-app --ttl 14d
idp destroy my-app
```

### CLI Configuration

```bash
idp config set aws.region us-east-1
idp config set aws.stateBucket my-state-bucket
idp config set aws.lockTable my-lock-table
idp config set aws.ecrRepo my-ecr-repo
```

## Configuration Reference

`.idp/config.yml` supports these fields:

```yaml
# Infrastructure template (required)
template: api-service          # api-service | api-database | scheduled-worker

# Container settings
container_port: 3000           # Port the container listens on (default: 80)
container_image: nginx:alpine  # Only used if no Dockerfile found

# Lifecycle
ttl: 7d                        # Auto-extended on each push (default: 7d)

# Resource sizing (Fargate)
cpu: 256                       # 256 | 512 | 1024 | 2048 | 4096
memory: 512                    # Must be valid for chosen CPU

# CloudWatch log retention
log_retention_days: 3          # 1, 3, 5, 7, 14, 30, 60, or 90 days

# Docker build (auto-detected)
dockerfile: Dockerfile         # Path to Dockerfile
build_context: .               # Docker build context directory

# Plain-text environment variables
environment:
  NODE_ENV: preview
  LOG_LEVEL: debug

# Secrets from AWS Secrets Manager (ECS valueFrom syntax)
secrets:
  API_KEY: "arn:aws:secretsmanager:REGION:ACCOUNT:secret:NAME:KEY::"

# Scheduled worker only
schedule_expression: "rate(1 hour)"
s3_bucket_arn: "arn:aws:s3:::my-bucket"
```

## Project Structure

```
mini-idp/
├── .github/workflows/
│   ├── preview-env.yml        # GitOps: branch push/delete triggers
│   ├── preview-setup.yml      # Reusable: branch name + config parsing
│   ├── provision.yml          # Reusable: tofu plan + apply
│   ├── destroy.yml            # Reusable: tofu destroy + cleanup
│   ├── ttl-cleanup.yml        # Scheduled: destroy expired environments
│   └── update-dashboard.yml   # Reusable: generate ENVIRONMENTS.md
├── infrastructure/
│   ├── backend.conf           # Shared backend config for local runs
│   ├── modules/               # Reusable Terraform modules
│   │   ├── networking/        # VPC, subnets, NAT, route tables
│   │   ├── ecs-service/       # Fargate service + ALB + circuit breaker
│   │   ├── rds-postgres/      # RDS PostgreSQL + auto credentials
│   │   ├── scheduled-task/    # ECS scheduled task + EventBridge
│   │   └── common/            # IAM roles, CloudWatch logs, Secrets Manager
│   ├── templates/             # Golden path infrastructure templates
│   │   ├── _base/             # Shared Terraform files (backend, networking, common)
│   │   ├── api-service/       # VPC + ECS + ALB + HTTPS
│   │   ├── api-database/      # Above + RDS PostgreSQL
│   │   └── scheduled-worker/  # VPC + ECS Scheduled Task
│   └── shared/                # One-time shared infrastructure
│       ├── ecr-preview/       # ECR repo + pull-through cache
│       └── preview-dns/       # Route 53 zone + ACM wildcard cert
├── cli/                       # TypeScript CLI (list, logs, unlock, create, destroy)
├── docs/                      # Architecture, runbook, template guide
└── ENVIRONMENTS.md            # Auto-generated dashboard of active environments
```

## Security

- **No long-lived credentials** — GitHub OIDC for all AWS access
- **Scoped IAM** — All roles limited to `idp-*` prefixed resources
- **Network isolation** — Databases in private subnets, no public IPs
- **Secrets management** — AWS Secrets Manager, never in env vars or logs
- **Deployment safety** — ECS circuit breaker with automatic rollback
- **HTTPS enforced** — ACM wildcard certificate, HTTP → HTTPS redirect
- **Audit trail** — Full history in GitHub Actions

## Cost Awareness

All resources are tagged with `idp:*` tags for cost attribution.

| Template | Estimate |
|----------|----------|
| api-service | ~$35/mo (NAT + Fargate + ALB) |
| api-database | ~$50/mo (above + RDS db.t3.micro) |
| scheduled-worker | ~$15/mo (NAT + Fargate, no ALB) |

TTL enforcement runs every 4 hours and destroys expired environments automatically. ECR lifecycle policies expire unused images after 1 day.

## License

MIT
