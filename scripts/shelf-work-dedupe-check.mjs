// Run with: node scripts/shelf-work-dedupe-check.mjs
// The shelf keeps one online copy per work (category + normalised title + author).
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { readEtsModule } from './lib/ets-module-staging.mjs';

const compile = source => stripTypeScriptTypes(source
  .replace(/^import\s+[\s\S]*?\s+from\s+['"][^'"]+['"];?\r?\n/gm, '')
  .replace(/^export /gm, ''), { mode: 'strip' });

const inserted = [];
const prompts = [];
let shelf = [];
let version = 1;
const context = vm.createContext({
  console,
  EncodedSourceUrl: { decode: () => null, str: value => String(value || '') },
  AppStorage: { get: () => version, setOrCreate: () => { version++; } },
  AppDatabase: { getInstance: () => ({
    initWithContext: async () => {},
    getAllBooks: async () => shelf,
    insertBook: async book => { inserted.push(book); },
    updateBook: async () => {}
  }) },
  HdsFeedback: { showToast() {} },
  CoverUrlNormalizer: { prefer: (a, b) => a || b, normalize: value => value },
  BookFieldSanitizer: { prefer: (a, b) => a || b, clean: value => value },
  ShelfWorkDuplicatePrompt: { offerSwitch: async (_context, _ui, shelfBook, candidate) => {
    prompts.push({ shelfBook, candidate });
    return null;
  } }
});
vm.runInContext([
  'model/data/Book.ts', 'core/book/BookTypeSupport.ts', 'utils/BookIdentity.ts',
  'utils/SearchExplorePendingBook.ets', 'utils/SearchBookShelfHelper.ets'
].map(file => compile(readEtsModule(file))).join('\n') +
  '\nglobalThis.api = { Book, SearchBook, BookTypeSupport, BookIdentity, SearchBookShelfHelper };', context);
const { Book, SearchBook, BookTypeSupport, BookIdentity, SearchBookShelfHelper } = context.api;

function make(Type, fields) {
  return Object.assign(new Type(), { origin: 'https://a.test', bookUrl: 'https://a.test/book/1' }, fields);
}

const key = (name, author, extra = {}) => BookIdentity.workKeyOf(make(Book, { name, author, ...extra }));

// Normalisation folds the usual source-to-source differences.
assert.equal(key('《诡秘之主》', '作者：爱潜水的乌贼'), key('诡秘之主', '爱潜水的乌贼'));
assert.equal(key('诡秘 之主', '爱潜水的乌贼 著'), key('诡秘之主', '爱潜水的乌贼'));
assert.equal(key('ＡＢＣ　传奇', 'Ｔｏｍ'), key('abc传奇', 'tom'));
// No reliable identity: missing/placeholder author, local and WebDAV/OPDS books.
assert.equal(key('诡秘之主', ''), '');
assert.equal(key('诡秘之主', '佚名'), '');
assert.equal(key('诡秘之主', '未知'), '');
assert.equal(key('诡秘之主', '爱潜水的乌贼', { origin: 'local' }), '');
// A novel and its comic/audio adaptation are different things to keep.
assert.notEqual(key('诡秘之主', '爱潜水的乌贼'),
  key('诡秘之主', '爱潜水的乌贼', { type: BookTypeSupport.AUDIO }));

const shelfBook = make(Book, { name: '诡秘之主', author: '爱潜水的乌贼', originName: 'A 站' });
const otherSource = make(SearchBook, { origin: 'https://b.test', originName: 'B 站',
  bookUrl: 'https://b.test/detail/9', name: '《诡秘之主》', author: '爱潜水的乌贼 著' });

// Same work from another source: never inserted; UI callers get the switch offer.
shelf = [shelfBook];
version++;
let change = await SearchBookShelfHelper.addToShelf({}, otherSource);
assert.equal(change.shelfKey, '');
assert.equal(change.sameWorkBook.bookUrl, shelfBook.bookUrl);
assert.equal(inserted.length, 0);
change = await SearchBookShelfHelper.addToShelf({}, otherSource, {});
assert.equal(prompts.length, 1);
assert.equal(prompts[0].shelfBook.bookUrl, shelfBook.bookUrl);
assert.equal(change.shelfKey, '', 'declined switch adds nothing');
assert.equal(inserted.length, 0);

// A temporary read of the work does not block adding.
shelf = [Object.assign(make(Book, { name: '诡秘之主', author: '爱潜水的乌贼' }), { pendingAddToShelf: true })];
version++;
change = await SearchBookShelfHelper.addToShelf({}, otherSource);
assert.equal(inserted.length, 1);
assert.notEqual(change.shelfKey, '');

// Without an author the work cannot be identified, so both copies are allowed.
inserted.length = 0;
shelf = [make(Book, { name: '诡秘之主', author: '' })];
version++;
await SearchBookShelfHelper.addToShelf({}, make(SearchBook, { origin: 'https://b.test',
  bookUrl: 'https://b.test/detail/9', name: '诡秘之主', author: '' }));
assert.equal(inserted.length, 1);

console.log('PASS shelf work dedupe: normalisation, exclusions, media category, switch offer, temporary reads');
