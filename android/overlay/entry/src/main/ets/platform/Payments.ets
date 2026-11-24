// platform/Payments.ts 的安卓实现：支付宝手机网站支付与兑换码（docs/android-recharge.md 方案 A + C）。
// 下单由服务端定价并签名，这里只把收银台地址交给系统浏览器（支付宝 App 装了会被拉起），回到应用后查单。
import bridge from '@arkui-x.bridge';
import { AccountCommerceApi } from '../account/AccountCommerceApi';

/** 与 SystemBridge.NAME 一致。 */
const SYSTEM_BRIDGE_NAME = 'io.legado.read/system';

export interface ExternalRechargeResult {
  status: string;
  points: number;
  /** 到账的充值点；会员兑换码时是实付之外留作充值点的差额。 */
  creditedPoints: number;
  debtOffsetPoints: number;
  /** 兑换码种类：'points' 点数码 / 'membership' 会员码；充值订单为空。 */
  kind: string;
  /** 会员码开通的档位（MONTHLY…）和名称；其余为空。 */
  sku: string;
  membershipName: string;
}

interface OrderResponse {
  orderId: string;
  checkoutUrl: string;
}

export const EXTERNAL_RECHARGE_AVAILABLE: boolean = true;

let systemBridge: bridge.BridgeObject | null = null;

async function openInBrowser(url: string): Promise<void> {
  if (!systemBridge) systemBridge = bridge.createBridge(SYSTEM_BRIDGE_NAME);
  const raw = await systemBridge.callMethod('openUrl', url);
  const result = JSON.parse(String(raw)) as Record<string, Object>;
  if (result['error']) throw new Error(String(result['error']));
}

function toResult(value: string): ExternalRechargeResult {
  const raw = JSON.parse(value) as Record<string, Object>;
  return {
    status: String(raw['status'] || 'PAID'),
    points: Number(raw['points']) || 0,
    creditedPoints: Number(raw['creditedPoints']) || 0,
    debtOffsetPoints: Number(raw['debtOffsetPoints']) || 0,
    kind: String(raw['kind'] || ''),
    sku: String(raw['sku'] || ''),
    membershipName: String(raw['membershipName'] || '')
  };
}

export async function startExternalRecharge(productId: string, token: string): Promise<string> {
  const value = await AccountCommerceApi.rechargeRequest('/orders', 'POST',
    JSON.stringify({ productId: productId, channel: 'ALIPAY' }), token);
  const order = JSON.parse(value) as OrderResponse;
  if (!order.checkoutUrl || !order.checkoutUrl.startsWith('https://')) {
    throw new Error('收银台地址无效');
  }
  await openInBrowser(order.checkoutUrl);
  return order.orderId;
}

export async function checkExternalRecharge(orderId: string, token: string): Promise<ExternalRechargeResult> {
  return toResult(await AccountCommerceApi.rechargeRequest(`/orders/${encodeURIComponent(orderId)}`, 'GET', '', token));
}

export async function redeemRechargeCode(code: string, token: string): Promise<ExternalRechargeResult> {
  return toResult(await AccountCommerceApi.rechargeRequest('/redeem', 'POST', JSON.stringify({ code: code }), token));
}
