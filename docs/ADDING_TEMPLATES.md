# Adding New Templates

Templates are compositions of modules. Shared boilerplate (backend, provider, tags, networking, common module, shared variables) lives in `infrastructure/templates/_base/` and is automatically copied into each template directory at CI time. Your template only needs the unique parts.

## Steps

### 1. Create the template directory

```
infrastructure/templates/my-new-template/
├── main.tf        # Template-specific module calls only
├── variables.tf   # Template-specific variables only
└── outputs.tf     # Outputs for the CLI
```

The `_base/` directory provides these shared files (copied in at CI time):
```
infrastructure/templates/_base/
├── backend.tf              # terraform{} + provider + tags locals
├── networking.tf           # module "networking" + shared VPC toggle + locals
├── common.tf               # module "common" (IAM roles, CloudWatch logs)
└── shared-variables.tf     # 13 shared variables (environment_name, owner, ttl, etc.)
```

### 2. Write main.tf

Your `main.tf` only needs template-specific content. All shared infrastructure is handled by `_base/`:

```hcl
####################################################################
# Template: My New Template
# Provisions: (describe what this template creates)
#
# Shared infrastructure (backend, provider, tags, networking, common)
# is provided by _base/*.tf — copied in at CI time.
####################################################################

locals {
  template_name = "my-new-template"
}

# --- Template-specific modules ---
module "ecs_service" {
  source                 = "../../modules/ecs-service"
  environment_name       = var.environment_name
  vpc_id                 = local.vpc_id
  public_subnet_ids      = local.public_subnet_ids
  private_subnet_ids     = local.private_subnet_ids
  task_execution_role_arn = module.common.task_execution_role_arn
  task_role_arn          = module.common.task_role_arn
  log_group_name         = module.common.log_group_name
  container_image        = var.container_image
  container_port         = var.container_port
  cpu                    = var.cpu
  memory                 = var.memory
  acm_certificate_arn    = var.acm_certificate_arn
  route53_zone_id        = var.route53_zone_id
  dns_name               = var.preview_domain != "" ? "${var.environment_name}.${var.preview_domain}" : ""
  aws_region             = var.aws_region
  environment_variables  = var.environment_variables
  secret_variables       = var.secret_variables
  tags                   = local.tags
}
```

The key points:
- Set `template_name` in locals — this flows into the tag set computed by `_base/backend.tf`
- Reference `local.vpc_id`, `local.public_subnet_ids`, `local.private_subnet_ids` — these are computed by `_base/networking.tf`
- Reference `module.common.*` — this is set up by `_base/common.tf`
- The `_base/` files handle backend config, provider, tags, networking (with shared VPC toggle), and the common module

### 3. Define template-specific variables

Shared variables (`environment_name`, `owner`, `ttl`, `created_at`, `expires_at`, `aws_region`, `cpu`, `memory`, `log_retention_days`, `environment_variables`, `secret_variables`, `use_shared_networking`, `state_bucket`) are provided by `_base/shared-variables.tf`. Your `variables.tf` only needs **template-specific** variables.

**Important:** Variables with different defaults per template (like `container_image`) must go in your template's `variables.tf`, not in `_base/`.

Example for an API-style template:

```hcl
####################################################################
# Template-specific variables for: my-new-template
#
# Shared variables (environment_name, owner, ttl, etc.) are in
# _base/shared-variables.tf — copied in at CI time.
####################################################################

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

variable "acm_certificate_arn" {
  description = "ARN of an ACM certificate for HTTPS. Leave empty for HTTP-only."
  type        = string
  default     = ""
}

variable "route53_zone_id" {
  description = "Route 53 hosted zone ID for DNS record. Leave empty to skip DNS."
  type        = string
  default     = ""
}

variable "preview_domain" {
  description = "Base domain for preview environments (e.g. preview.yourdomain.com)."
  type        = string
  default     = ""
}
```

See existing templates for examples: `api-service/variables.tf` (~37 lines), `scheduled-worker/variables.tf` (~25 lines).

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

In `cli/src/lib/templates.ts`, add to the `TEMPLATES` array (single source of truth for template names, descriptions, and cost estimates). Both the `create` and `templates` commands import from this shared module.

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

When consumers call `provision.yml` cross-repo, the workflow checks out the mini-idp repository to access template code. The `_base/*.tf` files are copied into the template directory via `cp infrastructure/templates/_base/*.tf infrastructure/templates/{template}/` before `tofu init`. Your new template will be available to all consumer repos as soon as it's merged to `main` in mini-idp. No changes needed in consumer repos unless the template requires new config fields in `.idp/config.yml`.

**Important:** The `_base/` file `shared-variables.tf` is intentionally not named `variables.tf` — this avoids overwriting the template's own `variables.tf` during the CI copy step.
