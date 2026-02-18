import * as readline from 'readline';

/**
 * Prompt the user for input on the terminal.
 *
 * Creates a readline interface, asks the question, and resolves with
 * the trimmed answer. The interface is closed automatically.
 */
export function prompt(question: string): Promise<string> {
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
