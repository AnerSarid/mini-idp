#!/usr/bin/env node

import { Command } from 'commander';
import { registerAuthCommand } from './commands/auth.js';
import { registerCreateCommand } from './commands/create.js';
import { registerDestroyCommand } from './commands/destroy.js';
import { registerListCommand } from './commands/list.js';
import { registerExtendCommand } from './commands/extend.js';
import { registerTemplatesCommand } from './commands/templates.js';
import { registerUnlockCommand } from './commands/unlock.js';

const program = new Command();

program
  .name('idp')
  .description('Mini IDP CLI - Self-service infrastructure provisioning')
  .version('1.0.0');

registerAuthCommand(program);
registerCreateCommand(program);
registerDestroyCommand(program);
registerListCommand(program);
registerExtendCommand(program);
registerTemplatesCommand(program);
registerUnlockCommand(program);

program.parse(process.argv);
