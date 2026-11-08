#!/usr/bin/env node
// EPUB XHTML → 阅读器正文转换、目录切章与图片标记的回归检查。
// 直接加载 entry 下的纯 TS 模块（EpubHtmlConverter / EpubChapterPlanner / ReaderImageMarker），
// 因此测到的就是应用实际运行的代码。
// Usage: node --experimental-strip-types scripts/epub-converter-check.mjs

import { loadReaderModules } from './lib/load-reader-modules.mjs';

const { EpubHtmlConverter, EpubImageRef, EpubChapterPlanner, EpubChapterSegment, EpubTocEntry, ReaderImageMarker,
  ReaderActionMarker, EpubNoteLink, EpubTextOffsetMap, EpubOriginalDocument, EpubOriginalPiece, EpubOriginalPosition,
  EpubOriginalSpot, EpubOriginalScript, EpubOriginalLayoutOptions, ReaderNightImage, cleanup } = await loadReaderModules();

let failures = 0;
const check = (condition, message, detail = '') => {
  if (condition) {
    console.log(`  ok - ${message}`);
  } else {
    failures++;
    console.error(`  FAIL - ${message}${detail ? `\n         ${detail}` : ''}`);
  }
};
const equal = (actual, expected, message) =>
  check(actual === expected, message, `expected ${JSON.stringify(expected)}\n         actual   ${JSON.stringify(actual)}`);

// 图片解析桩：路径即 src，尺寸由表给出。
const sizes = { 'cover.jpg': [1200, 1800], 'gaiji.png': [32, 32], 'divider.png': [600, 40] };
const resolve = (src) => {
  if (src === 'missing.jpg') return null;
  const ref = new EpubImageRef();
  ref.path = `/book/${src}`;
  const size = sizes[src];
  if (size) {
    ref.width = size[0];
    ref.height = size[1];
  }
  return ref;
};
const convert = (body, startId = '', endId = '') =>
  EpubHtmlConverter.convert(`<html><head><title>T</title><style>p{}</style></head><body>${body}</body></html>`,
    resolve, startId, endId);
const marker = (src) => {
  const size = sizes[src] || [0, 0];
  return ReaderImageMarker.create(`/book/${src}`, size[0], size[1]);
};

