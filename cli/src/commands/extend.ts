import { Command } from 'commander';
import chalk from 'chalk';
import ora from 'ora';
import dayjs from 'dayjs';
import { requireAuth } from '../lib/config.js';
import { getEnvironment, updateEnvironmentMetadata } from '../lib/environments.js';

const TTL_REGEX = /^\d+[dh]$/;

function parseTtl(ttl: string): { value: number; unit: 'day' | 'hour' } {
  const value = parseInt(ttl.slice(0, -1), 10);
  const unit = ttl.slice(-1) === 'd' ? 'day' as const : 'hour' as const;
  return { value, unit };
}

export function registerExtendCommand(program: Command): void {
  program
    .command('extend <name>')
    .description('Extend the TTL of an environment')
    .requiredOption('--ttl <ttl>', 'Additional time to live (e.g. 7d, 24h)')
    .action(async (name: string, opts) => {
      try {
        requireAuth();

        if (!TTL_REGEX.test(opts.ttl)) {
          process.stderr.write(
            chalk.red('TTL must be a number followed by d (days) or h (hours).\n')
          );
          process.exit(1);
        }

        const spinner = ora('Fetching environment...').start();
        let env;
        try {
          env = await getEnvironment(name);
        } catch {
          spinner.fail('Environment not found');
          process.stderr.write(chalk.red(`Environment "${name}" does not exist.\n`));
          process.exit(1);
        }
        spinner.stop();

        const { value, unit } = parseTtl(opts.ttl);
        const currentExpiry = dayjs(env.metadata.expires_at);
        const baseTime = currentExpiry.isAfter(dayjs()) ? currentExpiry : dayjs();
        const newExpiry = baseTime.add(value, unit);

        process.stdout.write(`\nEnvironment: ${chalk.cyan(name)}\n`);
        process.stdout.write(`Current expiry: ${currentExpiry.format('YYYY-MM-DD HH:mm')}\n`);
        process.stdout.write(`New expiry:     ${chalk.green(newExpiry.format('YYYY-MM-DD HH:mm'))}\n\n`);

        const updateSpinner = ora('Updating expiry...').start();
        const updatedMetadata = {
          ...env.metadata,
          expires_at: newExpiry.toISOString(),
          ttl: opts.ttl,
        };
        await updateEnvironmentMetadata(name, updatedMetadata);
        updateSpinner.succeed('Expiry updated');

        process.stdout.write(
          chalk.green(`\nEnvironment "${name}" extended to ${newExpiry.format('YYYY-MM-DD HH:mm')}.\n`)
        );
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        process.stderr.write(chalk.red(`Error: ${message}\n`));
        process.exit(1);
      }
    });
}
