// 系统密钥库里的 AES-256-CBC 加解密，密钥不出密钥库。安卓构建会用 android/overlay 里的同名文件替换本文件。
// 鸿蒙实现用 HUKS；别名、算法参数与原先各凭据库里的写法相同，已保存的密文照常可读。
import { huks } from '@kit.UniversalKeystoreKit';

const keyReady: Map<string, Promise<void>> = new Map<string, Promise<void>>();

function errorCode(error: Object): number {
  const value = error as Record<string, Object>;
  return Number(value?.['code'] || value?.['errorCode'] || 0);
}

function errorText(error: Object): string {
  if (error instanceof Error && error.message) return error.message;
  const value = error as Record<string, Object>;
  return String(value?.['message'] || value?.['code'] || error || '未知错误');
}

function isMissingEntity(error: Object): boolean {
  const message = errorText(error).toLowerCase();
  return [12000011, 12000013].includes(errorCode(error)) ||
    message.includes('entity does not exist') || message.includes('credential does not exist');
}

function isAlreadyExists(error: Object): boolean {
  return errorCode(error) === 12000017 || errorText(error).toLowerCase().includes('already exist');
}

function keyProperties(): huks.HuksParam[] {
  return [
    { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
    { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256 },
    { tag: huks.HuksTag.HUKS_TAG_PURPOSE,
      value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT | huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT },
    { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_CBC },
    { tag: huks.HuksTag.HUKS_TAG_PADDING, value: huks.HuksKeyPadding.HUKS_PADDING_PKCS7 }
  ];
}

async function createKeyIfMissing(alias: string): Promise<void> {
  let exists = false;
  try {
    exists = await huks.isKeyItemExist(alias, { properties: [] });
  } catch (error) {
    if (!isMissingEntity(error as Object)) throw new Error(errorText(error as Object));
  }
  if (exists) return;
  try {
    await huks.generateKeyItem(alias, { properties: keyProperties() });
  } catch (error) {
    // 并发调用方先建好了
    if (!isAlreadyExists(error as Object)) throw new Error(errorText(error as Object));
  }
}

async function ensureKey(alias: string): Promise<void> {
  let ready = keyReady.get(alias);
  if (!ready) {
    ready = createKeyIfMissing(alias);
    keyReady.set(alias, ready);
  }
  try {
    await ready;
  } catch (error) {
    keyReady.delete(alias);
    throw new Error(errorText(error as Object));
  }
}

export class KeystoreCipher {
  private readonly alias: string;

  constructor(alias: string) {
    this.alias = alias;
  }

  encrypt(input: Uint8Array, iv: Uint8Array): Promise<Uint8Array> {
    return this.transform(huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT, input, iv);
  }

  decrypt(input: Uint8Array, iv: Uint8Array): Promise<Uint8Array> {
    return this.transform(huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT, input, iv);
  }

  private async transform(purpose: huks.HuksKeyPurpose, input: Uint8Array, iv: Uint8Array): Promise<Uint8Array> {
    await ensureKey(this.alias);
    const properties: huks.HuksParam[] = [
      { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
      { tag: huks.HuksTag.HUKS_TAG_PURPOSE, value: purpose },
      { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_CBC },
      { tag: huks.HuksTag.HUKS_TAG_PADDING, value: huks.HuksKeyPadding.HUKS_PADDING_PKCS7 },
      { tag: huks.HuksTag.HUKS_TAG_IV, value: iv }
    ];
    const session = await huks.initSession(this.alias, { properties: properties });
    const result = await huks.finishSession(session.handle, { properties: properties, inData: input });
    if (!result.outData) throw new Error('系统密钥服务未返回数据');
    return result.outData;
  }
}
