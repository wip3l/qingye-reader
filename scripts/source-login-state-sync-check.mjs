// 书源的登录状态只留在本机：纯字符串令牌不上传，拉取时已有书源保留本机的登录密钥和登录表单。
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';

const source = fs.readFileSync(new URL('../entry/src/main/ets/account/CloudSyncCoordinator.ets', import.meta.url), 'utf8');
function method(name) {
  const at = source.search(new RegExp(`^  (?:private )?(?:static )?(?:async )?${name}\\(`, 'm'));
  assert(at >= 0, name);
  return source.slice(at, source.indexOf('\n  }', at) + 4);
}
class BookSource { constructor() { this.loginHeader = ''; this.loginInfo = ''; this.variable = ''; } }
BookSource.VALIDATION_UNCHECKED = 0;
class Rule {}
const names = ['loginHeaderForSync', 'sanitizeBookSourceHeader', 'mergeLocalSensitiveHeaders',
  'containsSensitiveHeader', 'isSensitiveHeaderName', 'bookSourceFromPayload'];
const Sync = vm.runInNewContext(stripTypeScriptTypes(
  `class CloudSyncCoordinator { ${names.map(method).join('\n')} }; CloudSyncCoordinator`),
  { BookSource, BookListRule: Rule, SearchRule: Rule, ExploreRule: Rule, BookInfoRule: Rule, TocRule: Rule,
    ContentRule: Rule, JSON });

// 上传：令牌字符串不出本机；请求头 JSON 只去掉敏感字段。
assert.equal(Sync.loginHeaderForSync('a1b2c3d4e5f6-api-key'), '');
assert.equal(Sync.loginHeaderForSync(''), '');
assert.equal(Sync.loginHeaderForSync('{"Authorization":"Bearer x","X-Client":"app"}'), '{"X-Client":"app"}');
assert.equal(Sync.loginHeaderForSync('["not","an","object"]'), '');

// 拉取：已有书源保留本机登录密钥与登录表单（云端旧令牌、空值都不能覆盖）。
const local = Object.assign(new BookSource(), {
  bookSourceUrl: 'agg', loginHeader: 'new-key', loginInfo: '{"邮箱":"a@b.c","密码":"new"}', variable: 'cfg'
});
const db = { getBookSource: async url => url === 'agg' ? local : null };
const restored = await Sync.bookSourceFromPayload(db, { bookSourceUrl: 'agg', loginHeader: 'old-key' });
assert.equal(restored.loginHeader, 'new-key', 'a remote old token never replaces the token this device logged in with');
assert.equal(restored.loginInfo, local.loginInfo, 'saved account fields survive a pull');
assert.equal(restored.variable, 'cfg');
local.loginHeader = '';
assert.equal((await Sync.bookSourceFromPayload(db, { bookSourceUrl: 'agg', loginHeader: 'old-key' })).loginHeader, '',
  'a logged-out device stays logged out');

// 本机没有的书源：只接受云端请求头 JSON 里的非敏感字段，旧版本上传过的令牌字符串丢弃。
const fresh = await Sync.bookSourceFromPayload(db, { bookSourceUrl: 'other', loginHeader: 'leaked-key' });
assert.equal(fresh.loginHeader, '');
assert.equal(fresh.loginInfo, '');
const json = await Sync.bookSourceFromPayload(db, { bookSourceUrl: 'other', loginHeader: '{"X-Client":"app"}' });
assert.equal(json.loginHeader, '{"X-Client":"app"}');
console.log('PASS: book-source login state stays on this device across cloud sync');
