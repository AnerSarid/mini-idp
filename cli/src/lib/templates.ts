export interface TemplateInfo {
  name: string;
  description: string;
  resources: string[];
  estimatedCost: string;
}

export const TEMPLATES: readonly TemplateInfo[] = [
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
] as const;

/** Valid template names derived from the canonical list. */
export type TemplateName = (typeof TEMPLATES)[number]['name'];

/** Flat array of template name strings — handy for validation and display. */
export const TEMPLATE_NAMES = TEMPLATES.map((t) => t.name);
