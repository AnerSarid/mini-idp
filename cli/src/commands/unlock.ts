import { Command } from 'commander';
import chalk from 'chalk';
import ora from 'ora';
import { requireAuth } from '../lib/config.js';
import { getEnvironment } from '../lib/environments.js';
import { DynamoDBClient, GetItemCommand, DeleteItemCommand } from '@aws-sdk/client-dynamodb';
import { getConfigValue } from '../lib/config.js';
import * as readline from 'readline';

const LOCK_TABLE = 'mini-idp-terraform-locks';
const STATE_BUCKET = 'mini-idp-terraform-state';

function prompt(question: string): Promise<string> {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });
  return new Promise((resolve) => {
    rl.question(question, (answer) => {
      rl.close();
      resolve(answer.trim());
    });
  });
}

function getDynamoClient(): DynamoDBClient {
  return new DynamoDBClient({ region: getConfigValue('aws.region') });
}

/**
 * Build the DynamoDB lock ID for an environment.
 * Terraform's S3 backend uses the format: <bucket>/<key>
 */
function buildLockId(environmentName: string): string {
  return `${STATE_BUCKET}/environments/${environmentName}/terraform.tfstate`;
}

export function registerUnlockCommand(program: Command): void {
  program
    .command('unlock <name>')
    .description('Force-unlock a stuck Terraform state lock for an environment')
    .option('--force', 'Skip confirmation prompt')
    .action(async (name: string, opts) => {
      try {
        requireAuth();

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
            TableName: LOCK_TABLE,
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
            TableName: LOCK_TABLE,
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
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        process.stderr.write(chalk.red(`Error: ${message}\n`));
        process.exit(1);
      }
    });
}
