// 插图全屏查看：查看器参数的编码、图片实际画出的矩形，以及两种排版的接线（点插图打开、整页插图只认中间一列）。
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { readEtsModule } from './lib/ets-module-staging.mjs';

const sandbox = vm.createContext({});
vm.runInContext(stripTypeScriptTypes(readEtsModule('core/reader/ReaderImageViewerSpec.ts')
  .replace(/^export /gm, '') + '\nglobalThis.Spec = ReaderImageViewerSpec;'), sandbox);
const Spec = sandbox.Spec;

const spec = new Spec();
spec.source = '/data/book/OEBPS/Images/渡口.jpg';
spec.uri = 'file:///data/book/OEBPS/Images/%E6%B8%A1%E5%8F%A3.jpg';
spec.caption = '渡口远山';
spec.x = 26.04;
spec.y = 180.5;
spec.width = 308;
spec.height = 200.27;
spec.naturalWidth = 1200;
spec.naturalHeight = 780;
const decoded = Spec.decode(spec.encode());
assert.equal(decoded.source, spec.source);
assert.equal(decoded.uri, spec.uri);
assert.equal(decoded.caption, '渡口远山');
assert.deepEqual([decoded.x, decoded.y, decoded.width, decoded.height], [26, 180.5, 308, 200.3]);
assert.deepEqual([decoded.naturalWidth, decoded.naturalHeight], [1200, 780]);
assert.equal(Spec.decode('%7Bbroken'), null, '坏数据返回 null');
assert.equal(Spec.decode(encodeURIComponent(JSON.stringify({ s: 'a' }))), null, '没有可加载地址时不打开');
console.log('PASS: spec encode/decode');

assert.deepEqual(Array.from(Spec.containRect(0, 0, 300, 600, 1200, 800)), [0, 200, 300, 200], '横图放进竖框上下留白');
assert.deepEqual(Array.from(Spec.containRect(10, 20, 400, 200, 100, 100)), [110, 20, 200, 200], '方图放进横框左右留白');
assert.deepEqual(Array.from(Spec.containRect(5, 6, 70, 80, 0, 0)), [5, 6, 70, 80], '原图尺寸未知时就是整个框');
console.log('PASS: contain rect');

const readBook = readEtsModule('pages/ReadBook.ets');
function method(source, name) {
  const start = source.search(new RegExp(`^  (?:private )?(?:async )?${name}\\(`, 'm'));
  assert(start >= 0, name);
  return source.slice(start, source.indexOf('\n  }', start) + 4);
}
const hit = method(readBook, 'readerV2ImageMarkerAt');
assert.match(hit, /rect\.height\(\) >= content\.height\(\) \* 0\.6/, '整页插图');
assert.match(hit, /xPx < content\.left \+ third \|\| xPx > content\.right - third/, '整页插图点两侧照常翻页');
assert.match(hit, /isReaderComicModeActive\(\)/, '漫画模式不接管');
assert.match(method(readBook, 'readerV2ActionAtLocalPoint'), /readerV2ImageMarkerAt\(/, '翻页阅读点插图');
assert.match(method(readBook, 'readerContinuousV2ActionAtPoint'), /readerV2ImageMarkerAt\(/, '滚动阅读点插图');
assert.match(method(readBook, 'openReaderSourceAction'), /READER_IMAGE_MARKER_PREFIX/);
assert.match(method(readBook, 'onBackPress'), /this\.readerImageViewer = null/, '返回键先关查看器');
// 关闭时不能按对象比较（@State 存的是代理）：比较失败会留下一层透明查看器挡住翻页。
assert.doesNotMatch(readBook, /this\.readerImageViewer === spec/, '关闭时直接清掉查看器');

const original = readEtsModule('pages/EpubOriginalReadBook.ets');
assert.match(original, /slot\.bridge\.onImage = /);
assert.match(method(original, 'onBackPress'), /this\.imageViewer = null/);
assert.doesNotMatch(original, /this\.imageViewer === spec/);
assert.match(readEtsModule('components/reader/ReaderImageViewer.ets'),
  /hitTestBehavior\(this\.closingState \? HitTestMode\.None/, '关闭动画期间不挡触摸');
const script = readEtsModule('core/book/EpubOriginalScript.ts');
assert.match(script, /'annotation', 'image'\]/, '网页能调到 image');
assert.match(script, /box\.height >= window\.innerHeight \* 0\.6/, '文件排版整页插图同样只认中间一列');
assert(script.indexOf("closest('a[href]')") < script.indexOf("closest('img, image')"), '图片链接仍按链接处理');
console.log('PASS: wiring');
