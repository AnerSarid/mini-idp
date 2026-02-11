# Operations Runbook

## Initial Setup

### 1. Create AWS OIDC Provider for GitHub Actions

```bash
# Create the OIDC identity provider
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

### 2. Create IAM Role for GitHub Actions

Create `github-actions-role` with this trust policy (replace `YOUR_ORG/mini-idp`):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:YOUR_ORG/mini-idp:*"
        }
      }
    }
  ]
}
```

Attach these managed policies (or create a custom one scoped to IDP resources):
- `AmazonECS_FullAccess`
- `AmazonRDSFullAccess`
- `AmazonVPCFullAccess`
- `AmazonS3FullAccess`
- `SecretsManagerReadWrite`
- `CloudWatchLogsFullAccess`
- `IAMFullAccess` (scoped to `idp-*` roles)
- `ElasticLoadBalancingFullAccess`
- `AmazonEventBridgeFullAccess`

### 3. Set GitHub Secrets

In your repository settings, add:
- `AWS_ROLE_ARN`: The ARN of the IAM role created above

### 4. Create GitHub Environment

Create a `production` environment in Settings → Environments. Optionally add protection rules.

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
aws s3 cp s3://mini-idp-terraform-state/environments/my-env/metadata.json -
```

### List all environments in S3

```bash
aws s3api list-objects-v2 \
  --bucket mini-idp-terraform-state \
  --prefix environments/ \
  --delimiter / \
  --query "CommonPrefixes[].Prefix"
```

## Troubleshooting

### Terraform state lock stuck

If a workflow fails mid-apply, the DynamoDB lock may persist:

```bash
aws dynamodb delete-item \
  --table-name mini-idp-terraform-locks \
  --key '{"LockID": {"S": "mini-idp-terraform-state/environments/ENV_NAME/terraform.tfstate"}}'
```

### Environment stuck in "destroying" status

The TTL cleanup marks environments as "destroying" before triggering the workflow. If the destroy fails:

1. Check the GitHub Actions run for errors
2. Fix the issue (usually a dependency or permissions problem)
3. Re-trigger: `gh workflow run destroy.yml --field environment_name=NAME`

### State file corruption

S3 versioning is enabled. Recover a previous version:

```bash
aws s3api list-object-versions \
  --bucket mini-idp-terraform-state \
  --prefix environments/NAME/terraform.tfstate

aws s3api get-object \
  --bucket mini-idp-terraform-state \
  --key environments/NAME/terraform.tfstate \
  --version-id VERSION_ID \
  recovered-state.tfstate
```

### OIDC authentication fails

Verify the trust policy matches your repository:
```bash
aws iam get-role --role-name github-actions-role \
  --query "Role.AssumeRolePolicyDocument"
```

Check that the GitHub environment name matches what's in the workflow (`production`).
