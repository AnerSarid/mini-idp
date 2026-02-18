import { Command } from 'commander';
import chalk from 'chalk';
import ora from 'ora';
import dayjs from 'dayjs';
import { getEnvironment, updateEnvironmentMetadata } from '../lib/environments.js';
import { parseTtl, validateTtl } from '../lib/ttl.js';
import { withAuth } from '../lib/command.js';

export function registerExtendCommand(program: Command): void {
  program
    .command('extend <name>')
    .description('Extend the TTL of an environment')
    .requiredOption('--ttl <ttl>', 'Additional time to live (e.g. 7d, 24h)')
    .action(withAuth(async (name: string, opts) => {
        validateTtl(opts.ttl);

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
        // Compute the effective TTL from creation to new expiry (the actual total lifetime)
        const createdAt = dayjs(env.metadata.created_at);
        const totalHours = newExpiry.diff(createdAt, 'hour');
        const effectiveTtl = totalHours >= 24 && totalHours % 24 === 0
          ? `${totalHours / 24}d`
          : `${totalHours}h`;
        const updatedMetadata = {
          ...env.metadata,
          expires_at: newExpiry.toISOString(),
          ttl: effectiveTtl,
        };
        await updateEnvironmentMetadata(name, updatedMetadata);
        updateSpinner.succeed('Expiry updated');

        process.stdout.write(
          chalk.green(`\nEnvironment "${name}" extended to ${newExpiry.format('YYYY-MM-DD HH:mm')}.\n`)
        );
    }));
}
