import { readFile } from 'node:fs/promises';
import { parseMembershipSalesPilot } from './membershipSales.js';

function required(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

function positiveInt(name: string, fallback: number): number {
  const value = Number(process.env[name] || fallback);
  return Number.isSafeInteger(value) && value > 0 ? value : fallback;
}

function nonNegativeInt(name: string, fallback: number): number {
  const value = Number(process.env[name] ?? fallback);
  return Number.isSafeInteger(value) && value >= 0 ? value : fallback;
}

function csvSet(name: string, fallback: string): ReadonlySet<string> {
  const values = (process.env[name]?.trim() || fallback)
    .split(',')
    .map((value) => value.trim().toUpperCase())
    .filter(Boolean);
  return new Set(values);
}

export const config = {
  membershipEnabled: process.env.MEMBERSHIP_ENABLED === 'true',
  membershipSalesPilot: parseMembershipSalesPilot(process.env.MEMBERSHIP_PILOT_USER_IDS,
    process.env.MEMBERSHIP_PILOT_SKUS, process.env.MEMBERSHIP_PILOT_UNTIL),
  membershipSourceLimitsEnabled: process.env.MEMBERSHIP_SOURCE_LIMITS_ENABLED === 'true',
  lottery: {
    campaignId: process.env.LOTTERY_CAMPAIGN_ID?.trim() || 'double11-2026',
    // e.g. https://huodong.example.com; the page and /lottery/api/ must share this origin.
    pageOrigin: (process.env.LOTTERY_PAGE_ORIGIN?.trim() || '').replace(/\/+$/, '')
  },
  cloudFiles: {
    enabled: process.env.CLOUD_FILES_ENABLED === 'true',
    endpoint: process.env.HUAWEICLOUD_OBS_ENDPOINT?.trim() || '',
    region: process.env.HUAWEICLOUD_OBS_REGION?.trim() || '',
    bucket: process.env.HUAWEICLOUD_OBS_BUCKET?.trim() || '',
    ak: process.env.HUAWEICLOUD_OBS_AK?.trim() || '',
    sk: process.env.HUAWEICLOUD_OBS_SK?.trim() || ''
  },
  port: Number(process.env.PORT || '8080'),
  host: process.env.HOST?.trim() || '127.0.0.1',
  publicBaseUrl: (process.env.PUBLIC_BASE_URL?.trim() || 'https://qingye.icynol.com').replace(/\/+$/, ''),
  databaseUrl: required('DATABASE_URL'),
  sessionSecret: required('SESSION_SECRET'),
  huaweiClientId: required('HUAWEI_CLIENT_ID'),
  huaweiClientSecret: required('HUAWEI_CLIENT_SECRET'),
  huaweiRedirectUri: process.env.HUAWEI_REDIRECT_URI?.trim() || '',
  huaweiAppId: required('HUAWEI_APP_ID'),
  huaweiBundleName: process.env.HUAWEI_BUNDLE_NAME?.trim() || 'io.legado.read',
  iapKeyId: required('HUAWEI_IAP_KEY_ID'),
  iapIssuerId: required('HUAWEI_IAP_ISSUER_ID'),
  iapPrivateKeyPath: required('HUAWEI_IAP_PRIVATE_KEY_PATH'),
  iapRootCaPath: required('HUAWEI_IAP_ROOT_CA_PATH'),
  iapRootUrl: required('HUAWEI_IAP_ROOT_URL').replace(/\/+$/, ''),
  iap: {
    deliverableStatuses: csvSet(
      'HUAWEI_IAP_DELIVERABLE_STATUSES',
      required('HUAWEI_IAP_DELIVERABLE_STATUSES')
    ),
    revocationStatuses: csvSet(
      'HUAWEI_IAP_REVOCATION_STATUSES',
      '2,3,4,5,CANCELED,CANCELLED,REFUNDED,REVOKED,FAILED,EXPIRED'
    ),
    reconciliationIntervalMs: positiveInt(
      'HUAWEI_IAP_RECONCILIATION_INTERVAL_MS',
      6 * 60 * 60 * 1000
    ),
    reconciliationBatchSize: positiveInt('HUAWEI_IAP_RECONCILIATION_BATCH_SIZE', 50)
  },
  http: {
    trustedProxies: (process.env.TRUSTED_PROXIES?.trim() || '127.0.0.1,::1')
      .split(',')
      .map((value) => value.trim())
      .filter(Boolean),
    upstreamTimeoutMs: positiveInt('UPSTREAM_HTTP_TIMEOUT_MS', 15_000),
    globalRateLimitPerMinute: positiveInt('GLOBAL_RATE_LIMIT_PER_MINUTE', 120),
    authRateLimitPerMinute: positiveInt('AUTH_RATE_LIMIT_PER_MINUTE', 10),
    sensitiveRateLimitPerMinute: positiveInt('SENSITIVE_RATE_LIMIT_PER_MINUTE', 20),
    // Sync exchange is a paginated bulk operation. It needs a separate budget
    // from point/TTS redemption endpoints, otherwise a normal first download
    // is rejected after only twenty pages.
    syncRateLimitPerMinute: positiveInt('SYNC_RATE_LIMIT_PER_MINUTE', 120)
  },
  auth: {
    sessionTtlDays: positiveInt('SESSION_TTL_DAYS', 7)
  },
  database: {
    connectionTimeoutMs: positiveInt('DATABASE_CONNECTION_TIMEOUT_MS', 5_000),
    queryTimeoutMs: positiveInt('DATABASE_QUERY_TIMEOUT_MS', 20_000),
    statementTimeoutMs: positiveInt('DATABASE_STATEMENT_TIMEOUT_MS', 15_000),
    idleTransactionTimeoutMs: positiveInt('DATABASE_IDLE_TRANSACTION_TIMEOUT_MS', 15_000)
  },
  sis: {
    ak: process.env.HUAWEICLOUD_SIS_AK?.trim() || '',
    sk: process.env.HUAWEICLOUD_SIS_SK?.trim() || '',
    projectId: process.env.HUAWEICLOUD_SIS_PROJECT_ID?.trim() || '',
    region: process.env.HUAWEICLOUD_SIS_REGION?.trim() || 'cn-north-4',
    endpoint: (
      process.env.HUAWEICLOUD_SIS_ENDPOINT?.trim()
      || 'https://sis-ext.cn-north-4.myhuaweicloud.com'
    ).replace(/\/+$/, ''),
    dailyBillingUnitLimit: positiveInt('HUAWEICLOUD_SIS_DAILY_BILLING_UNIT_LIMIT', 25_000),
    perUserRequestsPerMinute: positiveInt('HUAWEICLOUD_SIS_USER_REQUESTS_PER_MINUTE', 30),
    maxConcurrent: positiveInt('HUAWEICLOUD_SIS_MAX_CONCURRENT', 6),
    maxConcurrentPerUser: positiveInt('HUAWEICLOUD_SIS_MAX_CONCURRENT_PER_USER', 2),
    queueLimit: nonNegativeInt('HUAWEICLOUD_SIS_QUEUE_LIMIT', 20),
    queueTimeoutMs: positiveInt('HUAWEICLOUD_SIS_QUEUE_TIMEOUT_MS', 10_000),
    cacheMaxBytes: positiveInt('HUAWEICLOUD_SIS_CACHE_MAX_BYTES', 128 * 1024 * 1024),
    cacheMaxEntryBytes: positiveInt('HUAWEICLOUD_SIS_CACHE_MAX_ENTRY_BYTES', 8 * 1024 * 1024),
    cacheTtlMs: positiveInt('HUAWEICLOUD_SIS_CACHE_TTL_MS', 5 * 60 * 1000),
    usageRetentionDays: positiveInt('TTS_USAGE_RETENTION_DAYS', 30)
  },
  sync: {
    requestBodyLimitBytes: positiveInt('SYNC_REQUEST_BODY_LIMIT_BYTES', 2 * 1024 * 1024),
    responseBodyLimitBytes: positiveInt('SYNC_RESPONSE_BODY_LIMIT_BYTES', 2 * 1024 * 1024),
    maxDevicesPerUser: positiveInt('SYNC_MAX_DEVICES_PER_USER', 20),
    maxEntitiesPerUser: positiveInt('SYNC_MAX_ENTITIES_PER_USER', 20_000),
    maxEntityBytesPerUser: positiveInt('SYNC_MAX_ENTITY_BYTES_PER_USER', 128 * 1024 * 1024),
    maxChangesPerUser: positiveInt('SYNC_MAX_CHANGES_PER_USER', 100_000),
    maxChangeBytesPerUser: positiveInt('SYNC_MAX_CHANGE_BYTES_PER_USER', 256 * 1024 * 1024),
    maxDailyWritesPerUser: positiveInt('SYNC_MAX_DAILY_WRITES_PER_USER', 5_000),
    initialMaxDailyWritesPerUser: positiveInt(
      'SYNC_INITIAL_MAX_DAILY_WRITES_PER_USER',
      20_000
    ),
    initialSyncWindowMs: positiveInt('SYNC_INITIAL_WINDOW_MS', 24 * 60 * 60 * 1000),
    responseCompressionThresholdBytes: positiveInt(
      'SYNC_RESPONSE_COMPRESSION_THRESHOLD_BYTES',
      1024
    ),
    // Receipts only make retried uploads idempotent; three days covers offline retries.
    receiptRetentionDays: positiveInt('SYNC_RECEIPT_RETENTION_DAYS', 3),
    maintenanceIntervalMs: positiveInt('SYNC_MAINTENANCE_INTERVAL_MS', 6 * 60 * 60 * 1000)
  }
};

export async function readSecretFile(path: string): Promise<string> {
  return (await readFile(path, 'utf8')).trim();
}
