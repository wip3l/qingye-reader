# 云端本地书籍分类修复 · 2026-10-25

新增 `meta.mediaCategory`（`novel` / `comic`），以及受登录与限流保护的 `POST /v1/cloud-files/:id/metadata` 接口。
旧云文件可由保留本地书籍的新客户端补齐分类，未下载设备在后续同步时刷新书架分类。

## 更新

适用现有部署：运行目录 `/www/wwwroot/qingye.icynol.com`，systemd 服务 `legado-account.service`，Node `/www/server/nodejs/v22.23.1/bin/node`。
上传 `qingye-cloud-book-category-20261025.zip` 至服务器 `/root`，以 root 执行：

```bash
stage=$(mktemp -d /root/qingye-cloud-book-category.XXXXXX)
unzip -q /root/qingye-cloud-book-category-20261025.zip -d "$stage"
bash "$stage/update.sh"
```

看到 `PASS: cloud book category update installed` 即成功。更新会短暂重启服务。
只想先检查兼容性可执行 `bash "$stage/update.sh" --check`，该模式只生成备份和候选文件，不替换运行文件、不重启服务。

脚本校验包内 SHA256，按精确代码片段对当前 `cloudFileService.js`、`cloudFileRoutes.js` 生成增量补丁，保留模块的其他现有逻辑。
遇到 `BASELINE_MISMATCH` 会在停止服务前退出，请保留输出供适配，不要强行覆盖。
重复执行已安装补丁不会重启服务。包内 `runtime/` 是当前源码编译出的完整模块供核对，实际更新由 `patch.mjs` 处理当前服务器文件；不要单独覆盖它们。

不需要安装依赖或执行 SQL，不修改配置、密钥、会员和额度数据。网络健康检查显式直连。
更新前备份路径为 `/root/qingye-cloud-book-category-backup.XXXXXX`，由脚本打印。
替换或健康检查失败时，脚本会尝试恢复这两个模块并启动原服务。

## 回滚

使用更新时打印的实际备份路径：

```bash
bash "$stage/rollback.sh" /root/qingye-cloud-book-category-backup.XXXXXX
```

回滚前会核对备份校验和及当前运行文件，拒绝覆盖后续版本的修改。

## 生效条件与验证

先更新服务端，再更新客户端。旧客户端仍可使用原有上传和下载功能；分类显示修复需要新版客户端。
已经上传的漫画，需要至少一台保留本地文件且已识别漫画的设备用新版客户端同步一次，其他设备随后同步即可刷新。
若所有设备只有未下载占位项，旧元数据无法凭 EPUB 扩展名判断漫画，需在一台设备下载识别后再同步补齐。

服务端构建和云文件测试通过。更新包预检在内存中运行候选模块的真实校验、补齐及路由代码，不连接数据库或对象存储。
脚本已在本地临时目录配合模拟服务验证预检、安装、重复执行、手动回滚、启动失败自动恢复、版本不兼容拒绝和后续版本保护。
部署脚本验证本地和公网 `/health`、新接口拒绝未登录请求、服务进程稳定性；账号内的跨设备实际显示需在更新客户端后确认。

文件：`update.sh` 更新，`rollback.sh` 回滚，`patch.mjs` / `patch.json` 增量补丁，`check.mjs` 预检，`runtime/` 编译模块，`src/` 对应 TypeScript 源码，`SHA256SUMS` 包内校验表。
