# Mini IDP — Elegant Improvements

A senior DevOps review of the codebase's architecture, not from a "what's broken" lens (that's in IMPROVEMENTS.md), but from an **elegance** lens: where the design is clean and where it could be tighter.

Overall impression: this is a well-structured project. The separation of modules/templates/shared infrastructure is sound, the GitOps flow is cohesive, and the CLI is sensibly scoped. The observations below are about refinement, not rescue.

---

## What's Already Elegant

Worth calling out what works well, because these are patterns to protect:

1. **The template composition model.** Templates compose modules (common + networking + ecs-service/rds/scheduled-task) rather than copy-pasting resources. Adding a new template is additive — you write a new `main.tf` that wires existing modules together. This is exactly right.

2. **S3 as the metadata plane.** Using the same state bucket for both Terraform state (`environments/{name}/terraform.tfstate`) and application metadata (`environments/{name}/metadata.json`, `outputs.json`) is a genuinely clean design. One bucket, one namespace convention, no extra database.

3. **The provision/extend collapse.** Both actions route through the same `provision.yml` workflow — `tofu apply` is idempotent, so "extend" is just "apply again with a new TTL." This is the Terraform way and avoids a separate update path.

4. **Concurrency group on branch name.** The `concurrency.group: preview-${{ branch }}` pattern in `preview-env.yml` elegantly prevents the dual-destroy race (PR close + branch delete both fire). One line handles what would otherwise be fragile state-machine logic.

5. **The reusable workflow contract.** Consumer repos call `provision.yml`/`destroy.yml` via `workflow_call` — no infrastructure code copied into consuming repos. This is the right boundary for a platform team.

---

## 1. Three Template `main.tf` Files Are 70% Identical

**Where:** `infrastructure/templates/api-service/main.tf`, `api-database/main.tf`, `scheduled-worker/main.tf`

All three templates repeat the same blocks verbatim:
- `terraform {}` block (backend, providers)
- `locals { tags = { ... } }` — same 8 tags, only the `"idp:template"` value differs
- `module "networking"` with the shared/per-env toggle
- `data "terraform_remote_state" "shared_networking"` with the same config
- `locals { vpc_id, public_subnet_ids, private_subnet_ids }` resolution
- `module "common"` call

The actual template-specific content is just the last 20-30 lines of each file.

**Why it matters:** When you add a fourth template, you'll copy-paste 60 lines of boilerplate and change one string. When you change the tag schema, you update three files. This is the one place where DRY is clearly violated.

**Elegant fix:** Extract a `base.tf` or use a shared `.tf` file that all templates symlink/include. Terraform doesn't have native includes, but the standard pattern is a `_base.tf` symlink:

```
templates/
  _base/
    backend.tf      # terraform{} + provider + tags locals
    networking.tf   # module "networking" + shared lookup + locals
    common.tf       # module "common"
  api-service/
    _base.tf -> ../_base/*.tf   (symlinks)
    main.tf                      (only the unique parts)
```

Alternatively, flatten the shared blocks into a Terragrunt `generate` block or a pre-processing step. But symlinks are the zero-dependency approach and they're well-understood in the Terraform ecosystem.

---

## 2. The `prompt()` Function Is Copy-Pasted Across Three Commands

**Where:** `cli/src/commands/auth.ts:7-17`, `create.ts:50-61`, `destroy.ts:9-20`, `unlock.ts:18-29`

Four identical `prompt()` implementations creating and closing readline interfaces.

**Elegant fix:** Move to `cli/src/lib/prompt.ts`:

```typescript
import * as readline from 'readline';

export function prompt(question: string): Promise<string> {
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  return new Promise((resolve) => {
    rl.question(question, (answer) => { rl.close(); resolve(answer.trim()); });
  });
}
```

Four imports, zero duplication. This is the same thing you already did with `ttl.ts` — just finish the job.

---

## 3. The CLI Error Handling Pattern Is Consistent but Verbose

**Where:** Every command file follows this exact pattern:

```typescript
.action(async (name, opts) => {
  try {
    requireAuth();
    // ... actual logic ...
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    process.stderr.write(chalk.red(`Error: ${message}\n`));
    process.exit(1);
  }
});
```

This is fine for 3 commands. With 8 commands, it's noise. The `requireAuth()` + try/catch + error formatting is identical everywhere.

**Elegant fix:** A wrapper that handles the ceremony:

```typescript
// lib/command.ts
export function withAuth(fn: (...args: any[]) => Promise<void>) {
  return async (...args: any[]) => {
    try {
      requireAuth();
      await fn(...args);
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      process.stderr.write(chalk.red(`Error: ${message}\n`));
      process.exit(1);
    }
  };
}
```

Then commands become:

```typescript
.action(withAuth(async (name, opts) => {
  // just the logic, no boilerplate
}));
```

