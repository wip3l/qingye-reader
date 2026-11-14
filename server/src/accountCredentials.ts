import { createHmac, randomBytes, randomInt, scrypt as scryptCallback, timingSafeEqual } from 'node:crypto';

/**
 * scrypt N=2^15, r=8：每次约 32 MB 内存、几十毫秒，异步跑在 libuv 线程池里，不阻塞事件循环。
 * 参数写进哈希串，以后调高参数时旧哈希仍能校验。
 */
const SCRYPT_N = 1 << 15;
const SCRYPT_R = 8;
const SCRYPT_P = 1;
const SCRYPT_KEY_BYTES = 32;
const SCRYPT_MAX_N = 1 << 17;
const RECOVERY_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
export const RECOVERY_CODE_COUNT = 8;

export class CredentialError extends Error {
  constructor(readonly code: string, message: string) {
    super(message);
  }
}

function scrypt(password: string, salt: Buffer, n: number, r: number, p: number): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    scryptCallback(password.normalize('NFKC'), salt, SCRYPT_KEY_BYTES,
      { N: n, r, p, maxmem: 160 * n * r }, (error, key) => error ? reject(error) : resolve(key));
  });
}

export async function hashPassword(password: string): Promise<string> {
  const salt = randomBytes(16);
  const key = await scrypt(password, salt, SCRYPT_N, SCRYPT_R, SCRYPT_P);
  return `scrypt$${SCRYPT_N}$${SCRYPT_R}$${SCRYPT_P}$${salt.toString('base64')}$${key.toString('base64')}`;
}

export async function verifyPassword(password: string, stored: string): Promise<boolean> {
  const parts = stored.split('$');
  if (parts.length !== 6 || parts[0] !== 'scrypt') return false;
  const n = Number(parts[1]);
  const r = Number(parts[2]);
  const p = Number(parts[3]);
  if (!Number.isInteger(n) || n < 2 || n > SCRYPT_MAX_N || (n & (n - 1)) !== 0 ||
    !Number.isInteger(r) || r < 1 || r > 16 || !Number.isInteger(p) || p < 1 || p > 4) {
    return false;
  }
  const salt = Buffer.from(parts[4]!, 'base64');
  const expected = Buffer.from(parts[5]!, 'base64');
  if (salt.length < 16 || expected.length !== SCRYPT_KEY_BYTES) return false;
  const actual = await scrypt(password, salt, n, r, p);
  return timingSafeEqual(actual, expected);
}

let dummyHash: Promise<string> | null = null;
/** 用户名不存在时也算一次哈希，响应时间不暴露用户名是否注册过。 */
export async function burnPasswordCheck(password: string): Promise<void> {
  dummyHash ??= hashPassword(randomBytes(12).toString('hex'));
  await verifyPassword(password, await dummyHash);
}

export interface NormalizedUsername {
  username: string;
  key: string;
}

/** 字母开头，3~20 位字母、数字或下划线；比较时不区分大小写。 */
export function normalizeUsername(raw: unknown): NormalizedUsername {
  const username = typeof raw === 'string' ? raw.trim() : '';
  if (!/^[A-Za-z][A-Za-z0-9_]{2,19}$/.test(username)) {
    throw new CredentialError('INVALID_USERNAME', '用户名需为 3~20 位字母、数字或下划线，并以字母开头');
  }
  return { username, key: username.toLowerCase() };
}

/** 8~64 位，至少包含字母、数字、符号中的两类，且不能与用户名相同。 */
export function validatePassword(raw: unknown, username = ''): string {
  const password = typeof raw === 'string' ? raw : '';
  const length = Array.from(password).length;
  if (length < 8 || length > 64 || /[\u0000-\u001f\u007f]/.test(password)) {
    throw new CredentialError('INVALID_PASSWORD', '密码需为 8~64 位');
  }
  const kinds = [/[A-Za-z]/, /[0-9]/, /[^A-Za-z0-9]/].filter(pattern => pattern.test(password)).length;
  if (kinds < 2) {
    throw new CredentialError('WEAK_PASSWORD', '密码至少要包含字母、数字、符号中的两类');
  }
  if (username && password.toLowerCase() === username.toLowerCase()) {
    throw new CredentialError('WEAK_PASSWORD', '密码不能与用户名相同');
  }
  return password;
}

/** 形如 ABCD-EFGH-JKLM，12 位约 60 bit；去掉了容易看错的 0/O、1/I。 */
export function generateRecoveryCodes(count = RECOVERY_CODE_COUNT): string[] {
  const codes = new Set<string>();
  while (codes.size < count) {
    let raw = '';
    for (let index = 0; index < 12; index++) raw += RECOVERY_ALPHABET[randomInt(RECOVERY_ALPHABET.length)];
    codes.add(`${raw.substring(0, 4)}-${raw.substring(4, 8)}-${raw.substring(8)}`);
  }
  return Array.from(codes);
}

export function normalizeRecoveryCode(raw: unknown): string {
  const code = typeof raw === 'string' ? raw.toUpperCase().replace(/[^A-Z0-9]/g, '') : '';
  if (code.length !== 12) throw new CredentialError('INVALID_RECOVERY_CODE', '恢复码格式不正确');
  return code;
}

/**
 * 恢复码用服务端密钥做 HMAC：数据库泄露时不能离线穷举。
 * 密钥来自 SESSION_SECRET，更换它会让已发出的恢复码一并失效（登录会话本来也会失效）。
 */
export function recoveryCodeHasher(secret: string): (code: string) => string {
  const key = createHmac('sha256', secret).update('qingye-recovery-code-v1').digest();
  return code => createHmac('sha256', key).update(normalizeRecoveryCode(code)).digest('hex');
}

/** 连续输错 5 次起锁定，1、2、4… 分钟，最长 1 小时。 */
export function loginLockMinutes(failures: number): number {
  if (failures < 5) return 0;
  return Math.min(60, 2 ** (failures - 5));
}

export function randomReaderName(): string {
  return `读者${randomInt(1000, 10000)}`;
}