try {
  console.log('whitespace');
  equal(convert('<p>It was the best of times,\n   it was the worst of times,\n   it was the age.</p>').content,
    'It was the best of times, it was the worst of times, it was the age.',
    '源码硬换行折叠为空格，不再拆成多个段落');
  equal(convert('<p>这是第一行\n    这是第二行</p>').content, '这是第一行这是第二行', '中文之间的源码换行不产生空格');
  equal(convert('<p>one</p>\n\n\n<p>two</p>   <div>three</div>').content, 'one\n\ntwo\n\nthree', '块级元素各成一段，段落之间是空行');
  equal(convert('<p>　　全角缩进保留</p>').content, '　　全角缩进保留', '段首全角缩进不被裁掉');
  equal(convert('<p>a<br/>b</p>').content, 'a\nb', '<br> 是块内换行，只输出单个换行');
  equal(convert('<pre>line 1\nline 2</pre>').content, 'line 1\n\nline 2', '<pre> 内的换行保留');
  equal(convert('<p>a<span>b</span><em>c</em> d</p>').content, 'abc d', '行内标签不引入空格');
  equal(convert('<h2>Chapter One</h2><p>Yes</p><p>No</p><p>诗一行<br/>诗二行<br/><img src="cover.jpg"/>诗三行</p>').content,
    `Chapter One\n\nYes\n\nNo\n\n诗一行\n诗二行\n\n${marker('cover.jpg')}\n\n诗三行`,
    '标题与短段落之间是空行（不会被阅读器当作软换行合并），块内 <br> 仍是单换行');

  console.log('semantics');
  equal(convert('<p><ruby>漢字<rp>(</rp><rt>かんじ</rt><rp>)</rp></ruby>を読む</p>').content, '漢字を読む',
    'ruby 注音不混入正文');
  equal(convert('<table><tr><td>a</td><td>b</td></tr><tr><td>c</td><td>d</td></tr></table>').content,
    'a | b\n\nc | d', '表格按行输出，单元格之间有分隔');
  equal(convert('<ul><li>one</li><li><p>two</p></li></ul>').content, '　• one\n\ntwo', '列表项带圆点，空圆点行被丢弃');
  equal(convert('<figure><img src="cover.jpg"/><figcaption>图注</figcaption></figure><p>正文</p>').content,
    `${marker('cover.jpg')}\n\n图注\n\n正文`, 'figcaption 独立成段');
  equal(convert('<dl><dt>词</dt><dd>释义</dd></dl>').content, '词\n\n释义', 'dt/dd 分行');
  equal(convert('<!-- <p>注释</p> --><p>正文</p><script>var a = "<p>x</p>";</script>').content, '正文',
    '注释与脚本不输出');
  equal(convert('<h2>第一章 <small>开端</small></h2><p>正文</p>').headingText, '第一章 开端', '提取第一个标题文本');
  equal(JSON.stringify(convert('<h1>卷一</h1><p>甲</p><h3><img src="gaiji.png"/>第一节</h3><h2></h2>').headings),
    JSON.stringify([{ level: 1, text: '卷一' }, { level: 3, text: '第一节' }]), '收集全部标题及其层级，忽略空标题');
  equal(convert('<p>水是 H<sub>2</sub>O，见注<sup>12</sup>，<sup><a href="#n">3</a></sup>，x<sup>n</sup></p>').content,
    '水是 H₂O，见注¹²，³，xn', '纯数字上下标转为 Unicode 上下标字符');

  console.log('entities');
  equal(convert('<p>&ldquo;Hi&rdquo;&mdash;he said&hellip; caf&eacute; &Eacute;cole &amp; &lt;b&gt;</p>').content,
    '“Hi”—he said… café École & <b>', '常见命名实体与大写变体');
  equal(convert('<p>&#x1F600;&#128512;&#xD800;&unknown;</p>').content, '\u{1F600}\u{1F600}&#xD800;&unknown;',
    '补充平面码点正确解码，非法实体原样保留');
  equal(convert('<p>a&nbsp;&nbsp;b</p>').content, 'a b', 'nbsp 按空白处理');

  console.log('images');
  equal(convert('<p>前文</p><div><img src="cover.jpg" alt="封面"/></div><p>后文</p>').content,
    `前文\n\n${marker('cover.jpg')}\n\n后文`, '块级图片输出带尺寸的标记');
  const info = ReaderImageMarker.parse(marker('cover.jpg'));
  check(info.source === '/book/cover.jpg' && info.width === 1200 && info.height === 1800, '标记可解析出路径与尺寸');
  equal(ReaderImageMarker.parse(ReaderImageMarker.create('https://a.b/c|d.jpg')).source, 'https://a.b/c|d.jpg',
    '无尺寸标记兼容旧格式（含 | 的地址不被误判）');
  equal(convert('<p>他写下了<img src="gaiji.png" alt="𠮷"/>这个字。</p>').content, '他写下了𠮷这个字。',
    '行内外字图片用 alt 顶替，段落不被截断');
  equal(convert('<p>他写下了<img src="gaiji.png"/>这个字。</p>').content, '他写下了这个字。', '无 alt 的行内小图被省略');
  equal(convert('<p><img src="gaiji.png"/></p>').content, marker('gaiji.png'), '独占一行的小图仍然是图片块');
  equal(convert('<p>说明文字<img src="cover.jpg"/>继续</p>').content,
    `说明文字\n\n${marker('cover.jpg')}\n\n继续`, '与文字同行的大图仍然独立成块');
  equal(convert('<p>a<img src="missing.jpg"/>b<img src="https://x/y.png"/>c</p>').content, 'a b c',
    '不存在或远程的图片被忽略');
  equal(convert('<svg><image xlink:href="cover.jpg" width="100%"/></svg>').content, marker('cover.jpg'),
    'SVG 包裹的封面图');
  equal(convert('<object data="cover.jpg" type="image/jpeg"></object><object data="a.swf"></object>').content,
    marker('cover.jpg'), 'object 只接受图片类型');
  check(convert('<img src="cover.jpg"/><img src="cover.jpg"/>').imagePaths.length === 1 &&
    !convert('<img src="cover.jpg"/>').hasText, 'imagePaths 去重，纯图片段 hasText=false');

  console.log('charset & paths');
  const bytes = (text) => Uint8Array.from(Buffer.from(text, 'latin1'));
  equal(EpubHtmlConverter.sniffCharset(bytes('<?xml version="1.0" encoding="GBK"?><html>')), 'gb18030', 'XML 声明 GBK');
  equal(EpubHtmlConverter.sniffCharset(bytes('<html><head><meta charset="Shift_JIS">')), 'shift_jis', 'meta charset');
  equal(EpubHtmlConverter.sniffCharset(bytes('<html><head><meta http-equiv="Content-Type" content="text/html; charset=big5">')),
    'big5', 'http-equiv 中的 charset');
  equal(EpubHtmlConverter.sniffCharset(Uint8Array.from([0xFF, 0xFE, 0x3C, 0x00])), 'utf-16le', 'UTF-16 BOM');
  equal(EpubHtmlConverter.sniffCharset(bytes('<html><body>plain</body></html>')), '', '未声明时返回空');
  equal(EpubHtmlConverter.resolvePath('/root/OEBPS/text', '../images/my%20pic.jpg#x', '/root'),
    '/root/OEBPS/images/my pic.jpg', '相对路径解码并归一化');
  equal(EpubHtmlConverter.resolvePath('/root/OEBPS/text', '/images/a.jpg', '/root'), '/root/images/a.jpg',
    '以 / 开头的引用相对容器根目录');

  console.log('anchors');
  const multi = '<h1 id="c1">一</h1><p>甲</p><h1 id="c2">二</h1><p>乙</p><div><a name="c3"></a><h1>三</h1><p>丙</p></div>';
  equal(convert(multi, 'c1', 'c2').content, '一\n\n甲', '按锚点切出第一段');
  equal(convert(multi, 'c2', 'c3').content, '二\n\n乙', '按锚点切出中间段');
  equal(convert(multi, 'c3', '').content, '三\n\n丙', 'name 锚点与文件结尾');
  equal(convert(multi, 'nope', '').content, convert(multi).content, '找不到起始锚点时退回整个文件');

  console.log('toc');
  const nav = `<nav epub:type="toc"><ol>
    <li><a href="text/ch1.xhtml">第一章</a><ol><li><a href="text/ch1.xhtml#s2">第二节</a></li></ol></li>
    <li><a href="text/ch%202.xhtml#top">第二章 &amp; 续</a></li>
    <li><a href="https://example.com">外链</a></li></ol></nav>
    <nav epub:type="landmarks"><a href="text/cover.xhtml">Cover</a></nav>`;
  const navEntries = EpubChapterPlanner.parseNavToc(nav, '/root/OEBPS', '/root');
  check(navEntries.length === 3 && navEntries[1].fragment === 's2' &&
    navEntries[2].path === '/root/OEBPS/text/ch 2.xhtml' && navEntries[2].title === '第二章 & 续',
    'nav 目录：嵌套条目、锚点、实体、忽略外链与 landmarks', JSON.stringify(navEntries));
  const ncx = `<ncx><navMap>
    <navPoint id="a"><navLabel><text>卷一</text></navLabel><content src="v1.xhtml"/>
      <navPoint id="b"><navLabel><text>第一章</text></navLabel><content src="v1.xhtml#c1"/></navPoint>
      <navPoint id="c"><navLabel><text>第二章</text></navLabel><content src="c2.xhtml"/></navPoint>
    </navPoint>
    <navPoint id="d"><navLabel><text>后记</text></navLabel><content src="end.xhtml"/></navPoint></navMap></ncx>`;
  const ncxEntries = EpubChapterPlanner.parseNcxToc(ncx, '/root', '/root');
  equal(ncxEntries.map((entry) => entry.title).join(','), '卷一,第一章,第二章,后记', 'NCX 嵌套 navPoint 的第一个子项不再丢失');

  console.log('chapter planning');
  const toc = (path, fragment, title) => {
    const entry = new EpubTocEntry();
    entry.path = path;
    entry.fragment = fragment;
    entry.title = title;
    return entry;
  };
  const plan = (files, tocEntries) => {
    const grouped = EpubChapterPlanner.groupTocByPath(tocEntries);
    const planner = new EpubChapterPlanner(grouped.size > 0);
    for (const file of files) {
      planner.beginFile();
      for (const cut of EpubChapterPlanner.planFileCuts(file.body, grouped.get(file.path) || [])) {
        planner.addPiece(file.path, cut.startId, cut.endId, cut.title,
          EpubHtmlConverter.convertBody(file.body, resolve, cut.startId, cut.endId), file.title || '');
      }
      planner.endFile();
    }
    return planner;
  };

  // 一个文件多章 + 被拆分工具切开的章节 + 未入目录的插图页
  const book = plan([
    { path: '/b/cover.xhtml', body: '<img src="cover.jpg"/>' },
    { path: '/b/v1.xhtml', body: '<div id="c1"><h1>第一章</h1><p>甲</p></div><div id="c2"><h1>第二章</h1><p>乙</p></div>' },
    { path: '/b/v1_split_001.xhtml', body: '<p>乙的后半</p>' },
    { path: '/b/illus.xhtml', body: '<img src="cover.jpg"/>' },
    { path: '/b/c3.xhtml', body: '<h1>第三章</h1><p>丙</p>' },
  ], [toc('/b/v1.xhtml', '', '卷一'), toc('/b/v1.xhtml', 'c1', '第一章'), toc('/b/v1.xhtml', 'c2', '第二章'),
    toc('/b/c3.xhtml', '', '第三章')]);
  equal(book.chapters.map((chapter) => chapter.title).join(','), '封面,卷一 第一章,第二章,第三章',
    '按目录切章：指向同一位置的条目合并标题，无目录条目的文件不单独成章');
  check(book.chapters[2].segments.length === 3 && book.chapters[2].content.includes('乙的后半') &&
    book.chapters[2].content.endsWith(marker('cover.jpg')), '拆分文件与插图页并入前一章',
    JSON.stringify(book.chapters[2]));
  check(book.chapters[1].segments[0].endId === 'c2' && book.chapters[2].segments[0].startId === 'c2',
    '片段记录锚点范围');
  check(!book.isComicDominant() && book.spineFileCount === 5 && book.imageOnlyFileCount === 2,
    '少量插图页不识别为漫画');
  equal(EpubChapterPlanner.chapterIndexForPath(book.chapters, '/b/illus.xhtml'), 2, '按文件迁移阅读进度（并入的文件）');
  equal(EpubChapterPlanner.chapterIndexForPath(book.chapters, '/b/v1.xhtml#c2'), 1, '按文件迁移阅读进度（多章文件取第一章）');
  equal(EpubChapterPlanner.chapterIndexForPath(book.chapters, '/b/gone.xhtml'), -1, '找不到文件返回 -1');

  const encoded = EpubChapterPlanner.encodeVariable(book.chapters[2].segments, book.chapters[2].headings);
  equal(JSON.stringify(EpubChapterPlanner.decodeSegments(encoded)), JSON.stringify(book.chapters[2].segments),
    '片段列表可往返序列化');
  equal(JSON.stringify(EpubChapterPlanner.decodeHeadings(encoded)), JSON.stringify([{ level: 1, text: '第二章' }]),
    '章内标题随章节保存并可还原');
  equal(EpubChapterPlanner.decodeHeadings(EpubChapterPlanner.encodeVariable(book.chapters[0].segments)).length, 0,
    '没有标题的章节不写入标题列表');
  equal(EpubChapterPlanner.decodeSegments('').length + EpubChapterPlanner.decodeSegments('{"k":1}').length +
    EpubChapterPlanner.decodeSegments('{"epubSegments":').length, 0, '非法 variable 返回空片段');

  // 锚点之前的内容归上一章
  const leading = plan([
    { path: '/b/a.xhtml', body: '<p>甲</p>' },
    { path: '/b/b.xhtml', body: '<p>甲的结尾</p><h1 id="x">乙章</h1><p>乙</p>' },
  ], [toc('/b/a.xhtml', '', '甲章'), toc('/b/b.xhtml', 'x', '乙章')]);
  check(leading.chapters.length === 2 && leading.chapters[0].content === '甲\n\n甲的结尾' &&
    leading.chapters[1].content === '乙章\n\n乙', '第一个锚点之前的内容并入上一章', JSON.stringify(leading.chapters));

  // 没有目录：一个文件一章，取标题或 <title>
  const noToc = plan([
    { path: '/b/1.xhtml', body: '<img src="cover.jpg"/>' },
    { path: '/b/2.xhtml', body: '<h2>序</h2><p>甲</p>' },
    { path: '/b/3.xhtml', body: '<p>乙</p>', title: '文档标题' },
    { path: '/b/4.xhtml', body: '<p>丙</p>' },
    { path: '/b/5.xhtml', body: '  <p> </p> ' },
  ], []);
  equal(noToc.chapters.map((chapter) => chapter.title).join(','), '封面,序,文档标题,第4节',
    '无目录时一个文件一章，空文件被跳过');

  // 目录残缺：超过长度上限后另起续篇
  const long = '<p>' + '字'.repeat(70000) + '</p>';
  const sparse = plan([
    { path: '/b/1.xhtml', body: '<p>开始</p>' }, { path: '/b/2.xhtml', body: long },
    { path: '/b/3.xhtml', body: long }, { path: '/b/4.xhtml', body: long },
  ], [toc('/b/1.xhtml', '', '正文')]);
  equal(sparse.chapters.map((chapter) => chapter.title).join(','), '正文,正文（2）,正文（3）',
    '目录残缺的长内容按长度上限拆成续篇');

  // 漫画识别
  const comic = plan([1, 2, 3, 4, 5].map((n) => ({ path: `/b/${n}.xhtml`, body: '<img src="cover.jpg"/>' })), []);
  check(comic.isComicDominant(), '纯图 spine 识别为漫画');

  // 锚点索引：与逐个正则查找的结果一致
  {
    const body = `<p>id="fake"</p><div class="x" id="a1">一</div><a name='n1'></a>` +
      '<span xml:id="x1">二</span><p id="a1">重复</p><h2 title="t" id="h-1.2">三</h2><br/>';
    equal(EpubHtmlConverter.findAnchorOffset(body, 'a1'), body.indexOf('<div class="x"'), '同名 id 取第一次出现');
    equal(EpubHtmlConverter.findAnchorOffset(body, 'n1'), body.indexOf('<a name='), 'name 属性与单引号');
    equal(EpubHtmlConverter.findAnchorOffset(body, 'x1'), body.indexOf('<span'), 'xml:id');
    equal(EpubHtmlConverter.findAnchorOffset(body, 'h-1.2'), body.indexOf('<h2'), '含正则特殊字符的 id');
    equal(EpubHtmlConverter.findAnchorOffset(body, 'fake'), -1, '正文文字里的 id= 不算锚点');
    equal(EpubHtmlConverter.findAnchorOffset(body, ' a1 '), body.indexOf('<div class="x"'), '查找前去掉首尾空白');
    equal(EpubHtmlConverter.findAnchorOffset(body, ''), 0, '空 id 表示文件开头');
    equal(EpubHtmlConverter.findAnchorOffset('<p id="z">另一个文件</p>', 'a1'), -1, '换了 body 重新建索引');
    equal(EpubHtmlConverter.findAnchorOffset(body, 'x1'), body.indexOf('<span'), '切回原 body 仍正确');
  }

  console.log('note links');
  {
    // 链接解析桩：同文件锚点记到 ch1.xhtml，其它文件按 href 原样。
    const resolveLink = (href) => EpubNoteLink.create(href.startsWith('#') ? 'Text/ch1.xhtml' :
      `Text/${EpubHtmlConverter.withoutFragment(href)}`, EpubHtmlConverter.fragmentOf(href));
    const withNotes = (body) => EpubHtmlConverter.convertBody(body, resolve, '', '', resolveLink).content;
    // 标记显示成 {文字→文件#锚点}，便于断言。
    const readable = (text) => text.replace(/\[\[LEGADO_READER_ACTION_V3:[^\]]+\]\]/g, (raw) => {
      const data = ReaderActionMarker.parse(raw);
      const target = data ? EpubNoteLink.parse(data.url) : null;
      return target ? `{${data.label}→${target.path}#${target.fragment}}` : raw;
    });
    const plainOf = (text) => text.replace(/\[\[LEGADO_READER_ACTION_V3:[^\]]+\]\]/g,
      (raw) => ReaderActionMarker.parse(raw).label);

    const epub3 = '<p>正文<a epub:type="noteref" href="#fn1">1</a>继续。</p>' +
      '<aside epub:type="footnote" id="fn1"><p>注释一</p></aside><p>下一段</p>';
    equal(readable(withNotes(epub3)), '正文{1→Text/ch1.xhtml#fn1}继续。\n\n下一段',
      'EPUB3 noteref 变成注释标记，被引用的 aside 脚注不再留在正文里');
    equal(readable(withNotes('<p>正文<sup><a href="#n2">2</a></sup>，<a href="notes.xhtml#n3">[3]</a>，' +
      '见<a href="ch2.xhtml#s1">第二章</a>。</p>')),
      '正文{²→Text/ch1.xhtml#n2}，{[3]→Text/notes.xhtml#n3}，见第二章。',
      '上标编号与跨文件尾注识别为注释，普通章节链接仍是文字');
    equal(readable(withNotes('<p>多看<a class="duokan-footnote" href="#df-1"><img src="gaiji.png"/></a>文字</p>' +
      '<ol class="duokan-footnote-content"><li id="df-1"><p><a href="#dfref-1">◎</a>多看注释</p></li></ol>')),
      '多看{注→Text/ch1.xhtml#df-1}文字', '只有图标的注释显示成“注”，多看注释列表不留在正文里');
    equal(readable(withNotes('<p id="r1"><a href="text.xhtml#ref1">[1]</a>尾注条目</p><p>正文<a href="#x">①</a>。</p>')),
      '[1]尾注条目\n\n正文{①→Text/ch1.xhtml#x}。', '尾注列表开头返回正文的编号不当注释');
    equal(readable(withNotes('<p>见<a href="#fn9" epub:type="noteref">1</a></p><aside epub:type="footnote" id="other">' +
      '<p>无人引用</p></aside>')), '见{1→Text/ch1.xhtml#fn9}\n\n无人引用', '没被引用的 aside 照常显示');
    equal(EpubHtmlConverter.convertBody(epub3, resolve).content, '正文1继续。\n\n注释一\n\n下一段',
      '不传链接解析时与以前的转换结果一致');

    const notes = '<aside epub:type="footnote" id="fn1"><p><a epub:type="backlink" href="#r">1</a>. 注释一内容</p></aside>' +
      '<p class="note"><a id="n5" href="#r5">[5]</a>第五条注释</p>' +
      '<p><a id="n6"></a>第六条<br/><a id="n7"></a>第七条</p>' +
      '<div><a id="n8"></a></div><p>第八条在后面一段</p>';
    const note = (id) => EpubHtmlConverter.convertNote(notes, id, resolve).content;
    equal(note('fn1'), '注释一内容', 'aside 注释去掉返回链接与开头标点');
    equal(note('n5'), '第五条注释', '锚点在段内链接上时取整段并去掉编号');
    equal(note('n6'), '第六条', '同一段里排着多条注释时只取到下一个锚点');
    equal(note('n7'), '第七条', '同一段里的最后一条注释');
    equal(note('n8'), '第八条在后面一段', '锚点所在块没有文字时取后面一段');
    equal(note('missing'), '', '找不到锚点时返回空');

    const oldText = EpubHtmlConverter.convertBody(epub3, resolve).content;
    const newText = withNotes(epub3);
    equal(plainOf(newText), '正文1继续。\n\n下一段', '标记换回显示文字后只少了脚注块');
    equal(EpubTextOffsetMap.map(oldText, newText, 2), 2, '注释编号之前的偏移不变');
    const afterNote = newText.indexOf('继续');
    equal(EpubTextOffsetMap.map(oldText, newText, oldText.indexOf('继续')), afterNote, '注释编号之后的偏移跳过标记');
    equal(EpubTextOffsetMap.map(oldText, newText, oldText.indexOf('下一段')), newText.indexOf('下一段'),
      '被去掉的脚注块之后的偏移对齐到新正文');
    equal(EpubTextOffsetMap.map(oldText, newText, oldText.indexOf('注释一') + 1), newText.indexOf('下一段'),
      '落在被去掉的脚注块里的偏移归到它后面');
    equal(readable(withNotes('<p>页<a id="pg1"/>码<a href="#n1">1</a>。</p><p id="n1">注</p>')),
      '页码{1→Text/ch1.xhtml#n1}。\n\n注', '没有结束标签的 <a id/> 不吞掉后面的注释链接');

    // 单文件几千条注释：每个注释链接都查锚点是否在 aside 里，不能每次从头扫文件。
    const count = 8000;
    const parts = [];
    for (let n = 0; n < count; n++) parts.push(`<p>正文${n}<a href="#n${n}" id="r${n}">[${n}]</a>继续。</p><a id="p${n}"></a>`);
    parts.push('<aside>');
    for (let n = 0; n < count; n++) parts.push(`<p id="n${n}"><a href="#r${n}">[${n}]</a>注释${n}</p>`);
    parts.push('</aside>');
    EpubHtmlConverter.clearAnchorIndex();
    const started = performance.now();
    const big = withNotes(parts.join(''));
    const elapsed = performance.now() - started;
    equal((big.match(/\[\[LEGADO_READER_ACTION_V3:/g) || []).length, count, `${count} 个注释编号都换成注释标记`);
    // 改前同一用例约 15 秒（主线程卡死被系统杀掉），改后约 200ms。
    check(elapsed < 1500, `单文件 ${count} 条注释转换耗时 ${elapsed.toFixed(0)}ms`);
  }

  console.log('original layout');
  {
    const piece = new EpubOriginalPiece();
    piece.path = 'OEBPS/Text/ch1.xhtml';
    piece.html = '<?xml version="1.0"?><html xmlns="http://www.w3.org/1999/xhtml" lang="zh"><head><title>x</title>' +
      '<link rel="stylesheet" href="../Styles/main.css"/><link rel="alternate stylesheet" href="../Styles/alt.css"/>' +
      '<style>p{background:url(../Images/bg.png)}</style><script src="a.js"></script></head>' +
      '<body class="c1"><h1 id="t">标题</h1><p>正文<a href="#fn1">1</a><a id="p2"/>后文<img src="../Images/a.jpg"/></p>' +
      '<div style="background-image:url(\'../Images/b.png\')" onclick="x()">x</div><a href="http://e.com">外</a>' +
      '<a href="/OEBPS/x.xhtml">根</a><script>alert(1)</script><p id="end">尾</p></body></html>';
    const segment = new EpubChapterSegment();
    segment.path = piece.path;
    segment.endId = 'end';
    const html = EpubOriginalDocument.build([piece], [segment], EpubOriginalScript.injection(new EpubOriginalLayoutOptions()),
      '第一章');
    const origin = EpubOriginalDocument.ORIGIN;
    check(html.includes(`<link rel="stylesheet" href="${origin}/OEBPS/Styles/main.css">`), '样式表地址改成虚拟站点的绝对地址');
    check(!html.includes('alt.css'), '备用样式表不引入');
    check(html.includes(`url(${origin}/OEBPS/Images/bg.png)`) && html.includes(`url('${origin}/OEBPS/Images/b.png')`),
      '<style> 与内联样式里的 url() 都改写');
    check(html.includes(`href="${origin}/OEBPS/Text/ch1.xhtml#fn1"`), '本文件锚点链接带上文件路径，点开时能找到目标');
    check(html.includes(`href="${origin}/OEBPS/x.xhtml"`) && html.includes('href="http://e.com"'), '根路径改写，外部链接不动');
    check(html.includes('<a id="p2"></a>后文'), '非空元素的自闭合写法改成成对标签');
    check(!/alert\(1\)|a\.js|onclick/.test(html), '书里的脚本与事件属性都去掉');
    check(html.includes('<body class="c1">') && html.includes('lang="zh"') && !html.includes('id="end"'),
      '保留 html/body 属性，按锚点只取本章片段');
    equal(EpubOriginalDocument.pathOf(`${origin}/OEBPS/Text/ch%201.xhtml#fn1`), 'OEBPS/Text/ch 1.xhtml', '虚拟地址还原路径');
    equal(EpubOriginalDocument.pathOf(`${origin}/../secret`), '', '越出解压目录的地址不放行');
    equal(EpubOriginalDocument.pathOf('https://example.com/a.css'), '', '其它站点不放行');
    check(EpubOriginalDocument.isChapterUrl(EpubOriginalDocument.chapterUrl(3, 7)), '章节文档地址可识别');
    check(EpubOriginalDocument.isScript('OEBPS/js/a.js'), '脚本文件识别为不放行');
    let scriptOk = true;
    try {
      new Function(EpubOriginalScript.injection(new EpubOriginalLayoutOptions()).script);
    } catch (error) {
      scriptOk = false;
      console.error(error);
    }
    check(scriptOk, '注入脚本语法正确');
    const tricky = new EpubOriginalLayoutOptions();
    tricky.target.kind = 'spot';
    tricky.target.snippet = '$&</script>';
    const trickyScript = EpubOriginalScript.injection(tricky).script;
    check(!trickyScript.includes('</script>') && trickyScript.includes('$&'), '定位文字里的 </script> 与 $& 不破坏脚本');
    const baseScript = EpubOriginalScript.injection(new EpubOriginalLayoutOptions()).script;
    check(/speechInfo: speechInfo, ttsMark: ttsMark, ttsClear: ttsClear/.test(baseScript), '朗读取字、高亮与清除接口挂在 __legado 上');
    equal(EpubOriginalScript.ttsMarkColor('#0A59F7', false), 'rgba(10,89,247,0.3)', '朗读高亮色：#RRGGBB 浅色');
    equal(EpubOriginalScript.ttsMarkColor('#FF3D7BFF', true), 'rgba(61,123,255,0.42)', '朗读高亮色：#AARRGGBB 去掉透明度');
    check(EpubOriginalScript.ttsMarkColor('bogus', false).startsWith('rgba('), '朗读高亮色：无法解析时用默认色');

    // 夜间图片：深色时各模式给插图的滤镜，以及自动模式的判断。
    const nightStyle = (mode) => {
      const options = new EpubOriginalLayoutOptions();
      options.forceDark = true;
      options.nightImage = mode;
      return EpubOriginalScript.injection(options);
    };
    check(nightStyle('original').style.includes('img,video,canvas,svg image') &&
      nightStyle('original').style.includes('invert(1) hue-rotate(180deg)!important'), '夜间图片保持原色：插图反回来');
    check(nightStyle('dim').style.includes('brightness(0.8) invert(1)'), '夜间图片调暗：先压暗再反回来');
    check(!nightStyle('invert').style.includes('invert(1)'), '夜间图片反色：插图不再反回来');
    const autoInjection = nightStyle('auto');
    check(autoInjection.style.includes('[data-legado-night="invert"]{filter:none') &&
      autoInjection.script.includes('"auto":true'), '夜间图片自动：默认调暗、标记为反色的不加滤镜，脚本开启判断');
    check(!nightStyle('bogus').style.includes('brightness('), '未知取值按保持原色处理');
    const lightOptions = new EpubOriginalLayoutOptions();
    lightOptions.nightImage = 'invert';
    check(!EpubOriginalScript.injection(lightOptions).style.includes('invert('), '浅色时不加任何反色样式');
    let autoScriptOk = true;
    try {
      new Function(autoInjection.script);
    } catch (error) {
      autoScriptOk = false;
      console.error(error);
    }
    check(autoScriptOk, '自动模式注入脚本语法正确');
    const pixels = (count, rgba) => {
      const data = new Uint8Array(count * 4);
      for (let i = 0; i < count; i++) data.set(rgba(i), i * 4);
      return data;
    };
    check(ReaderNightImage.shouldInvert(pixels(400, (i) => i % 10 === 0 ? [20, 20, 20, 255] : [250, 250, 250, 255])),
      '白底黑线的图判为反色');
    check(!ReaderNightImage.shouldInvert(pixels(400, (i) => [40 + (i % 120), 90, 160 - (i % 80), 255])),
      '深色彩色照片不反色');
    check(!ReaderNightImage.shouldInvert(pixels(400, (i) => i % 3 === 0 ? [230, 60, 60, 255] : [245, 245, 245, 255])),
      '浅底但大面积彩色的插画不反色');
    check(ReaderNightImage.shouldInvert(pixels(400, (i) => i % 8 === 0 ? [0, 0, 0, 255] : [0, 0, 0, 0])),
      '透明底黑线稿按白底合成后判为反色');
    const invert = ReaderNightImage.invertMatrix();
    const apply = (rgb) => [0, 1, 2].map((row) => Math.max(0, Math.min(1,
      invert[row * 5] * rgb[0] + invert[row * 5 + 1] * rgb[1] + invert[row * 5 + 2] * rgb[2] + invert[row * 5 + 4])));
    check(apply([1, 1, 1]).every((v) => Math.abs(v - 0.08) < 0.01) && apply([0, 0, 0]).every((v) => Math.abs(v - 0.92) < 0.01),
      '反色矩阵：白变深灰、黑变浅灰');
    const red = apply([0.9, 0.1, 0.1]);
    check(red[0] > red[1] && red[0] > red[2], '反色矩阵保留色相（红仍偏红）');

    const content = `标题\n\n正文${ReaderActionMarker.create('1', 'legado-epub-note:a#b')}后文¹ 很长的一段内容在这里继续写下去，` +
      '一直写到足够长的位置。';
    const spot = EpubOriginalPosition.spotAt(content, content.indexOf('后文'));
    check(spot.snippet.startsWith('后文1很长'), '普通阅读器偏移换成紧凑文字片段（上标统一成数字、去掉空白）');
    equal(EpubOriginalPosition.offsetFor(content, spot), content.indexOf('后文'), '片段换回同一个偏移');
    const webSpot = new EpubOriginalSpot();
    webSpot.snippet = '很长的一段内容在这里继续写下去';
    webSpot.fraction = 0.5;
    equal(EpubOriginalPosition.offsetFor(content, webSpot), content.indexOf('很长'), '网页回报的片段找到普通正文里的位置');
    const missing = new EpubOriginalSpot();
    missing.snippet = '完全不存在的文字片段';
    missing.fraction = 1;
    check(EpubOriginalPosition.offsetFor(content, missing) > content.indexOf('很长'), '找不到片段时按比例定位');
  }

  // 单文件上千章：按锚点切章不再随章数平方增长
  {
    const count = 3000;
    const parts = [];
    const entries = [];
    for (let n = 1; n <= count; n++) {
      parts.push(`<h2 id="c${n}">第${n}章</h2><p>${'正文'.repeat(40)}</p>`);
      entries.push(toc('/big.xhtml', `c${n}`, `第${n}章`));
    }
    const started = performance.now();
    const planned = plan([{ path: '/big.xhtml', body: parts.join('') }], entries);
    const elapsed = performance.now() - started;
    equal(planned.chapters.length, count, '单文件 3000 个目录锚点切成 3000 章');
    equal(planned.chapters[count - 1].title, `第${count}章`, '最后一章标题正确');
    // 改前同一用例约 1.4 秒（每切一章都从头正则扫描整个文件），改后约 50ms。
    check(elapsed < 800, `单文件 3000 章切章耗时 ${elapsed.toFixed(0)}ms`);
  }
} finally {
  cleanup();
}

console.log(failures === 0 ? '\nALL CHECKS PASSED' : `\n${failures} CHECK(S) FAILED`);
process.exit(failures === 0 ? 0 : 1);
