import { EpubOriginalInjection } from './EpubOriginalDocument';
import { ReaderNightImage } from '../reader/ReaderNightImage';

/** 原版排版的页边距（CSS 像素，已含状态栏、导航条）。 */
export class EpubOriginalMargins {
  top: number = 24;
  right: number = 20;
  bottom: number = 24;
  left: number = 20;
}

/** 章节载入后要停在哪里：开头、末尾、一段文字（EpubOriginalSpot）或一个锚点。 */
export class EpubOriginalTarget {
  kind: string = 'start';
  snippet: string = '';
  fraction: number = 0;
  anchor: string = '';
}

export class EpubOriginalLayoutOptions {
  paged: boolean = true;
  /** 翻页模式下拖动与翻页动画由原生截图翻页层负责，网页只在原地换页（见 step / show）。 */
  nativeTurn: boolean = false;
  forceDark: boolean = false;
  /** 深色时插图怎么处理（ReaderNightImage 的值）；只在 forceDark 时有意义。 */
  nightImage: string = ReaderNightImage.ORIGINAL;
  /**
   * 用应用的阅读字体代替书里的字体：空串不改；'system' 用系统字体；其余是字体文件在虚拟站点里的地址。
   * 只换字体，字号、行距等仍按书的样式。
   */
  readerFont: string = '';
  /** 双翻页开关（与应用排版共用）；翻页模式下屏幕够宽时一屏并排两栏，见 SPREAD_MEDIA。 */
  spread: boolean = false;
  margins: EpubOriginalMargins = new EpubOriginalMargins();
  target: EpubOriginalTarget = new EpubOriginalTarget();
}

/** 自动模式在网页里逐张判断插图用的参数，与 ReaderNightImage.shouldInvert 相同。 */
class EpubOriginalNightConfig {
  auto: boolean = false;
  minLuma: number = ReaderNightImage.AUTO_MIN_LUMA;
  maxColorful: number = ReaderNightImage.AUTO_MAX_COLORFUL;
  spread: number = ReaderNightImage.AUTO_COLOR_SPREAD;
}

class EpubOriginalScriptConfig {
  paged: boolean = true;
  nativeTurn: boolean = false;
  night: EpubOriginalNightConfig = new EpubOriginalNightConfig();
  top: number = 0;
  bottom: number = 0;
  /** 双翻页生效的媒体查询；空串表示不并排。 */
  spreadQuery: string = '';
  target: EpubOriginalTarget = new EpubOriginalTarget();
}

/**
 * 嵌进章节文档的样式和脚本。书的样式在前，这里只追加分页需要的几条：
 * 翻页模式用 CSS 多栏把正文切成一屏宽的栏，翻页就是横向移动一栏；滚动模式只加页边距。
 * 脚本通过 LegadoEpubHost（javaScriptProxy）回报版面、位置、点击和链接，页面经 window.__legado 控制翻页。
 * 位置用“去掉空白、统一上下标数字”的紧凑文字表示，规则与 EpubOriginalPosition 一致。
 */
export class EpubOriginalScript {
  static readonly HOST_NAME: string = 'LegadoEpubHost';
  /**
   * 何时并排两栏，与应用排版 ReadBook.readerViewportFitsSpread 同一规则：比高宽，或接近方形且至少 600 宽
   * （书本式折叠屏展开时略高于宽）。写成媒体查询，折叠/旋转时网页自己切换，不用重载章节。
   */
  static readonly SPREAD_MEDIA: string = '(min-aspect-ratio: 1001/1000), (min-width: 600px) and (min-aspect-ratio: 4/5)';
  static readonly HOST_METHODS: string[] = ['ready', 'position', 'tap', 'link', 'edge', 'stepped'];
  /** 朗读高亮的底色：浅色页面正片叠底、深色页面滤色，字的颜色不受影响。 */
  static ttsMarkColor(accent: string, dark: boolean): string {
    const match = /^#(?:([0-9a-fA-F]{2}))?([0-9a-fA-F]{2})([0-9a-fA-F]{2})([0-9a-fA-F]{2})$/.exec(accent || '');
    const alpha = dark ? 0.42 : 0.3;
    if (!match) return dark ? `rgba(90,140,255,${alpha})` : `rgba(10,89,247,${alpha})`;
    return `rgba(${parseInt(match[2], 16)},${parseInt(match[3], 16)},${parseInt(match[4], 16)},${alpha})`;
  }

