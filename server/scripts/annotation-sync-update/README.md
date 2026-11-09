# 划线与笔记云同步 · 服务端增量更新包 · 2026-11-10

App 新增的正文划线与笔记用同步类型 `book_annotation` 上传。没更新的服务端不认识这个类型，会拒收（`INVALID_ENTITY_TYPE`）；
App 遇到时会把划线留在本机、其余数据照常同步，每 6 小时再试一次。装上这个更新后，划线就能在设备之间同步。

更新只在 `sync.js` 的同步类型白名单里加一项，没有数据库迁移，也不修改环境文件。
它和“同步数据特殊字符清理”（`qingye-sync-text-20261109`）改的是同一个文件的不同位置，两个包先装哪个都可以。

适用当前服务器：运行目录 `/www/wwwroot/qingye.icynol.com`，服务 `legado-account.service`，Node `/www/server/nodejs/v22.23.1/bin/node`。

## 安装

上传 ZIP 到 `/root`，以 root 执行：

```bash
stage=$(mktemp -d /root/qingye-annotation-sync.XXXXXX)
unzip -q /root/qingye-annotation-sync-20261110.zip -d "$stage"
bash "$stage/update.sh" --check
bash "$stage/update.sh"
```

看到 `PASS: annotation sync installed` 即完成。更新会短暂重启服务。

- `--check` 只做预检，不替换文件、不重启服务：把补丁打到线上 `sync.js` 的副本上，线上模块和已知版本不一致时提示
  `BASELINE_MISMATCH` 并退出；再在 `/tmp` 的临时运行副本里加载，确认划线类型能通过、未知类型仍被拒绝。
- 补丁可以重复执行；已经装过时提示 `Already installed`，不会重启。
- 替换或健康检查失败时，脚本会恢复原模块并启动服务。

## 回滚

```bash
bash "$stage/rollback.sh" /root/qingye-annotation-sync-backup.XXXXXX
```

回滚恢复原来的 `sync.js`。已经上传的划线留在库里；回滚后 App 会再次把划线留在本机不传。

包内文件：`update.sh` 更新、`rollback.sh` 回滚、`common.sh` 公共设置、`patch.mjs` 打补丁、`patch.json` 补丁内容、
`check.mjs` 预检、`runtime/` 打完补丁后的参考模块、`src/` 源码、`RELEASE.json`、`SHA256SUMS`。