---

## 4. New S3Client on Every Call

**Where:** `cli/src/lib/environments.ts:40-42`

`getS3Client()` creates a new `S3Client` on every function call. `listEnvironments()` then calls `getS3Client()` once for the listing, then once per environment for the metadata fetch. 10 environments = 11 SDK client instances.

This works, but the AWS SDK's `S3Client` is designed to be long-lived — it manages connection pooling, credential caching, and retry state internally. Creating throwaway clients defeats all of that.

**Elegant fix:** Module-level lazy singleton:

```typescript
let _s3: S3Client | null = null;
function getS3Client(): S3Client {
  return (_s3 ??= new S3Client({ region: getConfigValue('aws.region') }));
}
```

Same for the `DynamoDBClient` in `unlock.ts`.

---

## 5. Sequential S3 Fetches in `listEnvironments()`

**Where:** `cli/src/lib/environments.ts:72-84`

After listing all metadata keys, the function fetches each one sequentially in a `for` loop. With 15 environments, that's 15 sequential HTTP requests.

**Elegant fix:** `Promise.allSettled()`:

```typescript
const environments = await Promise.allSettled(
  metadataKeys.map(async (key) => {
    const result = await client.send(new GetObjectCommand({ Bucket: bucket, Key: key }));
    const body = await streamToString(result.Body as NodeJS.ReadableStream);
    return JSON.parse(body) as EnvironmentMetadata;
  })
);
return environments
  .filter((r): r is PromiseFulfilledResult<EnvironmentMetadata> => r.status === 'fulfilled')
  .map((r) => r.value);
```

Same data, same error handling, 3-5x faster for real usage.

---

## 6. The `tfvars` Generation in Workflows Is Fragile

**Where:** `.github/workflows/provision.yml:270-375`

The workflow generates `.tfvars` files using heredocs with `sed -i 's/^          //'` to strip YAML indentation. This is the most fragile part of the whole system — a refactor of the YAML indentation level silently breaks the tfvars output.

The pattern of conditionally appending lines (`if [[ -n "$CPU" && "$CPU" != "256" ]]; then echo ...`) is also error-prone: you're manually tracking which values are "default" in bash, duplicating what Terraform's variable defaults already handle.

**Elegant fix:** Write the tfvars as JSON instead of HCL. Terraform accepts `-var-file=foo.tfvars.json` natively, and `jq` makes JSON assembly trivial from shell:

```bash
jq -n \
  --arg env "${{ inputs.environment_name }}" \
  --arg owner "${{ inputs.owner }}" \
  --arg ttl "${{ inputs.ttl }}" \
  --arg created "$CREATED_AT" \
  --arg expires "$EXPIRES_AT" \
  '{environment_name: $env, owner: $owner, ttl: $ttl, created_at: $created, expires_at: $expires}' \
  > "${TFVARS_FILE}"
```

Then merge in optional fields with `jq '. + {key: $val}'` — no indentation bugs, no sed post-processing, no manual default tracking. Terraform handles missing keys via variable defaults.

The same approach should replace the `metadata.json` heredoc generation in the same workflow.

---

## 7. The `destroy.yml` Rebuilds tfvars From Metadata — Unnecessarily

**Where:** `.github/workflows/destroy.yml:81-138`

The destroy workflow reads metadata from S3 and reconstructs a tfvars file so that `tofu destroy -var-file=...` has all the variables it needs. This reconstruction is ~60 lines of careful bash that mirrors the provision workflow's tfvars generation.

**Why this is inelegant:** Terraform doesn't need accurate variable values to destroy. It destroys what's in state, not what's in the plan. The only reason you need `-var-file` at all is that the template's `variables.tf` declares required variables with no defaults, so Terraform refuses to run without them.

**Elegant fix — pick one:**

