# 自定义主题云同步 · 服务端增量更新包 · 2026-11-16

终身超级会员的自定义主题（主题包素材、方案的启动封面与预览图）改为通过云文件同步。
**App 的这个版本要在本更新装好之后再发布**；没装时 App 上传主题会被拒绝，书籍和字体不受影响。

- 云文件新增类型 `THEME`，附加信息新增 `packageId`（主题包）与 `schemeId`（方案图片），二者必须且只能有一个。
- 云文件列表多返回 `createdAt`，设备据此只保留同一主题最新上传的一份。
- 迁移 032：`cloud_files` 与 `cloud_file_tombstones` 的类型检查加上 `THEME`。事务执行、可重复执行，旧代码照常工作。
- 主题文件与书籍、字体共用 1GB 存储空间和每月 1GB 下载额度。

适用当前服务器：运行目录 `/www/wwwroot/qingye.icynol.com`，服务 `legado-account.service`，
Node `/www/server/nodejs/v22.23.1/bin/node`，数据库 `legado_commerce`。不修改环境文件。

## 安装

上传 ZIP 到 `/root`，以 root 执行：

```bash
stage=$(mktemp -d /root/qingye-cloud-theme.XXXXXX)
unzip -q /root/qingye-cloud-theme-20261116.zip -d "$stage"
bash "$stage/update.sh" --check
bash "$stage/update.sh"
```

看到 `PASS: custom theme cloud files installed` 即完成。更新会短暂重启服务。

- `--check` 只做预检：把五处改动打到线上 `cloudFileService.js` 的副本上。线上文件是历次补丁叠出来的，和任何一次干净构建都不完全相同，
  所以每处改动只认它要改的那一句、忽略空白差异，已有的跳过；找不到时提示 `BASELINE_MISMATCH` 并写明是哪一处，然后退出。
  打好的副本在内存里实际运行，检查主题标识规则、上传准备与列表；不执行迁移、不替换文件、不重启服务。
- 正式安装先执行迁移并核对两个类型检查都含 `THEME`，再替换模块、重启服务。
- 文件替换或健康检查失败时，脚本会恢复原 `cloudFileService.js` 并启动服务，数据库保留。
- 装好后检查：服务健康、`/v1/cloud-files/summary` 未登录返回 401、公网健康检查。

## 回滚

```bash
bash "$stage/rollback.sh" /root/qingye-cloud-theme-backup.XXXXXX
```

回滚恢复原来的 `cloudFileService.js`。迁移放宽的类型检查和已上传的主题文件保留：旧代码不会再接收新的主题上传，
已有主题文件照常占用空间、可在 App 云空间页删除。

包内文件：`update.sh` 更新、`rollback.sh` 回滚、`common.sh` 公共设置、`patch.mjs` 打补丁（含五处改动）、
`check.mjs` 预检、`runtime/` 打在抽奖版本上的参考结果（只供核对）、`src/` 源码、`migrations/` 本次迁移、`RELEASE.json`、`SHA256SUMS`。
