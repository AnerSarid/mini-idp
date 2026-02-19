# Operations Runbook

## Initial Setup

### 1. Create AWS OIDC Provider for GitHub Actions

```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

### 2. Create IAM Role for GitHub Actions

Create an IAM role with this trust policy. Replace `YOUR_ORG` and `YOUR_ACCOUNT_ID`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::YOUR_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": [
            "repo:YOUR_ORG/mini-idp:*",
            "repo:YOUR_ORG/YOUR-APP-REPO:*"
          ]
        }
      }
    }
  ]
}
```

> **Note:** Add each consumer repo that needs preview environments to the `sub` condition array.

Attach the scoped custom policy from `infrastructure/idp-permissions.json`. This policy limits access to `idp-*` prefixed resources only.

> **Security note:** Do not use AWS-managed full-access policies (e.g. `AmazonECS_FullAccess`, `AmazonRDSFullAccess`). A compromised GitHub Actions token combined with broad IAM permissions could lead to full AWS account takeover. The scoped policy is the only supported approach.

### 3. Create State Backend

```bash
# S3 bucket for Terraform state
aws s3api create-bucket --bucket YOUR-STATE-BUCKET --region YOUR-REGION
aws s3api put-bucket-versioning --bucket YOUR-STATE-BUCKET \
  --versioning-configuration Status=Enabled

# DynamoDB table for state locking
aws dynamodb create-table \
  --table-name YOUR-LOCK-TABLE \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST
```

### 4. Update backend.conf

Edit `infrastructure/backend.conf` with your values:

```hcl
bucket         = "your-state-bucket"
region         = "your-region"
dynamodb_table = "your-lock-table"
encrypt        = true
```

### 5. Deploy Shared Infrastructure

```bash
# Preview DNS (Route 53 zone + ACM wildcard cert)
cd infrastructure/shared/preview-dns
tofu init -backend-config=../../backend.conf
tofu apply -var="preview_domain=preview.yourdomain.com"

# ECR repository for Docker images
cd ../ecr-preview
tofu init -backend-config=../../backend.conf
tofu apply
```

### 6. Set GitHub Repository Variables

In Settings > Secrets and variables > Actions > Variables:

| Variable | Value | Description |
|----------|-------|-------------|
| `AWS_REGION` | `us-east-1` | AWS region |
| `STATE_BUCKET` | `your-state-bucket` | S3 state bucket name |
| `LOCK_TABLE` | `your-lock-table` | DynamoDB lock table name |
| `ECR_REPO` | `mini-idp-preview` | ECR repository name |
| `PREVIEW_DOMAIN` | `preview.yourdomain.com` | Preview environment base domain |
| `PREVIEW_ZONE_ID` | `Z01234...` | Route 53 hosted zone ID |
| `PREVIEW_ACM_CERT_ARN` | `arn:aws:acm:...` | ACM wildcard certificate ARN |

### 7. Set GitHub Repository Secrets

| Secret | Value | Description |
|--------|-------|-------------|
| `AWS_ROLE_ARN` | `arn:aws:iam::ACCOUNT:role/ROLE` | IAM role for OIDC auth |

### 8. Create GitHub Environment

Create a `production` environment in Settings > Environments. Optionally add protection rules (required reviewers, deployment branches).

### 9. First-Time AWS Service Setup

Some AWS services require a one-time service-linked role:

```bash
# Required before first RDS instance (api-database template)
aws iam create-service-linked-role --aws-service-name rds.amazonaws.com

# Required before first ECS cluster (usually auto-created)
aws iam create-service-linked-role --aws-service-name ecs.amazonaws.com
```

## Cross-Repo Setup

To enable preview environments in a consumer repo:

### 1. Add repo to IAM trust policy

Update the OIDC trust policy to include the new repo:

```bash
# Add "repo:YOUR_ORG/new-app-repo:*" to the sub condition array
aws iam update-assume-role-policy --role-name YOUR-ROLE --policy-document file://trust-policy.json
```

### 2. Set variables and secrets on the consumer repo

Set the same GitHub variables and secrets on the consumer repo:

```bash
gh variable set AWS_REGION --body "us-east-1" --repo YOUR_ORG/new-app-repo
gh variable set STATE_BUCKET --body "your-state-bucket" --repo YOUR_ORG/new-app-repo
gh variable set ECR_REPO --body "mini-idp-preview" --repo YOUR_ORG/new-app-repo
gh variable set PREVIEW_DOMAIN --body "preview.yourdomain.com" --repo YOUR_ORG/new-app-repo
gh variable set PREVIEW_ZONE_ID --body "Z01234..." --repo YOUR_ORG/new-app-repo
gh variable set PREVIEW_ACM_CERT_ARN --body "arn:aws:acm:..." --repo YOUR_ORG/new-app-repo
gh secret set AWS_ROLE_ARN --body "arn:aws:iam::ACCOUNT:role/ROLE" --repo YOUR_ORG/new-app-repo
```

### 3. Add workflow and config

