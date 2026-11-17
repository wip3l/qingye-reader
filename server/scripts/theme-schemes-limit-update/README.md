# 自定义主题同步上限 · 服务端增量更新包 · 2026-11-17

所有自定义主题的方案设置（配色、文案、素材键等）合成一项同步数据，方案一多就超过普通数据的 64KB 单项上限，
App 里显示“自定义主题过大，已跳过”。图片与主题包走云文件，不受这个上限影响。

更新后 `custom_theme_schemes` 单项上限放宽到 960KB，与终身超级会员单个书源的上限相同（冲突回执会带回整项数据，
单项必须小于 2MB 响应预算的一半）。书源（512KB / 960KB）和其他同步数据（64KB）的上限不变。
没有数据库迁移，不修改环境文件，只改 `sync.js` 中的两处语句。

适用当前服务器：运行目录 `/www/wwwroot/qingye.icynol.com`，服务 `legado-account.service`，Node `/www/server/nodejs/v22.23.1/bin/node`。

## 安装

上传 ZIP 到 `/root`，以 root 执行：

```bash
stage=$(mktemp -d /root/qingye-theme-schemes-limit.XXXXXX)
unzip -q /root/qingye-theme-schemes-limit-20261117.zip -d "$stage"
bash "$stage/update.sh" --check
bash "$stage/update.sh"
```

看到 `PASS: custom theme sync limit raised to 960KB` 即完成。更新会短暂重启服务。

- `--check` 只做预检，不替换文件、不重启服务：把补丁打到线上 `sync.js` 的副本上，
  线上模块与预期不一致时提示 `BASELINE_MISMATCH` 并退出；再在 `/tmp` 的临时运行副本里加载打过补丁的模块，
  核对自定义主题、书源与其他数据各自的上限。
- 补丁只认被改的两条语句、容忍空白差异，可以重复执行；已经装过时提示 `Already installed`，不会重启。
- 旧版 App 无需更新即可上传更大的自定义主题。

## 回滚

使用安装时输出的备份目录：

```bash
bash "$stage/rollback.sh" /root/qingye-theme-schemes-limit-backup.XXXXXX
```

线上 `sync.js` 在本次更新之后又被改过时，回滚脚本会拒绝覆盖。
