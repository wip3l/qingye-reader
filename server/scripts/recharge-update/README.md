# 安卓端点数充值（支付宝 + 兑换码）· 服务端增量更新包 · 2026-11-23

安卓版的“充值”改为支付宝手机网站支付和兑换码（鸿蒙版仍只走华为应用内支付，不受影响）。
**安卓新包要在本更新装好之后再发布**，否则充值面板和兑换码都返回 404。

- 新接口：
  - `GET /v1/recharge/channels`（档位与渠道开关）、`POST /v1/recharge/orders`（支付宝下单，返回收银台地址）、
    `GET /v1/recharge/orders/:id`（查单，未完成时顺带向支付宝查一次）、`POST /v1/recharge/redeem`（兑换码）
  - `POST /v1/recharge/notify/alipay`（支付宝异步通知，不登录，验签后才处理）
- 迁移 034：新表 `recharge_orders`（支付宝订单）和 `redeem_codes`（只存兑换码的 SHA-256），并授权给服务账号。
- `index.js` 改动：挂上充值接口；`/v1/iap/credit` 的入账改用新模块 `pointCredit.js`（规则不变：先抵扣退款欠款，
  再加 balance 与 paid_balance，写幂等流水）。`config.js` 增加 `ALIPAY_*` 配置，`accountAuth.js` 把 `recharge_orders`
  登记为注销时保留的交易记录。新增 `alipay.js`、`pointCredit.js`、`rechargeRoutes.js` 和发卡工具 `redeem-codes.mjs`。
- 规则：1 元 = 10 点，档位与华为内购相同（10/60/100/300/500/1000 点），金额只由服务端算；充值和兑换都记充值点
  （可买会员）。支付宝全额退款按华为退款的规则冲正（已花掉的部分记欠款），部分退款只记日志、人工处理。

适用当前服务器：运行目录 `/www/wwwroot/qingye.icynol.com`，服务 `legado-account.service`，
Node `/www/server/nodejs/v22.23.1/bin/node`，数据库 `legado_commerce`。**不修改环境文件**：
没配支付宝时只开放兑换码，支付宝下单返回“支付宝充值暂未开放”。

## 安装

上传 ZIP 到 `/root`，以 root 执行：

```bash
stage=$(mktemp -d /root/qingye-recharge.XXXXXX)
unzip -q /root/qingye-recharge-20261123.zip -d "$stage"
bash "$stage/update.sh" --check
bash "$stage/update.sh"
```

看到 `PASS: Android recharge installed` 即完成，同一行会说明支付宝是否已配置。更新会短暂重启服务。

- `--check` 只做预检，不执行正式库迁移、不替换文件、不重启服务：
  - 把补丁打到线上 `index.js`、`config.js`、`accountAuth.js` 的副本上；线上模块和账号密码更新（index、accountAuth）
    或抽奖更新（config）装上的版本不一致时提示 `BASELINE_MISMATCH` 并退出。打补丁的结果和包内参考模块只允许有空白差异。
  - 在 `/tmp` 的临时运行副本里，以服务自己的用户、带服务环境加载新模块：检查接口都已挂上、档位与金额、
    未签名的支付宝通知被拒；配置了支付宝时还会读取两个密钥文件并生成一个签名的收银台地址（不会联网）。
  - 在新建的临时数据库里跑包内完整迁移，用真实 PostgreSQL 检查：034 能在已有数据上执行并可重复执行、
    新表授权给了服务账号（用临时角色模拟）；华为内购入账先抵扣欠款且幂等；8 个并发的付款通知只入账一次；
    金额不符的通知被忽略、超时关闭后才付的款照样入账；4 个并发的全额退款通知只冲正一次、已花掉的部分记成欠款；
    8 个账号抢同一个兑换码只有一个到账，过期和不存在的码被拒；每张带 `user_id` 的表都登记在注销清单里。跑完即删库删角色。
