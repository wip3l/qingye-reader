# 华为账号、点数与主题权益服务

该服务是客户端 `entry/src/main/ets/account` 的可信后端。它负责：

- 使用客户端上传的 Authorization Code 向华为换取 Access Token，再从华为账号接口读取 OpenID。
- 每个 OpenID 仅赠送一次 300 点。
- 从数据库主题目录读取上架状态、价格和有效期，并在事务中完成扣点与权益延期。
- 校验 IAP JWS 证书链、调用华为订单状态查询接口，并按订单号幂等充值。
- 返回账号级余额和主题权益，供多个终端同步。

## 运行

1. 创建 PostgreSQL 数据库并按顺序执行全部迁移：

   ```sh
   psql -v ON_ERROR_STOP=1 "$DATABASE_URL" -f migrations/001_account_commerce.sql
   psql -v ON_ERROR_STOP=1 "$DATABASE_URL" -f migrations/002_custom_profile.sql
   psql -v ON_ERROR_STOP=1 "$DATABASE_URL" -f migrations/003_tts_billing.sql
   psql -v ON_ERROR_STOP=1 "$DATABASE_URL" -f migrations/004_tts_usage_allocations.sql
   psql -v ON_ERROR_STOP=1 "$DATABASE_URL" -f migrations/005_data_sync.sql
   psql -v ON_ERROR_STOP=1 "$DATABASE_URL" -f migrations/006_sync_device_metadata.sql
   psql -v ON_ERROR_STOP=1 "$DATABASE_URL" -f migrations/007_sync_performance.sql
   psql -v ON_ERROR_STOP=1 "$DATABASE_URL" -f migrations/008_security_hardening.sql
   psql -v ON_ERROR_STOP=1 "$DATABASE_URL" -f migrations/009_initial_sync_window.sql
   psql -v ON_ERROR_STOP=1 "$DATABASE_URL" -f migrations/010_compact_sync_change_markers.sql
   psql -v ON_ERROR_STOP=1 "$DATABASE_URL" -f migrations/011_theme_catalog.sql
   psql -v ON_ERROR_STOP=1 "$DATABASE_URL" -f migrations/012_qingluan_water_theme.sql
   psql -v ON_ERROR_STOP=1 "$DATABASE_URL" -f migrations/013_cat_pipi_theme.sql
   psql -v ON_ERROR_STOP=1 "$DATABASE_URL" -f migrations/014_anime_themes.sql
   psql -v ON_ERROR_STOP=1 "$DATABASE_URL" -f migrations/015_letterpress_page_theme.sql
   ```

2. 根据 `.env.example` 配置运行环境。所有 Client Secret、IAP 私钥和数据库凭据只能放在服务端密钥管理中，不得写入 HarmonyOS 工程。

3. 安装、构建并启动：

   ```sh
   npm install
   npm run build
   npm start
   ```

4. 将服务部署到带 HTTPS 的华为云函数、云容器或其他可信环境，再把公网地址写入客户端的
   `AccountCommerceConfig.API_BASE_URL`。

## AppGallery Connect 配置

- 开启 Account Kit，并把 OAuth Client ID 写入 `entry/src/main/module.json5`。
- 开通华为商户服务与 IAP Kit。
- 创建以下“消耗型”商品，定价必须保持 1 元 = 10 点：

  | 商品 ID | 价格 | 点数 |
  | --- | ---: | ---: |
  | `legado_points_10` | ¥1 | 10 |
  | `legado_points_60` | ¥6 | 60 |
  | `legado_points_100` | ¥10 | 100 |
  | `legado_points_300` | ¥30 | 300 |
  | `legado_points_500` | ¥50 | 500 |
  | `legado_points_1000` | ¥100 | 1000 |

