import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';
import { Book } from '@legado/sourceengine';
import { HuksSecretStore } from './HuksSecretStore';

/**
 * 隐私书架的开关与密码。哪些书属于隐私书架记在 books.isPrivate 列里，这里只管入口本身。
 * 设置只存在本机：不进云同步，密码用系统密钥库（HUKS）加密保存。
 */
export class PrivateShelfStore {
  static readonly KEY_ENABLED: string = 'privateShelfEnabled';
  static readonly KEY_HAS_PASSWORD: string = 'privateShelfHasPassword';
  /** 进入时先用系统指纹/人脸验证，失败或取消再退回密码；只在设了密码时有意义。 */
  static readonly KEY_BIOMETRIC: string = 'privateShelfBiometric';
  private static readonly STORE_NAME: string = 'private_shelf_settings';
  private static readonly SECRET_NAME: string = 'password';
  private static readonly secrets: HuksSecretStore =
    new HuksSecretStore('private_shelf_secrets', 'legado_harmony_private_shelf_secret_v1');
  private static loaded: boolean = false;

  /** 读入开关状态并同步到 AppStorage；重复调用只读一次磁盘。 */
  static async load(context: Context): Promise<void> {
    if (PrivateShelfStore.loaded) return;
    const store = await preferences.getPreferences(context, PrivateShelfStore.STORE_NAME);
    const enabled = await store.get(PrivateShelfStore.KEY_ENABLED, false);
    const hasPassword = await store.get(PrivateShelfStore.KEY_HAS_PASSWORD, false);
    AppStorage.setOrCreate(PrivateShelfStore.KEY_ENABLED, enabled === true);
    AppStorage.setOrCreate(PrivateShelfStore.KEY_HAS_PASSWORD, hasPassword === true);
    const biometric = await store.get(PrivateShelfStore.KEY_BIOMETRIC, false);
    AppStorage.setOrCreate(PrivateShelfStore.KEY_BIOMETRIC, biometric === true && hasPassword === true);
    PrivateShelfStore.loaded = true;
  }

  static async setEnabled(context: Context, enabled: boolean): Promise<void> {
    const store = await preferences.getPreferences(context, PrivateShelfStore.STORE_NAME);
    await store.put(PrivateShelfStore.KEY_ENABLED, enabled);
    await store.flush();
    AppStorage.setOrCreate(PrivateShelfStore.KEY_ENABLED, enabled);
  }

  static async setBiometric(context: Context, enabled: boolean): Promise<void> {
    const store = await preferences.getPreferences(context, PrivateShelfStore.STORE_NAME);
    await store.put(PrivateShelfStore.KEY_BIOMETRIC, enabled);
    await store.flush();
    AppStorage.setOrCreate(PrivateShelfStore.KEY_BIOMETRIC, enabled);
  }

  /** 传空串即清除密码，同时关掉指纹/人脸解锁，下次设密码要重新打开。 */
  static async setPassword(context: Context, password: string): Promise<void> {
    await PrivateShelfStore.secrets.save(context, PrivateShelfStore.SECRET_NAME, password);
    const store = await preferences.getPreferences(context, PrivateShelfStore.STORE_NAME);
    await store.put(PrivateShelfStore.KEY_HAS_PASSWORD, password.length > 0);
    if (password.length === 0) await store.put(PrivateShelfStore.KEY_BIOMETRIC, false);
    await store.flush();
    AppStorage.setOrCreate(PrivateShelfStore.KEY_HAS_PASSWORD, password.length > 0);
    if (password.length === 0) AppStorage.setOrCreate(PrivateShelfStore.KEY_BIOMETRIC, false);
  }

  /** 没设密码时任何输入都算通过；密文读不出来（密钥丢失）时一律不通过，只能重置。 */
  static async verifyPassword(context: Context, input: string): Promise<boolean> {
    await PrivateShelfStore.load(context);
    if (AppStorage.get<boolean>(PrivateShelfStore.KEY_HAS_PASSWORD) !== true) return true;
    const saved = await PrivateShelfStore.secrets.read(context, PrivateShelfStore.SECRET_NAME);
    if (saved.unreadable || !saved.value) return false;
    return saved.value === input;
  }

  /** 关闭隐私书架并清除密码，用于“重置隐私书架”。隐私书籍由调用方删除。 */
  static async reset(context: Context): Promise<void> {
    await PrivateShelfStore.setPassword(context, '');
    await PrivateShelfStore.setEnabled(context, false);
  }

  /** 隐私书架之外的入口（桌面卡片、快捷方式、局域网阅读等）只应看到这些书。 */
  static publicBooks(books: Book[]): Book[] {
    return books.filter((book: Book) => !book.isPrivate);
  }
}
