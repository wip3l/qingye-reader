-- 设置类同步数据被别的设备、“本地为主”首次同步或恢复操作替换时，留一份旧版本，
-- 用户可以在“设置历史”里找回。同一设备连续修改自己的设置不记录。
-- 每项保留最近 10 份、90 天，每个账号合计不超过 3MB（由服务代码在写入时清理）。
-- 同一次同步替换的行 replaced_at 相同（事务时间），客户端按 (replaced_at, replaced_by_device) 分组显示。

BEGIN;

CREATE TABLE IF NOT EXISTS sync_entity_history (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  revision BIGINT NOT NULL CHECK (revision > 0),
  -- 被替换时是删除状态则为 NULL。
  payload JSONB,
  written_by_device UUID,
  written_at TIMESTAMPTZ NOT NULL,
  replaced_by_device UUID NOT NULL,
  replaced_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- other_device：别的设备同步替换；local_first：“本地为主”强制替换；restore：恢复设置历史。
  reason TEXT NOT NULL CHECK (reason IN ('other_device', 'local_first', 'restore'))
);

CREATE INDEX IF NOT EXISTS sync_entity_history_user_replaced_idx
  ON sync_entity_history(user_id, replaced_at DESC);
CREATE INDEX IF NOT EXISTS sync_entity_history_entity_idx
  ON sync_entity_history(user_id, entity_type, entity_id, replaced_at DESC);

DO $$
DECLARE application_role NAME;
BEGIN
  SELECT tableowner INTO application_role FROM pg_tables
    WHERE schemaname='public' AND tablename='point_wallets';
  IF application_role IS NOT NULL AND application_role <> current_user THEN
    EXECUTE format('GRANT SELECT, INSERT, DELETE ON TABLE sync_entity_history TO %I', application_role);
    EXECUTE format('GRANT USAGE, SELECT ON SEQUENCE sync_entity_history_id_seq TO %I', application_role);
  END IF;
END
$$;

COMMIT;
