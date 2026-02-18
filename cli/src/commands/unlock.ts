import { Command } from 'commander';
import chalk from 'chalk';
import ora from 'ora';
import { getEnvironment } from '../lib/environments.js';
import { GetItemCommand, DeleteItemCommand } from '@aws-sdk/client-dynamodb';
import { getConfigValue } from '../lib/config.js';
import { prompt } from '../lib/prompt.js';
import { getDynamoClient } from '../lib/clients.js';
import { withAuth } from '../lib/command.js';

function getLockTable(): string {
  return getConfigValue('aws.lockTable');
}

function getStateBucket(): string {
  return getConfigValue('aws.stateBucket');
}

/**
 * Build the DynamoDB lock ID for an environment.
 * Terraform's S3 backend uses the format: <bucket>/<key>
 */
function buildLockId(environmentName: string): string {
  return `${getStateBucket()}/environments/${environmentName}/terraform.tfstate`;
}

export function registerUnlockCommand(program: Command): void {
  program
    .command('unlock <name>')
    .description('Force-unlock a stuck Terraform state lock for an environment')
    .option('--force', 'Skip confirmation prompt')
    .action(withAuth(async (name: string, opts) => {
        // Verify the environment exists
        const envSpinner = ora('Checking environment...').start();
        try {
          await getEnvironment(name);
        } catch {
          envSpinner.fail('Environment not found');
          process.stderr.write(
            chalk.red(`Environment "${name}" does not exist in S3.\n`)
          );
          process.exit(1);
        }
        envSpinner.stop();

        const client = getDynamoClient();
        const lockId = buildLockId(name);

        // Check if a lock exists
        const checkSpinner = ora('Checking for state lock...').start();
        const getResult = await client.send(
          new GetItemCommand({
            TableName: getLockTable(),
            Key: { LockID: { S: lockId } },
          })
        );

        if (!getResult.Item || !getResult.Item.Info) {
          checkSpinner.succeed('No active lock found');
          process.stdout.write(
            chalk.green(`\nEnvironment "${name}" is not locked.\n`)
          );
          return;
        }

        checkSpinner.stop();

        // Parse lock info
        let lockInfo: { ID?: string; Created?: string; Info?: string; Who?: string; Operation?: string } = {};
        try {
          lockInfo = JSON.parse(getResult.Item.Info.S ?? '{}');
        } catch {
          // Lock exists but info is unparseable
        }

        process.stdout.write('\n');
        process.stdout.write(chalk.bold.yellow('Active State Lock Found\n'));
        process.stdout.write(`  Environment: ${chalk.cyan(name)}\n`);
        process.stdout.write(`  Lock ID:     ${lockInfo.ID ?? 'unknown'}\n`);
        process.stdout.write(`  Created:     ${lockInfo.Created ?? 'unknown'}\n`);
        process.stdout.write(`  Operation:   ${lockInfo.Operation ?? 'unknown'}\n`);
        process.stdout.write(`  Who:         ${lockInfo.Who ?? 'unknown'}\n`);
        if (lockInfo.Info) {
          process.stdout.write(`  Info:        ${lockInfo.Info}\n`);
        }
        process.stdout.write('\n');
        process.stdout.write(
          chalk.yellow(
            'WARNING: Only unlock if you are certain no Terraform operation is running.\n' +
            'Unlocking during an active operation can corrupt your state.\n'
          )
        );

        if (!opts.force) {
          const confirm = await prompt('Type "unlock" to confirm: ');
          if (confirm !== 'unlock') {
            process.stdout.write(chalk.yellow('Aborted.\n'));
            return;
          }
        }

        const unlockSpinner = ora('Removing state lock...').start();
        await client.send(
          new DeleteItemCommand({
            TableName: getLockTable(),
            Key: { LockID: { S: lockId } },
          })
        );
        unlockSpinner.succeed('State lock removed');

        process.stdout.write(
          chalk.green(`\nEnvironment "${name}" has been unlocked.\n`)
        );
        process.stdout.write(
          chalk.gray('You can now re-run provision or destroy workflows.\n')
        );
    }));
}
