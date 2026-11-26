-- 用户名可以修改，30 天一次：记下上次修改的时间。第一次设置用户名不算修改，不写这一列。
-- 表级授权已覆盖新列，无需另行授权。

BEGIN;

ALTER TABLE app_users ADD COLUMN IF NOT EXISTS username_changed_at TIMESTAMPTZ;

COMMIT;
