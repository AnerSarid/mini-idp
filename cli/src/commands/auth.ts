import { Command } from 'commander';
import chalk from 'chalk';
import { setConfig, getConfig } from '../lib/config.js';
import { validateToken } from '../lib/github.js';
import { prompt } from '../lib/prompt.js';

export function registerAuthCommand(program: Command): void {
  const auth = program.command('auth').description('Authentication management');

  auth
    .command('login')
    .description('Authenticate with GitHub')
    .action(async () => {
      try {
        const token = await prompt('GitHub Personal Access Token: ');
        if (!token) {
          process.stderr.write(chalk.red('Token cannot be empty.\n'));
          process.exit(1);
        }

        process.stdout.write(chalk.gray('Validating token...\n'));
        const username = await validateToken(token);
        setConfig('github.token', token);
        process.stdout.write(
          chalk.green(`Authenticated as ${chalk.bold(username)}\n`)
        );

        const owner = await prompt(`GitHub repo owner [${username}]: `);
        setConfig('github.owner', owner || username);

        const currentRepo = getConfig().github.repo;
        const repo = await prompt(`GitHub repo name [${currentRepo}]: `);
        if (repo) {
          setConfig('github.repo', repo);
        }

        process.stdout.write(chalk.green('\nAuthentication configured.\n'));
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        process.stderr.write(chalk.red(`Authentication failed: ${message}\n`));
        process.exit(1);
      }
    });

  auth
    .command('status')
    .description('Show current authentication status')
    .action(() => {
      const cfg = getConfig();
      if (!cfg.github.token) {
        process.stdout.write(chalk.yellow('Not authenticated.\n'));
        return;
      }
      process.stdout.write(chalk.green('Authenticated\n'));
      process.stdout.write(`  Owner: ${cfg.github.owner}\n`);
      process.stdout.write(`  Repo:  ${cfg.github.repo}\n`);
      process.stdout.write(`  Region: ${cfg.aws.region}\n`);
      process.stdout.write(`  State Bucket: ${cfg.aws.stateBucket}\n`);
    });

  auth
    .command('logout')
    .description('Clear stored credentials')
    .action(() => {
      setConfig('github.token', '');
      setConfig('github.owner', '');
      process.stdout.write(chalk.green('Logged out.\n'));
    });
}