- 在 IAP 后台生成 Server API 密钥，配置 Key ID、Issuer ID、App ID 和 `.p8` 私钥。
- 从华为官方证书页面下载 Huawei CBG Root CA G2，并通过只读密钥挂载提供给服务。
- 按应用发布站点选择当前 IAP Server API `rootUrl`，不要盲目沿用示例值。
- 上线前必须用 IAP 沙盒覆盖：支付成功、取消支付、服务端超时、客户端确认失败重试、重复订单和退款/撤销。

## 业务规则

- 主题的上架状态、兑换点数和有效天数由 `theme_catalog` 管理；默认是 60 点、365 天。
- 已在有效期内再次获取时，从原到期日按该主题的 `valid_days` 继续延长。
- 充值点可以兑换主题和在线朗读字数包；赠送点只能兑换主题。

## 主题目录运营

新增客户端主题后，不需要修改或重新部署服务端。发布客户端版本前，在数据库登记主题：

```sql
INSERT INTO theme_catalog (theme_id, display_name, price_points, valid_days, enabled)
VALUES ('new-theme', '新主题', 60, 365, TRUE)
ON CONFLICT (theme_id) DO UPDATE SET
  display_name = EXCLUDED.display_name,
  price_points = EXCLUDED.price_points,
  valid_days = EXCLUDED.valid_days,
  enabled = EXCLUDED.enabled,
  updated_at = now();
```

临时下架只更新状态，不要删除记录；已有权益仍然保留：

```sql
UPDATE theme_catalog
SET enabled = FALSE, updated_at = now()
WHERE theme_id = 'new-theme';
```

`GET /v1/themes/catalog` 返回当前已上架的主题和服务端权威价格。新版客户端兑换时会回传刚刚确认的价格与有效期；若运营数据在兑换读取前已变化，服务端返回 `THEME_OFFER_CHANGED` 且不会扣点。未携带报价的旧客户端只允许兑换 60 点、365 天的兼容报价，调整价格前应先确认新版客户端已覆盖目标用户。应用角色只需目录的 `SELECT` 权限；兑换事务使用读取到的同一份报价完成扣点和延期，不授予客户端管理目录的权限。

迁移建议使用服务自身的 `DATABASE_URL` 执行。如果托管环境必须通过 PostgreSQL 管理员执行，`011_theme_catalog.sql` 会从现有 `point_wallets` 表的所有者识别应用角色，并仅授予主题目录的 `SELECT` 权限；主题上下架与改价仍由数据库管理员操作。
- 在线朗读字数包分标准和精品两档，每笔额度有效期 365 天，优先消耗最早到期额度。
- 华为云按每次请求向上取整计费：标准音色以 100 字为单位，精品音色以 50 字为单位；应用字数余额采用相同规则。
- 新账号首次打开在线朗读钱包，获得标准音色 5000 字、精品音色 1000 字，30 天有效。
- 合成请求先预占字数；华为云返回失败时自动退款。30 天明细保留期内，相同
  `requestId` 不重复扣字数；客户端始终应生成新的请求标识。
- 明细保留期内，成功合成的进程缓存过期后，相同 `requestId` 不会再次调用华为云；客户端必须使用新的请求标识重新计费生成。
- 服务端不保存朗读正文和音频，只保存输入哈希、计费记录和音频哈希；音频仅在进程内短时缓存。
- 点数不可转让、不可提现；退款和撤销订单由服务端定期对账并执行冲正。
- 服务端定期复查 IAP 订单。已退款或撤销的订单会冲正仍可用充值点；不足部分记为账号欠款并暂停兑换和在线朗读，后续充值优先抵扣欠款。

## 华为云 SIS 配置

