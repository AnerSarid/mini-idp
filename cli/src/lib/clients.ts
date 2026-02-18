/**
 * Lazy singleton AWS SDK clients.
 *
 * The AWS SDK v3 manages connection pooling, credential caching, and retry
 * state internally per client instance. Creating a new client on every call
 * defeats all of that. These singletons ensure we reuse a single client
 * across the CLI session.
 */

import { S3Client } from '@aws-sdk/client-s3';
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { getConfigValue } from './config.js';

let _s3: S3Client | null = null;
let _dynamo: DynamoDBClient | null = null;

export function getS3Client(): S3Client {
  return (_s3 ??= new S3Client({ region: getConfigValue('aws.region') }));
}

export function getDynamoClient(): DynamoDBClient {
  return (_dynamo ??= new DynamoDBClient({ region: getConfigValue('aws.region') }));
}
