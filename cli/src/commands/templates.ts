import { Command } from 'commander';
import chalk from 'chalk';

interface TemplateInfo {
  name: string;
  description: string;
  resources: string[];
  estimatedCost: string;
}

const TEMPLATES: TemplateInfo[] = [
  {
    name: 'api-service',
    description: 'ECS Fargate service with ALB, auto-scaling, and CloudWatch monitoring',
    resources: [
      'ECS Fargate Service',
      'Application Load Balancer',
      'CloudWatch Log Group & Alarms',
      'IAM Roles & Policies',
      'Security Groups',
    ],
    estimatedCost: '~$63/mo',
  },
  {
    name: 'api-database',
    description: 'ECS Fargate service with ALB and RDS PostgreSQL database',
    resources: [
      'ECS Fargate Service',
      'Application Load Balancer',
      'RDS PostgreSQL (db.t3.micro)',
      'CloudWatch Log Group & Alarms',
      'IAM Roles & Policies',
      'Security Groups',
      'DB Subnet Group',
    ],
    estimatedCost: '~$76/mo',
  },
  {
    name: 'scheduled-worker',
    description: 'EventBridge scheduled task running on ECS Fargate with optional S3 access',
    resources: [
      'ECS Fargate Task Definition',
      'EventBridge Scheduler Rule',
      'CloudWatch Log Group',
      'IAM Roles & Policies',
      'Security Groups',
      'S3 Access Policy (optional)',
    ],
    estimatedCost: '~$35/mo',
  },
];

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
