import chalk from 'chalk';
import { requireAuth } from './config.js';

/**
 * Wraps an async command action with:
 *  1. requireAuth() guard
 *  2. Consistent error formatting + process.exit(1)
 *
 * Commands become:
 *   .action(withAuth(async (name, opts) => { ... }))
 *
 * instead of repeating the try/catch + requireAuth boilerplate.
 */
export function withAuth<T extends unknown[]>(
  fn: (...args: T) => Promise<void>
): (...args: T) => Promise<void> {
  return async (...args: T) => {
    try {
      requireAuth();
      await fn(...args);
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      process.stderr.write(chalk.red(`Error: ${message}\n`));
      process.exit(1);
    }
  };
}