- 迁移以事务执行，可以重复执行；执行后检查服务账号能读写两张新表。
- 文件替换或健康检查失败时，脚本会恢复原来的三个模块、删掉新文件并启动服务，数据库保留。
- 装好后检查：服务健康、`/v1/recharge/channels` 未登录返回 401、未签名的支付宝通知返回 `failure`、公网健康检查。

## 开通支付宝（装好后随时可做）

1. 支付宝开放平台：为应用开通“手机网站支付”，加签方式选公钥（RSA2），记下应用 ID，下载支付宝公钥。
2. 把应用私钥、支付宝公钥各存成一个文件（PEM 或支付宝工具导出的单行 base64 都可以），属主为服务用户、权限 600，
   例如 `/etc/legado-account/alipay-app-private.pem`、`/etc/legado-account/alipay-public.pem`。
3. 在 `/etc/legado-account.env` 增加：

   ```
   ALIPAY_APP_ID=2021...
   ALIPAY_PRIVATE_KEY_PATH=/etc/legado-account/alipay-app-private.pem
   ALIPAY_PUBLIC_KEY_PATH=/etc/legado-account/alipay-public.pem
   ALIPAY_NOTIFY_URL=https://qingye.icynol.com/v1/recharge/notify/alipay
   # 可选：收款账号（2088 开头，配置后核对通知）、付款后/取消时跳回的页面、沙箱网关
   ALIPAY_SELLER_ID=2088...
   ALIPAY_RETURN_URL=https://qingye.icynol.com/
   ALIPAY_GATEWAY=https://openapi-sandbox.dl.alipaydev.com/gateway.do
   ```

4. 再跑一次 `bash "$stage/update.sh" --check`：会用新配置读密钥、生成签名的收银台地址，读不了密钥会在这里报错。
   通过后 `systemctl restart legado-account.service`。
5. 先用沙箱走一遍：下单 → 沙箱账号付款 → 通知入账 → 回到应用查单到账 → 退款冲正。正式上线时删掉 `ALIPAY_GATEWAY` 那行再重启。

## 发兑换码

```bash
systemd-run --quiet --wait --pipe -p EnvironmentFile=/etc/legado-account.env \
  -p WorkingDirectory=/www/wwwroot/qingye.icynol.com /www/server/nodejs/v22.23.1/bin/node redeem-codes.mjs \
  --batch 2026-11-shop --points 300 --count 50 --expires 2027-06-30
```

点数只能是 10/60/100/300/500/1000；明文只在这里打印一次，直接存到发卡渠道，不要留在服务器上。
加 `--dry-run` 只打印不写库。作废一批：`UPDATE redeem_codes SET revoked_at = now() WHERE batch = '…' AND redeemed_by IS NULL;`

## 回滚

```bash
bash "$stage/rollback.sh" /root/qingye-recharge-backup.XXXXXX
```

回滚恢复原来的 `index.js`、`config.js`、`accountAuth.js`，删掉新模块和发卡工具，充值接口随之消失。
数据库的新表、订单、兑换码和已到账的点数保留。回滚后支付宝的重发通知会落空：已付款但还没入账的订单，
重新装上本更新后查单或支付宝重发时会补入账。

## 上线后

```sql
SELECT status, count(*), sum(amount_fen) / 100.0 AS yuan FROM recharge_orders GROUP BY status;
SELECT batch, count(*) AS total, count(redeemed_by) AS used,
       count(*) FILTER (WHERE revoked_at IS NOT NULL) AS revoked FROM redeem_codes GROUP BY batch;
```

包内文件：`update.sh` 更新、`rollback.sh` 回滚、`common.sh` 公共设置、`patch.mjs` 打补丁、`patch.json` 补丁内容、
`check.mjs` 预检、`recharge-pg-check.mjs` 真实数据库检查、`runtime/` 参考模块与新文件、`src/` 源码、
`migrations/` 本次迁移、`test-migrations/` 临时库用的完整迁移、`RELEASE.json`、`SHA256SUMS`。
