# 修改用户名 · 服务端增量更新包 · 2026-11-25

设好用户名密码的账号可以修改用户名，30 天一次。新版 App 的“登录与账号安全”页用到这个接口，
**要先装好本更新再发布 App**，否则点保存会报 404。旧版 App 不受影响。

- 新接口 `POST /v1/account/username`（需登录）：验证当前密码后改名。只改大小写也算一次；
  第一次设置用户名不算修改。旧用户名立即释放，别人可以注册；密码、恢复码和已登录的设备都不变。
- 冷却期内再改返回 429 `USERNAME_CHANGE_TOO_SOON`；`/v1/account/login-methods` 多返回
  `usernameChangeAvailableAt`（冷却期内为下次能改的时间，毫秒；否则 `null`）。
- 迁移 036：`app_users` 增加可空列 `username_changed_at`（表级授权已覆盖，无需另行授权）。注销到期清理时一并清空。
- 只替换 `accountAuth.js`，不新增文件，不修改环境文件。

适用当前服务器：运行目录 `/www/wwwroot/qingye.icynol.com`，服务 `legado-account.service`，
Node `/www/server/nodejs/v22.23.1/bin/node`，数据库 `legado_commerce`。
线上 `accountAuth.js` 是 `qingye-recharge-20261123` 或更早的 `qingye-password-account-20261114` 装上的版本都可以。

## 安装

上传 ZIP 到 `/root`，以 root 执行：

```bash
stage=$(mktemp -d /root/qingye-username-change.XXXXXX)
unzip -q /root/qingye-username-change-20261125.zip -d "$stage"
bash "$stage/update.sh" --check
bash "$stage/update.sh"
```

看到 `PASS: username change installed` 即完成。更新会短暂重启服务。

- `--check` 只做预检，不执行正式库迁移、不替换文件、不重启服务：
  - 把补丁打到线上 `accountAuth.js` 的副本上，结果必须与包内两个参考版本之一只差空白；对不上时提示
    `BASELINE_MISMATCH` 或 `PATCH_RESULT_MISMATCH` 并退出。
  - 用线上运行目录的副本加载补好的模块、挂上路由，确认改名接口未登录返回 401、用户名格式不对时不碰数据库就拒绝。
  - 在新建的一次性数据库里跑全部迁移，用真实 PostgreSQL 走一遍改名：密码错、重名、同名、冷却期、
    旧名释放、新名登录、多个账号抢同一个名字只有一个成功、同一账号并发改名只成功一次、注销清理。跑完删掉临时库。
- 正式安装先执行迁移 036（可重复执行），再替换 `accountAuth.js` 并重启。替换或健康检查失败时，
  脚本会恢复原文件并启动服务，新加的列保留（旧代码不读它）。
- 装好后检查：服务健康、`/v1/account/username`、`/v1/account/password`、`/v1/account/login-methods`
  未登录返回 401、公网健康检查。

## 回滚

```bash
bash "$stage/rollback.sh" /root/qingye-username-change-backup.XXXXXX
```

回滚恢复原来的 `accountAuth.js`，改名接口随之下线。已经改过的用户名保持新名字，`username_changed_at` 列保留。

包内文件：`update.sh` 更新、`rollback.sh` 回滚、`common.sh` 公共设置、`patch.mjs` 与 `patch.json` 打补丁、
`check.mjs` 预检、`username-change-pg-check.mjs` 临时库检查、`migrations/` 正式迁移、`test-migrations/` 临时库用的全部迁移、
`runtime/` 参考结果（`accountAuth.js` 打在充值版本上，`accountAuth.pre-recharge.js` 打在用户名密码版本上，只供核对）、
`src/` 源码、`RELEASE.json`、`SHA256SUMS`。
