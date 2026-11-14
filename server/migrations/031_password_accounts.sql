BEGIN;

-- 用户名+密码账号：华为账号不再是唯一登录方式，可以只有用户名密码，之后再绑定华为账号。
ALTER TABLE app_users ALTER COLUMN huawei_open_id DROP NOT NULL;
ALTER TABLE app_users
  ADD COLUMN IF NOT EXISTS username TEXT,
  ADD COLUMN IF NOT EXISTS username_key TEXT,
  ADD COLUMN IF NOT EXISTS password_hash TEXT,
  ADD COLUMN IF NOT EXISTS password_changed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS failed_login_count INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS login_locked_until TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS registration_ip INET,
  ADD COLUMN IF NOT EXISTS deletion_requested_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

CREATE UNIQUE INDEX IF NOT EXISTS app_users_username_key_idx
  ON app_users(username_key) WHERE username_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS app_users_registration_ip_idx
  ON app_users(registration_ip, created_at) WHERE registration_ip IS NOT NULL;
CREATE INDEX IF NOT EXISTS app_users_deletion_due_idx
  ON app_users(deletion_requested_at) WHERE deletion_requested_at IS NOT NULL AND deleted_at IS NULL;

-- 一次性恢复码，只存 HMAC。
CREATE TABLE IF NOT EXISTS account_recovery_codes (
  user_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
  code_hash TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  used_at TIMESTAMPTZ,
  PRIMARY KEY (user_id, code_hash)
);

-- 新用户赠点按华为账号记：同一个华为账号换绑到别的账号、或注销后重新登录，都不会再领一次。
-- 只存 openId 的 SHA-256，账号注销后这里不留可直接对应到华为账号的标识。
CREATE TABLE IF NOT EXISTS huawei_welcome_claims (
  huawei_subject_hash TEXT PRIMARY KEY,
  user_id UUID REFERENCES app_users(id) ON DELETE SET NULL,
  claimed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO huawei_welcome_claims (huawei_subject_hash, user_id, claimed_at)
SELECT encode(sha256(convert_to(u.huawei_open_id, 'UTF8')), 'hex'), u.id, MIN(l.created_at)
FROM app_users u
JOIN point_ledger l ON l.user_id = u.id AND l.reason = 'WELCOME_GRANT'
WHERE u.huawei_open_id IS NOT NULL
GROUP BY u.huawei_open_id, u.id
ON CONFLICT (huawei_subject_hash) DO NOTHING;

DO $$
DECLARE application_role NAME;
BEGIN
  SELECT tableowner INTO application_role FROM pg_tables
    WHERE schemaname='public' AND tablename='point_wallets';
  IF application_role IS NOT NULL AND application_role <> current_user THEN
    EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE account_recovery_codes TO %I', application_role);
    EXECUTE format('GRANT SELECT, INSERT, UPDATE ON TABLE huawei_welcome_claims TO %I', application_role);
  END IF;
END
$$;

COMMIT;
