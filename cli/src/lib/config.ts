import Conf from 'conf';

interface IdpConfig {
  github: {
    token: string;
    owner: string;
    repo: string;
  };
  aws: {
    region: string;
    stateBucket: string;
    lockTable: string;
    ecrRepo: string;
  };
}

const config = new Conf<IdpConfig>({
  projectName: 'mini-idp',
  defaults: {
    github: {
      token: '',
      owner: '',
      repo: 'mini-idp',
    },
    aws: {
      region: 'us-east-1',
      stateBucket: 'mini-idp-terraform-state',
      lockTable: 'mini-idp-terraform-locks',
      ecrRepo: 'mini-idp-preview',
    },
  },
});

type ConfigPath =
  | 'github.token'
  | 'github.owner'
  | 'github.repo'
  | 'aws.region'
  | 'aws.stateBucket'
  | 'aws.lockTable'
  | 'aws.ecrRepo';

export function getConfig(): IdpConfig {
  return {
    github: config.get('github'),
    aws: config.get('aws'),
  };
}

export function getConfigValue(key: ConfigPath): string {
  return config.get(key) as string;
}

export function setConfig(key: ConfigPath, value: string): void {
  config.set(key, value);
}

export function requireAuth(): void {
  const token = getConfigValue('github.token');
  const owner = getConfigValue('github.owner');
  if (!token || !owner) {
    process.stderr.write('Not authenticated. Run `idp auth login` first.\n');
    process.exit(1);
  }
}
