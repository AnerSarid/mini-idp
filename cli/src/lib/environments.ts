import {
  S3Client,
  ListObjectsV2Command,
  GetObjectCommand,
  PutObjectCommand,
} from '@aws-sdk/client-s3';
import { getConfigValue } from './config.js';

export interface EnvironmentMetadata {
  name: string;
  template: string;
  owner: string;
  status: string;
  created_at: string;
  expires_at: string;
  ttl: string;
  inputs: Record<string, string>;
}

export interface EnvironmentOutputs {
  [key: string]: string;
}

function getS3Client(): S3Client {
  return new S3Client({ region: getConfigValue('aws.region') });
}

function getBucket(): string {
  return getConfigValue('aws.stateBucket');
}

async function streamToString(stream: NodeJS.ReadableStream): Promise<string> {
  const chunks: Buffer[] = [];
  for await (const chunk of stream) {
    chunks.push(Buffer.from(chunk));
  }
  return Buffer.concat(chunks).toString('utf-8');
}

export async function listEnvironments(): Promise<EnvironmentMetadata[]> {
  const client = getS3Client();
  const bucket = getBucket();

  const command = new ListObjectsV2Command({
    Bucket: bucket,
    Prefix: 'environments/',
    Delimiter: '',
  });

  const response = await client.send(command);
  const metadataKeys = (response.Contents ?? [])
    .map((obj) => obj.Key!)
    .filter((key) => key.endsWith('/metadata.json'));

  const environments: EnvironmentMetadata[] = [];

  for (const key of metadataKeys) {
    try {
      const getCmd = new GetObjectCommand({ Bucket: bucket, Key: key });
      const result = await client.send(getCmd);
      const body = await streamToString(result.Body as NodeJS.ReadableStream);
      environments.push(JSON.parse(body) as EnvironmentMetadata);
    } catch {
      // Skip environments with unreadable metadata
    }
  }

  return environments;
}

export async function getEnvironment(
  name: string
): Promise<{ metadata: EnvironmentMetadata; outputs: EnvironmentOutputs | null }> {
  const client = getS3Client();
  const bucket = getBucket();

  const metadataCmd = new GetObjectCommand({
    Bucket: bucket,
    Key: `environments/${name}/metadata.json`,
  });

  const metadataResult = await client.send(metadataCmd);
  const metadataBody = await streamToString(
    metadataResult.Body as NodeJS.ReadableStream
  );
  const metadata = JSON.parse(metadataBody) as EnvironmentMetadata;

  let outputs: EnvironmentOutputs | null = null;
  try {
    const outputsCmd = new GetObjectCommand({
      Bucket: bucket,
      Key: `environments/${name}/outputs.json`,
    });
    const outputsResult = await client.send(outputsCmd);
    const outputsBody = await streamToString(
      outputsResult.Body as NodeJS.ReadableStream
    );
    outputs = JSON.parse(outputsBody) as EnvironmentOutputs;
  } catch {
    // Outputs may not exist yet
  }

  return { metadata, outputs };
}

export async function getEnvironmentOutputs(
  name: string
): Promise<EnvironmentOutputs | null> {
  const client = getS3Client();
  const bucket = getBucket();

  try {
    const command = new GetObjectCommand({
      Bucket: bucket,
      Key: `environments/${name}/outputs.json`,
    });
    const result = await client.send(command);
    const body = await streamToString(result.Body as NodeJS.ReadableStream);
    return JSON.parse(body) as EnvironmentOutputs;
  } catch {
    return null;
  }
}

export async function updateEnvironmentMetadata(
  name: string,
  metadata: EnvironmentMetadata
): Promise<void> {
  const client = getS3Client();
  const bucket = getBucket();

  const command = new PutObjectCommand({
    Bucket: bucket,
    Key: `environments/${name}/metadata.json`,
    Body: JSON.stringify(metadata, null, 2),
    ContentType: 'application/json',
  });

  await client.send(command);
}

export async function environmentExists(name: string): Promise<boolean> {
  try {
    await getEnvironment(name);
    return true;
  } catch {
    return false;
  }
}
