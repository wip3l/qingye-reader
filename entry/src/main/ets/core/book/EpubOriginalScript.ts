import { EpubOriginalInjection } from './EpubOriginalDocument';

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
  forceDark: boolean = false;
  margins: EpubOriginalMargins = new EpubOriginalMargins();
  target: EpubOriginalTarget = new EpubOriginalTarget();
}

class EpubOriginalScriptConfig {
  paged: boolean = true;
  top: number = 0;
  bottom: number = 0;
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
  static readonly HOST_METHODS: string[] = ['ready', 'position', 'tap', 'link', 'edge'];

  static injection(options: EpubOriginalLayoutOptions): EpubOriginalInjection {
    const injection = new EpubOriginalInjection();
    injection.style = EpubOriginalScript.style(options);
    const config = new EpubOriginalScriptConfig();
    config.paged = options.paged;
    config.top = options.margins.top;
    config.bottom = options.margins.bottom;
    config.target = options.target;
    // 文字片段可能含有 "</script>"，按 JSON 转义尖括号。
    const json = JSON.stringify(config).replace(/</g, '\\u003c');
    // 用函数替换：文字片段里的 "$&" 之类不能被当成替换模式。
    injection.script = EpubOriginalScript.SCRIPT.replace('__LEGADO_CONFIG__', (): string => json);
    return injection;
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
        'box-sizing:border-box;}img,video{object-fit:contain;}' :
      'html{margin:0!important;padding:0!important;}' +
        `body{box-sizing:border-box!important;margin:0!important;padding:${padding}!important;max-width:none!important;}` +
        'img,svg,video{max-width:100%!important;box-sizing:border-box;}img,video{object-fit:contain;}';
    // 不能写 text-size-adjust:none：它会连网页组件的文字缩放（textZoomRatio）一起关掉，字号缩放就失效了。
    css += 'html{-webkit-tap-highlight-color:transparent;}';
    if (options.forceDark) {
      // 应用处于深色模式时，与段评网页的夜间处理相同：整体反色，图片再反回来；翻页模式下 body 之外的栏露出的是 html 的底色。
      css += 'html{background:#141414!important;}body{filter:invert(.92) hue-rotate(180deg)!important;}' +
        'img,video,picture,canvas,svg image,[style*="background-image"]{filter:invert(1) hue-rotate(180deg)!important;}';
    }
    return css;
  }

  private static readonly SCRIPT: string = String.raw`(function () {
  var cfg = __LEGADO_CONFIG__;
  var host = window.LegadoEpubHost || null;
  var paged = cfg.paged;
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
  function layout() {
    width = window.innerWidth || document.documentElement.clientWidth || 1;
    if (paged) count = Math.max(1, Math.round(document.documentElement.scrollWidth / width));
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
  function firstVisible(c) {
    var lo = 0, hi = c.text.length - 1;
    while (lo < hi) {
      var mid = (lo + hi) >> 1, r = rectAt(c, mid);
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
  function isNote(a) {
    var semantics = ((a.getAttribute('epub:type') || '') + ' ' + (a.getAttribute('role') || '')).toLowerCase();
    if (/\b(?:doc-)?backlink\b/.test(semantics)) return false;
    if (/\b(?:doc-)?noteref\b/.test(semantics)) return true;
    if (/footnote|endnote|noteref|note-ref|notelink/i.test(a.getAttribute('class') || '')) return true;
    var text = (a.textContent || '').replace(/\s+/g, ' ').trim();
    if (!text) return !!a.querySelector('img,image');
    return NOTE.test(text);
  }
  function start() {
    if (started) return;
    started = true;
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
    window.scrollTo(base - dx, 0);
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
    layout();
    goSpot(s.snippet, s.fraction);
  });
  window.__legado = { next: next, prev: prev, goSpot: goSpot, goAnchor: goAnchor, goPage: goPage, screen: screen,
    preview: preview };
  var begin = function () {
    if (document.fonts && document.fonts.ready) document.fonts.ready.then(start, start); else start();
  };
  if (document.readyState === 'complete') begin(); else window.addEventListener('load', begin);
  setTimeout(start, 4000);
})();`;
}