1. 在 `cn-north-4` 开通语音交互服务 SIS 和语音合成。
2. 为服务端 IAM 用户配置调用 SIS 所需的最小权限，创建独立 AK/SK。
3. 在服务器密钥管理中配置：

   - `HUAWEICLOUD_SIS_AK`
   - `HUAWEICLOUD_SIS_SK`
   - `HUAWEICLOUD_SIS_PROJECT_ID`
   - `HUAWEICLOUD_SIS_REGION=cn-north-4`
   - `HUAWEICLOUD_SIS_ENDPOINT=https://sis-ext.cn-north-4.myhuaweicloud.com`
   - `HUAWEICLOUD_SIS_DAILY_BILLING_UNIT_LIMIT=25000`
   - `HUAWEICLOUD_SIS_USER_REQUESTS_PER_MINUTE=30`
   - `HUAWEICLOUD_SIS_MAX_CONCURRENT=6`
   - `HUAWEICLOUD_SIS_MAX_CONCURRENT_PER_USER=2`
   - `HUAWEICLOUD_SIS_QUEUE_LIMIT=20`
   - `HUAWEICLOUD_SIS_CACHE_MAX_BYTES=134217728`

在线朗读使用 SIS 实时语音合成 RTTS：支持的音色直接返回 `word_level` 时间戳，其他音色
根据 PCM 静音边界生成分段时间轴。服务器必须允许出站 WSS/443 访问配置的 SIS endpoint。
旧客户端仍可请求 MP3；携带 `timed: true` 的新版客户端返回 16 kHz PCM 和时间轴。
新客户端同时携带 `transport: binary-v1`，服务端使用二进制封包返回时间轴和 PCM，避免
Base64 的约 33% 体积膨胀；未携带该字段的旧客户端继续接收原 JSON，升级顺序不受限制。

默认并发值针对单机 2 核 2GB：全局最多 6 个 SIS 合成、每用户最多 2 个，额外请求最多
排队 20 个。进程内音频缓存按总量 128MB、单条 8MB、5 分钟 TTL 控制，不再按固定条数
无限放大内存占用。

## 数据同步性能与清理

阅读统计另走 `/v1/sync/reading-stats`，共享账号鉴权和同步设备校验，使用独立游标与记录配额。上线前执行 `migrations/025_reading_statistics.sql`，再发布服务端和客户端。记录以原始 ID 幂等写入，删除标记永久保留以防离线旧记录复活；不得纳入普通回执过期清理。完整口径、隐私策略与验收步骤见 [阅读统计的数据约定](../docs/reading-statistics.md)。

- 客户端按最多 100 项且约 768KB 动态分批，书源单项不得超过 512KB。
- `sync_entities` 是完整数据的唯一存储；`sync_changes` 每个实体只保留一个轻量最新变更
  标记，拉取时关联当前实体，不再重复保存 payload 或累积历史版本。
- 服务端批量读取幂等回执，并在一个 PostgreSQL 事务中完成实体、变更标记和回执写入。
- 客户端声明支持时，`/v1/sync/*` JSON 响应自动使用 Gzip。
- 操作回执默认保留 7 天并每 6 小时小批量清理。
- 已完成的 TTS 请求明细默认保留 30 天后小批量删除；额度账本、点数账本、订单、兑换记录
  和未完成的额度预占不参与清理。
- 服务端同时限制单账号设备数、实体数、实体存储字节、变更标记数和每日写入数；达到上限时返回明确的配额错误。
- 单账号首次开始同步后的 24 小时内可写入 20,000 项，足以完成大型备份初始化；窗口结束后自动恢复每日 5,000 项。实体上限为 20,000，总实体数据上限为 128MB。
- `007_sync_performance.sql` 记录每台设备已确认的同步游标；`010` 将完整历史改为每实体
  一个递增标记，新旧设备仍使用同一版同步协议。

缺少任一必需值时，账号、主题和充值接口仍可运行，`/v1/tts/synthesize` 返回
`TTS_NOT_CONFIGURED`。`/health` 的 `sisConfigured` 可用于发布检查，但不会暴露任何凭据。
每日预算按华为云计费单位统计（标准 100 字或精品 50 字为一个单位），达到上限后暂停新的
合成请求；建议内测期保持默认值，根据实际付费率、华为云账单和峰值用量逐步上调。

发布、监控和回滚检查见 [OPERATIONS.md](./OPERATIONS.md)。
