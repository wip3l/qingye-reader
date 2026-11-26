// 固定版式 EPUB：OPF 声明解析、页面大小、单页与对开排法（含从右往左翻），以及文件排版的接线。
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { loadReaderModules } from './lib/load-reader-modules.mjs';
import { readEtsModule } from './lib/ets-module-staging.mjs';

const { EpubFixedLayout, EpubOriginalDocument, EpubOriginalScript, EpubOriginalLayoutOptions, EpubFixedScriptConfig,
  cleanup } = await loadReaderModules();
try {
  const opf = `<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0">
  <metadata>
    <meta property="rendition:layout">pre-paginated</meta>
    <meta property="rendition:spread">landscape</meta>
    <meta property="rendition:viewport">width=1200, height=1600</meta>
  </metadata>
  <manifest>
    <item id="cover" href="Text/cover.xhtml" media-type="application/xhtml+xml"/>
    <item id="p1" href="Text/p%201.xhtml" media-type="application/xhtml+xml"/>
    <item id="p2" href="Text/p2.xhtml" media-type="application/xhtml+xml"/>
    <item id="notes" href="Text/notes.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine page-progression-direction="rtl">
    <itemref idref="cover" properties="rendition:page-spread-center"/>
    <itemref idref="p1" properties="page-spread-right"/>
    <itemref idref="p2" properties="page-spread-left"/>
    <itemref idref="notes" properties="rendition:layout-reflowable"/>
  </spine>
</package>`;
  const pkg = EpubFixedLayout.parsePackage(opf, 'OEBPS/content.opf');
  assert.equal(pkg.fixed, true);
  assert.equal(pkg.rtl, true);
  assert.equal(pkg.noSpread, false);
  assert.deepEqual([pkg.width, pkg.height], [1200, 1600]);
  assert.equal(pkg.isFixed('OEBPS/Text/cover.xhtml'), true);
  assert.equal(pkg.isFixed('OEBPS/Text/p 1.xhtml'), true, '路径按 OPF 目录解析并解码');
  assert.equal(pkg.isFixed('OEBPS/Text/notes.xhtml'), false, '单页声明可重排的不算');
  assert.equal(pkg.sideOf('OEBPS/Text/cover.xhtml'), 'center');
  assert.equal(pkg.sideOf('OEBPS/Text/p 1.xhtml'), 'right');
  assert.equal(pkg.sideOf('OEBPS/Text/p2.xhtml'), 'left');
  assert.equal(pkg.firstPath, 'OEBPS/Text/cover.xhtml');
  const epub2 = EpubFixedLayout.parsePackage('<package><metadata><meta name="rendition:layout" content="pre-paginated"/>' +
    '<meta name="rendition:spread" content="none"/></metadata><manifest><item id="a" href="a.xhtml"/></manifest>' +
    '<spine><itemref idref="a"/></spine></package>', 'content.opf');
  assert.equal(epub2.fixed, true, 'EPUB 2 写法');
  assert.equal(epub2.noSpread, true);
  assert.equal(epub2.isFixed('a.xhtml'), true);
  const reflow = EpubFixedLayout.parsePackage('<package><manifest><item id="a" href="a.xhtml"/></manifest>' +
    '<spine><itemref idref="a"/></spine></package>', 'content.opf');
  assert.equal(reflow.fixed, false, '普通书不受影响');
  console.log('PASS: package');

  assert.deepEqual(Array.from(EpubFixedLayout.pageSize('<head><meta name="viewport" content="width=1024, height=768"/></head>')),
    [1024, 768]);
  assert.deepEqual(Array.from(EpubFixedLayout.pageSize('<meta content="width=600,height=800" name="viewport">')), [600, 800]);
  assert.deepEqual(Array.from(EpubFixedLayout.pageSize('<meta name="viewport" content="width=device-width"><body>' +
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1240 1754"><image href="a.jpg"/></svg></body>')),
    [1240, 1754], '没有数字视口时取 svg viewBox');
  assert.deepEqual(Array.from(EpubFixedLayout.pageSize('<body><p>文字</p></body>')), [0, 0]);
  console.log('PASS: page size');

  const views = (list) => list.map((v) => [v.left, v.right, v.center]);
  assert.deepEqual(views(EpubFixedLayout.singleViews(3)), [[-1, -1, 0], [-1, -1, 1], [-1, -1, 2]]);
  assert.deepEqual(views(EpubFixedLayout.spreadViews(['', '', '', '', ''], false, true)),
    [[-1, 0, -1], [1, 2, -1], [3, 4, -1]], '从左往右：封面单独在右，其后两两成对');
  assert.deepEqual(views(EpubFixedLayout.spreadViews(['', '', '', ''], false, false)),
    [[0, 1, -1], [2, 3, -1]], '不是全书第一章时从头两两成对');
  assert.deepEqual(views(EpubFixedLayout.spreadViews(['', '', '', '', ''], true, true)),
    [[0, -1, -1], [2, 1, -1], [4, 3, -1]], '从右往左：先读的放右边');
  assert.deepEqual(views(EpubFixedLayout.spreadViews(['center', 'right', 'left', 'right', 'right'], true, true)),
    [[-1, -1, 0], [2, 1, -1], [-1, 3, -1], [-1, 4, -1]], '按书里的 page-spread 拼，缺一边就单放');
  assert.deepEqual(views(EpubFixedLayout.spreadViews(['left', 'left', 'right'], false, false)),
    [[0, -1, -1], [1, 2, -1]], '连续两个左页：前一个单放');
  assert.equal(EpubFixedLayout.viewOf(EpubFixedLayout.spreadViews(['', '', '', '', ''], false, true), 3), 2);
  console.log('PASS: views');

  const options = new EpubOriginalLayoutOptions();
  options.paged = true;
  options.fixed = new EpubFixedScriptConfig();
  options.fixed.pages = [[1200, 1600]];
  options.fixed.single = [[-1, -1, 0]];
  options.fixed.spread = [[-1, 0, -1]];
  options.fixedBackground = '#F4F1EA';
  const injection = EpubOriginalScript.injection(options);
  assert.match(injection.style, /legado-fxl-page\{position:absolute/);
  assert.doesNotMatch(injection.style, /column-width/, '固定版式不分栏');
  assert.match(injection.style, /html\.legado-fxl-spread::after/, '对开时才画书脊');
  assert.match(injection.script, /"fixed":\{"pages":\[\[1200,1600\]\]/);
  assert.doesNotThrow(() => new vm.Script(injection.script), '注入的脚本语法正确');
  const html = EpubOriginalDocument.buildFixed([{ path: 'OEBPS/Text/p1.xhtml',
    html: '<html><head><link rel="stylesheet" href="../Styles/a.css"/><script>alert(1)</script></head>' +
      '<body><img src="../Images/a.jpg"/><a href="p2.xhtml">下一页</a></body></html>' }], injection, '绘本');
  assert.match(html, /<iframe class="legado-fxl-page" data-legado-file="OEBPS\/Text\/p1.xhtml"/);
  assert.match(html, /srcdoc="[^"]*https:\/\/epub\.legado\.local\/OEBPS\/Images\/a\.jpg/, '页里的地址改成虚拟站点');
  assert.doesNotMatch(html, /alert\(1\)/, '书里的脚本去掉');
  assert.match(html, /user-select:none/, '页里的文字不能选');
  console.log('PASS: document');

  const page = readEtsModule('pages/EpubOriginalReadBook.ets');
  assert.match(page, /if \(this\.isFixedChapter\(index\)\) \{\s*options\.fixed = await this\.fixedConfig/);
  assert.match(page, /const direction = this\.screenDirection\(screenDirection\);/, '翻页层方向按阅读方向换算');
  assert.match(page, /tapZoneAction\(this\.fixedRtl\(\) \? 1 - x : x, y\)/, '从右往左翻的书九宫格镜像');
  assert.match(page, /固定版式的页面暂不支持朗读/);
  assert.match(page, /legado-file:\$\{path\}/, '链到文件开头落到那一页');
  const script = readEtsModule('core/book/EpubOriginalScript.ts');
  assert.match(script, /if \(fx\) \{ fxLayout\(\); return; \}/);
  assert.match(script, /if \(fx && fxZoom > 1\) zones\.push/, '放大时整屏不归翻页层');
  assert(script.indexOf('e.stopImmediatePropagation();') < script.indexOf("var audio = e.target && e.target.closest ? e.target.closest('.legado-audio')"),
    '固定版式的点按处理先于通用处理');
  assert.match(readEtsModule('pages/ReadBook.ets'), /maybeShowFixedLayoutTip\(\)/);
  console.log('PASS: wiring');
} finally {
  cleanup();
}
