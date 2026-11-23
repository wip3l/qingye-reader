import { Context } from '@kit.AbilityKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import preferences from '@ohos.data.preferences';
import { KeystoreCipher } from '../platform/KeystoreCipher';

class HuksEncryptedSecret {
  version: number = 1;
  iv: string = '';
  data: string = '';
}

/** What a stored secret looks like when it is read back. */
export class HuksSecretReadResult {
  value: string = '';
  // a record exists on disk but could not be decrypted (key lost, data damaged)
  unreadable: boolean = false;
}

/**
 * Small secrets kept in app preferences, encrypted with an AES-256 key that never leaves the system keystore
 * (HUKS). Same scheme as the WebDAV and OPDS credential stores; one instance per preferences file and key alias.
 */
export class HuksSecretStore {
  private readonly storeName: string;
  private readonly keyAlias: string;
  private readonly cipher: KeystoreCipher;

  constructor(storeName: string, keyAlias: string) {
    this.storeName = storeName;
    this.keyAlias = keyAlias;
    this.cipher = new KeystoreCipher(keyAlias);
  }

  /** An empty value removes the record. */
  async save(context: Context, name: string, value: string): Promise<void> {
    const store = await preferences.getPreferences(context, this.storeName);
    if (!value) {
      await store.delete(name);
      await store.flush();
      return;
    }
    const iv = (await cryptoFramework.createRandom().generateRandom(16)).data;
    const plaintext = new util.TextEncoder().encodeInto(value);
    try {
      const encrypted = await this.cipher.encrypt(plaintext, iv);
      const helper = new util.Base64Helper();
      const record = new HuksEncryptedSecret();
      record.iv = helper.encodeToStringSync(iv);
      record.data = helper.encodeToStringSync(encrypted);
      await store.put(name, JSON.stringify(record));
      await store.flush();
    } finally {
      plaintext.fill(0);
    }
  }

  async read(context: Context, name: string): Promise<HuksSecretReadResult> {
    const result = new HuksSecretReadResult();
    const store = await preferences.getPreferences(context, this.storeName);
    const raw = await store.get(name, '');
    if (typeof raw !== 'string' || !raw) return result;
    try {
      const record = JSON.parse(raw) as HuksEncryptedSecret;
      if (!record || record.version !== 1 || !record.iv || !record.data) throw new Error('invalid record');
      const helper = new util.Base64Helper();
      const plaintext = await this.cipher.decrypt(helper.decodeSync(record.data), helper.decodeSync(record.iv));
      result.value = util.TextDecoder.create('utf-8').decodeToString(plaintext);
      plaintext.fill(0);
    } catch (error) {
      console.warn(`[HuksSecretStore] 无法读取已保存的密文 ${this.storeName}/${name}:`,
        HuksSecretStore.errorMessage(error as Object));
      result.unreadable = true;
    }
    return result;
  }

  private static errorMessage(error: Object): string {
    if (error instanceof Error && error.message) return error.message;
    const value = error as Record<string, Object>;
    return String(value?.['message'] || value?.['code'] || error || '未知错误');
  }
}
