// Explicit release step. Credentials come only from the existing server environment.
import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { createHash } from 'node:crypto';
import { createObsStore } from '../dist/cloudObjectStore.js';
import { COMIC_COLOR_MODELS, comicColorObjectKey } from '../dist/comicColorModels.js';
import { publishModel, safePublishError } from './comic-color-model-publish.mjs';

for (const key of Object.keys(process.env)) if (/^(http_proxy|https_proxy|all_proxy)$/i.test(key)) delete process.env[key];
process.env.NO_PROXY = '*'; process.env.no_proxy = '*';
const folder = resolve(process.argv[2] || '../harmony-book-ai-engine/models/comic-colorizer');
const apply = process.argv.includes('--upload');
const data = [];
for (const model of COMIC_COLOR_MODELS) {
  const body = await readFile(resolve(folder, model.file));
  if (body.length !== model.bytes || createHash('sha256').update(body).digest('hex') !== model.sha256) {
    throw new Error(`Invalid local model: ${model.file}`);
  }
  data.push({ model, body });
  console.log(`Verified ${model.file}: ${model.bytes} bytes`);
}
if (!apply) { console.log('Local validation complete. Add --upload to publish to private OBS.'); process.exit(0); }
const e = process.env;
for (const key of ['ENDPOINT', 'REGION', 'BUCKET', 'AK', 'SK']) {
  if (!e['HUAWEICLOUD_OBS_' + key]) throw new Error(`Missing HUAWEICLOUD_OBS_${key}`);
}
try {
  const store = createObsStore({ endpoint: e.HUAWEICLOUD_OBS_ENDPOINT, region: e.HUAWEICLOUD_OBS_REGION,
    bucket: e.HUAWEICLOUD_OBS_BUCKET, ak: e.HUAWEICLOUD_OBS_AK, sk: e.HUAWEICLOUD_OBS_SK });
  for (const { model, body } of data) {
    await publishModel({ model, body, key: comicColorObjectKey(model), store });
  }
} catch (error) {
  // SDK/fetch errors can contain credentials or signed URLs; deliberately do not print them.
  console.error(`OBS publication failed: ${safePublishError(error)}`);
  console.error('PUT/GET 403 AccessDenied: check OBS permissions for qingye/ai/comic-colorizer/.');
  process.exitCode = 1;
}
