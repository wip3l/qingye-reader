-- Second exclusive theme for super lifetime members: claimed yearly like obsidian-archive, never sold for points.
INSERT INTO theme_catalog (theme_id, display_name, price_points, valid_days, enabled, member_included, acquisition)
VALUES ('celestial-vault', '星穹御藏', 0, 365, TRUE, FALSE, 'SUPER_CLAIM')
ON CONFLICT (theme_id) DO NOTHING;