Copy the `preview-env.yml` workflow template to the consumer repo's `.github/workflows/` directory. Update the `uses:` references to point to your mini-idp org/repo:

```yaml
provision:
  uses: YOUR_ORG/mini-idp/.github/workflows/provision.yml@main
```

Add `.idp/config.yml` with the desired template and settings.

### 4. Create the `production` environment

In the consumer repo's Settings > Environments, create a `production` environment.

## Common Operations

### Manually trigger a provision

```bash
gh workflow run provision.yml \
  --field template=api-service \
  --field environment_name=test-env \
  --field owner=admin@example.com \
  --field ttl=2h
```

### Manually trigger a destroy

```bash
gh workflow run destroy.yml \
  --field environment_name=test-env
```

### Force TTL cleanup

```bash
gh workflow run ttl-cleanup.yml
```

### Check environment metadata

```bash
# Via CLI
idp list

# Via AWS CLI
aws s3 cp s3://YOUR-STATE-BUCKET/environments/my-env/metadata.json -
```

### List all environments in S3

```bash
aws s3api list-objects-v2 \
  --bucket YOUR-STATE-BUCKET \
  --prefix environments/ \
  --delimiter / \
  --query "CommonPrefixes[].Prefix"
```

### Tail container logs

```bash
# Via CLI (recommended)
idp logs my-env
idp logs my-env --follow --since 30m

# Via AWS CLI
aws logs tail /ecs/idp-my-env --follow --since 1h
```

### Apply shared infrastructure changes

When updating shared Terraform modules:

```bash
# ECR changes
cd infrastructure/shared/ecr-preview
tofu init -backend-config=../../backend.conf
tofu plan
tofu apply

# DNS/cert changes
cd infrastructure/shared/preview-dns
tofu init -backend-config=../../backend.conf
tofu plan
tofu apply
```

## Troubleshooting

### Terraform state lock stuck

If a workflow fails mid-apply, the DynamoDB lock may persist.

**Option 1 — CLI (recommended):**

```bash
idp unlock my-env
```

**Option 2 — AWS CLI:**

```bash
aws dynamodb delete-item \
  --table-name YOUR-LOCK-TABLE \
  --key '{"LockID": {"S": "YOUR-STATE-BUCKET/environments/ENV_NAME/terraform.tfstate"}}'
```

### DynamoDB state digest mismatch

If re-provisioning fails with "state data in S3 does not have the expected content," the DynamoDB `-md5` digest entry from a previous environment is stale. The destroy workflow normally cleans this up, but if a destroy was run before this cleanup step was added, the digest may persist.

**Fix:**

```bash
aws dynamodb delete-item \
  --table-name YOUR-LOCK-TABLE \
  --key '{"LockID": {"S": "YOUR-STATE-BUCKET/environments/ENV_NAME/terraform.tfstate-md5"}}'
```

Then re-run the provision.

### Environment stuck in "destroying" status

The TTL cleanup marks environments as "destroying" before triggering the workflow. If the destroy fails:

1. Check the GitHub Actions run for errors
2. Fix the issue (usually a dependency or permissions problem)
3. Re-trigger: `gh workflow run destroy.yml --field environment_name=NAME`

The TTL cleanup also has self-healing: environments stuck in "destroying" for over 2 hours are automatically retried.

### State file corruption

S3 versioning is enabled. Recover a previous version:

```bash
aws s3api list-object-versions \
  --bucket YOUR-STATE-BUCKET \
  --prefix environments/NAME/terraform.tfstate

aws s3api get-object \
  --bucket YOUR-STATE-BUCKET \
  --key environments/NAME/terraform.tfstate \
  --version-id VERSION_ID \
  recovered-state.tfstate
```

### OIDC authentication fails

Verify the trust policy matches your repository:
```bash
aws iam get-role --role-name YOUR-ROLE \
  --query "Role.AssumeRolePolicyDocument"
```

Common causes:
- Repository name mismatch in `sub` condition
- Missing `sts.amazonaws.com` in `aud` condition
- GitHub environment name doesn't match workflow (`production`)
- Consumer repo not added to the trust policy's `sub` array

### Cross-repo workflow fails with "not found"

When a consumer repo calls `uses: YOUR_ORG/mini-idp/.github/workflows/provision.yml@main`:

- The mini-idp repo must be **public**, or the consumer repo must have access to it
- The workflow file must have `on: workflow_call:` as a trigger
- The `@main` ref must point to a branch or tag where the workflow exists

### RDS fails with "service-linked role" error

First-time RDS usage in an AWS account requires:
```bash
aws iam create-service-linked-role --aws-service-name rds.amazonaws.com
```

### PostgreSQL version unavailable

AWS periodically retires minor versions. If `tofu apply` fails with "Cannot find version X.Y":
1. Check available versions: `aws rds describe-db-engine-versions --engine postgres --query "DBEngineVersions[].EngineVersion"`
2. Update `infrastructure/modules/rds-postgres/main.tf` with a current version
3. Commit and push to main