  static injection(options: EpubOriginalLayoutOptions): EpubOriginalInjection {
    const injection = new EpubOriginalInjection();
    injection.style = EpubOriginalScript.style(options);
    const config = new EpubOriginalScriptConfig();
    config.paged = options.paged;
    config.nativeTurn = options.paged && options.nativeTurn;
    config.night.auto = options.forceDark && ReaderNightImage.normalize(options.nightImage) === ReaderNightImage.AUTO;
    config.top = options.margins.top;
    config.bottom = options.margins.bottom;
    config.spreadQuery = options.paged && options.spread ? EpubOriginalScript.SPREAD_MEDIA : '';
    config.target = options.target;
    // 文字片段可能含有 "</script>"，按 JSON 转义尖括号。
    const json = JSON.stringify(config).replace(/</g, '\\u003c');
    // 用函数替换：文字片段里的 "$&" 之类不能被当成替换模式。
    injection.script = EpubOriginalScript.SCRIPT.replace('__LEGADO_CONFIG__', (): string => json);
    return injection;
  }

  /**
   * 双页中缝的书脊阴影，与应用排版 ReadBook.readerDoublePageSpine 同一组色标。挂在 html 上固定在屏幕中间，
   * 不随横向翻页移动，也在 body 之外，夜间整页反色不会把它变成亮条。
   */
  static spineStyle(dark: boolean): string {
    const k = dark ? 2.6 : 1;
    const shade = (alpha: number, at: number): string =>
      `rgba(0,0,0,${Math.min(0.4, alpha * k).toFixed(3)}) ${Math.round(at * 100)}%`;
    const stops = [shade(0, 0), shade(0.02, 0.22), shade(0.06, 0.42), shade(0.11, 0.5), shade(0.05, 0.57),
      shade(0.015, 0.76), shade(0, 1)].join(',');
    return 'html::after{content:"";position:fixed;top:0;bottom:0;left:calc(50% - 22px);width:44px;' +
      `pointer-events:none;z-index:2147483647;background:linear-gradient(to right,${stops});}`;
  }

  static style(options: EpubOriginalLayoutOptions): string {
    const m = options.margins;
    const px = (value: number): string => `${Math.max(0, Math.round(value))}px`;
    const padding = `${px(m.top)} ${px(m.right)} ${px(m.bottom)} ${px(m.left)}`;
    let css = options.paged ?
      'html{height:100vh!important;width:100vw!important;margin:0!important;padding:0!important;' +
        'overflow:hidden!important;touch-action:none;}' +
        'body{box-sizing:border-box!important;height:100vh!important;width:100vw!important;max-width:none!important;' +
        `min-height:0!important;margin:0!important;padding:${padding}!important;` +
        `column-width:calc(100vw - ${px(m.left + m.right)})!important;column-gap:${px(m.left + m.right)}!important;` +
        'column-fill:auto!important;overflow:visible!important;}' +
        `img,svg,video{max-width:100%!important;max-height:calc(100vh - ${px(m.top + m.bottom)})!important;` +
        'box-sizing:border-box;}img,video{object-fit:contain;}' +
        // 并排两栏：栏宽 = (一屏 - 两侧页边距 - 中缝) / 2，中缝取左右边距之和，翻一屏正好移过两栏。
        (options.spread ? `@media ${EpubOriginalScript.SPREAD_MEDIA}{body{column-width:auto!important;` +
          `column-count:2!important;}${EpubOriginalScript.spineStyle(options.forceDark)}}` : '') :
      'html{margin:0!important;padding:0!important;}' +
        `body{box-sizing:border-box!important;margin:0!important;padding:${padding}!important;max-width:none!important;}` +
        'img,svg,video{max-width:100%!important;box-sizing:border-box;}img,video{object-fit:contain;}';
    if (options.readerFont) {
      const family = options.readerFont === 'system' ? 'sans-serif' :
        '"LegadoReaderFont",sans-serif';
      if (options.readerFont !== 'system') {
        css += `@font-face{font-family:"LegadoReaderFont";src:url("${options.readerFont.replace(/"/g, '%22')}");}`;
      }
      css += `body,body *{font-family:${family}!important;}`;
    }
    // 不能写 text-size-adjust:none：它会连网页组件的文字缩放（textZoomRatio）一起关掉，字号缩放就失效了。
    css += 'html{-webkit-tap-highlight-color:transparent;}';
    if (options.forceDark) {
      // 应用处于深色模式时，与段评网页的夜间处理相同：整体反色（invert .92 + 色相转回）；翻页模式下 body 之外的栏露出的是 html 的底色。
      // 插图跟着整页一起被反色，再按“夜间图片”设置决定给它加什么滤镜：
      // 保持原色 = 先反回来；调暗 = 先压暗再反回来（整页反色后剩下压暗）；反色 = 不加，留着整页的反色；
      // 自动 = 默认按调暗，脚本判断为白底少色的图（标记 data-legado-night="invert"）不加。
      css += 'html{background:#141414!important;}body{filter:invert(.92) hue-rotate(180deg)!important;}';
      // 不含 picture：它里面的 img 已经有滤镜，再给外层加一次会叠两遍。
      const media = 'img,video,canvas,svg image,[style*="background-image"]';
      const keep = 'invert(1) hue-rotate(180deg)';
      const dim = `brightness(${ReaderNightImage.DIM_BRIGHTNESS}) invert(1) hue-rotate(180deg)`;
      const mode = ReaderNightImage.normalize(options.nightImage);
      if (mode === ReaderNightImage.ORIGINAL) {
        css += `${media}{filter:${keep}!important;}`;
      } else if (mode === ReaderNightImage.DIM) {
        css += `${media}{filter:${dim}!important;}`;
      } else if (mode === ReaderNightImage.AUTO) {
        css += `${media}{filter:${dim}!important;}` +
          '[data-legado-night="invert"]{filter:none!important;}';
      }
    }
    return css;
  }

