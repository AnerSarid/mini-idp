import { Octokit } from '@octokit/rest';
import { getConfigValue } from './config.js';

function getOctokit(): Octokit {
  const token = getConfigValue('github.token');
  return new Octokit({ auth: token });
}

function getRepoInfo(): { owner: string; repo: string } {
  return {
    owner: getConfigValue('github.owner'),
    repo: getConfigValue('github.repo'),
  };
}

export async function triggerWorkflow(
  workflowFile: string,
  inputs: Record<string, string>
): Promise<void> {
  const octokit = getOctokit();
  const { owner, repo } = getRepoInfo();

  await octokit.actions.createWorkflowDispatch({
    owner,
    repo,
    workflow_id: workflowFile,
    ref: 'main',
    inputs,
  });
}

export async function getWorkflowRun(runId: number): Promise<{
  id: number;
  status: string | null;
  conclusion: string | null;
  html_url: string;
}> {
  const octokit = getOctokit();
  const { owner, repo } = getRepoInfo();

  const { data } = await octokit.actions.getWorkflowRun({
    owner,
    repo,
    run_id: runId,
  });

  return {
    id: data.id,
    status: data.status,
    conclusion: data.conclusion,
    html_url: data.html_url,
  };
}

export async function waitForWorkflowCompletion(
  workflowFile: string,
  createdAfter: Date,
  timeoutMs: number = 30 * 60 * 1000
): Promise<{ conclusion: string; html_url: string }> {
  const octokit = getOctokit();
  const { owner, repo } = getRepoInfo();

  const pollInterval = 10_000;
  const startTime = Date.now();

  while (Date.now() - startTime < timeoutMs) {
    const { data } = await octokit.actions.listWorkflowRuns({
      owner,
      repo,
      workflow_id: workflowFile,
      created: `>=${createdAfter.toISOString()}`,
      per_page: 1,
    });

    if (data.workflow_runs.length > 0) {
      const run = data.workflow_runs[0];

      if (run.status === 'completed') {
        return {
          conclusion: run.conclusion ?? 'unknown',
          html_url: run.html_url,
        };
      }
    }

    await sleep(pollInterval);
  }

  const timeoutMin = Math.round(timeoutMs / 60_000);
  throw new Error(`Workflow timed out after ${timeoutMin} minutes`);
}

export async function validateToken(token: string): Promise<string> {
  const octokit = new Octokit({ auth: token });
  const { data } = await octokit.users.getAuthenticated();
  return data.login;
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
