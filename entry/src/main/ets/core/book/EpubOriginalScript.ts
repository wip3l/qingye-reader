import { EpubOriginalInjection } from './EpubOriginalDocument';
import { ReaderNightImage } from '../reader/ReaderNightImage';
import { EpubDuokanExtensions } from './EpubDuokanExtensions';
import { EpubOriginalFont } from './EpubOriginalFont';

/** 原版排版的页边距（CSS 像素，已含状态栏、导航条）。 */
export class EpubOriginalMargins {
  top: number = 24;
  right: number = 20;
  bottom: number = 24;
  left: number = 20;

  /** 四边都不留（多看全屏页）。 */
  static none(): EpubOriginalMargins {
    const margins = new EpubOriginalMargins();
    margins.top = 0;
    margins.right = 0;
    margins.bottom = 0;
    margins.left = 0;
    return margins;
  }
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
   * 代替书里字体的字体：空串不改；'sans' / 'serif' 用系统黑体 / 宋体（旧值 'system' 同 'sans'）；
   * 其余是字体文件在虚拟站点里的地址。只换字体，字号、行距等仍按书的样式。见 EpubOriginalFont。
   */
  readerFont: string = '';
  /**
   * 只换正文：脚本按字数找出正文用的字体，只给用这款字体（或网页默认字体）、字号不比正文大一截、
   * 不在标题/注音/代码里的元素标上 data-legado-font；书里单独设了字体的文字保持原样。false 则全部文字都换。
   */
  readerFontBodyOnly: boolean = true;
  /** 双翻页开关（与应用排版共用）；翻页模式下屏幕够宽时一屏并排两栏，见 SPREAD_MEDIA。 */
  spread: boolean = false;
  margins: EpubOriginalMargins = new EpubOriginalMargins();
  target: EpubOriginalTarget = new EpubOriginalTarget();
  /** 多看全屏页（duokan-page-fullscreen）：页面传进来的页边距为零；只有一张图时脚本让它铺满屏幕。 */
  fullscreen: boolean = false;
  /** 多看“~slim”图的虚拟地址对照（下标一一对应），全屏页在瘦长屏幕上换用 slimTo。 */
  slimFrom: string[] = [];
  slimTo: string[] = [];
  /** 书里的音频由原生播放器放（见 EpubAudioPlayer）：载入时它正在放哪个（虚拟地址）、playing / paused，空串表示没有。 */
  mediaSrc: string = '';
  mediaState: string = '';
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
  /** 只换正文的字体（见 EpubOriginalLayoutOptions.readerFontBodyOnly）。 */
  fontBody: boolean = false;
  night: EpubOriginalNightConfig = new EpubOriginalNightConfig();
  top: number = 0;
  bottom: number = 0;
  /** 双翻页生效的媒体查询；空串表示不并排。 */
  spreadQuery: string = '';
  target: EpubOriginalTarget = new EpubOriginalTarget();
  fullscreen: boolean = false;
  slimFrom: string[] = [];
  slimTo: string[] = [];
  slimRatio: number = EpubDuokanExtensions.SLIM_MIN_RATIO;
  mediaSrc: string = '';
  mediaState: string = '';
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
  static readonly HOST_METHODS: string[] = ['ready', 'position', 'tap', 'link', 'edge', 'stepped', 'gallery',
    'media'];
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
    config.fontBody = !!options.readerFont && options.readerFontBodyOnly;
    config.night.auto = options.forceDark && ReaderNightImage.normalize(options.nightImage) === ReaderNightImage.AUTO;
    config.top = options.margins.top;
    config.bottom = options.margins.bottom;
    config.spreadQuery = options.paged && options.spread ? EpubOriginalScript.SPREAD_MEDIA : '';
    config.target = options.target;
    config.fullscreen = options.fullscreen;
    config.slimFrom = options.slimFrom;
    config.slimTo = options.slimTo;
    config.mediaSrc = options.mediaSrc;
    config.mediaState = options.mediaState;
    // 文字片段可能含有 "</script>"，按 JSON 转义尖括号。
    const json = JSON.stringify(config).replace(/</g, '\\u003c');
    // 用函数替换：文字片段里的 "$&" 之类不能被当成替换模式。
    injection.script = EpubOriginalScript.SCRIPT.replace('__LEGADO_CONFIG__', (): string => json);
    return injection;
  }

  /**
   * 双页中缝的书脊阴影，与应用排版 ReaderSpreadSpine 同一组色标。挂在 html 上固定在屏幕中间，
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

  /**
   * 多看画廊（div.duokan-image-gallery 里的若干 div.duokan-image-gallery-cell）：脚本把各格叠成一摞卡片
   * （网格里同占一格），当前一张在最前，前后两张缩小藏在后面、从两侧露边，左右滑动换卡，下面一排小点标出第几张。
   * 只有两格以上的画廊会被改造（加 legado-gallery 类）。翻页模式下整个画廊不跨栏，图片再让出说明文字与小点的高度。
   * 卡片甩出去时可以越过画廊、盖住页边距，但裁在页边之内，不会画到相邻的栏、也不会撑出横向滚动。
   */
  static galleryStyle(options: EpubOriginalLayoutOptions): string {
    const m = options.margins;
    const side = Math.max(0, Math.round(Math.max(m.left, m.right))) + 12;
    const height = options.paged ? '.legado-gallery-track img,.legado-gallery-track svg,.legado-gallery-track video{' +
      `max-height:calc(100vh - ${Math.max(0, Math.round(m.top + m.bottom))}px - 7em)!important;}` : '';
    return '.legado-gallery{position:relative;break-inside:avoid;-webkit-column-break-inside:avoid;touch-action:pan-y;' +
      `overflow:clip!important;overflow-clip-margin:${side}px;}` +
      '.legado-gallery-track{display:grid!important;grid-template-columns:100%;align-items:center;width:100%;' +
      'position:relative;}' +
      '.legado-gallery-track>*{grid-area:1/1!important;min-width:0!important;max-width:100%!important;' +
      'box-sizing:border-box!important;margin-left:0!important;margin-right:0!important;float:none!important;' +
      'transform-origin:50% 50%;will-change:transform,opacity;backface-visibility:hidden;}' +
      // 后面的卡片只露出图，说明文字随换卡淡入淡出（脚本按进度设 --legado-gallery-caption）。
      '.legado-gallery-track>*>:not(img):not(svg):not(video):not(picture){' +
      'opacity:var(--legado-gallery-caption,1);}' +
      height +
      '.legado-gallery-dots{display:flex;justify-content:center;align-items:center;gap:6px;margin:.4em 0 .2em;' +
      'height:6px;line-height:0;text-indent:0;}' +
      // 小点用中灰：书里的字色可能和画廊背后的底图一样深（黑字压在暗色背景图上），跟字色会看不见。
      '.legado-gallery-dots>span{display:block;width:6px;height:6px;border-radius:3px;background:#8C8C8C;' +
      'opacity:.45;transition:opacity .2s,width .2s;}' +
      '.legado-gallery-dots>span.on{width:14px;opacity:.95;}';
  }

  /**
   * 多看出血与全屏页用的样式。出血属性在交给网页前已改写成 --legado-bleed（EpubDuokanExtensions），
   * 登记成不继承，脚本读到的就是元素自己写的值。全屏页只有一张图时，脚本换成 .legado-fullscreen 铺满一屏。
   */
  static duokanStyle(): string {
    return `@property ${EpubDuokanExtensions.BLEED_PROPERTY}{syntax:"*";inherits:false;}` +
      '.legado-fullscreen{display:block;width:100vw;height:100vh;margin:0;padding:0;' +
      'background-position:center;background-repeat:no-repeat;background-size:contain;}';
  }

  /**
   * 书里的音频（多看写法 <audio class="duokan-audio" placeholder="封面图" activestate="播放时的图" title="曲名">）：
   * <audio> 本身没有 controls 时网页什么都不画，脚本在它前面放一块可点的卡片——有封面图就是整张图，没有就是一条带曲名的横条；
   * 右上角的小圆标表示状态（♪ 未播放、暂停竖线 = 正在放、三角 = 已暂停），播放时底边一条进度线。
   * 曲名、圆标都用伪元素画，不进正文文字，位置换算与朗读取字不受影响。
   */
  static mediaStyle(): string {
    return 'audio{display:none!important;}' +
      '.legado-audio{position:relative;display:block;margin:.6em 0;text-indent:0;line-height:0;cursor:pointer;' +
      'break-inside:avoid;-webkit-column-break-inside:avoid;-webkit-user-select:none;user-select:none;}' +
      '.legado-audio>img.legado-audio-cover{display:block;width:100%;height:auto;margin:0;}' +
      '.legado-audio.legado-audio-pill{display:flex;align-items:center;min-height:44px;padding:0 48px 0 14px;' +
      'border-radius:12px;background:rgba(128,128,128,.14);overflow:hidden;}' +
      '.legado-audio.legado-audio-pill::before{content:"\\266A  " attr(data-title);font-size:.95em;line-height:1.4;' +
      'white-space:nowrap;overflow:hidden;text-overflow:ellipsis;}' +
      '.legado-audio-badge{position:absolute;top:8px;right:8px;width:28px;height:28px;border-radius:14px;' +
      'background:rgba(0,0,0,.5);color:#FFF;font-size:15px;line-height:28px;text-align:center;pointer-events:none;}' +
      '.legado-audio-pill>.legado-audio-badge{top:50%;margin-top:-14px;}' +
      '.legado-audio-badge::before{content:"\\266A";}' +
      // 正在放：两条竖线；暂停：向右的三角（边框画的）。
      '.legado-audio[data-state="playing"]>.legado-audio-badge::before{content:"";position:absolute;left:9px;top:8px;' +
      'width:3px;height:12px;background:#FFF;box-shadow:7px 0 0 #FFF;}' +
      '.legado-audio[data-state="paused"]>.legado-audio-badge::before{content:"";position:absolute;left:11px;top:8px;' +
      'border-style:solid;border-width:6px 0 6px 10px;border-color:transparent transparent transparent #FFF;}' +
      '.legado-audio-progress{position:absolute;left:0;bottom:0;height:3px;width:0;background:rgba(255,255,255,.9);' +
      'box-shadow:0 0 2px rgba(0,0,0,.5);pointer-events:none;}' +
      '.legado-audio[data-state="idle"]>.legado-audio-progress{display:none;}' +
      'video{background:#000;}';
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
    css += EpubOriginalScript.galleryStyle(options);
    css += EpubOriginalScript.duokanStyle();
    css += EpubOriginalScript.mediaStyle();
    if (options.readerFont) {
      const family = EpubOriginalFont.cssFamily(options.readerFont);
      if (EpubOriginalFont.isFileFont(options.readerFont)) {
        css += `@font-face{font-family:"LegadoReaderFont";src:url("${options.readerFont.replace(/"/g, '%22')}");}`;
      }
      css += options.readerFontBodyOnly ? `[data-legado-font]{font-family:${family}!important;}` :
        `body,body *{font-family:${family}!important;}`;
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
    // 画廊里没露出来的格子被轨道移到了画廊左右两侧，按字本身的位置会算到别的页上；画廊里的字一律按画廊算。
    var g = galleryOf(node);
    if (g) return g.el.getBoundingClientRect();
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
  // ---- 多看画廊：各格叠成一摞卡片，当前一张在最前，前后两张缩小一点藏在它后面、从左右两边露出一条边；
  // 拖动时当前这张跟着手指甩出去再缩到后面，相邻那张从后面放大到最前。首尾相接循环（样式见 galleryStyle）。
  // 翻页模式下拖动由原生翻页层接管，所以把当前屏上画廊的位置经 gallery() 报给原生层：从画廊上起手横滑时
  // 原生层不翻页，由这里切换；要翻页就从画廊外面滑。
  var galleries = [], galleryDrag = null, galleryCandidate = null, galleryDecided = false;
  var galleryJson = '', galleryAnim = null;
  // 两侧露出的卡片相对当前卡片的偏移、甩出去时最远的距离（都按画廊宽度的比例），以及后面卡片的缩放。
  var PEEK = 0.11, SWING = 0.6, BACK_SCALE = 0.9;
  function setupGalleries() {
    var list = document.querySelectorAll('.duokan-image-gallery');
    for (var i = 0; i < list.length; i++) {
      var el = list[i];
      if (el.__legadoGallery || galleryOf(el)) continue;
      var cells = [];
      for (var c = el.firstElementChild; c; c = c.nextElementSibling) {
        if (/(?:^|\s)duokan-image-gallery-cell(?:\s|$)/.test(c.getAttribute('class') || '')) cells.push(c);
      }
      if (cells.length < 2) continue;
      var track = document.createElement('div');
      track.className = 'legado-gallery-track';
      el.insertBefore(track, cells[0]);
      for (var j = 0; j < cells.length; j++) track.appendChild(cells[j]);
      var dots = document.createElement('div');
      dots.className = 'legado-gallery-dots';
      dots.setAttribute('aria-hidden', 'true');
      for (var k = 0; k < cells.length; k++) dots.appendChild(document.createElement('span'));
      el.insertBefore(dots, track.nextSibling);
      el.classList.add('legado-gallery');
      var state = { el: el, track: track, dots: dots, cells: cells, index: 0 };
      el.__legadoGallery = state;
      galleries.push(state);
      galleryShow(state, 0);
    }
  }
  function galleryOf(node) {
    if (!galleries.length) return null;
    for (var p = node; p && p !== document.body; p = p.parentNode) {
      if (p.__legadoGallery) return p.__legadoGallery;
    }
    return null;
  }
  function galleryCellOf(g, node) {
    for (var p = node; p && p !== g.el; p = p.parentNode) {
      var i = g.cells.indexOf(p);
      if (i >= 0) return i;
    }
    return -1;
  }
  // 第 i 张相对当前这张隔几张（循环，取较近的一边）。
  function galleryDelta(g, i) {
    var n = g.cells.length, d = ((i - g.index) % n + n) % n;
    return d > n / 2 ? d - n : d;
  }
  // 按拖动进度画出这一摞：p > 0 往下一张、p < 0 往上一张，±1 是换完。
  function galleryPaint(g, p) {
    var n = g.cells.length, w = Math.max(1, g.el.clientWidth);
    var a = Math.min(1, Math.abs(p)), dir = p > 0 ? 1 : (p < 0 ? -1 : 0);
    for (var i = 0; i < n; i++) {
      var d = galleryDelta(g, i);
      // 只有两张时另一张同时是上一张和下一张，放到拖动的那一侧。
      if (n === 2 && d !== 0) d = dir || 1;
      var x = 0, s = BACK_SCALE, z = 1, o = 1, cap = 0, dim = 1;
      if (d === 0) {
        // 当前这张：先甩到一边，过半后缩到后面，落在对面那一侧露边的位置。
        x = -dir * w * (PEEK * a + SWING * Math.sin(Math.PI * a));
        s = 1 - (1 - BACK_SCALE) * a;
        z = a < 0.5 ? 4 : 2;
        cap = Math.max(0, 1 - 2 * a);
        dim = a;
      } else if (dir && d === dir) {
        // 接上来的那张：从露边处移到正中、放大到原大。
        x = dir * PEEK * w * (1 - a);
        s = BACK_SCALE + (1 - BACK_SCALE) * a;
        z = 3;
        cap = Math.max(0, 2 * a - 1);
        dim = 1 - a;
      } else if (Math.abs(d) === 1) {
        // 另一侧露边的那张：三张时它换完正好到对面，从后面横穿过去；更多张时淡出。
        x = d * PEEK * w;
        if (dir && n === 3) x = d * PEEK * w * (1 - 2 * a);
        else if (dir) o = 1 - a;
        z = 1;
      } else if (dir && d === 2 * dir) {
        // 下一轮要露边的那张在拖动那一侧淡入。
        x = dir * PEEK * w;
        o = a;
        z = 0;
      } else {
        o = 0;
        z = 0;
      }
      var cell = g.cells[i], st = cell.style;
      st.transform = 'translate3d(' + x.toFixed(1) + 'px,0,0) scale(' + s.toFixed(4) + ')';
      st.zIndex = String(z);
      st.opacity = String(o);
      st.visibility = o > 0 ? 'visible' : 'hidden';
      st.pointerEvents = d === 0 ? 'auto' : 'none';
      st.filter = dim > 0 ? 'brightness(' + (1 - 0.22 * dim).toFixed(3) + ')' : 'none';
      st.setProperty('--legado-gallery-caption', cap.toFixed(3));
    }
  }
  function galleryDots(g) {
    var dots = g.dots.children;
    for (var i = 0; i < dots.length; i++) dots[i].className = i === g.index ? 'on' : '';
  }
  function galleryShow(g, index) {
    galleryFinish();
    var n = g.cells.length;
    g.index = ((index % n) + n) % n;
    galleryPaint(g, 0);
    galleryDots(g);
  }
  function galleryFinish() {
    var a = galleryAnim;
    if (!a) return;
    galleryAnim = null;
    if (a.frame) cancelAnimationFrame(a.frame);
    if (a.timer) clearTimeout(a.timer);
    a.done();
  }
  // 从 from 动到 to 后执行 done。没有帧可画时 rAF 会停，定时器保证一定落定。
  function galleryAnimate(g, from, to, done) {
    galleryFinish();
    var a = { frame: 0, timer: 0, done: done }, begin = 0, duration = 300;
    var step = function (time) {
      if (galleryAnim !== a) return;
      if (!begin) begin = time;
      var k = Math.min(1, (time - begin) / duration), e = 1 - Math.pow(1 - k, 3);
      galleryPaint(g, from + (to - from) * e);
      if (k < 1) a.frame = requestAnimationFrame(step); else galleryFinish();
    };
    galleryAnim = a;
    a.frame = requestAnimationFrame(step);
    a.timer = setTimeout(galleryFinish, duration + 150);
  }
  function galleryProgress(g, dx) {
    return Math.max(-1, Math.min(1, -dx / Math.max(1, g.el.clientWidth)));
  }
  function galleryMove(g, dx) {
    galleryPaint(g, galleryProgress(g, dx));
  }
  function galleryRelease(g, dx, elapsed, cancel) {
    var w = Math.max(1, g.el.clientWidth), p = galleryProgress(g, dx);
    var flick = !cancel && (Math.abs(dx) > w * 0.18 || (Math.abs(dx) > 24 && elapsed < 250));
    var target = flick ? (dx < 0 ? 1 : -1) : 0;
    galleryReport(true);
    galleryAnimate(g, p, target, function () {
      if (target) g.index = ((g.index + target) % g.cells.length + g.cells.length) % g.cells.length;
      galleryPaint(g, 0);
      galleryDots(g);
      // 落定后再报一次，原生层这时才预截当前页。
      galleryReport(false);
    });
  }
  // 当前屏上的画廊（视口坐标、CSS 像素）以及各自停在第几格；只在翻页模式下报，滚动模式不经原生层拖动。
  function galleryReport(moving) {
    if (!paged || !started || (!galleries.length && !videos.length) || !host || !host.gallery) return;
    var zones = [], w = window.innerWidth, h = window.innerHeight;
    // 正在放的视频也报上去（v=1）：在它上面拖动是拖进度条，原生层不翻页；停下来以后照常翻页。
    for (var k = 0; k < videos.length; k++) {
      var vr = videos[k].getBoundingClientRect();
      if (videos[k].paused || vr.width < 1 || vr.right <= 0 || vr.left >= w || vr.bottom <= 0 || vr.top >= h) continue;
      zones.push({ l: Math.round(vr.left), t: Math.round(vr.top), r: Math.round(vr.right), b: Math.round(vr.bottom),
        i: 0, n: 1, v: 1 });
    }
    for (var i = 0; i < galleries.length; i++) {
      var g = galleries[i], r = g.el.getBoundingClientRect();
      if (r.width < 1 || r.right <= 0 || r.left >= w || r.bottom <= 0 || r.top >= h) continue;
      zones.push({ l: Math.round(r.left), t: Math.round(r.top), r: Math.round(r.right), b: Math.round(r.bottom),
        i: g.index, n: g.cells.length });
    }
    var json = JSON.stringify({ moving: moving ? 1 : 0, zones: zones });
    if (json === galleryJson) return;
    galleryJson = json;
    host.gallery(json);
  }
  // 触摸起手在画廊上、横向拖动时这次拖动归画廊，返回 true 表示本次 touchmove 已处理。
  // 方向判定与原生翻页层一致：横向位移大于竖向的 0.8 倍。
  function galleryTouchMove(e) {
    if (e.touches.length !== 1) return false;
    var dx = e.touches[0].clientX - sx, dy = e.touches[0].clientY - sy;
    if (galleryDrag) { galleryMove(galleryDrag, dx); return true; }
    if (!galleryCandidate || galleryDecided) return false;
    if (Math.abs(dx) < 8 && Math.abs(dy) < 8) return false;
    galleryDecided = true;
    if (Math.abs(dx) <= Math.abs(dy) * 0.8) return false;
    galleryDrag = galleryCandidate;
    moved = true; dragging = false; pull = 0;
    galleryMove(galleryDrag, dx);
    return true;
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
    pauseVideos(true);
    report();
    galleryReport(false);
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
    // 念到画廊里某一格的说明文字时，先把画廊切到那一格，高亮才落在看得见的地方。
    var startNode = s.nodes[s.nodeOf[a]], g = galleryOf(startNode);
    if (g) {
      var cell = galleryCellOf(g, startNode);
      if (cell >= 0 && cell !== g.index) { galleryShow(g, cell); galleryReport(false); }
    }
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
  // 只换正文的字体：按字数找出正文的字体与字号，给正文元素标 data-legado-font（样式只认这个标记）。
  // 网页默认字体（html 上的字体，书没设字体的段落用它）也算正文；标题（h1-h6 或字号比正文大 25% 以上）、
  // 代码（注音跟着所在段落走），以及书里单独设了别的字体的文字（花体、符号字体等）都保持原样。
  function markBodyFont() {
    if (!cfg.fontBody || !document.body) return;
    var KEEP = 'h1,h2,h3,h4,h5,h6,rt,rp,code,pre,kbd,samp,tt,var,math,svg';
    var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, null);
    var els = [], families = {}, sizes = {}, n, el, info, len;
    while ((n = walker.nextNode())) {
      len = n.nodeValue.replace(/\s+/g, '').length;
      el = n.parentElement;
      if (!len || !el || /^(SCRIPT|STYLE|NOSCRIPT|TEMPLATE)$/.test(el.tagName)) continue;
      info = el.__legadoFont;
      if (!info) {
        var cs = getComputedStyle(el);
        info = el.__legadoFont = { family: cs.fontFamily, size: parseFloat(cs.fontSize) || 0 };
        els.push(el);
      }
      families[info.family] = (families[info.family] || 0) + len;
      sizes[info.size] = (sizes[info.size] || 0) + len;
    }
    var pick = function (tally) {
      var best = null, most = -1;
      for (var k in tally) if (tally[k] > most) { most = tally[k]; best = k; }
      return best;
    };
    var bodyFamily = pick(families), bodySize = parseFloat(pick(sizes)) || 0;
    var rootFamily = getComputedStyle(document.documentElement).fontFamily;
    for (var i = 0; i < els.length; i++) {
      el = els[i];
      info = el.__legadoFont;
      delete el.__legadoFont;
      if (info.family !== bodyFamily && info.family !== rootFamily) continue;
      if (bodySize > 0 && info.size > bodySize * 1.25) continue;
      if (el.closest(KEEP)) continue;
      el.setAttribute('data-legado-font', '');
    }
  }
  // ---- 多看出血（duokan-bleed，已改写成 --legado-bleed）：把元素朝写明的几边撑到这一页的边缘 ----
  // 左右：按元素所在的页（并排两栏时是半屏）算出它离页边还差多少，用负外边距加宽度补上；
  // 上：只有元素正好在一栏顶端时才往上顶到屏幕边；下：在一栏底部时把高度补到屏幕边。
  var bleedItems = [];
  function bleedTargets() {
    var found = [];
    var add = function (el) { if (found.indexOf(el) < 0) found.push(el); };
    var walk = function (rules) {
      for (var i = 0; i < rules.length; i++) {
        var rule = rules[i];
        if (rule.cssRules && !rule.selectorText) { walk(rule.cssRules); continue; }
        if (!rule.style || !rule.selectorText || !rule.style.getPropertyValue('--legado-bleed')) continue;
        try {
          var list = document.querySelectorAll(rule.selectorText);
          for (var j = 0; j < list.length; j++) add(list[j]);
        } catch (e) {}
      }
    };
    for (var s = 0; s < document.styleSheets.length; s++) {
      var rules = null;
      try { rules = document.styleSheets[s].cssRules; } catch (e) { rules = null; }
      if (rules) walk(rules);
    }
    var inline = document.querySelectorAll('[style*="--legado-bleed"]');
    for (var k = 0; k < inline.length; k++) add(inline[k]);
    return found;
  }
  function bleedReset() {
    for (var i = 0; i < bleedItems.length; i++) {
      var item = bleedItems[i];
      if (item.style === null) item.el.removeAttribute('style'); else item.el.setAttribute('style', item.style);
    }
    bleedItems = [];
  }
  function applyBleed() {
    bleedReset();
    var targets = bleedTargets();
    if (!targets.length) return;
    var spread = paged && !!cfg.spreadQuery && window.matchMedia && window.matchMedia(cfg.spreadQuery).matches;
    var w = window.innerWidth || 1, h = window.innerHeight || 1;
    var plans = [];
    // 先全部量完再改，免得改了前一个影响后一个的位置。
    for (var i = 0; i < targets.length; i++) {
      var el = targets[i], cs = getComputedStyle(el);
      var value = (cs.getPropertyValue('--legado-bleed') || '').toLowerCase();
      if (!value) continue;
      var all = /\ball\b/.test(value);
      var r = el.getBoundingClientRect();
      if (r.width < 1) continue;
      var absLeft = r.left + window.scrollX, x = paged ? absLeft - Math.floor((absLeft + 1) / w) * w : r.left;
      var pageStart = spread && x >= w / 2 ? w / 2 : 0, pageEnd = spread && x < w / 2 ? w / 2 : w;
      var plan = { el: el, ml: parseFloat(cs.marginLeft) || 0, mr: parseFloat(cs.marginRight) || 0,
        mt: parseFloat(cs.marginTop) || 0, width: r.width, height: r.height, left: 0, right: 0, top: 0, bottom: 0 };
      if (all || value.indexOf('left') >= 0) plan.left = Math.max(0, x - pageStart);
      if (all || value.indexOf('right') >= 0) plan.right = Math.max(0, pageEnd - (x + r.width));
      var topGap = paged ? r.top : r.top + window.scrollY;
      if ((all || value.indexOf('top') >= 0) && topGap <= cfg.top + 2) plan.top = Math.max(0, topGap);
      if ((all || value.indexOf('bottom') >= 0) && paged && r.bottom >= h - cfg.bottom - 2) plan.bottom = Math.max(0, h - r.bottom);
      if (plan.left || plan.right || plan.top || plan.bottom) plans.push(plan);
    }
    for (var p = 0; p < plans.length; p++) {
      var q = plans[p], st = q.el.style;
      bleedItems.push({ el: q.el, style: q.el.getAttribute('style') });
      if (q.left || q.right) {
        st.setProperty('box-sizing', 'border-box', 'important');
        st.setProperty('max-width', 'none', 'important');
        st.setProperty('width', (q.width + q.left + q.right) + 'px', 'important');
        st.setProperty('margin-left', (q.ml - q.left) + 'px', 'important');
        st.setProperty('margin-right', (q.mr - q.right) + 'px', 'important');
      }
      if (q.top) st.setProperty('margin-top', (q.mt - q.top) + 'px', 'important');
      if (q.bottom) st.setProperty('min-height', (q.height + q.bottom) + 'px', 'important');
    }
  }
  // ---- 多看全屏页（duokan-page-fullscreen）：页面传来的页边距已是零；整页只有一张图时换成铺满一屏的背景图，
  // 图与屏幕比例相近（裁掉不到 12%）就铺满裁边，否则完整显示。瘦长屏幕有“~slim”图时换用它 ----
  function slimFor(url) {
    var from = cfg.slimFrom || [], to = cfg.slimTo || [];
    if (!from.length || window.innerHeight / Math.max(1, window.innerWidth) < cfg.slimRatio) return url;
    var key = '';
    try { key = new URL(url, document.baseURI).href; } catch (e) { return url; }
    for (var i = 0; i < from.length; i++) {
      var candidate = '';
      try { candidate = new URL(from[i], document.baseURI).href; } catch (e) { continue; }
      if (candidate === key) return to[i];
    }
    return url;
  }
  function applyFullscreen() {
    if (!cfg.fullscreen) return;
    if (compact().text.length > 40) return;
    var media = document.querySelectorAll('img, svg image');
    if (media.length !== 1) return;
    var node = media[0], url = '';
    if (node.nodeName.toLowerCase() === 'img') url = node.currentSrc || node.src;
    else url = node.getAttribute('href') || node.getAttribute('xlink:href') ||
      node.getAttributeNS('http://www.w3.org/1999/xlink', 'href') || '';
    if (!url) return;
    url = slimFor(new URL(url, document.baseURI).href);
    var box = document.createElement('div');
    box.className = 'legado-fullscreen';
    box.setAttribute('role', 'img');
    box.setAttribute('aria-label', node.getAttribute('alt') || '');
    box.style.backgroundImage = 'url("' + url.replace(/"/g, '%22') + '")';
    for (var c = document.body.firstElementChild; c; c = c.nextElementSibling) {
      if (c.nodeName.toLowerCase() !== 'script') c.style.display = 'none';
    }
    document.body.insertBefore(box, document.body.firstChild);
    cache = null;
    var probe = new Image();
    probe.onload = function () {
      var iw = probe.naturalWidth, ih = probe.naturalHeight;
      if (!iw || !ih) return;
      var sw = window.innerWidth || 1, sh = window.innerHeight || 1;
      var scale = Math.max(sw / iw, sh / ih), crop = 1 - Math.min(sw / (iw * scale), sh / (ih * scale));
      box.style.backgroundSize = crop <= 0.12 ? 'cover' : 'contain';
    };
    probe.src = url;
  }
  // ---- 书里的音频与视频 ----
  // 音频：<audio> 前放一块卡片（样式见 mediaStyle），点它经 host.media(地址, 曲名) 交给原生播放器，换章、翻页都接着放；
  // 原生层把播放状态经 __legado.media 推回来，卡片据此换圆标、画进度线（有 activestate 图的播放时换图）。
  // 视频：加上浏览器自带的播放控件，就在网页里放；翻到别的页或换章时暂停。
  var mediaWidgets = [], videos = [];
  var mediaNow = { src: cfg.mediaSrc || '', state: cfg.mediaState || '', pos: 0, dur: 0 };
  function mediaSrcOf(el) {
    var value = el.getAttribute('src') || '';
    if (!value) {
      var sources = el.getElementsByTagName('source');
      for (var i = 0; i < sources.length && !value; i++) value = sources[i].getAttribute('src') || '';
    }
    if (!value) return '';
    try { return new URL(value, document.baseURI).href.replace(/#.*$/, ''); } catch (e) { return value; }
  }
  function setupMedia() {
    var list = document.getElementsByTagName('audio');
    for (var i = 0; i < list.length; i++) {
      var a = list[i], src = mediaSrcOf(a);
      if (!src || !a.parentNode) continue;
      var box = document.createElement('div');
      box.className = 'legado-audio';
      box.setAttribute('role', 'button');
      box.setAttribute('data-legado-media', src);
      box.setAttribute('data-title', (a.getAttribute('title') || '').trim());
      var cover = a.getAttribute('placeholder') || '';
      if (cover) {
        var img = document.createElement('img');
        img.className = 'legado-audio-cover';
        img.alt = '';
        img.src = cover;
        box.appendChild(img);
        box.__legadoCover = img;
        box.__legadoIdle = cover;
        box.__legadoActive = a.getAttribute('activestate') || '';
      } else {
        box.className += ' legado-audio-pill';
      }
      var badge = document.createElement('span');
      badge.className = 'legado-audio-badge';
      box.appendChild(badge);
      var bar = document.createElement('span');
      bar.className = 'legado-audio-progress';
      box.appendChild(bar);
      box.__legadoBar = bar;
      a.parentNode.insertBefore(box, a);
      mediaWidgets.push(box);
    }
    var vs = document.getElementsByTagName('video');
    for (var j = 0; j < vs.length; j++) {
      var v = vs[j];
      v.setAttribute('controls', '');
      v.setAttribute('playsinline', '');
      v.setAttribute('controlslist', 'nodownload');
      v.removeAttribute('autoplay');
      v.addEventListener('play', videoChanged);
      v.addEventListener('pause', videoChanged);
      v.addEventListener('ended', videoChanged);
      videos.push(v);
    }
    mediaPaint();
  }
  function videoChanged() { galleryReport(false); }
  function mediaPaint() {
    for (var i = 0; i < mediaWidgets.length; i++) {
      var box = mediaWidgets[i];
      var mine = box.getAttribute('data-legado-media') === mediaNow.src;
      // 正在准备（loading）也按“在放”画，点下去马上有反馈。
      var state = !mine ? 'idle' : (mediaNow.state === 'paused' ? 'paused' :
        (mediaNow.state === 'playing' || mediaNow.state === 'loading' ? 'playing' : 'idle'));
      if (box.getAttribute('data-state') !== state) box.setAttribute('data-state', state);
      var img = box.__legadoCover;
      if (img && box.__legadoActive && box.__legadoActive !== box.__legadoIdle) {
        var want = state === 'playing' ? box.__legadoActive : box.__legadoIdle;
        if (img.getAttribute('src') !== want) {
          // 换图不能改变版面：锁住当前的高度，新图按比例放进去。
          if (img.offsetHeight > 0) { img.style.height = img.offsetHeight + 'px'; img.style.objectFit = 'contain'; }
          img.setAttribute('src', want);
        }
      }
      var ratio = state !== 'idle' && mediaNow.dur > 0 ? Math.max(0, Math.min(1, mediaNow.pos / mediaNow.dur)) : 0;
      box.__legadoBar.style.width = (ratio * 100).toFixed(2) + '%';
    }
  }
  function media(src, state, pos, dur) {
    mediaNow = { src: src || '', state: state || '', pos: Number(pos) || 0, dur: Number(dur) || 0 };
    mediaPaint();
  }
  // 暂停视频；onlyHidden 时只停已经不在当前屏上的。
  function pauseVideos(onlyHidden) {
    var w = window.innerWidth, h = window.innerHeight;
    for (var i = 0; i < videos.length; i++) {
      var v = videos[i];
      if (v.paused) continue;
      if (onlyHidden) {
        var r = v.getBoundingClientRect();
        if (r.right > 0 && r.left < w && r.bottom > 0 && r.top < h) continue;
      }
      try { v.pause(); } catch (e) {}
    }
  }
  function start() {
    if (started) return;
    started = true;
    applyFullscreen();
    setupMedia();
    setupGalleries();
    applyBleed();
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
    if (galleryDrag) { galleryRelease(galleryDrag, 0, 0, true); galleryDrag = null; }
    // 上一次换卡的动画还没完就又按下：直接落定，免得新拖动从半路的画面开始。
    galleryFinish();
    galleryDecided = false;
    galleryCandidate = null;
    if (e.touches.length !== 1) { dragging = false; pull = 0; return; }
    sx = e.touches[0].clientX; sy = e.touches[0].clientY; st = Date.now();
    pull = 0;
    var hit = galleries.length && e.target && e.target.closest ? e.target.closest('.legado-gallery') : null;
    galleryCandidate = hit ? hit.__legadoGallery || null : null;
    if (!paged) {
      atTop = window.scrollY <= 1;
      atBottom = window.scrollY + window.innerHeight >= document.documentElement.scrollHeight - 2;
    }
    if (paged) stopAnimation();
    base = page * width; dragging = paged; moved = false;
  }, { passive: true });
  document.addEventListener('touchmove', function (e) {
    if (galleryTouchMove(e)) return;
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
  document.addEventListener('touchcancel', function () {
    if (!galleryDrag) return;
    galleryRelease(galleryDrag, 0, 0, true);
    galleryDrag = null;
  }, { passive: true });
  document.addEventListener('touchend', function (e) {
    if (galleryDrag) {
      galleryRelease(galleryDrag, e.changedTouches[0].clientX - sx, Date.now() - st, false);
      galleryDrag = null;
      pull = 0;
      return;
    }
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
    var audio = e.target && e.target.closest ? e.target.closest('.legado-audio') : null;
    if (audio) {
      e.preventDefault();
      e.stopPropagation();
      if (host && host.media) host.media(audio.getAttribute('data-legado-media') || '', audio.getAttribute('data-title') || '');
      return;
    }
    // 点视频交给它自己的播放控件，不当成翻页或呼出菜单的点按。
    if (e.target && e.target.closest && e.target.closest('video')) return;
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
    for (var mi = 0; mi < mediaWidgets.length; mi++) {
      if (mediaWidgets[mi].__legadoCover) mediaWidgets[mi].__legadoCover.style.height = '';
    }
    applyBleed();
    layout();
    goSpot(s.snippet, s.fraction);
  });
  window.__legado = { next: next, prev: prev, goSpot: goSpot, goAnchor: goAnchor, goPage: goPage, screen: screen,
    preview: preview, step: step, show: show, speechInfo: speechInfo, ttsMark: ttsMark, ttsClear: ttsClear,
    media: media, pauseVideos: pauseVideos };
  var begin = function () {
    var wait = function () {
      if (document.fonts && document.fonts.ready) document.fonts.ready.then(start, start); else start();
    };
    if (!cfg.fontBody) { wait(); return; }
    // 标记完正文才用上替换字体，得先让它载入，不然按书的字体分完页又换字形，页数就不对了。
    try { markBodyFont(); } catch (e) {}
    if (document.fonts && document.fonts.load) document.fonts.load('1em "LegadoReaderFont"').then(wait, wait);
    else wait();
  };
  if (document.readyState === 'complete') begin(); else window.addEventListener('load', begin);
  setTimeout(start, 4000);
})();`;
}
