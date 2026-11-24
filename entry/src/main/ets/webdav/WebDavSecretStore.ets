import { Context } from '@kit.AbilityKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import preferences from '@ohos.data.preferences';
import { KeystoreCipher } from '../platform/KeystoreCipher';
import { WebDavError } from './WebDavError';

class WebDavEncryptedSecret {
  version: number = 1;
  iv: string = '';
  data: string = '';
}

export class WebDavSecretStore {
  private static readonly STORE_NAME: string = 'webdav_secrets';
  private static readonly KEY_PREFIX: string = 'password_';
  private static readonly KEY_ALIAS: string = 'legado_harmony_webdav_secret_v1';
  private static runtimePasswords: Record<string, string> = {};
  private static readonly cipher: KeystoreCipher = new KeystoreCipher(WebDavSecretStore.KEY_ALIAS);

  static async savePassword(context: Context, connectionId: string, password: string,
    persistent: boolean): Promise<void> {
    if (!connectionId) return;
    WebDavSecretStore.runtimePasswords[connectionId] = password || '';
    const store = await preferences.getPreferences(context, WebDavSecretStore.STORE_NAME);
    if (!persistent || !password) {
      await store.delete(WebDavSecretStore.preferenceKey(connectionId));
      await store.flush();
      return;
    }
    const random = cryptoFramework.createRandom();
    const iv = (await random.generateRandom(16)).data;
    const plaintext = new util.TextEncoder().encodeInto(password);
    try {
      const encrypted = await WebDavSecretStore.cipher.encrypt(plaintext, iv);
      const helper = new util.Base64Helper();
      const record = new WebDavEncryptedSecret();
      record.iv = helper.encodeToStringSync(iv);
      record.data = helper.encodeToStringSync(encrypted);
      await store.put(WebDavSecretStore.preferenceKey(connectionId), JSON.stringify(record));
      await store.flush();
    } finally {
      WebDavSecretStore.clearBytes(plaintext);
    }
  }

  static async password(context: Context, connectionId: string): Promise<string> {
    if (!connectionId) return '';
    const runtime = WebDavSecretStore.runtimePasswords[connectionId];
    if (runtime !== undefined) return runtime;
    const store = await preferences.getPreferences(context, WebDavSecretStore.STORE_NAME);
    const raw = await store.get(WebDavSecretStore.preferenceKey(connectionId), '');
    if (typeof raw !== 'string' || !raw) return '';
    try {
      const record = JSON.parse(raw) as WebDavEncryptedSecret;
      if (!record || record.version !== 1 || !record.iv || !record.data) return '';
      const helper = new util.Base64Helper();
      const iv = helper.decodeSync(record.iv);
      const encrypted = helper.decodeSync(record.data);
      const plaintext = await WebDavSecretStore.cipher.decrypt(encrypted, iv);
      const value = util.TextDecoder.create('utf-8').decodeWithStream(plaintext, { stream: false });
      WebDavSecretStore.clearBytes(plaintext);
      WebDavSecretStore.runtimePasswords[connectionId] = value;
      return value;
    } catch (error) {
      console.warn('[WebDAV] 无法读取已保存的凭据:', WebDavSecretStore.errorMessage(error as Object));
      return '';
    }
  }

  static async deletePassword(context: Context, connectionId: string): Promise<void> {
    WebDavSecretStore.runtimePasswords[connectionId] = '';
    const store = await preferences.getPreferences(context, WebDavSecretStore.STORE_NAME);
    await store.delete(WebDavSecretStore.preferenceKey(connectionId));
    await store.flush();
  }

  private static preferenceKey(connectionId: string): string {
    return `${WebDavSecretStore.KEY_PREFIX}${connectionId.replace(/[^a-zA-Z0-9_-]/g, '_')}`;
  }

  private static clearBytes(value: Uint8Array): void {
    value.fill(0);
  }

  private static errorMessage(error: Object): string {
    return WebDavError.message(error);
  }
}
