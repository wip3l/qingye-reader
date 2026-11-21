# 用券开终身后升级不补回券额 · 服务端增量更新包 · 2026-11-19

用抵扣券开通的终身会员，补差价升级终身超级会员时不再把券额补回去。不需要更新 App。

- 开通终身会员时记下的升级抵扣额改为成交价（原来是成交价减券额）。促销价开通的仍按促销价抵扣。
- 迁移 033：已经用券开了终身、还没升级的账号，把抵扣额补回券额。事务执行、可重复执行；
  只改仍是“成交价减券额”的记录，手工调整过抵扣额的账号不动。
- 报价规则版本升到 3：安装瞬间还没付款的旧报价会提示“报价已过期”，重新查看价格即可。

例：原价 1290 点的终身会员用了减 100 点的券，实付 1190 点。升级终身超级会员（2490 点）时，
原来要补 1300 点，装好后补 1200 点。

适用当前服务器：运行目录 `/www/wwwroot/qingye.icynol.com`，服务 `legado-account.service`，
Node `/www/server/nodejs/v22.23.1/bin/node`，数据库 `legado_commerce`。不修改环境文件。

## 安装

上传 ZIP 到 `/root`，以 root 执行：

```bash
stage=$(mktemp -d /root/qingye-coupon-upgrade-credit.XXXXXX)
unzip -q /root/qingye-coupon-upgrade-credit-20261119.zip -d "$stage"
bash "$stage/update.sh" --check
bash "$stage/update.sh"
```

看到 `PASS: coupon upgrade credit installed` 即完成。更新会短暂重启服务。

- `--check` 只做预检：把两处改动打到线上 `membershipPolicy.js` 的副本上。线上文件是历次补丁叠出来的，
  所以每处改动只认它要改的那一句，已有的跳过；找不到时提示 `BASELINE_MISMATCH` 并写明是哪一处，然后退出。
  打好的副本在内存里实际运行，核对用券、不用券、促销价三种情况的抵扣额；并报告有多少个账号的抵扣额会被修正。
  不执行迁移、不替换文件、不重启服务。
- 正式安装先停服务、替换模块，在服务停着的时候执行迁移并核对没有遗漏，再启动服务。
- 文件替换、迁移或健康检查失败时，脚本会恢复原 `membershipPolicy.js` 并启动服务，数据库保留。
- 装好后检查：服务健康、`/v1/membership` 未登录返回 401、公网健康检查。

## 回滚

```bash
bash "$stage/rollback.sh" /root/qingye-coupon-upgrade-credit-backup.XXXXXX
```

回滚恢复原来的 `membershipPolicy.js`。迁移修正过的抵扣额保留；回滚之后新用券开通的终身会员会重新按“成交价减券额”记录，
再次安装本更新时迁移会一并修正。

包内文件：`update.sh` 更新、`rollback.sh` 回滚、`common.sh` 公共设置、`patch.mjs` 打补丁（含两处改动）、
`check.mjs` 预检、`runtime/` 打在抽奖版本上的参考结果（只供核对）、`src/` 源码、`migrations/` 本次迁移、`RELEASE.json`、`SHA256SUMS`。
