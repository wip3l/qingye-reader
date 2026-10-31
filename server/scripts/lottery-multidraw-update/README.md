# 抽奖改为每人三次 · 服务端增量更新包 · 2026-10-30

在已安装的抽奖更新（`qingye-lottery-20261030`）之上，改为每个账号最多抽 3 次：

- 账号只保留一张券。抽到更高档的奖项时，旧券标记为“已替换”（`REPLACED`），换发新券；没有更高时保留原券。
- 限量奖品的已发数量只计当前持有的人，换券时退回旧奖品的名额。
- 每次抽奖带上“第几次”。网络重试重复提交同一次，不会多扣次数。
- 券用掉后，剩余次数作废。
- 换券后，之前用旧券生成的会员报价无法付款，会提示“会员状态已变化，请重新查看价格”，避免按旧面额扣点。

迁移 028 给活动加上“每人次数”字段，把 `double11-2026` 设为 3 次；已有的抽奖记录算作第 1 次。

适用当前服务器：运行目录 `/www/wwwroot/qingye.icynol.com`，服务 `legado-account.service`，Node `/www/server/nodejs/v22.23.1/bin/node`，数据库 `legado_commerce`。

## 安装

上传 ZIP 到 `/root`，以 root 执行：

```bash
stage=$(mktemp -d /root/qingye-lottery-multidraw.XXXXXX)
unzip -q /root/qingye-lottery-multidraw-20261030.zip -d "$stage"
bash "$stage/update.sh" --check
bash "$stage/update.sh"
```

看到 `PASS: three-draw lottery installed` 即完成。更新会短暂重启服务，不修改环境文件。

- `--check` 只做预检：
  - 在 `/tmp` 的临时副本里加载新模块。
  - 在新建的临时数据库里运行真实 PostgreSQL 并发检查，用的是包内完整迁移，跑完即删。

  预检不执行正式库迁移，不替换文件，不重启服务。
- `lotteryService.js`、`lotteryRoutes.js` 必须与上一次抽奖更新装上的版本完全一致才会被替换，否则提示 `BASELINE_MISMATCH`，并在停服务前退出。
- 迁移以事务执行，可以重复执行。
- 文件替换或健康检查失败时，脚本会恢复原模块并启动服务，数据库保留。

装好后，把包里的 `web/index.html` 替换到 `/www/wwwroot/lottery-web/index.html`。新页面会显示剩余次数、每次的结果和当前的券。

```bash
cp "$stage/web/index.html" /www/wwwroot/lottery-web/index.html && chown www:www /www/wwwroot/lottery-web/index.html
```

## 调整次数与概率

```sql
UPDATE lottery_campaigns SET draws_per_user = 3 WHERE id = 'double11-2026';
UPDATE lottery_prizes SET weight = 40 WHERE id = 'double11-2026-lucky';
```

每次抽奖的概率按 `weight` 计算。多抽几次取最高后，用户最终拿到高档券的比例会明显变高，见方案文档。

## 回滚

```bash
bash "$stage/rollback.sh" /root/qingye-lottery-multidraw-backup.XXXXXX
```

- 回滚会恢复单次抽奖的两个模块，抽奖记录和券都保留。
- 回滚后，已经抽过的账号会被当作“已抽过”。如果某个账号换过券，页面可能显示较早的那次结果，但实际可用的券仍是最新那张。
- 想回到每人 1 次，更简单的办法是不回滚，直接把 `draws_per_user` 改成 1。

## 验证范围

- **本地**：服务端完整测试 118 项通过。新增的测试覆盖：三次取最高、换券退回限量名额、超额与乱序请求被拒绝、重试返回原结果、换券后旧报价被拒绝、用券后不能再抽。
- **部署脚本会验证**：
  - 真实 PostgreSQL 并发：16 个账号三轮并发换券后，每人只有一张券，5 张特等奖不超发，计数准确。
  - 原有的并发检查。
  - 服务健康状态、`drawsPerUser` 为 3、无来源的抽奖请求被拒绝。

包内文件：`update.sh` 更新、`rollback.sh` 回滚、`common.sh` 公共设置、`check.mjs` 预检、`BASELINE` 基线校验值、`runtime/` 编译模块、`src/` 源码、`migrations/` 本次迁移、`test-migrations/` 临时库用的完整迁移、`web/index.html` 抽奖页、`lottery-pg-concurrency.mjs` 并发检查、`RELEASE.json`、`SHA256SUMS`。
