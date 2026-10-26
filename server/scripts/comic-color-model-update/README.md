# 漫画着色模型按需下载

先更新服务端和 OBS，再分发新版 App。更新包包含三份模型（176.25 MiB）、签名下载接口和上传工具。模型放在现有私有 OBS 桶的 `qingye/ai/comic-colorizer/<sha256>/<file>`，无需公开桶权限；App 不持有 AK/SK。模型流量不计入用户云文件下载额度，仍产生正常的 OBS 流量费用。

适用部署：`/www/wwwroot/qingye.icynol.com`，systemd `legado-account.service`，Node `/www/server/nodejs/v22.23.1/bin/node`。模型凭据仅从该运行进程的 OBS 环境变量读取，不打印、不保存。

将更新包上传至服务器后，以 root 执行：

```bash
stage=$(mktemp -d /root/qingye-comic-color-models.XXXXXX)
unzip -q /root/qingye-comic-color-models.zip -d "$stage"
bash "$stage/scripts/comic-color-model-update/update.sh" --check
bash "$stage/scripts/comic-color-model-update/update.sh"
```

`--check` 校验本地模型与补丁兼容性，不上传、不重启。正式执行先上传模型并逐份下载核对 SHA-256，再增量修改 `index.js`、安装两个新模块并短暂重启服务。不需要 SQL、依赖安装或环境变量变更。若 OBS 权限限制在原云文件前缀，需要为上述新前缀允许 PutObject/GetObject/GetObjectMetadata；HEAD 403 不再直接中断：脚本先尝试 GET，若无法读取再携带 x-obs-forbid-overwrite 发起上传，最后回读校验。PUT/GET 的真实权限拒绝仍会停止，不修改权限。禁止覆盖头在启用或暂停多版本控制的桶上不生效；对象键按内容哈希固定，上传内容必须与本地固定哈希一致。

更新失败会尝试恢复服务端文件。已上传的不可变模型保留在 OBS，重试会验证并复用。服务器备份目录会打印。手动回滚前停止服务，恢复该目录的 `index.js` 和原有两个模型模块；标记为 `.absent` 的模块仅在确认仍为本次版本时删除，然后启动服务。回滚后不要继续分发依赖新接口的 App。

本地独立上传（需事先构建 server 并在当前进程配置 OBS 环境变量）：

```bash
node server/scripts/publish-comic-color-models.mjs harmony-book-ai-engine/models/comic-colorizer --upload
```

不传 `--upload` 只校验模型。所有 CLI 网络请求默认直连。

验收：新安装 App 开启彩色阅读或单页着色时，应先显示模型体积及 Wi-Fi 提示；取消后不开启、不下载。确认后显示进度，校验通过才开启；断网或取消后可重试，完整模型复用；下载后可离线使用。旧版已解包的模型校验通过后沿用。升级后若缺少模型，重新开启彩色阅读即可下载。

本地自动检查不替代实际 OBS 上传、服务器发布及真机下载验收。

## 上传失败诊断

日志输出固定模型文件名、HEAD/PUT/GET 阶段、HTTP 状态与允许列表中的 OBS/网络错误码；不输出签名 URL、AK/SK 或完整错误响应。`HEAD 403` 可能仅表示对象尚不存在且缺少 ListBucket，不应直接判断为凭据错误。若最终为 `PUT | HTTP 403 AccessDenied`，检查该账号对新模型前缀的写权限；`GET verification | HTTP 403 AccessDenied` 检查读权限；签名或时钟错误按对应错误码处理。
