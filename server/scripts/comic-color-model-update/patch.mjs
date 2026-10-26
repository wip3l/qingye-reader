import fs from 'node:fs';
import path from 'node:path';
const [source, destination] = process.argv.slice(2);
const filename = path.join(source, 'index.js');
let text = fs.readFileSync(filename, 'utf8');
const importLine = "import { registerComicColorModelRoutes } from './comicColorModelRoutes.js';";
const registration = `registerComicColorModelRoutes(app,
  obs.endpoint && obs.region && obs.bucket && obs.ak && obs.sk ? createObsStore(obs) : null,
  { authenticate, userId: requiredUserId,
    limit: userId => enforceAccountRateLimit(userId, 'ai-model-download', 20) });`;
if (text.includes(importLine) || text.includes('registerComicColorModelRoutes(app,')) {
  // Permit whitespace emitted by tsc; reject partial or incompatible installations.
  const compact = value => value.replace(/\s+/g, '');
  if (!text.includes(importLine) || !compact(text).includes(compact(registration))) throw Error('BASELINE_MISMATCH: existing model route');
} else {
  for (const anchor of ["import { createObsStore } from './cloudObjectStore.js';", 'const obs = config.cloudFiles;']) {
    if (text.split(anchor).length !== 2) throw Error('BASELINE_MISMATCH: ' + anchor);
  }
  text = text.replace("import { createObsStore } from './cloudObjectStore.js';",
    "import { createObsStore } from './cloudObjectStore.js';\n" + importLine);
  text = text.replace('const obs = config.cloudFiles;', 'const obs = config.cloudFiles;\n' + registration);
}
fs.mkdirSync(destination, {recursive:true});
fs.writeFileSync(path.join(destination, 'index.js'), text);
console.log('PASS: model route patch prepared');
