import { createPrivateKey, createPublicKey, createSign, createVerify, KeyObject } from 'node:crypto';

/**
 * 支付宝开放平台（gateway.do，RSA2）里本服务用到的三件事：手机网站支付下单（alipay.trade.wap.pay）、
 * 异步通知验签、主动查单（alipay.trade.query）。只依赖 node:crypto，签名规则见支付宝“自行实现签名”文档：
 * 去掉 sign（通知里还要去掉 sign_type）和空值，按参数名 ASCII 升序拼成 k=v&k=v，SHA256withRSA。
 */
export interface AlipayConfig {
  appId: string;
  /** 应用私钥：PEM，或支付宝工具导出的一行 base64（PKCS#8 或 PKCS#1 均可）。 */
  privateKey: string;
  /** 支付宝公钥（不是应用公钥）：PEM 或一行 base64。 */
  alipayPublicKey: string;
  gateway: string;
  notifyUrl: string;
  /** 付款完成后浏览器跳回的地址；可空。 */
  returnUrl: string;
  /** 用户在收银台点“返回商户”时去的地址；手机网站支付必填，可与 returnUrl 相同。 */
  quitUrl: string;
  /** 收款支付宝账号的 user_id（2088 开头）；配置了就在通知里核对 seller_id。 */
  sellerId: string;
}

export type AlipayFetch = (url: string, init: { method: string; headers: Record<string, string>;
  body: string }) => Promise<{ ok: boolean; status: number; text(): Promise<string> }>;

export interface AlipayTradeQuery {
  /** WAIT_BUYER_PAY / TRADE_CLOSED / TRADE_SUCCESS / TRADE_FINISHED；查无此单时为 NOT_FOUND。 */
  tradeStatus: string;
  tradeNo: string;
  totalAmount: string;
  raw: Record<string, unknown>;
}

function pemBody(key: string): string {
  return key.replace(/-----[^-]+-----/g, '').replace(/\s+/g, '');
}

export function loadPrivateKey(key: string): KeyObject {
  const trimmed = key.trim();
  if (trimmed.startsWith('-----')) return createPrivateKey(trimmed);
  const der = Buffer.from(pemBody(trimmed), 'base64');
  try {
    return createPrivateKey({ key: der, format: 'der', type: 'pkcs8' });
  } catch {
    return createPrivateKey({ key: der, format: 'der', type: 'pkcs1' });
  }
}

export function loadPublicKey(key: string): KeyObject {
  const trimmed = key.trim();
  if (trimmed.startsWith('-----')) return createPublicKey(trimmed);
  return createPublicKey({ key: Buffer.from(pemBody(trimmed), 'base64'), format: 'der', type: 'spki' });
}

/** 待签名串：去掉排除的键和空值，按键名 ASCII 升序拼接，值不做 URL 编码。 */
export function signContent(params: Record<string, string>, exclude: readonly string[]): string {
  return Object.keys(params)
    .filter(key => !exclude.includes(key) && params[key] !== undefined && params[key] !== '')
    .sort()
    .map(key => `${key}=${params[key]}`)
    .join('&');
}

export function rsa2Sign(content: string, privateKey: KeyObject): string {
  return createSign('RSA-SHA256').update(content, 'utf8').sign(privateKey, 'base64');
}

export function rsa2Verify(content: string, signature: string, publicKey: KeyObject): boolean {
  try {
    return createVerify('RSA-SHA256').update(content, 'utf8').verify(publicKey, signature, 'base64');
  } catch {
    return false;
  }
}

/** 支付宝要求的 timestamp：北京时间 yyyy-MM-dd HH:mm:ss。 */
export function alipayTimestamp(now: number): string {
  const beijing = new Date(now + 8 * 3600 * 1000);
  const pad = (value: number) => String(value).padStart(2, '0');
  return `${beijing.getUTCFullYear()}-${pad(beijing.getUTCMonth() + 1)}-${pad(beijing.getUTCDate())} ` +
    `${pad(beijing.getUTCHours())}:${pad(beijing.getUTCMinutes())}:${pad(beijing.getUTCSeconds())}`;
}

/** 分 → 支付宝金额字符串（元，两位小数）。 */
export function fenToYuan(fen: number): string {
  return (fen / 100).toFixed(2);
}

/** 支付宝金额字符串 → 分；格式不对返回 -1。 */
export function yuanToFen(amount: string): number {
  if (!/^\d+(\.\d{1,2})?$/.test(amount || '')) return -1;
  const [whole, fraction = ''] = amount.split('.');
  return Number(whole) * 100 + Number(fraction.padEnd(2, '0'));
}

