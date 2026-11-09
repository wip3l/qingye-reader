# 同步数据特殊字符清理 · 服务端增量更新包 · 2026-11-09

修复部分账号同步一直提示“服务暂时不可用”。原因是书名、书签、书源等数据里带有 NUL 字符（U+0000）或残缺的 emoji
（不成对的 UTF-16 代理项）。这类内容通常来自编码识别错误的本地文件或书源脚本。PostgreSQL 的 jsonb 不接受这两种字符，
写库时报 22P05 / 22P02，整批同步被回滚并返回 500，App 每次重试都会撞上同一条数据。

更新后，服务端在校验同步请求时会清理数据里的字符串：去掉 NUL，把残缺的代理项换成 U+FFFD，正常的 emoji 保持不变。
普通同步（`/v1/sync/exchange`）和阅读统计同步（`/v1/sync/reading-stats`）都会清理。没有数据库迁移，也不修改环境文件。

适用当前服务器：运行目录 `/www/wwwroot/qingye.icynol.com`，服务 `legado-account.service`，Node `/www/server/nodejs/v22.23.1/bin/node`，数据库 `legado_commerce`。

## 安装

上传 ZIP 到 `/root`，以 root 执行：

```bash
stage=$(mktemp -d /root/qingye-sync-text.XXXXXX)
unzip -q /root/qingye-sync-text-20261109.zip -d "$stage"
bash "$stage/update.sh" --check
bash "$stage/update.sh"
```

看到 `PASS: sync text cleaning installed` 即完成。更新会短暂重启服务。

- `--check` 只做预检，不替换文件、不重启服务：
  - 把补丁打到线上 `sync.js`、`readingStats.js` 的副本上；线上模块和抽奖更新、阅读统计更新装上的版本不一致时，
    提示 `BASELINE_MISMATCH` 并退出，线上文件不动。
  - 在 `/tmp` 的临时运行副本里加载打过补丁的模块，确认两条同步路径都能清理特殊字符。
  - 把清理后的数据交给正式库做一次只读的 jsonb 解析，确认能写入。
- 补丁可以重复执行；已经装过时提示 `Already installed`，不会重启。
- 替换或健康检查失败时，脚本会恢复原模块并启动服务。

## 回滚

```bash
bash "$stage/rollback.sh" /root/qingye-sync-text-backup.XXXXXX
```

回滚恢复原来的 `sync.js` 和 `readingStats.js`。更新期间已经写入的同步数据不受影响。

## 安装后

出问题的用户不需要做任何操作，下次自动同步就会成功。App 里“同步问题”页已有的记录不会自动消失，用户可以手动移除。

包内文件：`update.sh` 更新、`rollback.sh` 回滚、`common.sh` 公共设置、`patch.mjs` 打补丁、`patch.json` 补丁内容、
`check.mjs` 预检、`runtime/` 打完补丁后的参考模块、`src/` 源码、`RELEASE.json`、`SHA256SUMS`。
