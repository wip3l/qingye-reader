# 预付更高档立即生效 · 服务端增量更新包 · 2026-11-24

月度会员期间再开年度（应用内购买或兑换码），会员等级立刻显示年度，年度的每月朗读礼包也马上能领。
原来年度一段排在月度之后，要等月度那段用完才算年度。不需要更新 App。

- 会员等级改为取本期还没结束的已付各段里最高的一档。年度会员再加一个月，仍然算年度；
  各段都用完后照常到期。到期时间、价格、报价都不变。
- 只改 `membershipService.js` 里查会员等级的一句，没有数据库迁移。

适用当前服务器：运行目录 `/www/wwwroot/qingye.icynol.com`，服务 `legado-account.service`，
Node `/www/server/nodejs/v22.23.1/bin/node`，数据库 `legado_commerce`。不修改环境文件。

## 安装

上传 ZIP 到 `/root`，以 root 执行：

```bash
stage=$(mktemp -d /root/qingye-membership-tier.XXXXXX)
unzip -q /root/qingye-membership-tier-20261124.zip -d "$stage"
bash "$stage/update.sh" --check
bash "$stage/update.sh"
```

看到 `PASS: membership tier installed` 即完成。更新会短暂重启服务。

- `--check` 只做预检：把改动打到线上 `membershipService.js` 的副本上。线上文件是历次补丁叠出来的，
  所以只认要改的那一句查询，已改过的跳过；找不到时提示 `BASELINE_MISMATCH` 并退出。
  打好的副本和线上的 `membershipPolicy.js`、`membershipSales.js` 放在一起实际加载运行，核对查询条件与排序；
  再只读统计有多少个在期会员的等级会立刻变化。不替换文件、不重启服务。
- 文件替换或健康检查失败时，脚本会恢复原 `membershipService.js` 并启动服务。
- 装好后检查：服务健康、`/v1/membership` 未登录返回 401、公网健康检查。

## 回滚

```bash
bash "$stage/rollback.sh" /root/qingye-membership-tier-backup.XXXXXX
```

回滚恢复原来的 `membershipService.js`，等级回到只看当前生效那一段。已领的朗读礼包保留。

包内文件：`update.sh` 更新、`rollback.sh` 回滚、`common.sh` 公共设置、`patch.mjs` 打补丁、
`check.mjs` 预检、`runtime/` 打在抽奖版本上的参考结果（只供核对）、`src/` 源码、`RELEASE.json`、`SHA256SUMS`。
