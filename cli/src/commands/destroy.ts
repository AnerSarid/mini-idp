import { Command } from 'commander';
import chalk from 'chalk';
import ora from 'ora';
import { triggerWorkflow, waitForWorkflowCompletion } from '../lib/github.js';
import { getEnvironment } from '../lib/environments.js';
import { prompt } from '../lib/prompt.js';
import { withAuth } from '../lib/command.js';

export function registerDestroyCommand(program: Command): void {
  program
    .command('destroy <name>')
    .description('Destroy an environment')
    .action(withAuth(async (name: string) => {
        const spinner = ora('Fetching environment details...').start();
        let env;
        try {
          env = await getEnvironment(name);
        } catch {
          spinner.fail('Environment not found');
          process.stderr.write(chalk.red(`Environment "${name}" does not exist.\n`));
          process.exit(1);
        }
        spinner.stop();

        process.stdout.write('\n');
        process.stdout.write(chalk.bold.red('Destroy Environment\n'));
        process.stdout.write(`  Name:     ${chalk.cyan(name)}\n`);
        process.stdout.write(`  Template: ${env.metadata.template}\n`);
        process.stdout.write(`  Owner:    ${env.metadata.owner}\n`);
        process.stdout.write(`  Created:  ${env.metadata.created_at}\n`);
        process.stdout.write('\n');
        process.stdout.write(
          chalk.yellow('This will permanently destroy all resources.\n')
        );

        const confirm = await prompt(`Type "${name}" to confirm: `);
        if (confirm !== name) {
          process.stdout.write(chalk.yellow('Aborted.\n'));
          return;
        }

        const createdAfter = new Date();

        const triggerSpinner = ora('Triggering destroy workflow...').start();
        await triggerWorkflow('destroy.yml', {
          environment_name: name,
        });
        triggerSpinner.succeed('Workflow triggered');

        const waitSpinner = ora('Waiting for destruction to complete...').start();
        const result = await waitForWorkflowCompletion(
          'destroy.yml',
          createdAfter
        );
        waitSpinner.stop();

        if (result.conclusion === 'success') {
          process.stdout.write(
            chalk.green(`\nEnvironment "${name}" destroyed successfully.\n`)
          );
          process.stdout.write(`Workflow: ${chalk.gray(result.html_url)}\n`);
        } else {
          process.stderr.write(
            chalk.red(`\nDestroy failed: ${result.conclusion}\n`)
          );
          process.stderr.write(`Workflow: ${result.html_url}\n`);
          process.exit(1);
        }
    }));
}
