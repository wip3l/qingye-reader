# 安卓端点数充值

## 实现状态（方案 A + C 已实现）

- 服务端：`server/src/rechargeRoutes.ts`、`alipay.ts`、`pointCredit.ts`，迁移 `034_recharge.sql`，测试 `recharge.test.ts`。
  入账与 `/v1/iap/credit` 共用 `creditPaidPoints`（先抵扣欠款，再加 balance 与 paid_balance，写幂等流水）；全额退款按 IAP 规则冲正，
  部分退款只记日志、人工处理。
- 客户端：`platform/Payments.ets`（鸿蒙实现为空，安卓实现下单、经 `SystemBridge.openUrl` 打开收银台、查单、兑换码），
  `AccountCenter` 的充值面板在安卓上显示支付宝档位和兑换码。
- 兑换码：`node server/scripts/redeem-codes.mjs --batch <批次> --points <点数> --count <数量> [--expires YYYY-MM-DD]`，
  库里只存 SHA-256，明文只打印一次。

### 上线步骤

1. 跑迁移 `034_recharge.sql`。
2. 在支付宝开放平台为应用开通“手机网站支付”，把应用私钥、支付宝公钥放到服务器文件里，设置环境变量：
   `ALIPAY_APP_ID`、`ALIPAY_PRIVATE_KEY_PATH`、`ALIPAY_PUBLIC_KEY_PATH`、`ALIPAY_NOTIFY_URL`（如 `https://<域名>/v1/recharge/notify/alipay`），
   可选 `ALIPAY_RETURN_URL`、`ALIPAY_QUIT_URL`、`ALIPAY_SELLER_ID`（收款账号 2088 开头，配置后核对通知）、`ALIPAY_GATEWAY`（沙箱时改成沙箱网关）。
   四个必填项缺一个，支付宝下单就返回 503，兑换码不受影响。
3. 先用支付宝沙箱走一遍：下单 → 沙箱账号付款 → 通知入账 → 回到应用查单到账 → 退款冲正。
4. 部署服务端后再发安卓新包（旧包点充值只会提示去鸿蒙设备）。

## 调研（原文）

## 现状

- 鸿蒙端充值走华为应用内支付（IAP Kit）：客户端拿到 `jwsPurchaseOrder` → `POST /v1/iap/credit` →
  服务端验签并向华为查单（`server/src/iap.ts`）→ 同一事务里写 `point_ledger`（`IAP_RECHARGE`，幂等键 `iap:<订单号>`）、
  加 `point_wallets.paid_balance`，先抵扣 `account_debts.iap_debt_points`；退款由 `iapReconciliation.ts` 冲正。
- 商品写死在服务端 `PRODUCT_POINTS`：`legado_points_10/60/100/300/500/1000`，1 元 = 10 点。
- 安卓端没有华为账号服务和 IAP Kit，`AccountCenter.openRecharge()` 直接提示“安卓版暂未开放充值，可在鸿蒙设备上充值”。
- 安卓包目前通过 GitHub 预发布分发（`android-v4.6.037`），不受应用商店支付政策约束；上架商店后要按商店规则重新评估（见末节）。

## 可选方案

| 方案 | 客户端改动 | 服务端改动 | 前置条件 | 体验 |
| --- | --- | --- | --- | --- |
| A. 网页收银台（支付宝手机网站支付 / 微信 H5 支付） | 小：下单后用系统浏览器打开收银台地址，回到前台时查单 | 中：下单、异步通知、查单、入账 | 企业商户号；微信 H5 支付要在商户平台登记已备案的域名 | 跳浏览器再拉起支付宝/微信，多一步 |
| B. 原生 APP 支付（支付宝 SDK `PayTask.payV2`、微信 OpenSDK `PayReq`） | 中：新增原生桥 `PayBridge.java`，微信要加 `wxapi.WXPayEntryActivity` | 同 A，签名参数换成 APP 支付 | 同 A，另需支付宝开放平台应用、微信开放平台移动应用（登记包名 `io.legado.read` 和发布证书 MD5） | 直接拉起支付宝/微信，最好 |
| C. 兑换码 | 小：输入兑换码的入口 | 小：码表 + 兑换接口，入账同上 | 码在别处卖（小程序、店铺） | 最差，但不接任何支付 |
| D. Google Play 结算 | 中：Play Billing Library | 中：Google Play Developer API 验单 | 上架 Google Play；国内用户基本用不了 | 只对海外 Play 用户有意义 |
| E. 华为 HMS IAP（安卓版 SDK） | 中 | 中：HMS 订单验证与鸿蒙 IAP 不是同一套接口 | 设备装有 HMS Core（只有老华为机） | 覆盖面太小 |

