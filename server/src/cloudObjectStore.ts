import { createRequire } from 'node:module';

export interface CloudObjectStore {
  signUpload(key: string, md5: string, seconds: number, forbidOverwrite?: boolean): string;
  signDownload(key: string, seconds: number): string;
  head(key: string): Promise<{ bytes: number; etag: string }>;
  copy(source: string, destination: string, etag: string): Promise<void>;
  delete(key: string): Promise<void>;
}
interface ObsResult { CommonMsg: { Status: number }; InterfaceResult?: { ContentLength?: string; ETag?: string }; }
interface ObsSdk {
  createSignedUrlSync(params: object): { SignedUrl: string };
  getObjectMetadata(params: object): Promise<ObsResult>;
  copyObject(params: object): Promise<ObsResult>;
  deleteObject(params: object): Promise<ObsResult>;
}

/** The API handles metadata only. File bytes stay between the App and private OBS. */
export function createObsStore(options: { endpoint: string; bucket: string; region: string; ak: string; sk: string }): CloudObjectStore {
  const endpoint = new URL(options.endpoint);
  if (endpoint.protocol !== 'https:' || endpoint.username || endpoint.password || endpoint.search || endpoint.pathname !== '/') {
    throw new Error('OBS endpoint must be an HTTPS origin');
  }
  const ObsClient = createRequire(import.meta.url)('esdk-obs-nodejs') as new (options: object) => ObsSdk;
  const client = new ObsClient({ access_key_id: options.ak, secret_access_key: options.sk,
    server: endpoint.origin, region: options.region, is_secure: true, ssl_verify: true,
    signature: 'obs', timeout: 10, max_retry_count: 0 });
  const check = (result: ObsResult) => {
    if (result.CommonMsg.Status < 200 || result.CommonMsg.Status >= 300) {
      throw new Error(`OBS operation failed (${result.CommonMsg.Status})`);
    }
  };
  const sign = (params: object) => {
    const url = client.createSignedUrlSync(params).SignedUrl;
    if (!url || new URL(url).protocol !== 'https:') throw new Error('OBS signing failed');
    return url;
  };
  return {
    signUpload(key, md5, seconds, forbidOverwrite = false) {
      return sign({ Method: 'PUT', Bucket: options.bucket, Key: key, Expires: seconds,
        Headers: { 'Content-Type': 'application/octet-stream', 'Content-MD5': md5,
          ...(forbidOverwrite ? { 'x-obs-forbid-overwrite': 'true' } : {}) } });
    },
    signDownload(key, seconds) {
      return sign({ Method: 'GET', Bucket: options.bucket, Key: key, Expires: seconds,
        QueryParams: { 'response-cache-control': 'no-store' } });
    },
    async head(key) {
      const result = await client.getObjectMetadata({ Bucket: options.bucket, Key: key });
      check(result);
      const bytes = Number(result.InterfaceResult?.ContentLength), etag = result.InterfaceResult?.ETag;
      if (!Number.isSafeInteger(bytes) || bytes < 0 || !etag) throw new Error('OBS returned invalid object metadata');
      return { bytes, etag };
    },
    async copy(source, destination, etag) {
      // The SDK URL-encodes quotes in CopySourceIfMatch. Pass the bare MD5
      // for our single-PUT chunks, while rejecting wildcards and other ETag forms.
      const value = etag.trim();
      const copyEtag = value.startsWith('"') && value.endsWith('"') ? value.slice(1, -1) : value;
      if (!/^[a-fA-F0-9]{32}$/.test(copyEtag)) throw new Error('OBS copy requires a single-PUT MD5 ETag');
      const result = await client.copyObject({ Bucket: options.bucket, Key: destination,
        CopySource: `${options.bucket}/${source}`, CopySourceIfMatch: copyEtag });
      check(result);
      // CopyObject can return HTTP 200 with an error body; require its success result.
      if (!result.InterfaceResult?.ETag?.trim()) throw new Error('OBS copy returned no object ETag');
    },
    async delete(key) { check(await client.deleteObject({ Bucket: options.bucket, Key: key })); }
  };
}
