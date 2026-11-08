import fs from 'node:fs';
import path from 'node:path';

const projectRoot = path.resolve(import.meta.dirname, '..');
const scanRoots = [
  'entry/src/main/ets/core/book',
  'harmony-book-source-engine/sourceengine/src/main/ets/core/book',
  'harmony-book-source-engine/sourceengine/src/main/ets/core/http',
  'harmony-book-source-engine/sourceengine/src/main/ets/core/nativesource',
  'harmony-book-source-engine/sourceengine/src/main/ets/core/rule',
  'entry/src/main/ets/pages/BookSource.ets',
  'entry/src/main/ets/pages/ReadBook.ets',
  'entry/src/main/ets/pages/VerifyWeb.ets',
  'entry/src/main/ets/utils/CoverUrlNormalizer.ts'
];

// This is a regression check for previously embedded content adapters. It is not a legal opinion.
const forbidden = [
  ['fixed content URL', /https?:\/\/[a-z0-9.-]+\.(?:com|cn|cf|top|net|org)\/[a-z0-9_/?=&.-]+/i],
  ['legacy default credential', /tongrenshuqi134679/i],
  ['legacy content adapter', /BookSourceShuqiSupport|shuqi-comments|legado-shuqi-comment/i],
  ['platform-specific content API', /qidian_full_api|novel\.snssdk\.com|sinfonlineb\.fqnovel\.com/i],
  ['hardcoded aggregator host', /(?:101\.35\.133\.34|219\.154\.201\.122|aadcn|vossc\.com|langge\.cf|czyl\.cf|gyks\.cf)/i]
];

function filesUnder(target) {
  const absolute = path.join(projectRoot, target);
  const stat = fs.statSync(absolute);
  if (stat.isFile()) return [absolute];
  return fs.readdirSync(absolute, { withFileTypes: true }).flatMap((entry) => {
    const child = path.join(absolute, entry.name);
    if (entry.isDirectory()) return filesUnder(path.relative(projectRoot, child));
    return /\.(?:ets|ts)$/.test(entry.name) ? [child] : [];
  });
}

// W3C namespace URIs (XLink, SVG, XHTML) are identifiers, never fetched, so they are not content endpoints.
const namespaceUri = /https?:\/\/www\.w3\.org\/[a-z0-9_/.-]*/gi;

const failures = [];
for (const file of scanRoots.flatMap(filesUnder)) {
  const content = fs.readFileSync(file, 'utf8').replace(namespaceUri, '');
  for (const [label, pattern] of forbidden) {
    if (pattern.test(content)) failures.push(`${path.relative(projectRoot, file)}: ${label}`);
  }
}

const webBookService = fs.readFileSync(
  path.join(projectRoot, 'entry/src/main/ets/core/book/WebBookService.ts'), 'utf8');
if (!webBookService.includes('if (EncodedSourceUrl.isEncodedDataUrl(value))')) {
  failures.push('WebBookService.ts: encoded chapter descriptors are not protected from query-tail extraction');
}

if (failures.length > 0) {
  console.error('Neutral source-engine check failed:');
  failures.forEach((failure) => console.error(`- ${failure}`));
  process.exitCode = 1;
} else {
  console.log('Neutral source-engine check passed: no embedded content endpoint, default credential, or known platform adapter found.');
}