**建议：先做 A，再视情况升级到 B。** A 几乎不碰 ArkUI-X 原生层（只要能打开外部浏览器），服务端的订单、通知、入账、退款链路
B 可以原样复用，届时只换下单签名和客户端拉起方式。C 可作为没有商户号时的过渡。D、E 不建议。

## 服务端（A、B 共用）

1. 迁移 `034_recharge_orders.sql`：`recharge_orders(id, user_id, channel, product_id, amount_fen, points, status,
   provider_trade_no, created_at, paid_at, refunded_at)`，`(channel, provider_trade_no)` 唯一。
2. `POST /v1/recharge/orders`（需登录）：按 `PRODUCT_POINTS` 定价下单，金额只由服务端算，返回收银台地址（A）或
   APP 支付签名串（B）。
3. `POST /v1/recharge/notify/alipay`、`/notify/wechat`：验签（支付宝 RSA2、微信支付 v3 平台证书）、核对金额和商户号，
   在一个事务里改订单状态并入账。入账照搬 `/v1/iap/credit` 的逻辑：`point_ledger` 记 `WEB_RECHARGE`（或按渠道分开），
   幂等键 `recharge:<订单号>`，加 `paid_balance`，先抵扣欠款。建议把这段事务从 `index.ts` 抽成公用函数，IAP 和新渠道一起用。
4. `GET /v1/recharge/orders/:id`：客户端回到前台后查单；服务端顺带主动向支付宝/微信查一次，防止通知延迟。
5. 退款与对账：参照 `iapReconciliation.ts` 的冲正规则（已花掉的部分记欠款），定时拉取渠道账单核对。
6. 配置：商户号、应用 ID、私钥、平台证书路径进 `config.ts`，按现有 `readSecretFile` 方式读取。

## 客户端

- `AccountCenter.openRecharge()`：`huaweiServicesAvailable()` 为假时不再弹提示，改为打开安卓收银面板
  （复用现有充值档位 UI，商品来自服务端，不再取 IAP 商品列表）。
- 平台层新增 `platform/Payments.ts`，两份实现：鸿蒙版转出现有 IAP 流程；安卓版下单 →（A）经 `SystemBridge` 增加的
  `openUrl`（`Intent.ACTION_VIEW`）打开收银台 /（B）经 `PayBridge` 拉起 SDK → `onPageShow` 时查单并刷新余额。
  按 `docs/android-build.md` 的规则，两份实现一起补，`platform-parity-check.mjs` 会核对。
- 收银台页面（A）由服务端托管，可放在 `server/` 下与 `lottery-web` 同样的静态目录。

## 合规与上架

- 鸿蒙版必须继续只走 IAP：华为应用市场对数字商品要求使用应用内支付，鸿蒙包里不能出现外部支付入口。
  安卓支付代码只放在 `android/overlay` 的平台层实现里，鸿蒙包里不存在。
- 安卓包如上架 Google Play，数字商品须走 Play 结算（方案 D）；上架国内商店前，逐家确认对非游戏应用虚拟商品第三方支付的要求
  （华为应用市场的安卓应用通常也要求数字商品走 HMS IAP，需核实）。GitHub 直装不受限制。
- 点数协议、隐私政策要补充支付宝/微信支付的说明；充值页注明“点数仅用于本应用数字内容，不支持转让或提现”（与现有文案一致）。

## 待定

- 商户主体与资质：支付宝、微信支付都要企业（或个体工商户）主体，个人账号开不了 APP 支付和 H5 支付。
- 微信开放平台要的是发布证书的 MD5 签名（`docs/android-build.md` 只记了 SHA-256），用 `keytool -list -v` 从发布密钥取。
- 是否给安卓渠道单独定价或加手续费：渠道费率（约 0.6%）远低于 IAP，建议与鸿蒙同价。
