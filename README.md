# Mini IDP - Internal Developer Platform

A lightweight, self-service Internal Developer Platform that lets developers provision fully-configured AWS environments through a CLI — without writing Terraform or understanding AWS internals.

## What It Does

Developers pick a template, give it a name, and get a running environment in minutes:

```bash
idp create --template api-database --name my-feature --owner me@example.com --ttl 7d
```

The platform handles VPC, security groups, IAM roles, load balancers, databases, secrets, logging, and automatic cleanup.

## Templates

| Template | What You Get |
|----------|-------------|
| `api-service` | ECS Fargate + ALB + CloudWatch + Secrets Manager |
| `api-database` | Everything above + RDS PostgreSQL |
| `scheduled-worker` | ECS Scheduled Task + CloudWatch + optional S3 access |

## Architecture

```
Developer → CLI → GitHub Actions → OpenTofu → AWS
                                       ↕
                                   S3 (state + metadata)
```

- **CLI**: TypeScript tool that triggers GitHub Actions and reads environment state from S3
- **GitHub Actions**: Orchestrates OpenTofu plan/apply with OIDC-based AWS auth
- **Infrastructure**: Modular OpenTofu/Terraform with composable templates
- **State**: S3 + DynamoDB backend with per-environment state isolation

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for details.

## Prerequisites

- AWS account with OIDC provider configured for GitHub Actions
- GitHub repository with `AWS_ROLE_ARN` secret
- Node.js 18+
- AWS CLI configured (for the CLI's S3 reads)

## Quick Start

### 1. AWS Bootstrap

Create the Terraform state backend and OIDC provider:

```bash
# Create S3 bucket for state
aws s3api create-bucket --bucket mini-idp-terraform-state --region us-east-1

# Enable versioning
aws s3api put-bucket-versioning --bucket mini-idp-terraform-state \
  --versioning-configuration Status=Enabled

# Create DynamoDB table for state locking
aws dynamodb create-table \
  --table-name mini-idp-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST

# Set up GitHub OIDC provider (see docs/RUNBOOK.md for IAM role details)
```

### 2. Install the CLI

```bash
cd cli
npm install
npm run build
npm link  # makes `idp` available globally
```

### 3. Authenticate

```bash
idp auth login
# Enter your GitHub personal access token (needs repo + workflow scopes)
# Enter your GitHub username/org and repo name
```

### 4. Provision

```bash
# See available templates
idp templates

# Create an environment
idp create --template api-service --name my-app --owner you@example.com --ttl 7d

# List active environments
idp list

# Extend TTL
idp extend my-app --ttl 14d

# Tear down
idp destroy my-app
```

## Project Structure

```
mini-idp/
├── infrastructure/
│   ├── modules/           # Reusable Terraform modules
│   │   ├── networking/    # VPC, subnets, NAT, route tables
│   │   ├── ecs-service/   # Fargate service + ALB
│   │   ├── rds-postgres/  # RDS PostgreSQL + credentials
│   │   ├── scheduled-task/# ECS scheduled task
│   │   └── common/        # IAM roles, logs, secrets
│   ├── templates/         # Composable golden path templates
│   │   ├── api-service/
│   │   ├── api-database/
│   │   └── scheduled-worker/
│   └── environments/      # Generated tfvars (gitignored)
├── cli/                   # TypeScript CLI tool
├── .github/workflows/     # Provision, destroy, TTL cleanup
└── docs/                  # Architecture, runbook
```

## Security

- No long-lived AWS credentials — GitHub OIDC only
- Least-privilege IAM roles per template
- Databases in private subnets, no public IPs
- Secrets in AWS Secrets Manager, never in logs
- Network isolation via per-environment security groups
- Full audit trail via GitHub Actions history

## Cost Awareness

Every resource is tagged with `idp:*` tags for cost attribution. Approximate monthly costs:

| Template | Estimate |
|----------|----------|
| api-service | ~$63/mo |
| api-database | ~$76/mo |
| scheduled-worker | ~$35/mo |

TTL enforcement runs daily and destroys expired environments automatically.

## License

MIT