  private static readonly SCRIPT: string = String.raw`(function () {
  var cfg = __LEGADO_CONFIG__;
  var host = window.LegadoEpubHost || null;
  var paged = cfg.paged, nativeTurn = !!cfg.nativeTurn;
  var page = 0, count = 1, width = 1, started = false, cache = null, reportTimer = 0;
  var SUP = '⁰¹²³⁴⁵⁶⁷⁸⁹', SUB = '₀₁₂₃₄₅₆₇₈₉';
  var NOTE = /^[\[［(（【〔〈]?\s*(?:注|註|note)?\s*(?:\d{1,4}|[０-９]{1,4}|[一二三四五六七八九十]{1,3}|[⁰¹²³⁴⁵⁶⁷⁸⁹]{1,4}|[①-⓿❶-➓㉑-㉟㊱-㊿]|[*＊†‡§]{1,3})?\s*[\]］)）】〕〉]?$/i;
  function norm(s) {
    var r = '';
    for (var i = 0; i < s.length; i++) {
      var c = s.charAt(i);
      if (/\s/.test(c) || c === '​' || c === '﻿') continue;
      var k = SUP.indexOf(c);
      if (k < 0) k = SUB.indexOf(c);
      r += k >= 0 ? String(k) : c;
    }
    return r;
  }
  function compact() {
    if (cache) return cache;
    var nodes = [], text = [], nodeOf = [], offOf = [];
    var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, { acceptNode: function (n) {
      for (var p = n.parentNode; p && p !== document.body; p = p.parentNode) {
        var t = p.nodeName.toLowerCase();
        if (t === 'rt' || t === 'rp' || t === 'script' || t === 'style') return NodeFilter.FILTER_REJECT;
      }
      return NodeFilter.FILTER_ACCEPT;
    } });
    var n;
    while ((n = walker.nextNode())) {
      var v = n.nodeValue || '';
      for (var j = 0; j < v.length; j++) {
        var c = norm(v.charAt(j));
        if (!c) continue;
        text.push(c); nodeOf.push(nodes.length); offOf.push(j);
      }
      nodes.push(n);
    }
    cache = { nodes: nodes, text: text.join(''), nodeOf: nodeOf, offOf: offOf };
    return cache;
  }
  function find(text, snippet, fraction) {
    var expected = fraction * text.length;
    for (var len = snippet.length; len >= 6; len = Math.floor(len / 2)) {
      var probe = snippet.substring(0, len), best = -1, i = text.indexOf(probe);
      while (i >= 0) {
        if (best < 0 || Math.abs(i - expected) < Math.abs(best - expected)) best = i;
        i = text.indexOf(probe, i + 1);
      }
      if (best >= 0) return best;
    }
    return -1;
  }
  function rectAt(c, index) {
    var node = c.nodes[c.nodeOf[index]], off = c.offOf[index];
    var range = document.createRange();
    range.setStart(node, off);
    range.setEnd(node, Math.min(node.nodeValue.length, off + 1));
    var rects = range.getClientRects();
    return rects.length ? rects[0] : range.getBoundingClientRect();
  }
  // 多栏排版时最后一栏右侧的页边距不计入可滚动宽度，最后一页滚不到 (count-1)×width，正文会整体偏右一个页边距。
  // 在第 count 页末尾放一个 1px 的占位撑开滚动宽度，最后一页才能停在正确位置。
  var spacer = null;
  function layout() {
    width = window.innerWidth || document.documentElement.clientWidth || 1;
    if (!paged) return;
    if (spacer) spacer.style.left = '0px';
    // 并排两栏时最后一屏可能只有左栏，scrollWidth 只到半屏多一点，四舍五入会丢掉这一屏，所以向上取整。
    var spread = !!cfg.spreadQuery && window.matchMedia && window.matchMedia(cfg.spreadQuery).matches;
    var screens = document.documentElement.scrollWidth / width;
    count = Math.max(1, spread ? Math.ceil(screens - 0.05) : Math.round(screens));
    if (!spacer) {
      spacer = document.createElement('div');
      spacer.setAttribute('aria-hidden', 'true');
      spacer.style.cssText = 'position:absolute;top:0;width:1px;height:1px;pointer-events:none;visibility:hidden;';
      document.documentElement.appendChild(spacer);
    }
    spacer.style.left = (count * width - 1) + 'px';
  }
  function pageOfRect(r) {
    return Math.max(0, Math.min(count - 1, Math.floor((r.left + window.scrollX + 1) / width)));
  }
  var anim = 0, animTimer = 0;
  function stopAnimation() {
    if (anim) cancelAnimationFrame(anim);
    if (animTimer) clearTimeout(animTimer);
    anim = 0; animTimer = 0;
  }
  // 不用浏览器的平滑滚动：没有帧可画时（页面在后台、渲染被节流）它会停在半路。
  // 自己按帧插值，再用定时器保证最后一定落在目标位置。
  function slideTo(x, y, smooth) {
    stopAnimation();
    if (!smooth) { window.scrollTo(x, y); return; }
    var fromX = window.scrollX, fromY = window.scrollY, begin = 0, duration = 220;
    var step = function (time) {
      if (!begin) begin = time;
      var k = Math.min(1, (time - begin) / duration), e = 1 - Math.pow(1 - k, 3);
      window.scrollTo(fromX + (x - fromX) * e, fromY + (y - fromY) * e);
      anim = k < 1 ? requestAnimationFrame(step) : 0;
    };
    anim = requestAnimationFrame(step);
    // scroll 事件也要等帧才发，滚动模式在落定后主动回报一次位置。
    animTimer = setTimeout(function () { stopAnimation(); window.scrollTo(x, y); if (!paged) report(); },
      duration + 120);
  }
  function scrollToY(y, smooth) {
    slideTo(0, Math.max(0, y), smooth);
  }
  // 滚动模式的“页”是一屏（扣掉上下边距与一行重叠），页数进度条与普通阅读器的滚动模式一样按屏计。
  function screenStep() {
    return Math.max(80, window.innerHeight - cfg.top - cfg.bottom - 32);
  }
  function screenCount() {
    var range = Math.max(0, document.documentElement.scrollHeight - window.innerHeight);
    return Math.max(1, Math.ceil(range / screenStep() - 0.01) + 1);
  }
  function goPage(n, smooth) {
    if (!paged) {
      var total = screenCount(), target = Math.max(0, Math.min(total - 1, n));
      scrollToY(target === total - 1 ? document.documentElement.scrollHeight : target * screenStep(), smooth);
      report();
      return;
    }
    page = Math.max(0, Math.min(count - 1, n));
    slideTo(page * width, 0, smooth);
    report();
  }
  function goSpot(snippet, fraction) {
    var c = compact(), index = c.text.length ? find(c.text, norm(snippet || ''), fraction || 0) : -1;
    if (paged) {
      if (index >= 0) goPage(pageOfRect(rectAt(c, index)), false);
      else goPage(Math.round((fraction || 0) * (count - 1)), false);
      return;
    }
    if (index >= 0) scrollToY(rectAt(c, index).top + window.scrollY - cfg.top, false);
    else scrollToY((fraction || 0) * (document.documentElement.scrollHeight - window.innerHeight), false);
    report();
  }
  function goAnchor(id) {
    var el = document.getElementById(id) || (document.getElementsByName(id) || [])[0];
    if (!el) return false;
    var r = el.getBoundingClientRect();
    if (paged) goPage(pageOfRect(r), false);
    else { scrollToY(r.top + window.scrollY - cfg.top, false); report(); }
    return true;
  }
  // 当前屏第一个可见字在紧凑文字里的下标。
  function firstVisible(c, measure) {
    var lo = 0, hi = c.text.length - 1;
    while (lo < hi) {
      var mid = (lo + hi) >> 1, r = measure ? measure(c, mid) : rectAt(c, mid);
      // 滚动模式以上边距那条线为准，和 goSpot 把目标放到的位置一致，保存再恢复不会一次次往上挪。
      var before = paged ? r.right <= 1 : (r.top + r.bottom) / 2 < cfg.top;
      if (before) lo = mid + 1; else hi = mid;
    }
    return lo;
  }
  function spot() {
    var c = compact(), total = c.text.length;
    if (!total) return { snippet: '', fraction: 0 };
    var lo = firstVisible(c);
    return { snippet: c.text.substr(lo, 32), fraction: lo / total };
  }
  // 书签用的预览：从当前屏第一个可见字起取一段原文（空白合并），不超过 90 字。
  function preview() {
    var c = compact();
    if (!c.text.length) return '';
    var i = firstVisible(c), nodeIndex = c.nodeOf[i], text = c.nodes[nodeIndex].nodeValue.substring(c.offOf[i]);
    while (text.replace(/\s+/g, '').length < 90 && ++nodeIndex < c.nodes.length) text += c.nodes[nodeIndex].nodeValue;
    text = text.replace(/\s+/g, ' ').trim();
    return text.length > 90 ? text.substring(0, 90) + '…' : text;
  }
  function report() {
    if (!started) return;
    if (reportTimer) clearTimeout(reportTimer);
    reportTimer = setTimeout(function () {
      reportTimer = 0;
      var s = spot();
      if (!paged) {
        var range = document.documentElement.scrollHeight - window.innerHeight;
        count = screenCount();
        page = window.scrollY >= range - 2 ? count - 1 : Math.min(count - 1, Math.round(window.scrollY / screenStep()));
        s.scroll = range > 0 ? window.scrollY / range : 0;
      }
      s.page = page; s.count = count;
      if (host) host.position(JSON.stringify(s));
    }, 200);
  }
  // 栏数是按 scrollWidth 估的；书里有超宽元素时可能多估一栏，当前页已经铺到内容末尾也算最后一页。
  function isLastPage() {
    return page >= count - 1 || (page + 1) * width >= document.documentElement.scrollWidth - 2;
  }
  function next(smooth) {
    if (!paged) return screen(1);
    if (!isLastPage()) goPage(page + 1, smooth);
    else { goPage(page, false); if (host) host.edge(1); }
  }
  function prev(smooth) {
    if (!paged) return screen(-1);
    if (page > 0) goPage(page - 1, smooth);
    else { goPage(0, false); if (host) host.edge(-1); }
  }
  function screen(direction) {
    var y = window.scrollY, h = window.innerHeight;
    var step = screenStep();
    if (direction > 0 && y + h >= document.documentElement.scrollHeight - 2) { if (host) host.edge(1); return; }
    if (direction < 0 && y <= 0) { if (host) host.edge(-1); return; }
    scrollToY(y + direction * step, true);
  }
  // 原生翻页层用：不带动画地换到相邻页 / 指定页，等网页按新位置画过一帧再回报 stepped(token, moved, page, count)。
  // 已在本章首尾时 moved 为 0，由原生层决定是否翻章。
  function settled(token, moved) {
    var done = false;
    // moved 回报 1 表示网页按新位置画过帧；2 表示一直没等到帧、靠定时器兜底（原生层会多等再截图）。
    var send = function (viaFrame) {
      if (done) return;
      done = true;
      if (host) host.stepped(token, moved ? (viaFrame ? 1 : 2) : 0, page, count);
    };
    if (!moved) { send(true); return; }
    requestAnimationFrame(function () { requestAnimationFrame(function () { send(true); }); });
    setTimeout(function () { send(false); }, 150);
  }
  function step(direction, token) {
    stopAnimation();
    var moved = false;
    if (direction > 0 && !isLastPage()) { goPage(page + 1, false); moved = true; }
    else if (direction < 0 && page > 0) { goPage(page - 1, false); moved = true; }
    settled(token, moved);
  }
  function show(n, token) {
    stopAnimation();
    goPage(n, false);
    settled(token, true);
  }
  // ---- 朗读：从正文取出要念的文字，记下每个字在网页里的位置，用来高亮正在念的句子、翻到它所在的页 ----
  // 段落之间用换行分开，段内空白合并成一个空格；注音、脚本样式与注释上标链接不念。
  var BLOCK = /^(?:address|article|aside|blockquote|body|caption|center|dd|details|dialog|div|dl|dt|fieldset|figcaption|figure|footer|form|h[1-6]|header|hr|li|main|nav|ol|p|pre|section|summary|table|tbody|td|tfoot|th|thead|tr|ul)$/;
  var speechCache = null, markLayer = null;
  function blockOf(node) {
    for (var p = node.parentNode; p && p !== document.body; p = p.parentNode) {
      if (p.nodeType === 1 && BLOCK.test(p.nodeName.toLowerCase())) return p;
    }
    return document.body;
  }
  function speech() {
    if (speechCache) return speechCache;
    var out = [], nodes = [], nodeOf = [], offOf = [], last = '', lastBlock = null, pendingBreak = false;
    var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT | NodeFilter.SHOW_ELEMENT, { acceptNode: function (n) {
      if (n.nodeType !== 1) return NodeFilter.FILTER_ACCEPT;
      var t = n.nodeName.toLowerCase();
      if (t === 'rt' || t === 'rp' || t === 'script' || t === 'style' || t === 'noscript') return NodeFilter.FILTER_REJECT;
      if (t === 'a' && n.hasAttribute('href') && isNote(n)) return NodeFilter.FILTER_REJECT;
      return t === 'br' ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_SKIP;
    } });
    var push = function (c, node, off) { out.push(c); nodeOf.push(node); offOf.push(off); last = c; };
    var n;
    while ((n = walker.nextNode())) {
      if (n.nodeType === 1) { pendingBreak = true; continue; }
      var v = n.nodeValue || '';
      if (!v) continue;
      var block = blockOf(n);
      if (lastBlock && block !== lastBlock) pendingBreak = true;
      lastBlock = block;
      var index = nodes.length;
      nodes.push(n);
      for (var j = 0; j < v.length; j++) {
        var c = v.charAt(j), code = v.charCodeAt(j);
        // 零宽空格、BOM、软连字符
        if (code === 0x200b || code === 0xfeff || code === 0xad) continue;
        if (/\s/.test(c)) {
          if (out.length && !pendingBreak && last !== ' ' && last !== '\n') push(' ', index, j);
          continue;
        }
        if (pendingBreak && out.length) {
          if (last === ' ') { out[out.length - 1] = '\n'; last = '\n'; }
          else if (last !== '\n') push('\n', index, j);
        }
        pendingBreak = false;
        push(c, index, j);
      }
    }
    speechCache = { text: out.join(''), nodes: nodes, nodeOf: nodeOf, offOf: offOf };
    return speechCache;
  }
  // 空格可能被排版折叠、量不出位置，用后面第一个字的位置。
  function speechRect(s, i) {
    while (i < s.text.length - 1 && /\s/.test(s.text.charAt(i))) i++;
    return rectAt(s, i);
  }
  function speechPageOf(s, i) {
    return pageOfRect(speechRect(s, i));
  }
  // 当前屏第一个要念的字，以及翻页模式下每一页第一个字的下标（让朗读在页边断句，翻页时不念半句）。
  function speechInfo() {
    var s = speech(), total = s.text.length, breaks = [];
    if (!total) return JSON.stringify({ text: '', start: 0, breaks: breaks });
    var start = firstVisible(s, speechRect);
    if (start >= total) start = 0;
    if (paged) {
      for (var p = 1; p < count; p++) {
        var lo = 0, hi = total;
        while (lo < hi) {
          var mid = (lo + hi) >> 1;
          if (speechPageOf(s, mid) < p) lo = mid + 1; else hi = mid;
        }
        if (lo > 0 && lo < total && (!breaks.length || breaks[breaks.length - 1] < lo)) breaks.push(lo);
      }
    }
    return JSON.stringify({ text: s.text, start: start, breaks: breaks });
  }
  function ttsClear() {
    if (markLayer && markLayer.parentNode) markLayer.parentNode.removeChild(markLayer);
    markLayer = null;
  }
  // 给正在念的那一段文字铺上底色（盖在 body 外面，不受夜间反色影响），滚动模式下顺带把它滚进屏幕。
  // 返回它开头所在的页，翻页模式由原生层决定要不要翻过去。
  function ttsMark(start, end, color, dark) {
    ttsClear();
    var s = speech(), total = s.text.length;
    if (!total) return JSON.stringify({ page: -1 });
    var a = Math.max(0, Math.min(total - 1, start)), b = Math.max(a, Math.min(total - 1, end - 1));
    while (a < b && /\s/.test(s.text.charAt(a))) a++;
    while (b > a && /\s/.test(s.text.charAt(b))) b--;
    var range = document.createRange();
    var endNode = s.nodes[s.nodeOf[b]];
    range.setStart(s.nodes[s.nodeOf[a]], s.offOf[a]);
    range.setEnd(endNode, Math.min(endNode.nodeValue.length, s.offOf[b] + 1));
    var rects = range.getClientRects();
    var layer = document.createElement('div');
    layer.setAttribute('aria-hidden', 'true');
    layer.style.cssText = 'position:absolute;left:0;top:0;width:0;height:0;pointer-events:none;z-index:2147483647;';
    var sx = window.scrollX, sy = window.scrollY, first = null, lastRect = null;
    for (var i = 0; i < rects.length; i++) {
      var r = rects[i];
      if (r.width < 1 || r.height < 1) continue;
      if (!first) first = r;
      lastRect = r;
      var box = document.createElement('div');
      box.style.cssText = 'position:absolute;border-radius:3px;background:' + color + ';' +
        'mix-blend-mode:' + (dark ? 'screen' : 'multiply') + ';' +
        'left:' + (r.left + sx - 1) + 'px;top:' + (r.top + sy) + 'px;width:' + (r.width + 2) + 'px;height:' + r.height + 'px;';
      layer.appendChild(box);
    }
    document.documentElement.appendChild(layer);
    markLayer = layer;
    if (!paged && first) {
      var top = cfg.top, bottom = window.innerHeight - cfg.bottom;
      if (first.top < top || lastRect.bottom > bottom) {
        scrollToY(first.top + window.scrollY - top - Math.round(Math.max(0, bottom - top) * 0.2), true);
      }
    }
    return JSON.stringify({ page: paged ? speechPageOf(s, a) : page });
  }
  function isNote(a) {
    var semantics = ((a.getAttribute('epub:type') || '') + ' ' + (a.getAttribute('role') || '')).toLowerCase();
    if (/\b(?:doc-)?backlink\b/.test(semantics)) return false;
    if (/\b(?:doc-)?noteref\b/.test(semantics)) return true;
    if (/footnote|endnote|noteref|note-ref|notelink/i.test(a.getAttribute('class') || '')) return true;
    var text = (a.textContent || '').replace(/\s+/g, ' ').trim();
    if (!text) return !!a.querySelector('img,image');
    return NOTE.test(text);
  }
  // 夜间图片“自动”：把每张插图缩小画进画布取样，白底少色的图标记为反色（样式里不再反回来）。
  // 插图都在虚拟站点同源，画布可以读像素；读不了就按调暗处理。
  function nightInvert(d) {
    var n = cfg.night, counted = 0, luma = 0, colorful = 0;
    for (var i = 0; i + 3 < d.length; i += 4) {
      var a = d[i + 3] / 255;
      var r = (d[i] * a + 255 * (1 - a)) / 255, g = (d[i + 1] * a + 255 * (1 - a)) / 255,
        b = (d[i + 2] * a + 255 * (1 - a)) / 255;
      luma += 0.2126 * r + 0.7152 * g + 0.0722 * b;
      if (Math.max(r, g, b) - Math.min(r, g, b) > n.spread) colorful++;
      counted++;
    }
    if (!counted) return true;
    return luma / counted >= n.minLuma && colorful / counted <= n.maxColorful;
  }
  function nightMark(target, source) {
    try {
      var w = 48, h = Math.max(1, Math.min(96, Math.round(48 * source.naturalHeight / Math.max(1, source.naturalWidth))));
      var canvas = document.createElement('canvas');
      canvas.width = w; canvas.height = h;
      var g = canvas.getContext('2d');
      g.drawImage(source, 0, 0, w, h);
      target.setAttribute('data-legado-night', nightInvert(g.getImageData(0, 0, w, h).data) ? 'invert' : 'keep');
    } catch (e) {
      target.setAttribute('data-legado-night', 'keep');
    }
  }
  function nightWhenLoaded(target, source) {
    if (source.complete && source.naturalWidth) nightMark(target, source);
    else source.addEventListener('load', function () { nightMark(target, source); }, { once: true });
  }
  function nightClassify() {
    if (!cfg.night || !cfg.night.auto) return;
    var images = document.images;
    for (var i = 0; i < images.length; i++) nightWhenLoaded(images[i], images[i]);
    var svgImages = document.querySelectorAll('svg image');
    for (var j = 0; j < svgImages.length; j++) {
      var node = svgImages[j];
      var href = node.getAttribute('href') || node.getAttribute('xlink:href') ||
        node.getAttributeNS('http://www.w3.org/1999/xlink', 'href');
      if (!href) continue;
      var probe = new Image();
      probe.src = new URL(href, document.baseURI).href;
      nightWhenLoaded(node, probe);
    }
  }
  function start() {
    if (started) return;
    started = true;
    nightClassify();
    layout();
    var t = cfg.target || {};
    if (t.kind === 'end') {
      if (paged) goPage(count - 1, false);
      else { scrollToY(document.documentElement.scrollHeight, false); report(); }
    } else if (t.kind === 'spot') {
      goSpot(t.snippet, t.fraction);
    } else if (!(t.kind === 'anchor' && goAnchor(t.anchor))) {
      if (paged) goPage(0, false); else { scrollToY(0, false); report(); }
    }
    // 定位完要等网页按新位置画过一帧再报就绪：立即报的话，原生层撤掉加载遮罩、上页截图时
    // 网页表面还是载入时画的章首，会闪一下章首再跳到进度处。后面的槽位可能不出帧，留个兜底。
    var announced = false;
    var announce = function () {
      if (announced) return;
      announced = true;
      if (host) host.ready(count, page);
    };
    requestAnimationFrame(function () { requestAnimationFrame(announce); });
    setTimeout(announce, 150);
  }
  var sx = 0, sy = 0, st = 0, base = 0, dragging = false, moved = false;
  // 滚动模式：已经在章末继续上拉、在章首继续下拉超过这个距离，就接着读下一章、上一章。
  var PULL = 72, pull = 0, atTop = false, atBottom = false;
  document.addEventListener('touchstart', function (e) {
    if (e.touches.length !== 1) { dragging = false; pull = 0; return; }
    sx = e.touches[0].clientX; sy = e.touches[0].clientY; st = Date.now();
    pull = 0;
    if (!paged) {
      atTop = window.scrollY <= 1;
      atBottom = window.scrollY + window.innerHeight >= document.documentElement.scrollHeight - 2;
    }
    if (paged) stopAnimation();
    base = page * width; dragging = paged; moved = false;
  }, { passive: true });
  document.addEventListener('touchmove', function (e) {
    if (!paged && e.touches.length === 1) {
      var dyPull = e.touches[0].clientY - sy;
      if (atBottom && dyPull < -PULL) pull = 1;
      else if (atTop && dyPull > PULL) pull = -1;
      else pull = 0;
      return;
    }
    if (!dragging) return;
    var dx = e.touches[0].clientX - sx, dy = e.touches[0].clientY - sy;
    if (!moved && Math.abs(dx) < 8 && Math.abs(dy) < 8) return;
    if (!moved && Math.abs(dy) > Math.abs(dx)) { dragging = false; return; }
    moved = true;
    // 原生翻页层跟手时网页不动，只记下“拖过”，免得松手后的 click 被当成点按。
    if (!nativeTurn) window.scrollTo(base - dx, 0);
  }, { passive: true });
  document.addEventListener('touchend', function (e) {
    if (!paged) {
      // 手指离开时内容仍在章末（或章首）才翻章，避免一次正常的快速滑动被当成翻章。
      var stillBottom = window.scrollY + window.innerHeight >= document.documentElement.scrollHeight - 2;
      var direction = pull > 0 && stillBottom ? 1 : (pull < 0 && window.scrollY <= 1 ? -1 : 0);
      pull = 0;
      if (direction !== 0) { moved = true; if (host) host.edge(direction); }
      return;
    }
    if (!dragging || !moved) { dragging = false; return; }
    dragging = false;
    if (nativeTurn) return;
    var dx = e.changedTouches[0].clientX - sx;
    var flick = Math.abs(dx) > width * 0.18 || (Math.abs(dx) > 30 && Date.now() - st < 250);
    if (flick && dx < 0) next(true);
    else if (flick && dx > 0) prev(true);
    else goPage(page, true);
  }, { passive: true });
  document.addEventListener('click', function (e) {
    if (moved) { moved = false; e.preventDefault(); return; }
    var a = e.target && e.target.closest ? e.target.closest('a[href]') : null;
    if (a) {
      e.preventDefault();
      if (host) host.link(a.href, isNote(a) ? 1 : 0, e.clientX, e.clientY);
      return;
    }
    var selection = window.getSelection ? window.getSelection() : null;
    if (selection && !selection.isCollapsed) return;
    if (host) host.tap(e.clientX / Math.max(1, window.innerWidth), e.clientY / Math.max(1, window.innerHeight));
  }, true);
  window.addEventListener('scroll', function () { if (!paged) report(); }, { passive: true });
  window.addEventListener('resize', function () {
    if (!started) return;
    var s = spot();
    cache = null;
    speechCache = null;
    ttsClear();
    layout();
    goSpot(s.snippet, s.fraction);
  });
  window.__legado = { next: next, prev: prev, goSpot: goSpot, goAnchor: goAnchor, goPage: goPage, screen: screen,
    preview: preview, step: step, show: show, speechInfo: speechInfo, ttsMark: ttsMark, ttsClear: ttsClear };
  var begin = function () {
    if (document.fonts && document.fonts.ready) document.fonts.ready.then(start, start); else start();
  };
  if (document.readyState === 'complete') begin(); else window.addEventListener('load', begin);
  setTimeout(start, 4000);
})();`;
}
