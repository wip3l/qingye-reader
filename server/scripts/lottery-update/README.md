# 双 11 抽奖发券服务端增量更新包 · 2026-10-30

新增网页抽奖：网页用昵称验证码确认账号，每个账号限抽一次；奖品是只能用于终身会员和终身超级会员的抵扣券，购买时由会员报价自动抵扣。活动期间不用券开通终身超级会员，云空间提升到 5GB。迁移 026 新建活动、奖品、券、抽奖记录、网页会话和云空间赠送表；迁移 027 写入 `double11-2026` 活动和 5 档奖品，**写入时活动处于关闭状态**。

适用当前服务器：运行目录 `/www/wwwroot/qingye.icynol.com`，服务 `legado-account.service`，环境文件 `/etc/legado-account.env`，Node `/www/server/nodejs/v22.23.1/bin/node`，PostgreSQL `/www/server/pgsql/bin/psql`，数据库 `legado_commerce`。

## 安装

上传 ZIP 到 `/root`，以 root 执行（把域名换成抽奖页的实际域名，只写协议和域名）：

```bash
stage=$(mktemp -d /root/qingye-lottery.XXXXXX)
unzip -q /root/qingye-lottery-20261030.zip -d "$stage"
bash "$stage/update.sh" --check --origin https://huodong.example.com
bash "$stage/update.sh" --origin https://huodong.example.com
```

看到 `PASS: lottery update installed (campaign still disabled)` 即完成。更新会短暂重启服务，不需要安装 npm 依赖。

- `--check` 只做预检：
  - 生成备份和候选文件。
  - 在 `/tmp` 的临时副本里加载全部改动模块。
  - 在**新建的临时数据库**里运行真实 PostgreSQL 并发检查，跑完即删。临时库用包内 `test-migrations/` 的完整迁移建立，不读服务器上的 `migrations` 目录（以往更新没有同步那个目录）。

  预检不执行正式库迁移、不改环境文件、不重启服务。
- `--origin` 写入环境文件的 `LOTTERY_PAGE_ORIGIN`。抽奖页的所有提交都只接受这个来源。以后改域名，带新的 `--origin` 再执行一次即可。
- 脚本先校验包内 SHA256，再按精确的编译代码片段修改现有 6 个模块：`cloudFileService.js`、`config.js`、`index.js`、`membershipPolicy.js`、`membershipService.js`、`sync.js`。同时新增 `lotteryService.js`、`lotteryRoutes.js`，模块里的其他现有逻辑保持不变。
- 遇到 `BASELINE_MISMATCH` 时，脚本会在停服务前退出。请保留输出供适配，不要手动覆盖整个模块。不要与其他部署同时执行。
- 迁移以事务执行，可以重复执行。迁移会按现有 `point_wallets` 所属的应用角色授予新表权限。迁移 026 还会把订单表的点数校验改为“实付 + 升级抵扣 + 券 = 标价”，旧代码写入的订单券为 0，同样满足。
- 文件替换或健康检查失败时，脚本会恢复原模块和环境文件并启动服务，数据库保留不动。

## 宝塔与开启活动

1. 在宝塔建站点并开启 HTTPS，域名要有 ICP 备案。把包里的 `web/index.html` 上传到站点的 `/lottery/` 目录。
2. 在站点配置里加反向代理：

   ```nginx
   location /lottery/api/ {
       proxy_pass http://127.0.0.1:8080;
       proxy_set_header Host $host;
       proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
       proxy_set_header X-Forwarded-Proto $scheme;
   }
   ```

   站点和 Node 服务在同一台服务器上，所以用 `127.0.0.1`，现有 `TRUSTED_PROXIES` 默认值已包含它。
3. 打开 `https://<抽奖页域名>/lottery/`，确认能看到奖品表。
4. 开启活动：

   ```bash
   runuser -u postgres -- /www/server/pgsql/bin/psql -X -w -h /tmp -d legado_commerce \
     -c "UPDATE lottery_campaigns SET enabled = true WHERE id = 'double11-2026';"
   ```

   改为 `false` 即停止抽奖，已发的券不受影响。

## 回滚

使用更新时打印的实际备份路径：

```bash
bash "$stage/rollback.sh" /root/qingye-lottery-backup.XXXXXX
```

- 回滚会恢复 6 个原模块和原环境文件，删除新增的 2 个模块。
- 回滚前会核对文件是否仍是本次安装的版本，拒绝覆盖后续改动。
- **抽奖相关的表、已发的券和 5GB 赠送记录都保留**。旧代码不读取这些表：回滚后券不会再自动抵扣，云空间按 1GB 计算。
- 不要用只运行过 `--check` 生成的备份执行回滚。

## 验证范围

- **本地**：服务端完整测试 117 项通过，覆盖抽奖、验证码、自动用券、5GB 赠送、来源校验与 Cookie，以及旧报价兼容。生成更新包时还校验了三点：补丁能精确还原测试版本、重复应用不变、不改动无关代码。
- **部署脚本会验证**：
  - 候选模块在服务环境下能加载。
  - 真实 PostgreSQL 并发（同一账号并发抽奖只发一张券、限量奖品不超发、同一张券不会被两单使用、改选择与付款并发只成一个、5GB 只赠送一次）。
  - 本地与公网健康状态、抽奖状态接口、无来源的抽奖请求被拒绝（403）、服务进程稳定。
- **需要你在上线后自己验证**：网页验证、抽奖、在 App 里报价时扣点变化。本包尚未在线上部署过。

包内文件：

- `update.sh` 更新，`rollback.sh` 回滚，`common.sh` 公共设置
- `patch.mjs` / `patch.json` 增量补丁
- `check.mjs` 预检，`lottery-pg-concurrency.mjs` 真实库并发检查
- `runtime/` 编译模块，`src/` 对应源码，`migrations/` 本次迁移，`test-migrations/` 临时库用的完整迁移，`web/index.html` 抽奖页
- `RELEASE.json` 源码提交，`SHA256SUMS` 包内校验表

包内不含环境文件、数据库转储或凭据。
