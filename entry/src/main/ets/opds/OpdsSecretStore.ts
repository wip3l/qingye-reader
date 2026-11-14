import { Context } from '@kit.AbilityKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import preferences from '@ohos.data.preferences';
import { KeystoreCipher } from '../platform/KeystoreCipher';
import { OpdsError } from './OpdsError';

class OpdsEncryptedSecret {
  version: number = 1;
  iv: string = '';
  data: string = '';
}

export class OpdsSecretStore {
  private static readonly STORE_NAME: string = 'opds_secrets';
  private static readonly KEY_PREFIX: string = 'password_';
  private static readonly KEY_ALIAS: string = 'legado_harmony_opds_secret_v1';
  private static runtimePasswords: Record<string, string> = {};
  private static readonly cipher: KeystoreCipher = new KeystoreCipher(OpdsSecretStore.KEY_ALIAS);

  static async savePassword(context: Context, serverId: string, password: string,
    persistent: boolean): Promise<void> {
    if (!serverId) return;
    OpdsSecretStore.runtimePasswords[serverId] = password || '';
    const store = await preferences.getPreferences(context, OpdsSecretStore.STORE_NAME);
    if (!persistent || !password) {
      await store.delete(OpdsSecretStore.preferenceKey(serverId));
      await store.flush();
      return;
    }
    const random = cryptoFramework.createRandom();
    const iv = (await random.generateRandom(16)).data;
    const plaintext = new util.TextEncoder().encodeInto(password);
    try {
      const encrypted = await OpdsSecretStore.cipher.encrypt(plaintext, iv);
      const helper = new util.Base64Helper();
      const record = new OpdsEncryptedSecret();
      record.iv = helper.encodeToStringSync(iv);
      record.data = helper.encodeToStringSync(encrypted);
      await store.put(OpdsSecretStore.preferenceKey(serverId), JSON.stringify(record));
      await store.flush();
    } finally {
      OpdsSecretStore.clearBytes(plaintext);
    }
  }

  static async password(context: Context, serverId: string): Promise<string> {
    if (!serverId) return '';
    const runtime = OpdsSecretStore.runtimePasswords[serverId];
    if (runtime !== undefined) return runtime;
    const store = await preferences.getPreferences(context, OpdsSecretStore.STORE_NAME);
    const raw = await store.get(OpdsSecretStore.preferenceKey(serverId), '');
    if (typeof raw !== 'string' || !raw) return '';
    try {
      const record = JSON.parse(raw) as OpdsEncryptedSecret;
      if (!record || record.version !== 1 || !record.iv || !record.data) return '';
      const helper = new util.Base64Helper();
      const iv = helper.decodeSync(record.iv);
      const encrypted = helper.decodeSync(record.data);
      const plaintext = await OpdsSecretStore.cipher.decrypt(encrypted, iv);
      const value = util.TextDecoder.create('utf-8').decodeWithStream(plaintext, { stream: false });
      OpdsSecretStore.clearBytes(plaintext);
      OpdsSecretStore.runtimePasswords[serverId] = value;
      return value;
    } catch (error) {
      console.warn('[OPDS] 无法读取已保存的凭据:', OpdsSecretStore.errorMessage(error as Object));
      return '';
    }
  }

  static async deletePassword(context: Context, serverId: string): Promise<void> {
    OpdsSecretStore.runtimePasswords[serverId] = '';
    const store = await preferences.getPreferences(context, OpdsSecretStore.STORE_NAME);
    await store.delete(OpdsSecretStore.preferenceKey(serverId));
    await store.flush();
  }

  private static preferenceKey(serverId: string): string {
    return `${OpdsSecretStore.KEY_PREFIX}${serverId.replace(/[^a-zA-Z0-9_-]/g, '_')}`;
  }

  private static clearBytes(value: Uint8Array): void {
    value.fill(0);
  }

  private static errorMessage(error: Object): string {
    return OpdsError.message(error);
  }
}
