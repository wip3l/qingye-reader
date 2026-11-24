// 应用外充值（支付宝手机网站支付、兑换码）的统一出口。安卓构建会用 android/overlay 里的同名文件替换本文件。
// 鸿蒙上数字商品只能走华为应用内支付（应用市场规定），这里什么都不做，鸿蒙包里也没有外部支付入口。

export interface ExternalRechargeResult {
  /** PENDING（还没付款或通知未到）/ PAID / CLOSED / REFUNDED */
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
