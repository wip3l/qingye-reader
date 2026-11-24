#!/usr/bin/env node
// 兑换码管理（安卓端“兑换码”，见 docs/android-recharge.md）。服务器上经 /usr/local/bin/qingye-codes 调用，
// 它带上服务的环境文件（DATABASE_URL）在运行目录里执行本文件：
//
//   qingye-codes create --batch <批次> --sku MONTHLY|ANNUAL|LIFETIME|SUPER_LIFETIME --count 20 [--expires 2027-12-31]
//   qingye-codes create --batch <批次> --points 10|60|100|300|500|1000 --count 50 [--expires …]
//   qingye-codes list                       各批次：种类、总数、已用、未用、作废、过期
//   qingye-codes status <兑换码>            查一个码：批次、种类、是否用过、谁在何时用的
//   qingye-codes revoke --code <兑换码>     作废一个未用的码
//   qingye-codes revoke --batch <批次> --yes  作废整批里未用的码
//
// create 把明文写进 <--out-dir，默认 /root/qingye-codes>/<批次>.txt（权限 600，每行一个，可直接导入发卡平台的卡密），
// 数据库只存 SHA-256。加 --dry-run 或没有 DATABASE_URL 时只生成文件、不写库（演练用）。
// 兑换码 16 位，取自不易混淆的 32 个字符（去掉 0/O/1/I），约 80 位随机性；写成 XXXX-XXXX-XXXX-XXXX。
import { createHash, randomInt } from 'node:crypto';
import { closeSync, mkdirSync, openSync, writeSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { parseArgs } from 'node:util';

const ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const POINT_TIERS = [10, 60, 100, 300, 500, 1000];
// 与 membershipPolicy.ts 的 MEMBERSHIP_PRODUCTS 一致；兑换时服务端按当时报价开通，面值只用来记账。
const MEMBERSHIPS = {
  MONTHLY: { name: '月度会员', points: 60 },
  ANNUAL: { name: '年度会员', points: 480 },
  LIFETIME: { name: '终身会员', points: 1290 },
  SUPER_LIFETIME: { name: '终身超级会员', points: 2490 }
};

const { values, positionals } = parseArgs({ allowPositionals: true, options: {
  batch: { type: 'string' }, points: { type: 'string' }, sku: { type: 'string' }, count: { type: 'string', default: '1' },
  expires: { type: 'string' }, code: { type: 'string' }, 'out-dir': { type: 'string', default: '/root/qingye-codes' },
  'dry-run': { type: 'boolean', default: false }, yes: { type: 'boolean', default: false }
} });
const [command, ...rest] = positionals;

function fail(message) {
  console.error(message);
  process.exit(2);
}
// 与服务端 redeemCodeHash 一致：去空格和连字符、转大写后取 SHA-256。
const normalize = code => String(code || '').replace(/[\s-]/g, '').toUpperCase();
const hash = code => createHash('sha256').update(normalize(code), 'utf8').digest('hex');
const pretty = code => code.match(/.{4}/g).join('-');
const kindLabel = (sku, points) => sku ? `${MEMBERSHIPS[sku]?.name ?? sku}码` : `${points} 点码`;
const day = value => value ? new Date(value).toLocaleString('zh-CN', { timeZone: 'Asia/Shanghai', hour12: false }) : '—';

async function withDb(work) {
  if (!process.env.DATABASE_URL) fail('没有 DATABASE_URL：请用 qingye-codes 调用（它会带上服务的环境文件）');
  const { default: pg } = await import('pg');
  const client = new pg.Client({ connectionString: process.env.DATABASE_URL });
  await client.connect();
  try {
    return await work(client);
  } finally {
    await client.end();
  }
}

async function create() {
  const batch = (values.batch || '').trim();
  if (!batch || !/^[\w.-]{1,64}$/.test(batch)) fail('--batch 必填，只能用字母、数字、点、下划线、连字符');
  if (!!values.sku === !!values.points) fail('--sku（会员码）和 --points（点数码）二选一');
  const sku = values.sku ? values.sku.toUpperCase() : null;
  if (sku && !MEMBERSHIPS[sku]) fail(`--sku 只能是 ${Object.keys(MEMBERSHIPS).join('/')}`);
  const points = sku ? MEMBERSHIPS[sku].points : Number(values.points);
  if (!sku && !POINT_TIERS.includes(points)) fail(`--points 只能是 ${POINT_TIERS.join('/')}，与充值档位一致`);
  const count = Number(values.count);
  if (!Number.isInteger(count) || count < 1 || count > 1000) fail('--count 取 1–1000');
  const expiresAt = values.expires ? new Date(`${values.expires}T23:59:59+08:00`) : null;
  if (expiresAt && (Number.isNaN(expiresAt.getTime()) || expiresAt.getTime() <= Date.now())) {
    fail('--expires 格式是 YYYY-MM-DD（北京时间当天结束），且要晚于今天');
  }

  const codes = new Set();
  while (codes.size < count) {
    let code = '';
    for (let i = 0; i < 16; i++) code += ALPHABET[randomInt(ALPHABET.length)];
    codes.add(code);
  }
  const dryRun = values['dry-run'] || !process.env.DATABASE_URL;
  const outDir = resolve(values['out-dir']);
  mkdirSync(outDir, { recursive: true, mode: 0o700 });
  const file = join(outDir, `${batch}${dryRun ? '.dry-run' : ''}.txt`);
  // 'wx'：同名文件已存在就失败，不会覆盖已经发出去的码。先建文件再写库，写库失败时删掉重来即可。
  let fd;
  try {
    fd = openSync(file, 'wx', 0o600);
  } catch (error) {
    if (error.code === 'EEXIST') fail(`${file} 已存在：换一个批次名，或确认旧文件已不需要后删掉`);
    throw error;
  }
  try {
    writeSync(fd, [...codes].map(pretty).join('\n') + '\n');
  } finally {
    closeSync(fd);
  }
  if (!dryRun) {
    await withDb(async client => {
      await client.query('BEGIN');
      try {
        const existing = await client.query('SELECT 1 FROM redeem_codes WHERE batch = $1 LIMIT 1', [batch]);
        if (existing.rowCount) throw new Error(`批次 ${batch} 已存在，换一个批次名`);
        for (const code of codes) {
          await client.query(`INSERT INTO redeem_codes (code_hash, batch, points, expires_at, membership_sku)
            VALUES ($1, $2, $3, $4, $5)`, [hash(code), batch, points, expiresAt, sku]);
        }
        await client.query('COMMIT');
      } catch (error) {
        await client.query('ROLLBACK');
        console.error(`未写库，请删掉 ${file} 后重试`);
        throw error;
      }
    });
  }
  console.log(`${dryRun ? '[演练，未写库] ' : ''}批次 ${batch}：${count} 个${kindLabel(sku, points)}` +
    (expiresAt ? `，${values.expires} 后失效` : '，不过期'));
  console.log(`明文：${file}（权限 600）。导入发卡平台后请删掉，不要留在服务器上。`);
}

async function list() {
  await withDb(async client => {
    const { rows } = await client.query(`SELECT batch, membership_sku AS sku, points, count(*)::int AS total,
        count(redeemed_by)::int AS used,
        count(*) FILTER (WHERE redeemed_by IS NULL AND revoked_at IS NOT NULL)::int AS revoked,
        count(*) FILTER (WHERE redeemed_by IS NULL AND revoked_at IS NULL AND expires_at <= now())::int AS expired,
        count(*) FILTER (WHERE redeemed_by IS NULL AND revoked_at IS NULL
          AND (expires_at IS NULL OR expires_at > now()))::int AS available,
        min(created_at) AS created, max(expires_at) AS expires
      FROM redeem_codes GROUP BY batch, membership_sku, points ORDER BY min(created_at)`);
    if (!rows.length) return console.log('还没有兑换码');
    console.table(rows.map(r => ({ 批次: r.batch, 种类: kindLabel(r.sku, r.points), 总数: r.total, 已用: r.used,
      可用: r.available, 作废: r.revoked, 过期: r.expired, 创建: day(r.created), 失效: r.expires ? day(r.expires) : '不过期' })));
  });
}

async function status(code) {
  if (!normalize(code)) fail('用法：qingye-codes status <兑换码>');
  await withDb(async client => {
    const { rows } = await client.query(`SELECT c.batch, c.membership_sku AS sku, c.points, c.created_at, c.expires_at,
        c.redeemed_by, c.redeemed_at, c.revoked_at, u.username, u.display_name
      FROM redeem_codes c LEFT JOIN app_users u ON u.id = c.redeemed_by WHERE c.code_hash = $1`, [hash(code)]);
    const r = rows[0];
    if (!r) return console.log('没有这个兑换码');
    const state = r.redeemed_by ? `已兑换：${day(r.redeemed_at)}，账号 ${r.username || r.display_name || ''}（${r.redeemed_by}）`
      : r.revoked_at ? `已作废：${day(r.revoked_at)}`
        : r.expires_at && new Date(r.expires_at).getTime() <= Date.now() ? '已过期' : '可用';
    console.log(`批次 ${r.batch} · ${kindLabel(r.sku, r.points)} · 创建 ${day(r.created_at)} · ` +
      `失效 ${r.expires_at ? day(r.expires_at) : '不过期'}\n${state}`);
  });
}

async function revoke() {
  if (!!values.code === !!values.batch) fail('--code 和 --batch 二选一');
  if (values.batch && !values.yes) fail('作废整批要加 --yes 确认（只作废其中未用的码）');
  await withDb(async client => {
    const { rowCount } = values.code
      ? await client.query(`UPDATE redeem_codes SET revoked_at = now()
          WHERE code_hash = $1 AND redeemed_by IS NULL AND revoked_at IS NULL`, [hash(values.code)])
      : await client.query(`UPDATE redeem_codes SET revoked_at = now()
          WHERE batch = $1 AND redeemed_by IS NULL AND revoked_at IS NULL`, [values.batch]);
    console.log(`已作废 ${rowCount} 个（已兑换或已作废的不受影响）`);
  });
}

if (command === 'create') await create();
else if (command === 'list') await list();
else if (command === 'status') await status(rest[0] || values.code);
else if (command === 'revoke') await revoke();
else fail('用法：qingye-codes create|list|status|revoke …（见文件开头的说明）');
