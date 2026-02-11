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

Compose existing modules:

```hcl
module "networking" {
  source           = "../../modules/networking"
  environment_name = var.environment_name
  tags             = local.tags
}

module "common" {
  source           = "../../modules/common"
  environment_name = var.environment_name
  tags             = local.tags
}

# Add template-specific modules here
```

Every template must include:
- The `terraform` block with S3 backend config
- The `provider "aws"` block with `default_tags`
- The `locals` block computing the standard tag set
- The `networking` and `common` modules

### 3. Define variables

At minimum, every template needs these variables:

```hcl
variable "environment_name" { type = string }
variable "owner"            { type = string }
variable "ttl"              { type = string }
variable "created_at"       { type = string }
variable "expires_at"       { type = string }
variable "aws_region"       { type = string, default = "us-east-1" }
```

Add template-specific variables as needed.

### 4. Register in the provision workflow

Add the template name to `.github/workflows/provision.yml`:

```yaml
template:
  type: choice
  options:
    - api-service
    - api-database
    - scheduled-worker
    - my-new-template    # Add here
```

### 5. Update the CLI

In `cli/src/commands/create.ts`, add to the `TEMPLATES` array and `COST_ESTIMATES`.

In `cli/src/commands/templates.ts`, add the description.

### 6. Handle template-specific variables in the workflow

If your template has unique variables (like `scheduled-worker` has `schedule_expression`), add conditional tfvars generation in the provision workflow's "Generate tfvars" step.
