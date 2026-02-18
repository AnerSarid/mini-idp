import { Command } from 'commander';
import chalk from 'chalk';
import ora from 'ora';
import dayjs from 'dayjs';
import { triggerWorkflow, waitForWorkflowCompletion } from '../lib/github.js';
import { environmentExists, getEnvironment } from '../lib/environments.js';
import { parseTtl, validateTtl } from '../lib/ttl.js';
import { prompt } from '../lib/prompt.js';
import { withAuth } from '../lib/command.js';
import { TEMPLATES, TEMPLATE_NAMES, type TemplateName } from '../lib/templates.js';

const COST_MAP = Object.fromEntries(
  TEMPLATES.map((t) => [t.name, t.estimatedCost])
) as Record<TemplateName, string>;

const NAME_REGEX = /^[a-z0-9][a-z0-9-]*[a-z0-9]$/;
const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function validateName(name: string): string {
  if (name.length > 32) {
    throw new Error('Name must be 32 characters or fewer.');
  }
  if (name.length < 2) {
    throw new Error('Name must be at least 2 characters.');
  }
  if (!NAME_REGEX.test(name)) {
    throw new Error(
      'Name must be lowercase alphanumeric with hyphens, cannot start/end with a hyphen.'
    );
  }
  return name;
}

function validateOwner(owner: string): string {
  if (!EMAIL_REGEX.test(owner)) {
    throw new Error('Owner must be a valid email address.');
  }
  return owner;
}

function computeExpiry(ttl: string): string {
  const { value, unit } = parseTtl(ttl);
  return dayjs().add(value, unit).toISOString();
}

export function registerCreateCommand(program: Command): void {
  program
    .command('create')
    .description('Create a new environment')
    .requiredOption(
      '--template <template>',
      `Template to use (${TEMPLATE_NAMES.join(', ')})`
    )
    .requiredOption('--name <name>', 'Environment name')
    .requiredOption('--owner <owner>', 'Owner email address')
    .option('--ttl <ttl>', 'Time to live (e.g. 7d, 24h)', '7d')
    .option('--schedule <expression>', 'Cron schedule (for scheduled-worker)')
    .option('--s3-bucket <arn>', 'S3 bucket ARN (for scheduled-worker)')
    .action(withAuth(async (opts) => {
        const template = opts.template as TemplateName;
        if (!TEMPLATE_NAMES.includes(template)) {
          process.stderr.write(
            chalk.red(`Invalid template. Choose from: ${TEMPLATE_NAMES.join(', ')}\n`)
          );
          process.exit(1);
        }

        const name = validateName(opts.name);
        validateOwner(opts.owner);
        const ttl = validateTtl(opts.ttl);

        if (template === 'scheduled-worker' && !opts.schedule) {
          process.stderr.write(
            chalk.red('--schedule is required for scheduled-worker template.\n')
          );
          process.exit(1);
        }

        const spinner = ora('Checking for existing environment...').start();
        const exists = await environmentExists(name);
        spinner.stop();

        if (exists) {
          process.stderr.write(
            chalk.red(`Environment "${name}" already exists.\n`)
          );
          process.exit(1);
        }

        const expiresAt = computeExpiry(ttl);

        process.stdout.write('\n');
        process.stdout.write(chalk.bold('Environment Summary\n'));
        process.stdout.write(`  Name:     ${chalk.cyan(name)}\n`);
        process.stdout.write(`  Template: ${chalk.cyan(template)}\n`);
        process.stdout.write(`  Owner:    ${opts.owner}\n`);
        process.stdout.write(`  TTL:      ${ttl}\n`);
        process.stdout.write(`  Expires:  ${dayjs(expiresAt).format('YYYY-MM-DD HH:mm')}\n`);
        process.stdout.write(
          `  Est Cost: ${chalk.yellow(COST_MAP[template])}\n`
        );
        if (opts.schedule) {
          process.stdout.write(`  Schedule: ${opts.schedule}\n`);
        }
        if (opts.s3Bucket) {
          process.stdout.write(`  S3 Bucket: ${opts.s3Bucket}\n`);
        }
        process.stdout.write('\n');

        const confirm = await prompt('Proceed? (y/N) ');
        if (confirm.toLowerCase() !== 'y') {
          process.stdout.write(chalk.yellow('Aborted.\n'));
          return;
        }

        const inputs: Record<string, string> = {
          environment_name: name,
          template,
          owner: opts.owner,
          ttl,
          action: 'apply',
        };

        if (opts.schedule) {
          inputs.schedule_expression = opts.schedule;
        }
        if (opts.s3Bucket) {
          inputs.s3_bucket_arn = opts.s3Bucket;
        }

        const createdAfter = new Date();

        const triggerSpinner = ora('Triggering provision workflow...').start();
        await triggerWorkflow('provision.yml', inputs);
        triggerSpinner.succeed('Workflow triggered');

        const waitSpinner = ora('Waiting for provisioning to complete...').start();
        const result = await waitForWorkflowCompletion(
          'provision.yml',
          createdAfter
        );
        waitSpinner.stop();

        if (result.conclusion === 'success') {
          process.stdout.write(chalk.green('\nEnvironment created successfully!\n\n'));

          try {
            const env = await getEnvironment(name);
            if (env.outputs) {
              process.stdout.write(chalk.bold('Outputs:\n'));
              for (const [key, value] of Object.entries(env.outputs)) {
                process.stdout.write(`  ${key}: ${chalk.cyan(value)}\n`);
              }
            }
          } catch {
            process.stdout.write(
              chalk.gray('Outputs not yet available. Run `idp list` to check.\n')
            );
          }

          process.stdout.write(`\nWorkflow: ${chalk.gray(result.html_url)}\n`);
        } else {
          process.stderr.write(
            chalk.red(`\nProvisioning failed: ${result.conclusion}\n`)
          );
          process.stderr.write(`Workflow: ${result.html_url}\n`);
          process.exit(1);
        }
    }));
}
