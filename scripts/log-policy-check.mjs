import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const scan = ['entry/src/main/ets'];
const files = scan.flatMap((p) => {
  const walk = (dir) => fs.readdirSync(path.join(root, dir), { withFileTypes: true }).flatMap((e) => {
    const rel = path.join(dir, e.name);
    return e.isDirectory() ? walk(rel) : /\.(ets|ts)$/.test(e.name) ? [rel] : [];
  });
  return walk(p);
});
// token 后面跟 s 的是用量计数（如 completion_tokens），不是凭据。
const SENSITIVE_NAME = '(cookie|token(?!s)|password|passwd|secret|authorization)';
const SENSITIVE_VALUE = new RegExp(
  `\\$\\{[^}]*${SENSITIVE_NAME}[^}]*\\}|,\\s*[\\w.]*${SENSITIVE_NAME}\\w*\\s*[,)]`, 'i');
const violations = [];
for (const rel of files) {
  const lines = fs.readFileSync(path.join(root, rel), 'utf8').split(/\r?\n/);
  lines.forEach((line, i) => {
    if (!/console\.(log|info|warn|error|debug)\s*\(/.test(line)) return;
    // console.log 不进发布日志规范：出现地址或凭据字样一律拦下。
    if (/console\.log\s*\(/.test(line) && /(URL|url|Cookie|cookie|token|password|secret)/i.test(line)) {
      violations.push(`${rel}:${i + 1}`);
      return;
    }
    // 其余级别：不允许把凭据类变量的值直接插进日志（模板插值或作为参数）。
    if (SENSITIVE_VALUE.test(line)) violations.push(`${rel}:${i + 1}`);
  });
}
if (violations.length) {
  console.error(`Log policy check failed (${violations.length} potentially sensitive logs):\n${violations.join('\n')}`);
  process.exit(1);
}
console.log('Log policy check passed.');
