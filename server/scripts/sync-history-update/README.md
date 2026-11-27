# 同步设置历史 · 服务端增量更新包 · 2026-11-26

新装机首次同步误选“本地为主”时，默认设置会覆盖云端，其他设备同步后也跟着丢失。本更新让服务端在设置类数据被强制替换时
留一份旧版本，新版 App 的“设置历史”页可以列出并恢复。**要先装好本更新再发布 App**，否则设置历史页读不到云端记录
（本机记录不受影响），恢复云端记录会报 404。旧版 App 不受影响。

- 迁移 037：新表 `sync_entity_history`，并给服务所用角色授权。
- 记录规则：只在设置类数据（阅读设置、替换规则、主题设置、自定义主题、显示模式、书架布局、搜索设置）
  被“本地为主”首次同步强制替换（`local_first`），或被“恢复设置历史”替换（`restore`）时记录被替换的版本；内容相同不记。
  正常同步里设备修改自己看到过的版本不记录。
- 保留：每项最近 10 份、90 天，每个账号合计不超过 3MB，写入时在同一事务里清理。
- 新接口：`GET /v1/sync/history`（列表，只有元数据，同一设备同一原因两分钟内的替换合成一组）、
  `POST /v1/sync/history/restore`（`deviceId` + `historyIds`，把选中版本写回为新版本，所有设备照常同步拿到）。都需登录。
- `accountAuth.js`：账号注销到期时连同 `sync_entity_history` 一起清掉。
- 按编译块补丁替换 `sync.js`、`index.js`、`accountAuth.js`，不新增文件，不修改环境文件。

适用当前服务器：运行目录 `/www/wwwroot/qingye.icynol.com`，服务 `legado-account.service`，
Node `/www/server/nodejs/v22.23.1/bin/node`，数据库 `legado_commerce`，环境文件 `/etc/legado-account.env`。
线上 `sync.js` 应是 `qingye-theme-schemes-limit-20261117` 装上的版本，`index.js` 是 `qingye-recharge-20261123`，
`accountAuth.js` 是 `qingye-username-change-20261125`。

## 安装

上传 ZIP 到 `/root`，以 root 执行：

```bash
stage=$(mktemp -d /root/qingye-sync-history.XXXXXX)
unzip -q /root/qingye-sync-history-20261126.zip -d "$stage"
bash "$stage/update.sh" --check
bash "$stage/update.sh"
```

看到 `PASS: sync settings history installed` 即完成。更新会短暂重启服务。

- `--check` 只做预检，不执行正式库迁移、不替换文件、不重启服务：
  - 把补丁打到线上三个模块的副本上；线上模块与上述版本不一致时提示 `BASELINE_MISMATCH` 并退出。
    打完补丁的结果和包内参考模块只允许有空白差异，代码有任何不同都会退出。
  - 在 `/tmp` 的临时运行副本里带服务环境加载新模块，检查导出、保留上限、注销清单和两个新路由都已就位。
  - 在新建的临时数据库里跑包内完整迁移，用真实 PostgreSQL 检查：037 能在已有同步数据上执行并可重复执行；
    只有强制替换和恢复才记录、内容相同不记；列表分组与恢复；外账号、过期 ID、未同步过的设备都被拒绝且不写入；
    8 个并发恢复同一版本只生效一次；8 台设备同时强制覆盖各自留下被替换的版本；每项 10 份、每账号 3MB 的清理；
    每张带 `user_id` 的表都登记在注销清单里。跑完即删库。
- 迁移以事务执行，可以重复执行；执行后检查服务所用角色能读写、删除新表。
- 文件替换或健康检查失败时，脚本会恢复原来的三个文件并启动服务，数据库保留。
- 装好后检查：服务健康，两个新接口和同步接口未登录都返回 401，公网健康检查。

## 回滚

```bash
bash "$stage/rollback.sh" /root/qingye-sync-history-backup.XXXXXX
```

回滚恢复原来的三个文件，新接口随之消失，强制替换也不再记录。`sync_entity_history` 表和已有记录保留，旧代码不使用它。

## 上线后

查看记录量：

```sql
SELECT count(*) AS rows, count(DISTINCT user_id) AS users,
       pg_size_pretty(COALESCE(sum(octet_length(payload::text)), 0)) AS payload
FROM sync_entity_history;
```

包内文件：`update.sh` 更新、`rollback.sh` 回滚、`common.sh` 公共设置、`patch.mjs` 打补丁、`patch.json` 补丁内容、
`check.mjs` 预检、`sync-history-pg-check.mjs` 真实数据库检查、`runtime/` 参考模块、`src/` 源码、
`migrations/` 本次迁移、`test-migrations/` 临时库用的完整迁移、`RELEASE.json`、`SHA256SUMS`。
