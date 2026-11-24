#!/usr/bin/env node
// 生成一批充值兑换码（安卓端“兑换码充值”，见 docs/android-recharge.md）。
// 数据库只存 SHA-256，明文只在这里打印一次，请直接保存到发卡渠道，不要留在服务器上。
//
//   DATABASE_URL=postgres://... node scripts/redeem-codes.mjs --batch 2026-11-shop --points 300 --count 50 [--expires 2027-06-30]
//   不带 DATABASE_URL 或加 --dry-run 时只打印，不写库（演练用）。
//
// 兑换码 16 位，取自不易混淆的 32 个字符（去掉 0/O/1/I），约 80 位随机性；打印成 XXXX-XXXX-XXXX-XXXX。
import { createHash, randomInt } from 'node:crypto';
import { parseArgs } from 'node:util';

const ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const { values } = parseArgs({ options: {
  batch: { type: 'string' }, points: { type: 'string' }, count: { type: 'string', default: '1' },
  expires: { type: 'string' }, 'dry-run': { type: 'boolean', default: false }
} });

const batch = (values.batch || '').trim();
const points = Number(values.points);
const count = Number(values.count);
const expiresAt = values.expires ? new Date(`${values.expires}T23:59:59+08:00`) : null;
if (!batch || !/^[\w.-]{1,64}$/.test(batch)) throw new Error('--batch 必填，只能用字母、数字、点、下划线、连字符');
if (![10, 60, 100, 300, 500, 1000].includes(points)) throw new Error('--points 只能是 10/60/100/300/500/1000，与充值档位一致');
if (!Number.isInteger(count) || count < 1 || count > 1000) throw new Error('--count 取 1–1000');
if (expiresAt && Number.isNaN(expiresAt.getTime())) throw new Error('--expires 格式是 YYYY-MM-DD（北京时间当天结束）');

function newCode() {
  let code = '';
  for (let i = 0; i < 16; i++) code += ALPHABET[randomInt(ALPHABET.length)];
  return code;
}
// 与服务端 redeemCodeHash 一致：去空格和连字符、转大写后取 SHA-256。
const hash = code => createHash('sha256').update(code.replace(/[\s-]/g, '').toUpperCase(), 'utf8').digest('hex');
const pretty = code => code.match(/.{4}/g).join('-');

const codes = Array.from({ length: count }, newCode);
const dryRun = values['dry-run'] || !process.env.DATABASE_URL;
if (!dryRun) {
  const { default: pg } = await import('pg');
  const client = new pg.Client({ connectionString: process.env.DATABASE_URL });
  await client.connect();
  try {
    await client.query('BEGIN');
    for (const code of codes) {
      await client.query('INSERT INTO redeem_codes (code_hash, batch, points, expires_at) VALUES ($1, $2, $3, $4)',
        [hash(code), batch, points, expiresAt]);
    }
    await client.query('COMMIT');
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    await client.end();
  }
}
console.error(`${dryRun ? '[演练，未写库] ' : ''}批次 ${batch}：${count} 个，每个 ${points} 点` +
  (expiresAt ? `，${values.expires} 后失效` : '，不过期'));
for (const code of codes) console.log(pretty(code));