export class AlipayClient {
  private readonly privateKey: KeyObject;
  private readonly publicKey: KeyObject;

  constructor(readonly config: AlipayConfig, private readonly fetcher: AlipayFetch = fetch as unknown as AlipayFetch,
    private readonly clock: () => number = Date.now) {
    this.privateKey = loadPrivateKey(config.privateKey);
    this.publicKey = loadPublicKey(config.alipayPublicKey);
  }

  private commonParams(method: string, bizContent: Record<string, string>): Record<string, string> {
    return {
      app_id: this.config.appId,
      method,
      format: 'JSON',
      charset: 'utf-8',
      sign_type: 'RSA2',
      timestamp: alipayTimestamp(this.clock()),
      version: '1.0',
      biz_content: JSON.stringify(bizContent)
    };
  }

  private signed(params: Record<string, string>): Record<string, string> {
    return { ...params, sign: rsa2Sign(signContent(params, ['sign']), this.privateKey) };
  }

  /** 手机网站支付收银台地址：客户端在系统浏览器里打开，支付宝 App 装了会被拉起。 */
  wapPayUrl(order: { outTradeNo: string; amountFen: number; subject: string; expireMinutes: number }): string {
    const expire = alipayTimestamp(this.clock() + order.expireMinutes * 60 * 1000);
    const params = this.commonParams('alipay.trade.wap.pay', {
      out_trade_no: order.outTradeNo,
      total_amount: fenToYuan(order.amountFen),
      subject: order.subject,
      product_code: 'QUICK_WAP_WAY',
      quit_url: this.config.quitUrl || this.config.returnUrl,
      time_expire: expire
    });
    params.notify_url = this.config.notifyUrl;
    if (this.config.returnUrl) params.return_url = this.config.returnUrl;
    const query = new URLSearchParams(this.signed(params));
    return `${this.config.gateway}?${query.toString()}`;
  }

  /** 异步通知验签：去掉 sign 和 sign_type 后验 RSA2；还要核对 app_id 与（配置了的话）seller_id。 */
  verifyNotify(params: Record<string, string>): boolean {
    if (!params.sign || params.sign_type !== 'RSA2') return false;
    if (params.app_id !== this.config.appId) return false;
    if (this.config.sellerId && params.seller_id !== this.config.sellerId) return false;
    return rsa2Verify(signContent(params, ['sign', 'sign_type']), params.sign, this.publicKey);
  }

  /** 主动查单；响应也要验签（签的是 alipay_trade_query_response 那段原始 JSON 文本）。 */
  async queryTrade(outTradeNo: string): Promise<AlipayTradeQuery> {
    const params = this.signed(this.commonParams('alipay.trade.query', { out_trade_no: outTradeNo }));
    const response = await this.fetcher(this.config.gateway, {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded;charset=utf-8' },
      body: new URLSearchParams(params).toString()
    });
    if (!response.ok) throw new Error(`Alipay query HTTP ${response.status}`);
    const text = await response.text();
    const node = extractResponseNode(text, 'alipay_trade_query_response');
    const parsed = JSON.parse(text) as { sign?: string };
    if (!node || !parsed.sign || !rsa2Verify(node, parsed.sign, this.publicKey)) {
      throw new Error('Alipay query signature invalid');
    }
    const body = JSON.parse(node) as Record<string, unknown>;
    if (body.code !== '10000') {
      if (body.sub_code === 'ACQ.TRADE_NOT_EXIST') {
        return { tradeStatus: 'NOT_FOUND', tradeNo: '', totalAmount: '', raw: body };
      }
      throw new Error(`Alipay query failed: ${String(body.sub_code || body.code)}`);
    }
    return {
      tradeStatus: String(body.trade_status || ''),
      tradeNo: String(body.trade_no || ''),
      totalAmount: String(body.total_amount || ''),
      raw: body
    };
  }
}

/** 从响应原文里截出 "<name>": 后面的那个 JSON 对象（验签要用原文，不能重新序列化）。 */
export function extractResponseNode(text: string, name: string): string | null {
  const key = `"${name}"`;
  const keyAt = text.indexOf(key);
  if (keyAt < 0) return null;
  const start = text.indexOf('{', keyAt + key.length);
  if (start < 0) return null;
  let depth = 0;
  let inString = false;
  for (let i = start; i < text.length; i++) {
    const ch = text[i];
    if (inString) {
      if (ch === '\\') i++;
      else if (ch === '"') inString = false;
      continue;
    }
    if (ch === '"') inString = true;
    else if (ch === '{') depth++;
    else if (ch === '}' && --depth === 0) return text.substring(start, i + 1);
  }
  return null;
}
