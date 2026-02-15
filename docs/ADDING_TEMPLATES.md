# Adding New Templates

Templates are compositions of modules. To add a new golden path template:

## Steps

### 1. Create the template directory

```
infrastructure/templates/my-new-template/
├── main.tf        # Module composition
├── variables.tf   # Input variables
└── outputs.tf     # Outputs for the CLI
```

### 2. Write main.tf

Start with the Terraform block using partial backend configuration:

```hcl
terraform {
  required_version = ">= 1.6.0"

  # All backend values are provided via -backend-config flags from CI.
  # For local use: tofu init -backend-config=../../backend.conf -backend-config="key=environments/<name>/terraform.tfstate"
  backend "s3" {
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.tags
  }
}

locals {
  tags = {
    "idp:managed"      = "true"
    "idp:environment"  = var.environment_name
    "idp:template"     = "my-new-template"
    "idp:owner"        = var.owner
    "idp:created-at"   = var.created_at
    "idp:ttl"          = var.ttl
    "idp:expires-at"   = var.expires_at
    "cost-center"      = "engineering"
  }
}
```

Then compose existing modules:

```hcl
module "networking" {
  source           = "../../modules/networking"
  environment_name = var.environment_name
  tags             = local.tags
}

module "common" {
  source             = "../../modules/common"
  environment_name   = var.environment_name
  log_retention_days = var.log_retention_days
  tags               = local.tags
}

# Add template-specific modules here
```

Every template **must** include:
- An empty `backend "s3" {}` block (values come from `-backend-config` flags)
- The `provider "aws"` block with `default_tags`
- The `locals` block computing the standard tag set
- The `networking` and `common` modules

### 3. Define variables

At minimum, every template needs these variables:

```hcl
variable "environment_name" {
  description = "Name of the environment"
  type        = string
}

variable "owner" {
  description = "Owner email"
  type        = string
}

variable "ttl" {
  description = "Time to live (e.g. 7d)"
  type        = string
  default     = "7d"
}

variable "created_at" {
  description = "Creation timestamp (ISO 8601)"
  type        = string
}

variable "expires_at" {
  description = "Expiration timestamp (ISO 8601)"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "container_image" {
  description = "Container image to deploy"
  type        = string
  default     = "nginx:alpine"
}

variable "container_port" {
  description = "Container port"
  type        = number
  default     = 80
}

variable "cpu" {
  description = "CPU units for the Fargate task (256, 512, 1024, 2048, 4096)"
  type        = number
  default     = 256
}

variable "memory" {
  description = "Memory in MiB for the Fargate task"
  type        = number
  default     = 512
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 3
}

variable "acm_certificate_arn" {
  description = "ARN of an ACM certificate for HTTPS"
  type        = string
  default     = ""
}

variable "route53_zone_id" {
  description = "Route 53 hosted zone ID for DNS record"
  type        = string
  default     = ""
}

variable "preview_domain" {
  description = "Base domain for preview environments"
  type        = string
  default     = ""
}

variable "environment_variables" {
  description = "Plain environment variables for the container"
  type        = map(string)
  default     = {}
}

variable "secret_variables" {
  description = "Secrets Manager ARN references for the container"
  type        = map(string)
  default     = {}
}
```

Add template-specific variables as needed (e.g. `schedule_expression` for scheduled-worker, `db_name` for api-database).

### 4. Define outputs

At minimum, expose the endpoint so the dashboard and PR comments can link to it:

```hcl
output "endpoint" {
  description = "HTTPS URL for the deployed service"
  value       = module.ecs_service.endpoint
}
```

### 5. Register in the provision workflow

Add the template name to the validation step in `.github/workflows/provision.yml`:

```yaml
# In the "Validate inputs" step
TEMPLATE="${{ inputs.template }}"
if [[ "$TEMPLATE" != "api-service" && "$TEMPLATE" != "api-database" && "$TEMPLATE" != "scheduled-worker" && "$TEMPLATE" != "my-new-template" ]]; then
  echo "::error::Invalid template '${TEMPLATE}'."
  exit 1
fi
```

Also add it to the `workflow_dispatch` choices:

```yaml
template:
  type: choice
  options:
    - api-service
    - api-database
    - scheduled-worker
    - my-new-template    # Add here
```

### 6. Handle template-specific variables in the workflow

If your template has unique variables, add conditional tfvars generation in the provision workflow's "Generate tfvars" step. See how `scheduled-worker` handles `schedule_expression` for an example.

### 7. Update the CLI

In `cli/src/commands/create.ts`, add to the `TEMPLATES` array and `COST_ESTIMATES`.

In `cli/src/commands/templates.ts`, add the template description.

### 8. Test locally

```bash
cd infrastructure/templates/my-new-template
tofu init -backend-config=../../backend.conf \
  -backend-config="key=environments/test-my-template/terraform.tfstate"
tofu plan -var="environment_name=test-my-template" \
  -var="owner=you@example.com" \
  -var="created_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  -var="expires_at=$(date -u -d '+7 days' +%Y-%m-%dT%H:%M:%SZ)"
```

## Cross-Repo Considerations

When consumers call `provision.yml` cross-repo, the workflow checks out the mini-idp repository to access template code. Your new template will be available to all consumer repos as soon as it's merged to `main` in mini-idp. No changes needed in consumer repos unless the template requires new config fields in `.idp/config.yml`.
