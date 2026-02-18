import { Command } from 'commander';
import chalk from 'chalk';
import { TEMPLATES } from '../lib/templates.js';

export function registerTemplatesCommand(program: Command): void {
  program
    .command('templates')
    .description('List available environment templates')
    .option('--json', 'Output as JSON')
    .action((opts) => {
      if (opts.json) {
        process.stdout.write(JSON.stringify(TEMPLATES, null, 2) + '\n');
        return;
      }

      process.stdout.write(chalk.bold('\nAvailable Templates\n'));
      process.stdout.write(chalk.gray('='.repeat(60)) + '\n\n');

      for (const template of TEMPLATES) {
        process.stdout.write(chalk.bold.cyan(template.name) + '\n');
        process.stdout.write(`  ${template.description}\n`);
        process.stdout.write(`  Estimated cost: ${chalk.yellow(template.estimatedCost)}\n`);
        process.stdout.write(chalk.gray('  Resources:\n'));
        for (const resource of template.resources) {
          process.stdout.write(chalk.gray(`    - ${resource}\n`));
        }
        process.stdout.write('\n');
      }

      process.stdout.write(
        chalk.gray('Use `idp create --template <name>` to provision an environment.\n\n')
      );
    });
}
