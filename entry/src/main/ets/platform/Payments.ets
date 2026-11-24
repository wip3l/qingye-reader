// 应用外充值（支付宝手机网站支付、兑换码）的统一出口。安卓构建会用 android/overlay 里的同名文件替换本文件。
// 鸿蒙上数字商品只能走华为应用内支付（应用市场规定），这里什么都不做，鸿蒙包里也没有外部支付入口。

export interface ExternalRechargeResult {
  /** PENDING（还没付款或通知未到）/ PAID / CLOSED / REFUNDED */
  status: string;
  points: number;
  creditedPoints: number;
  debtOffsetPoints: number;
}

/** 本平台是否提供应用外充值（支付宝 + 兑换码）。 */
export const EXTERNAL_RECHARGE_AVAILABLE: boolean = false;

/** 下单并在浏览器里打开收银台，返回订单号；回到应用后用 checkExternalRecharge 查结果。 */
export async function startExternalRecharge(_productId: string, _token: string): Promise<string> {
  throw new Error('本平台不支持应用外充值');
}

export async function checkExternalRecharge(_orderId: string, _token: string): Promise<ExternalRechargeResult> {
  throw new Error('本平台不支持应用外充值');
}

export async function redeemRechargeCode(_code: string, _token: string): Promise<ExternalRechargeResult> {
  throw new Error('本平台不支持兑换码充值');
}
