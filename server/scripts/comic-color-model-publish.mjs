import { createHash } from 'node:crypto';

const obsCodes = new Set(['AccessDenied', 'NoSuchKey', 'NoSuchBucket', 'SignatureDoesNotMatch',
  'InvalidAccessKeyId', 'RequestTimeTooSkewed', 'RequestExpired', 'BadDigest', 'EntityTooLarge',
  'ObjectAlreadyExists', 'FileAlreadyExists', 'PreconditionFailed', 'InternalError', 'SlowDown']);
const networkCodes = new Set(['ENOTFOUND','EAI_AGAIN','ECONNRESET','ECONNREFUSED','ETIMEDOUT',
  'UND_ERR_CONNECT_TIMEOUT','UND_ERR_HEADERS_TIMEOUT','UND_ERR_BODY_TIMEOUT','CERT_HAS_EXPIRED',
  'UNABLE_TO_VERIFY_LEAF_SIGNATURE','DEPTH_ZERO_SELF_SIGNED_CERT']);

class PublishFailure extends Error {}
async function httpFailure(response) {
  const body = (await response.text()).slice(0, 16384);
  const code = /<Code>([A-Za-z0-9]+)<\/Code>/.exec(body)?.[1];
  return new PublishFailure(`HTTP ${response.status}${obsCodes.has(code) ? ` ${code}` : ''}`);
}
export function safePublishError(error) {
  if (error instanceof PublishFailure) return error.message;
  const status = /^OBS operation failed \((\d{3})\)$/.exec(error?.message || '');
  if (status) return `HTTP ${status[1]}`;
  for (const code of [error?.code,error?.cause?.code]) if (networkCodes.has(code)) return code;
  if (error?.name === 'TimeoutError') return 'TIMEOUT';
  return 'REQUEST_FAILED';
}

/** Local bytes must be verified before calling. Never interpret HEAD 403 as definitive absence. */
export async function publishModel({model, body, key, store, fetcher = fetch, log = console.log}) {
  let phase = 'HEAD';
  const get = () => fetcher(store.signDownload(key, 1800), {
    redirect: 'error', signal: AbortSignal.timeout(600000) });
  try {
    log(`Checking ${model.file}`);
    let exists = false, readback;
    try { await store.head(key); exists = true; } catch (error) {
      if (!/^OBS operation failed \((403|404)\)$/.test(error?.message || '')) throw error;
      if (error.message === 'OBS operation failed (403)') {
        log(`HEAD 403 for ${model.file}; checking GET before protected upload`);
        phase = 'GET before upload';
        readback = await get();
        if (readback.ok) exists = true;
        else if (readback.status === 403 || readback.status === 404) {
          await readback.body?.cancel(); readback = undefined;
        } else throw await httpFailure(readback);
      }
    }
    if (!exists) {
      phase = 'PUT';
      log(`Uploading ${model.file}`);
      const md5 = createHash('md5').update(body).digest('base64');
      const response = await fetcher(store.signUpload(key, md5, 1800, true), { method:'PUT',
        headers:{'Content-Type':'application/octet-stream','Content-MD5':md5,'x-obs-forbid-overwrite':'true'},
        body, redirect:'error', signal:AbortSignal.timeout(600000) });
      // A concurrent protected upload may win. Never trust conflict alone: verify the resulting object.
      if (!response.ok && response.status !== 409 && response.status !== 412) throw await httpFailure(response);
      await response.body?.cancel();
    }
    phase = 'GET verification';
    log(`Verifying remote ${model.file}`);
    const response = readback || await get();
    if (!response.ok) throw await httpFailure(response);
    const hash = createHash('sha256'); let bytes = 0;
    for await (const chunk of response.body) {
      bytes += chunk.length;
      if (bytes > model.bytes) throw new PublishFailure('REMOTE_SIZE_MISMATCH');
      hash.update(chunk);
    }
    if (bytes !== model.bytes || hash.digest('hex') !== model.sha256) throw new PublishFailure('REMOTE_HASH_MISMATCH');
    log(`Published and verified ${model.file}`);
  } catch (error) {
    throw new PublishFailure(`${model.file} | ${phase} | ${safePublishError(error)}`);
  }
}
