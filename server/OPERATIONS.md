# 在线朗读发布与运营检查

## 首次发布

1. 备份 PostgreSQL，并在预发布库按顺序执行全部迁移；至少确认 `005` 至 `010` 已成功
   执行。`008` 会使旧的无 `jti` 会话失效，发布后用户需要重新登录一次。
2. 执行 `npm ci && npm test`。
3. 在服务端密钥管理配置 `.env.example` 中的 SIS 变量。AK/SK 不得进入镜像、日志或客户端。
4. 2 核 2GB 单机先保持每日 25000 个计费单位、单用户每分钟 30 次、全局并发 6、
   单用户并发 2、缓存 128MB 的默认保护值。
5. 发布一个实例，确认 `/health` 返回 `ok: true` 和 `sisConfigured: true`。
6. 确认服务器可以通过 443 端口连接
   `wss://sis-ext.<region>.myhuaweicloud.com/v1/<project_id>/rtts`。反向代理只需要承载
   App 到本服务的 HTTPS，请勿把 SIS AK/SK 下发给客户端。
7. 使用测试账号验证：首次试用到账、标准/精品各合成一次、失败退款、重复请求不重复扣费。
   新版客户端请求体会携带 `timed: true` 和 `transport: binary-v1`，服务端应返回
   `application/vnd.qingye.tts-timed`；旧客户端仍应收到 JSON Base64 响应。
8. 再逐步扩容。多实例共享 PostgreSQL，因此额度预占、幂等和每日预算仍保持一致。
9. 按当前华为 IAP 站点文档确认 `HUAWEI_IAP_DELIVERABLE_STATUSES`，并用沙盒验证成功、取消、退款和撤销状态；配置错误会安全地拒绝充值，而不会放行未知状态。

## 必测场景

- 49、50、51、99、100、101、499、500 个字符的合成与扣费。
- Emoji、组合字符、换行、中英文和标点。
- 相同 `requestId` 重发；相同 `requestId` 携带不同正文。
- 客户端超时后重试、SIS 4xx/5xx、服务进程在预占后退出。
- 字数不足、分钟限流、每日预算耗尽。
- 两台设备同时兑换字数包和同时朗读。
- 套餐临近过期时的优先扣减与失败退款。
- 支持逐字时间戳的音色返回 `WORD`；其他音色返回 `SILENCE_ALIGNED`，两种模式都应能
  连续播放、高亮和自动翻页。

## 监控建议

至少每 5 分钟采集以下指标并告警：

- `tts_usage` 各状态数量；`RESERVED` 超过 5 分钟应为 0。
- `REFUNDED / (SUCCEEDED + REFUNDED)`：15 分钟窗口超过 5% 告警。
- 标准、精品每日计费单位与环境变量上限的比例：达到 70%、90% 告警。
- `TTS_RATE_LIMITED`、`TTS_DAILY_BUDGET_EXHAUSTED` 次数。
- `TTS_SERVER_BUSY` 次数，以及进程 RSS、堆外 Buffer 内存和排队超时。
- 华为云 SIS 实际账单与 `tts_usage` 成功用量的日对账差异。
- PostgreSQL 事务错误率和接口 P95/P99 延迟。
- IAP `order_status`、`reversed_at`、`debt_points`，以及 `account_debts` 非零账号。
- `sync_changes`、`sync_entities`、`sync_operation_receipts` 的行数和磁盘占用。

同步标记不变量核对 SQL：

```sql
SELECT
  (SELECT count(*) FROM sync_entities) AS entities,
  (SELECT count(*) FROM sync_changes) AS markers,
  (SELECT count(*)
   FROM sync_entities entity
   LEFT JOIN sync_changes marker
     USING (user_id, entity_type, entity_id)
   WHERE marker.sequence_id IS NULL) AS missing_markers;
```

`010` 迁移完成后，`entities` 应等于 `markers`，`missing_markers` 必须为 0。

日用量核对 SQL：

```sql
SELECT
  tier,
  status,
  COUNT(*) AS requests,
  SUM(raw_chars) AS raw_chars,
  SUM(charged_chars) AS charged_chars,
  SUM(charged_chars / CASE WHEN tier = 'PREMIUM' THEN 50 ELSE 100 END) AS billing_units
FROM tts_usage
WHERE created_at >= date_trunc('day', now())
GROUP BY tier, status
ORDER BY tier, status;
```

滞留预占核对 SQL：

```sql
SELECT id, user_id, request_id, tier, charged_chars, created_at
FROM tts_usage
WHERE status = 'RESERVED'
  AND created_at < now() - interval '5 minutes'
ORDER BY created_at;
```

## 紧急止损

无需下架客户端即可止损：

1. 将 `HUAWEICLOUD_SIS_DAILY_BILLING_UNIT_LIMIT` 调到一个已达到的低值并滚动重启服务。
2. 保留目录、钱包和兑换接口；新合成会返回 `TTS_DAILY_BUDGET_EXHAUSTED`。
3. 检查华为云账单、异常账号和 `tts_usage`，不要删除账本记录。
4. 故障解除后逐步恢复每日预算。

如果必须完全停用 SIS，移除运行环境中的 SIS AK/SK 并滚动重启；合成接口会返回
`TTS_NOT_CONFIGURED`，账号、主题、充值和字数余额接口不受影响。

## 终身会员共享 MiMo 密钥

终身会员（`LIFETIME`、`SUPER_LIFETIME`，且没有退款欠款）可以在 App 的「MiMo 朗读」页一键填入运营方的
MiMo API Key（`POST /v1/membership/mimo-key`，迁移 `029_shared_provider_keys.sql`）。密钥会原样下发到
会员手机，调用直连小米、全部计入运营方的 MiMo 账户，服务端无法限额。

设置或更换密钥（建议用按量付费的 `sk-` 密钥）：

```sql
INSERT INTO shared_provider_keys(provider, api_key) VALUES ('mimo', 'sk-...')
ON CONFLICT (provider) DO UPDATE SET api_key = EXCLUDED.api_key, enabled = true, updated_at = now();
```

停止下发：`UPDATE shared_provider_keys SET enabled = false WHERE provider = 'mimo';`。已经填入的手机仍能继续使用旧密钥，
怀疑泄露时要到小米控制台删除该密钥并换新的。查看领取记录：

```sql
SELECT user_id, first_granted_at, last_granted_at, grant_count
FROM shared_provider_key_grants WHERE provider = 'mimo' ORDER BY last_granted_at DESC;
```
