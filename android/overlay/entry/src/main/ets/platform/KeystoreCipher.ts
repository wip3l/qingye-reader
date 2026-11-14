// platform/KeystoreCipher.ts 的安卓实现。
// HUKS 没有跨平台实现，经原生桥（SecretBridge.java）用安卓密钥库：AES-256-CBC、PKCS7 填充，密钥不出密钥库。
// 字节数组以 Base64 过桥。
import bridge from '@arkui-x.bridge';
import { util } from '@kit.ArkTS';

/** 与 SecretBridge.NAME 一致。 */
const SECRET_BRIDGE_NAME = 'io.legado.read/secret';

let secretBridge: bridge.BridgeObject | null = null;

async function call(method: string, ...args: string[]): Promise<string> {
  if (!secretBridge) secretBridge = bridge.createBridge(SECRET_BRIDGE_NAME);
  const raw = await secretBridge.callMethod(method, ...args);
  const result = JSON.parse(String(raw)) as Record<string, string>;
  if (result.error) throw new Error(result.error);
  return result.data || '';
}

export class KeystoreCipher {
  private readonly alias: string;

  constructor(alias: string) {
    this.alias = alias;
  }

  encrypt(input: Uint8Array, iv: Uint8Array): Promise<Uint8Array> {
    return this.transform('encrypt', input, iv);
  }

  decrypt(input: Uint8Array, iv: Uint8Array): Promise<Uint8Array> {
    return this.transform('decrypt', input, iv);
  }

  private async transform(method: string, input: Uint8Array, iv: Uint8Array): Promise<Uint8Array> {
    const helper = new util.Base64Helper();
    const output = await call(method, this.alias, helper.encodeToStringSync(input), helper.encodeToStringSync(iv));
    return helper.decodeSync(output);
  }
}
