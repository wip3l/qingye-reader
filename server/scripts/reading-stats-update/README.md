# 阅读统计同步服务端增量更新包 · 2026-10-27

增加受登录与限流保护的 `POST /v1/sync/reading-stats` 接口，支持按账号同步阅读片段、设备归属、书名快照和删除标记。重复上传不重复计数，删除记录不会被离线旧设备复活。数据库迁移 025 新建独立统计表，不占用书架同步额度。

适用当前服务器：运行目录 `/www/wwwroot/qingye.icynol.com`，服务 `legado-account.service`，Node `/www/server/nodejs/v22.23.1/bin/node`，PostgreSQL `/www/server/pgsql/bin/psql`，数据库 `legado_commerce`。

## 安装

上传 ZIP 到 `/root`，以 root 执行：

```bash
stage=$(mktemp -d /root/qingye-reading-stats.XXXXXX)
unzip -q /root/qingye-reading-stats-20261027.zip -d "$stage"
bash "$stage/update.sh" --check
bash "$stage/update.sh"
```

看到 `PASS: reading statistics update installed` 即完成。已安装时会提示 `Already installed`。更新需要短暂重启服务，无需安装 npm 依赖或修改环境变量。联网健康检查显式直连。

`--check` 只读取数据库先决条件、生成本地备份与候选文件，不执行迁移、不替换运行文件、不重启。脚本校验包内 SHA256，增量修改现有 `index.js`，添加 `readingStats.js`，保留其他服务端功能。遇到 `BASELINE_MISMATCH` 或文件不匹配时退出，请保留输出供适配，不要手动覆盖整个 index.js。不要与其他部署同时执行。

更新前打印 `/root/qingye-reading-stats-backup.XXXXXX` 备份路径。文件替换或健康检查失败会尝试恢复原代码。迁移以事务运行，新表会保留；不会主动删除数据库数据。迁移按现有 `point_wallets` 所属应用角色授予统计表和序列权限，与当前部署约定一致。

## 回滚

使用更新时打印的实际备份路径：

```bash
bash "$stage/rollback.sh" /root/qingye-reading-stats-backup.XXXXXX
```

回滚校验原文件与已安装候选文件，拒绝覆盖后续修改。恢复原 index.js；原先不存在的 readingStats.js 会移除。**统计表和已同步数据保留**，便于再次更新。不要用仅运行 `--check` 生成的备份执行回滚。

## 客户端与验证

先更新服务端，再使用包含阅读统计同步的新客户端。旧客户端的现有同步接口继续工作。设备身份持久化修复属于客户端，本服务端包不会合并或删除历史重复设备；卸载重装后也不会按设备型号强行合并。

本地完整服务端测试通过（105 项），包含 PostgreSQL 兼容引擎上的统计迁移、去重、删除、分页、权限与设备版本更新测试。部署脚本验证运行文件语法、模块校验逻辑、接口注册、本地与公网健康状态、新接口未登录返回 401、服务进程稳定性。真实账号跨设备同步需在部署后配合新客户端验证；本包尚未部署到线上。

包内 `runtime/` 为编译模块，`src/` 为对应源码，`migrations/025_reading_statistics.sql` 为迁移；`RELEASE.json` 记录源码提交和测试结果，`SHA256SUMS` 为包内校验清单。包不含环境文件、数据库转储或凭据。
