import { Command } from 'commander';
import chalk from 'chalk';
import ora from 'ora';
import dayjs from 'dayjs';
import { requireAuth } from '../lib/config.js';
import { listEnvironments } from '../lib/environments.js';

function statusColor(status: string): string {
  switch (status) {
    case 'active':
      return chalk.green(status);
    case 'provisioning':
      return chalk.yellow(status);
    case 'destroying':
      return chalk.red(status);
    case 'failed':
      return chalk.red(status);
    default:
      return chalk.gray(status);
  }
}

function pad(str: string, len: number): string {
  return str.padEnd(len);
}

function isExpired(expiresAt: string): boolean {
  return dayjs().isAfter(dayjs(expiresAt));
}

export function registerListCommand(program: Command): void {
  program
    .command('list')
    .description('List all environments')
    .option('--json', 'Output as JSON')
    .action(async (opts) => {
      try {
        requireAuth();

        const spinner = ora('Fetching environments...').start();
        const environments = await listEnvironments();
        spinner.stop();

        if (environments.length === 0) {
          process.stdout.write(chalk.gray('No environments found.\n'));
          return;
        }

        if (opts.json) {
          process.stdout.write(JSON.stringify(environments, null, 2) + '\n');
          return;
        }

        const cols = {
          name: 20,
          template: 18,
          owner: 28,
          status: 14,
          created: 12,
          expires: 12,
        };

        const header = [
          pad('NAME', cols.name),
          pad('TEMPLATE', cols.template),
          pad('OWNER', cols.owner),
          pad('STATUS', cols.status),
          pad('CREATED', cols.created),
          pad('EXPIRES', cols.expires),
        ].join('  ');

        process.stdout.write(chalk.bold(header) + '\n');
        process.stdout.write(
          chalk.gray('-'.repeat(header.length)) + '\n'
        );

        for (const env of environments) {
          const expired = isExpired(env.expires_at);
          const status = expired ? 'expired' : env.status;
          const createdDate = dayjs(env.created_at).format('YYYY-MM-DD');
          const expiresDate = dayjs(env.expires_at).format('YYYY-MM-DD');

          const row = [
            pad(env.name, cols.name),
            pad(env.template, cols.template),
            pad(env.owner, cols.owner),
            pad(statusColor(status), cols.status + 10), // account for ANSI codes
            pad(createdDate, cols.created),
            pad(expired ? chalk.red(expiresDate) : expiresDate, cols.expires),
          ].join('  ');

          process.stdout.write(row + '\n');
        }

        process.stdout.write(
          chalk.gray(`\n${environments.length} environment(s)\n`)
        );
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        process.stderr.write(chalk.red(`Error: ${message}\n`));
        process.exit(1);
      }
    });
}
