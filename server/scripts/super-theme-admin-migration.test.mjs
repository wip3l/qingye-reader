import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile, readdir } from 'node:fs/promises';
import { PGlite } from '@electric-sql/pglite';

test('administrator migration preserves SELECT-only catalog access and grants only claim ledger access', async () => {
  // Load a named database so production identity checks execute unchanged in the test.
  const bootstrap = new PGlite();
  await bootstrap.exec('CREATE DATABASE legado_commerce');
  const data = await bootstrap.dumpDataDir();
  await bootstrap.close();
  const db = new PGlite({ loadDataDir: data, database: 'legado_commerce' });
  try {
    const migrations = new URL('../migrations/', import.meta.url);
    // The database as it stood before 023; 030 adds a catalog row that needs 023's acquisition column.
    for (const file of (await readdir(migrations)).filter(n => n.endsWith('.sql') && !n.startsWith('023') &&
      !n.startsWith('030')).sort()) {
      await db.exec((await readFile(new URL(file, migrations), 'utf8')).replace(/^VACUUM[^;]*;/gm, ''));
    }
    await db.exec(`CREATE ROLE qingye NOSUPERUSER;
      GRANT USAGE ON SCHEMA public TO qingye;
      ALTER TABLE app_users OWNER TO qingye;
      ALTER TABLE theme_entitlements OWNER TO qingye;
      GRANT SELECT ON theme_catalog TO qingye;`);
    const sql = name => readFile(new URL('super-theme-update/' + name, import.meta.url), 'utf8');
    await db.exec(await sql('admin-check.sql'));
    const migration = (await readFile(new URL('023_super_exclusive_theme.sql', migrations), 'utf8')).trim();
    const admin = await sql('admin-prefix.sql') + '\n' + migration.slice(6, -7) + '\n' + await sql('admin-suffix.sql');
    const original = (await db.query("SELECT relowner,relacl::text FROM pg_class WHERE oid='theme_catalog'::regclass")).rows;
    await db.exec(admin);
    assert.deepEqual((await db.query("SELECT relowner,relacl::text FROM pg_class WHERE oid='theme_catalog'::regclass")).rows, original);
    await db.exec(`SET ROLE qingye;
      INSERT INTO app_users(id,huawei_open_id) VALUES('00000000-0000-0000-0000-000000000001','permission-fixture');
      INSERT INTO membership_theme_claims(user_id,theme_id,request_id,claimed_at,expires_at)
        VALUES('00000000-0000-0000-0000-000000000001','obsidian-archive','fixture',now(),now()+interval '1 year');
      RESET ROLE;`);
    const grants = (await db.query(`SELECT
      has_table_privilege('qingye','theme_catalog','UPDATE') AS catalog_update,
      has_table_privilege('qingye','theme_catalog','REFERENCES') AS catalog_reference,
      has_table_privilege('qingye','membership_theme_claims','SELECT') AS ledger_read,
      has_table_privilege('qingye','membership_theme_claims','INSERT') AS ledger_insert,
      has_table_privilege('qingye','membership_theme_claims','UPDATE') AS ledger_update`)).rows[0];
    assert.deepEqual(grants, { catalog_update:false, catalog_reference:false, ledger_read:true, ledger_insert:true, ledger_update:false });
    const records = (await db.query('SELECT * FROM membership_theme_claims')).rows;
    await db.exec(admin);
    assert.deepEqual((await db.query('SELECT * FROM membership_theme_claims')).rows, records);
    await db.exec(await sql('admin-disable.sql'));
    assert.equal((await db.query("SELECT enabled FROM theme_catalog WHERE theme_id='obsidian-archive'")).rows[0].enabled,false);
    assert.deepEqual((await db.query('SELECT * FROM membership_theme_claims')).rows, records);
    // Failure during validation rolls back the whole migration, without silently re-enabling a disabled theme.
    await assert.rejects(db.exec(admin), /Exclusive theme catalog verification failed/);
    await db.exec('ROLLBACK');
    assert.equal((await db.query("SELECT enabled FROM theme_catalog WHERE theme_id='obsidian-archive'")).rows[0].enabled,false);
  } finally { await db.close(); }
});
