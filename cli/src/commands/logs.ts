import { Command } from 'commander';
import chalk from 'chalk';
import ora from 'ora';
import { getEnvironment } from '../lib/environments.js';
import { getConfigValue } from '../lib/config.js';
import { spawn } from 'child_process';
import { withAuth } from '../lib/command.js';

export function registerLogsCommand(program: Command): void {
  program
    .command('logs <name>')
    .description('Tail container logs for an environment')
    .option('--since <duration>', 'How far back to start (e.g. 1h, 30m, 2d)', '1h')
    .option('--follow', 'Continuously stream new log events', false)
    .action(withAuth(async (name: string, opts) => {
        const spinner = ora('Verifying environment...').start();
        try {
          await getEnvironment(name);
        } catch {
          spinner.fail('Environment not found');
          process.stderr.write(
            chalk.red(`Environment "${name}" does not exist.\n`)
          );
          process.exit(1);
        }
        spinner.stop();

        const logGroupName = `/ecs/idp-${name}`;
        const region = getConfigValue('aws.region');

        process.stdout.write(`\nStreaming logs from ${chalk.cyan(logGroupName)}\n`);
        process.stdout.write(chalk.gray(`Region: ${region} | Since: ${opts.since}${opts.follow ? ' | Following...' : ''}\n\n`));

        const args = [
          'logs', 'tail', logGroupName,
          '--region', region,
          '--since', opts.since,
          '--format', 'short',
        ];

        if (opts.follow) {
          args.push('--follow');
        }

        const child = spawn('aws', args, {
          stdio: 'inherit',
          shell: true,
        });

        child.on('error', (err) => {
          process.stderr.write(
            chalk.red(`Failed to run aws CLI: ${err.message}\n`)
          );
          process.stderr.write(
            chalk.gray('Make sure the AWS CLI is installed and configured.\n')
          );
          process.exit(1);
        });

        child.on('exit', (code) => {
          if (code !== 0 && code !== null) {
            process.exit(code);
          }
        });
    }));
}