**(a)** Give every variable in every template a default value (even if it's `""`). Then `tofu destroy -auto-approve` works with zero var files. Destroy doesn't care about the values.

**(b)** Store the tfvars file itself in S3 during provision (alongside `metadata.json` and `outputs.json`). Destroy just downloads it. Zero reconstruction logic.

Option (b) is cleaner because it preserves the exact inputs that were used to create the environment — useful for auditing.

---

## 8. The `preview-env.yml` Config Parsing Could Be Its Own Reusable Workflow

**Where:** `.github/workflows/preview-env.yml:126-253` (the `setup` job)

The setup job does three things: sanitize branch name, parse `.idp/config.yml`, validate config. It's ~130 lines. This is the consumer-facing workflow — the one that lives in (or is referenced from) app repos.

If a consumer repo wants to customize behavior (different branch name sanitization, extra validation), they fork the whole 570-line workflow. The setup logic is the part most likely to need customization, but it's baked into the main flow.

**Elegant fix:** Extract setup as a reusable composite action or a separate `setup.yml` workflow that outputs all the config values. Then `preview-env.yml` becomes pure orchestration:

```yaml
jobs:
  setup:
    uses: ./.github/workflows/setup.yml@main
  build-image:
    needs: setup
    # ...
  provision:
    needs: [setup, build-image]
    uses: ./.github/workflows/provision.yml@main
```

This also makes the setup logic independently testable.

---

## 9. Inconsistent Naming Prefix Pattern Across Modules

**Where:** Across all modules

- `common/main.tf`: `local.prefix = "idp-${var.environment_name}"` — resources get `idp-foo-*`
- `ecs-service/main.tf`: `local.name_prefix = var.environment_name` — resources get `foo-*`
- `rds-postgres/main.tf`: `local.prefix = var.environment_name` — resources get `foo-*`
- `scheduled-task/main.tf`: `local.prefix = "idp-${var.environment_name}"` — resources get `idp-foo-*`

So an `api-database` environment named `my-app` creates:
- IAM roles: `idp-my-app-ecs-task-execution` (from common)
- ECS cluster: `my-app-cluster` (from ecs-service)
- RDS instance: `my-app-postgres` (from rds)
- Log group: `/ecs/idp-my-app` (from common)

Some resources have the `idp-` prefix, some don't. This makes IAM policies with `idp-*` resource patterns miss the unprefixed resources. It also makes CloudWatch log searches inconsistent.

**Elegant fix:** Standardize. Every module should receive `environment_name` and apply the `idp-` prefix consistently. Easiest: the templates pass `"idp-${var.environment_name}"` to all modules. Or each module applies `"idp-${var.environment_name}"` internally. Pick one, apply it everywhere.

---

## 10. The `TEMPLATES` Constant Lives in Two Places

**Where:** `cli/src/commands/create.ts:11` and `cli/src/commands/templates.ts:11-51`

`create.ts` has a minimal `TEMPLATES` array for validation. `templates.ts` has a rich `TEMPLATES` array with descriptions, resources, and costs. If you add a template, you update both. If the cost estimate changes, you update both.

**Elegant fix:** Single source of truth in `lib/templates.ts`:

```typescript
export const TEMPLATES = [ /* full definitions */ ] as const;
export type TemplateName = typeof TEMPLATES[number]['name'];
export const TEMPLATE_NAMES = TEMPLATES.map(t => t.name);
```

Both commands import from the same place.

---

## 11. The Dashboard Workflow's "Meaningful Change" Detection Is Clever but Brittle

**Where:** `.github/workflows/update-dashboard.yml:191-196`

```bash
if git diff ENVIRONMENTS.md | grep '^[+-]' | grep -v '^[+-][+-][+-]' | grep -v 'Last updated' | grep -qv '^$'; then
```

This chain of greps to detect non-timestamp changes is creative but will break if someone adds another auto-generated line (like an "Environment count" line). It also silently swallows errors — if `git diff` fails, the whole chain exits cleanly.

**Elegant fix:** Generate the dashboard content to a temp file, strip the timestamp from both files, then `diff`:

```bash
sed '/Last updated/d' ENVIRONMENTS.md > /tmp/old.md
sed '/Last updated/d' ENVIRONMENTS.new.md > /tmp/new.md
if ! diff -q /tmp/old.md /tmp/new.md > /dev/null 2>&1; then
  mv ENVIRONMENTS.new.md ENVIRONMENTS.md
  # commit
fi
```

More lines, but each line does one thing and the intent is obvious.

---

## Summary

| # | What | Effort | Impact |
|---|------|--------|--------|
| 1 | De-duplicate template boilerplate (symlinks or base module) | Medium | Prevents drift as templates grow |
| 2 | Extract shared `prompt()` utility | 10 min | Trivial DRY win |
| 3 | Command error-handling wrapper | 20 min | Reduces noise in 8 files |
| 4 | Singleton S3/DynamoDB clients | 10 min | Proper SDK usage |
| 5 | Parallel S3 fetches in `listEnvironments` | 15 min | Noticeably faster CLI |
| 6 | JSON tfvars instead of heredoc + sed | 1 hour | Eliminates the most fragile code path |
| 7 | Store tfvars in S3 (or default all destroy vars) | 30 min | Eliminates 60 lines of reconstruction |
| 8 | Extract setup into reusable workflow | 1 hour | Cleaner consumer-facing contract |
| 9 | Consistent `idp-` prefix across modules | 30 min | IAM + observability consistency |
| 10 | Single `TEMPLATES` source of truth | 15 min | One place to update |
| 11 | Cleaner dashboard diff detection | 15 min | Less brittle CI |

None of these are blocking. The project works. These are the kinds of refinements that make the difference between "this works" and "this is obviously right" — the kind of code where a new team member reads it and doesn't need to ask why.
