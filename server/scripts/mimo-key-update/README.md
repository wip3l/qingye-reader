# 终身会员一键填充 MiMo 密钥 · 服务端增量更新包 · 2026-11-01

App 的「MiMo 朗读」设置页新增「一键填充」：终身会员（终身会员、终身超级会员，且没有退款欠款）点击后，App 从服务端取回运营方的
MiMo API Key，填进密钥输入框；会员仍要勾选知情同意、测试通过后才保存到本机。

- 新接口 `POST /v1/membership/mimo-key`：需要登录；不是终身会员返回 403 `LIFETIME_MEMBERSHIP_REQUIRED`，没有存密钥返回 503
  `SHARED_KEY_UNAVAILABLE`；响应带 `Cache-Control: no-store`。
- 迁移 029 新建两张表：`shared_provider_keys`（存密钥）和 `shared_provider_key_grants`（每个账号的领取次数与时间）。
- **密钥会原样下发到会员手机**，之后会员直连小米，用量全部计入你的 MiMo 账户，服务端不能限额，也收不回已经填进手机的密钥。

适用当前服务器：运行目录 `/www/wwwroot/qingye.icynol.com`，服务 `legado-account.service`，Node `/www/server/nodejs/v22.23.1/bin/node`，数据库 `legado_commerce`。

## 安装

上传 ZIP 到 `/root`，以 root 执行：

```bash
stage=$(mktemp -d /root/qingye-mimo-key.XXXXXX)
unzip -q /root/qingye-mimo-shared-key-20261101.zip -d "$stage"
bash "$stage/update.sh" --check
bash "$stage/update.sh"
```

看到 `PASS: lifetime MiMo key route installed` 即完成。更新会短暂重启服务，不修改环境文件。

- `--check` 只做预检，不执行正式库迁移、不替换文件、不重启服务：
  - 在 `/tmp` 的临时运行副本里，用线上的 `membershipService.js` 等模块加载新的 `membershipRoutes.js`，检查接口。
  - 在新建的临时数据库里跑包内完整迁移，用真实接口检查：终身会员能取到密钥、8 个并发请求只留一条领取记录且次数准确、
    年度会员/非会员/有欠款的终身会员被拒绝、停用后不再下发。跑完即删库。
- `membershipRoutes.js` 必须与超级会员主题更新装上的版本内容一致（忽略换行符）才会被替换，否则提示 `BASELINE_MISMATCH`，并在停服务前退出。
- 迁移以事务执行，可以重复执行。
- 文件替换或健康检查失败时，脚本会恢复原模块并启动服务，数据库保留。

## 写入密钥（安装后必做）

建议用按量付费的 `sk-` 密钥。以 root 执行，把 `sk-...` 换成你的密钥：

```bash
runuser -u postgres -- /www/server/pgsql/bin/psql -X -w -h /tmp -d legado_commerce -v ON_ERROR_STOP=1 -c \
  "INSERT INTO shared_provider_keys(provider, api_key) VALUES ('mimo', 'sk-...')
   ON CONFLICT (provider) DO UPDATE SET api_key = EXCLUDED.api_key, enabled = true, updated_at = now();"
```

这条命令会把密钥留在 shell 历史里，执行后可以用 `history -d` 删掉对应记录，或改用交互式 psql 输入。更换密钥用同一条命令。

停止下发：

```sql
UPDATE shared_provider_keys SET enabled = false WHERE provider = 'mimo';
```

已经填进手机的密钥仍能继续用。怀疑泄露时，到小米 MiMo 控制台删除该密钥、换新的，再用上面的命令写入新密钥。

查看领取记录：

```sql
SELECT user_id, first_granted_at, last_granted_at, grant_count
FROM shared_provider_key_grants WHERE provider = 'mimo' ORDER BY last_granted_at DESC;
```

## 回滚

```bash
bash "$stage/rollback.sh" /root/qingye-mimo-key-backup.XXXXXX
```

回滚恢复原来的 `membershipRoutes.js`，新接口随之消失；两张新表和领取记录保留，不影响其他功能。

## 验证范围

- **本地**：服务端完整测试通过。新增测试覆盖：只给终身会员下发、拒绝年度会员/欠款/未登录、没存密钥时的提示、
  每次下发都记录；另有一项在嵌入式 PostgreSQL 上跑完整迁移和真实接口。
- **部署脚本会验证**：预检里的接口检查与真实 PostgreSQL 检查（见上），安装后服务健康、新接口对未登录请求返回 401、公网健康检查。

包内文件：`update.sh` 更新、`rollback.sh` 回滚、`common.sh` 公共设置、`check.mjs` 预检、`BASELINE` 基线校验值、
`runtime/` 编译模块、`src/` 源码、`migrations/` 本次迁移、`test-migrations/` 临时库用的完整迁移、
`mimo-key-pg-check.mjs` 真实数据库检查、`RELEASE.json`、`SHA256SUMS`。
