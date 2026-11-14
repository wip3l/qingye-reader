# 用户名密码账号与账号注销 · 服务端增量更新包 · 2026-11-14

App 新增“用户名登录 / 注册”和“登录与账号安全”页：不用华为账号也能注册，忘记密码用恢复码重设，
用户名账号可以绑定华为账号，华为账号用户也能补设用户名密码；所有账号都能申请注销。
**App 的这个版本要在本更新装好之后再发布**，否则新入口全部返回 404。

- 新接口：
  - `POST /v1/auth/register`、`POST /v1/auth/password`、`POST /v1/auth/recover`（注册、密码登录、恢复码重设）
  - `GET /v1/account/login-methods`、`POST /v1/account/password`、`POST /v1/account/recovery-codes`
  - `POST /v1/account/huawei`（给当前账号绑定华为账号）、`POST /v1/account/deletion`（申请注销）
- 迁移 031：
  - `app_users` 增加用户名、密码哈希、失败次数与锁定时间、注册 IP、注销申请与完成时间等列，`huawei_open_id` 改为可空
  - 新表 `account_recovery_codes`（只存 HMAC）和 `huawei_welcome_claims`（只存 openId 的 SHA-256）
  - 按已有的赠点流水回填领取记录：老用户的华为账号以后换绑或注销后重登，都不会再领一次 300 点
- `index.js` 改动：华为登录的赠点改为按华为账号判断、登录时撤销冷静期内的注销申请、挂上新接口、
  每小时处理一次冷静期（7 天）已满的注销。新增 `accountAuth.js`、`accountCredentials.js` 两个模块。
- 规则：用户名注册不送点，绑定没领过的华为账号时补发；华为账号已属于别的账号时拒绝绑定；
  连续输错 5 次密码起锁定 1、2、4… 分钟（最长 1 小时）；同一 IP 一天最多注册 20 个账号，注册 IP 两天后清空。
- 恢复码的 HMAC 密钥由 `SESSION_SECRET` 派生：更换 `SESSION_SECRET` 会让已发出的恢复码一起失效（登录会话本来也会失效）。

适用当前服务器：运行目录 `/www/wwwroot/qingye.icynol.com`，服务 `legado-account.service`，
Node `/www/server/nodejs/v22.23.1/bin/node`，数据库 `legado_commerce`。不修改环境文件。

## 安装

上传 ZIP 到 `/root`，以 root 执行：

```bash
stage=$(mktemp -d /root/qingye-password-account.XXXXXX)
unzip -q /root/qingye-password-account-20261114.zip -d "$stage"
bash "$stage/update.sh" --check
bash "$stage/update.sh"
```

看到 `PASS: username and password accounts installed` 即完成。更新会短暂重启服务。

- `--check` 只做预检，不执行正式库迁移、不替换文件、不重启服务：
  - 把补丁打到线上 `index.js` 的副本上；线上模块与抽奖更新装上的版本不一致时提示 `BASELINE_MISMATCH` 并退出。
    打完补丁的结果和包内参考模块只允许有空白差异（以前的补丁把个别调用排成了多行），代码有任何不同都会退出。
  - 在 `/tmp` 的临时运行副本里带服务环境加载两个新模块，检查接口都已挂上、密码哈希与恢复码可用。
  - 在新建的临时数据库里跑包内完整迁移，用真实 PostgreSQL 检查：031 能在已有数据上执行并可重复执行、
    老用户的赠点领取记录已回填、华为登录的 upsert 仍然有效；8 个并发注册同一用户名只成功一个、
    同一个恢复码并发只能用一次、8 个账号并发绑定同一个华为账号只有一个成功且只发一次 300 点、
    密码连续输错会锁定、注销到期后只处理一次且清掉登录方式；每张带 `user_id` 的表都登记在注销清单里。跑完即删库。
- 迁移以事务执行，可以重复执行；执行后检查服务所用角色能读写两张新表。
- 文件替换或健康检查失败时，脚本会恢复原 `index.js`、删掉两个新模块并启动服务，数据库保留。
- 装好后检查：服务健康、`/v1/account/login-methods` 未登录返回 401、用不存在的用户名登录返回 `INVALID_CREDENTIALS`、公网健康检查。

## 回滚

```bash
bash "$stage/rollback.sh" /root/qingye-password-account-backup.XXXXXX
```

回滚恢复原来的 `index.js` 并删掉两个新模块，新接口随之消失。数据库的新列、新表和已注册的用户名账号保留：
旧代码照常工作，只是这些账号暂时登录不了；已申请注销的账号不会再被自动处理，直到重新装上本更新。

## 上线后

- 线上隐私政策需要补上：用户名注册会保存用户名和加密后的密码、注册 IP 保留两天、可以申请注销及注销后删除与保留的数据。
- 查看注销情况：

```sql
SELECT count(*) FILTER (WHERE deletion_requested_at IS NOT NULL AND deleted_at IS NULL) AS pending,
       count(*) FILTER (WHERE deleted_at IS NOT NULL) AS deleted,
       count(*) FILTER (WHERE username IS NOT NULL) AS with_username
FROM app_users;
```

包内文件：`update.sh` 更新、`rollback.sh` 回滚、`common.sh` 公共设置、`patch.mjs` 打补丁、`patch.json` 补丁内容、
`check.mjs` 预检、`password-account-pg-check.mjs` 真实数据库检查、`runtime/` 参考模块与新模块、`src/` 源码、
`migrations/` 本次迁移、`test-migrations/` 临时库用的完整迁移、`RELEASE.json`、`SHA256SUMS`。
