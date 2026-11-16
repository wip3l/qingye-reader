/**
 * .qytheme 主题包的格式定义与纯逻辑（不依赖系统接口，Node 回归脚本可直接加载）。
 *
 * 包是一个 ZIP：manifest.json（格式、版本、名称、作者、所需能力、可选的资源清单）+ theme.json（方案设置、
 * 方案排版、可选的强调规则、字体绑定和包内部件）+ assets/（图片、矢量图和可选字体）。
 *
 * 格式 1 由应用导出：素材按内容哈希命名并逐个登记在清单里。格式 2 面向手写的主题包：清单里的 assets 可以省略，
 * 素材用 assets/ 下的文件名引用，应用导入时自己枚举、嗅探类型并计算摘要；theme.json 的 parts 节能带上
 * 主题自己的配色、素材和令牌，导入后注册为一个主题（ID 为 pack:<packageId>），自定义方案的各部件指向它。
 * 内置主题的素材随应用安装，包里只写部件来源 ID，不复制内置图片，也就不会把付费素材带出去。
 */

export const QYTHEME_FORMAT: string = 'qytheme';
export const QYTHEME_FORMAT_VERSION: number = 2;
export const QYTHEME_EXTENSION: string = '.qytheme';
export const QYTHEME_ASSET_PREFIX: string = 'qytheme-asset:';
/** 安装后的主题包作为主题的 ID 前缀；pack:self 在包内指代这个包自己，导入时换成真正的 ID。 */
export const PACK_THEME_PREFIX: string = 'pack:';
export const PACK_SELF_THEME_ID: string = 'pack:self';

export class ThemePackageFeatures {
  static readonly CUSTOM_SCHEME: string = 'custom-scheme-v1';
  static readonly READER_LAYOUT: string = 'reader-layout-v1';
  static readonly EMPHASIS_RULES: string = 'emphasis-rules-v3';
  static readonly FONTS: string = 'fonts-v1';
  static readonly THEME_PARTS: string = 'theme-parts-v1';
  // 方案自己覆盖的完整配色与强调气泡（customLightPalette 等字段）；老版本不认得这些字段，导入会少颜色。
  static readonly SCHEME_OVERRIDES: string = 'scheme-overrides-v1';
  // 角饰模式只有左上或只有右下一张图；老版本要求两张都在，导入会直接报错，所以只在用到时写进 requires。
  static readonly READER_SINGLE_CORNER: string = 'reader-single-corner-v1';
  // covers 超过 8 张（现在最多 16 张）；老版本最多收 8 张，多了导入直接报错，所以只在用到时写进 requires。
  static readonly BOOK_COVERS_16: string = 'book-covers-16-v1';
  // 气泡边框用了位图（PNG / WebP / JPG），或只有边框没有端饰；老版本只收 SVG 边框且要求端饰，导入会直接报错，
  // 所以只在用到时写进 requires。拉伸设置（frameSlice 等）老版本会忽略，不用声明。
  static readonly BUBBLE_FRAME: string = 'bubble-frame-v1';
  // 气泡端饰或书架边框用了位图（浅色、深色任意一张）；老版本这两处只收 SVG，导入会直接报错，
  // 所以只在用到时写进 requires。
  static readonly BITMAP_CAP_SHELF_FRAME: string = 'bitmap-cap-shelf-frame-v1';
  // 素材超过 64 个（现在最多 128 个）；老版本最多收 64 个，多了导入直接报错，所以只在用到时写进 requires。
  static readonly ASSETS_128: string = 'assets-128-v1';
  static readonly KNOWN: string[] = [
    ThemePackageFeatures.CUSTOM_SCHEME,
    ThemePackageFeatures.READER_LAYOUT,
    ThemePackageFeatures.EMPHASIS_RULES,
    ThemePackageFeatures.FONTS,
    ThemePackageFeatures.THEME_PARTS,
    ThemePackageFeatures.SCHEME_OVERRIDES,
    ThemePackageFeatures.READER_SINGLE_CORNER,
    ThemePackageFeatures.BOOK_COVERS_16,
    ThemePackageFeatures.BUBBLE_FRAME,
    ThemePackageFeatures.BITMAP_CAP_SHELF_FRAME,
    ThemePackageFeatures.ASSETS_128
  ];
}

export class ThemePackageLimits {
  static readonly MAX_PACKAGE_BYTES: number = 80 * 1024 * 1024;
  static readonly MAX_TOTAL_UNCOMPRESSED: number = 160 * 1024 * 1024;
  /** 不小于 AnimatedImagePolicy.MAX_PLAY_BYTES，能上传播放的动图也能随主题包导出。 */
  static readonly MAX_IMAGE_BYTES: number = 25 * 1024 * 1024;
  static readonly MAX_FONT_BYTES: number = 40 * 1024 * 1024;
  static readonly MAX_VECTOR_BYTES: number = 5 * 1024 * 1024;
  static readonly MAX_JSON_BYTES: number = 1024 * 1024;
  // 素材总数上限。超过 LEGACY_MAX_ASSETS 时清单要声明 assets-128-v1。
  static readonly MAX_ASSETS: number = 128;
  // 老版本应用的素材上限。
  static readonly LEGACY_MAX_ASSETS: number = 64;
  // 素材之外还有 manifest.json、theme.json 和目录条目，留出余量。
  static readonly MAX_ZIP_ENTRIES: number = 144;
  static readonly MAX_RULES: number = 200;
  static readonly MAX_NAME_LENGTH: number = 24;
  static readonly MAX_AUTHOR_LENGTH: number = 24;
  static readonly MAX_DESCRIPTION_LENGTH: number = 120;
  static readonly MAX_VERSION_LENGTH: number = 32;
  // 浅色（covers）和深色（coversDark）各自的上限。
  static readonly MAX_COVERS: number = 16;
  // 老版本应用的封面上限：covers 超过它时清单要声明 book-covers-16-v1。
  static readonly LEGACY_MAX_COVERS: number = 8;
  static readonly MAX_STARTUP_TEXT_LENGTH: number = 40;
}

/** 这份清单允许的素材个数：声明了 assets-128-v1 才放到 128 个，否则按老版本的 64 个。 */
export function maxAssetsFor(requires: string[]): number {
  return requires.includes(ThemePackageFeatures.ASSETS_128) ? ThemePackageLimits.MAX_ASSETS :
    ThemePackageLimits.LEGACY_MAX_ASSETS;
}

/** 素材数量超出时的提示：超过 64 个没声明 assets-128-v1 要单独说明。 */
export function tooManyAssetsMessage(count: number, requires: string[]): string {
  if (count <= ThemePackageLimits.MAX_ASSETS && !requires.includes(ThemePackageFeatures.ASSETS_128)) {
    return `主题包素材超过 ${ThemePackageLimits.LEGACY_MAX_ASSETS} 个时 requires 要包含 ${ThemePackageFeatures.ASSETS_128}`;
  }
  return '主题包素材数量超出上限';
}

export class ThemePackageAssetKinds {
  static readonly IMAGE: string = 'image';
  static readonly FONT: string = 'font';
  static readonly VECTOR: string = 'vector';
}

const IMAGE_EXTENSIONS: string[] = ['png', 'jpg', 'webp', 'gif', 'bmp'];
const FONT_EXTENSIONS: string[] = ['ttf', 'otf', 'ttc'];
const VECTOR_EXTENSIONS: string[] = ['svg'];

export class ThemePackageAsset {
  id: string = '';
  path: string = '';
  kind: string = ThemePackageAssetKinds.IMAGE;
  size: number = 0;
  sha256: string = '';
  // 字体的显示名；图片为空。
  name: string = '';
}

/** 再导出时保留的原始主题包信息，只用于展示。 */
export class ThemePackageCredits {
  packageId: string = '';
  name: string = '';
  author: string = '';
}

export class ThemePackageManifest {
  format: string = QYTHEME_FORMAT;
  formatVersion: number = QYTHEME_FORMAT_VERSION;
  packageId: string = '';
  name: string = '';
  author: string = '';
  exportedAt: number = 0;
  appVersion: string = '';
  requires: string[] = [];
  assets: ThemePackageAsset[] = [];
  // 格式 2 新增：作者自定的版本号与说明，以及部件缺省时回退到的内置主题。
  version: string = '';
  description: string = '';
  baseTheme: string = '';
  credits: ThemePackageCredits | null = null;
  // 清单里是否写了 assets；没写时由导入方枚举 assets/ 目录补全。
  assetsDeclared: boolean = true;
}

/** 方案排版或强调规则引用到的字体。assetId 为空表示导出时没有附带字体文件。 */
export class ThemePackageFont {
  family: string = '';
  name: string = '';
  assetId: string = '';
}

export class ThemePackageEmphasis {
  enabled: boolean = false;
  // ReaderRegexFontRule 的 JSON 形式（schemaVersion 3）。
  rulesJson: string = '';
}

// ---- 包内部件（格式 2） ----

export class ThemePackagePartColors {
  pageColor: string = '';
  cardColor: string = '';
  inputColor: string = '';
  primaryTextColor: string = '';
  subTextColor: string = '';
  dividerColor: string = '';
  accentColor: string = '';
  buttonColor: string = '';
  dangerColor: string = '';
}

export class ThemePackagePartReader {
  backgroundColor: string = '';
  textColor: string = '';
  subTextColor: string = '';
  contentTone: string = '';
  // 'ornaments'：左上、右下角饰；'image'：整图背景（可再带角饰叠在上面，老版本只显示整图）；
  // 'none'：只有底色；空：沿用基底主题。
  backgroundMode: string = '';
  // 角饰可以只有一张（另一角空着，需要 reader-single-corner-v1）；两张是同一个素材时右下角旋转 180° 显示。
  leading: string = '';
  trailing: string = '';
  image: string = '';
  imageFit: string = 'cover';
  // 左上、右下角饰各自的显示大小，相对默认尺寸（短边 × 0.36，夹在 112–260vp）的倍数；
  // 老版本不认得这两个字段，按 1 显示。
  leadingScale: number = 1;
  trailingScale: number = 1;
}

export const READER_ORNAMENT_SCALE_MIN: number = 0.5;
export const READER_ORNAMENT_SCALE_MAX: number = 2;

/** 缺省、0 或非法值都当 1；其余夹在 0.5–2，保留两位小数。 */
export function normalizeOrnamentScale(value: number | null | undefined): number {
  if (typeof value !== 'number' || !isFinite(value) || value <= 0) return 1;
  const clamped = Math.max(READER_ORNAMENT_SCALE_MIN, Math.min(READER_ORNAMENT_SCALE_MAX, value));
  return Math.round(clamped * 100) / 100;
}

/** 角饰模式只填了左上或右下其中一张。 */
export function readerHasSingleCorner(reader: ThemePackagePartReader | null | undefined): boolean {
  if (!reader || reader.backgroundMode !== 'ornaments') return false;
  return !reader.leading !== !reader.trailing;
}

export function partsUseSingleCorner(parts: ThemePackageParts | null | undefined): boolean {
  if (!parts) return false;
  return (!!parts.light && readerHasSingleCorner(parts.light.reader)) ||
    (!!parts.dark && readerHasSingleCorner(parts.dark.reader));
}

export class ThemePackagePartEmphasis {
  mode: string = '';
  bubbleStyle: string = '';
  color: string = '';
  textColor: string = '';
}

/**
 * 段评气泡（含本章说）的外观，写在每个模式自己的部件里。字段都可以空着：空着的沿用强调气泡样式推出来的样子。
 * 书源设置了段评颜色时仍以书源为准。旧版本应用不认这一节，段评照旧跟强调气泡样式走。
 */
export class ThemePackageCommentBubble {
  /** COMMENT_BUBBLE_SHAPES 之一；空串跟随强调气泡样式。 */
  shape: string = '';
  /** 圆角占气泡高的比例 0–0.5，只对 rounded 有效；负数用默认值。 */
  radius: number = -1;
  fill: string = '';
  stroke: string = '';
  text: string = '';
  /** COMMENT_BUBBLE_ORNAMENTS 之一（'none' 表示不画，'custom' 用 ornamentImage）；空串跟随强调气泡样式。 */
  ornament: string = '';
  ornamentColor: string = '';
  /**
   * 气泡图：整只气泡（含尾巴）的一张透明底图片。包里是素材引用；运行时是本机 URI。'none' 表示这个模式不用图片
   * （另一模式的图不沿用过来）。方案覆盖里只会是 'none' 或 pack:<packageId>（取那个包同一模式的气泡图与拉伸设置）。
   * 写了图片时形状、圆角、描边不再生效，底色只在 imageTint 时用来染色。旧版本应用不认，照旧画形状。
   */
  image: string = '';
  /** 左右拉伸线（占图宽的比例 0–0.49）；只用 left / right，图片按比例缩放，竖直方向不拉伸。null 用默认位置。 */
  imageSlice: ThemePackageBubbleSlice | null = null;
  /** 文字区离四边的比例；文字区的高度对齐气泡高（字号 × 1.32）。null 用默认位置。 */
  imageText: ThemePackageBubbleSlice | null = null;
  /** 中间部分：空串拉伸，'round' 平铺。 */
  imageRepeat: string = '';
  /** 气泡折到两行时前一段：空串裁到文字区底边（不画尾巴），'full' 画整图。 */
  imageBreak: string = '';
  /** 整张图染成底色（fill，没写时用推导出的底色）。 */
  imageTint: boolean = false;
  /** ornament 为 'custom' 时的角标图；方案覆盖里同样写 pack:<packageId>。 */
  ornamentImage: string = '';
  /** 'topLeft' / 'bottomRight'；空串是右上。 */
  ornamentCorner: string = '';
  /** 角标大小倍数 0.5–1.5；负数为 1。 */
  ornamentSize: number = -1;
}

/** outline 是默认的透明描边（颜色跟正文墨色），其余三种是实心气泡。 */
export const COMMENT_BUBBLE_SHAPES: string[] = ['outline', 'pill', 'rounded', 'cut'];
export const COMMENT_BUBBLE_SHAPE_NAMES: string[] = ['描边', '胶囊', '圆角', '切角'];
export const COMMENT_BUBBLE_DEFAULT_RADIUS: number = 0.2;
export const COMMENT_BUBBLE_RADIUS_MAX: number = 0.5;
/** 阅读页内置的小图形，与 ReaderCommentBubblePainter 画得出的一致。 */
export const COMMENT_BUBBLE_ORNAMENTS: string[] = [
  'none', 'star', 'sparkle', 'dot', 'moon', 'leaf', 'sprig', 'rose', 'paw', 'seal', 'diamond', 'pendant', 'scroll',
  'cord', 'signal', 'frame', 'sketch', 'postcard', 'folio', 'custom'
];
export const COMMENT_BUBBLE_ORNAMENT_NAMES: string[] = [
  '无', '星', '小星', '圆点', '月', '叶', '枝', '花', '爪印', '印章', '菱形', '坠饰', '卷轴',
  '绳结', '信号', '内框', '描影', '信封', '书签', '自定义图片'
];
/** 自定义角标图的位置；空串（右上）不写进包。 */
export const COMMENT_ORNAMENT_CORNERS: string[] = ['topLeft', 'topRight', 'bottomRight'];
export const COMMENT_ORNAMENT_CORNER_NAMES: string[] = ['左上', '右上', '右下'];
export const COMMENT_ORNAMENT_SIZE_MIN: number = 0.5;
export const COMMENT_ORNAMENT_SIZE_MAX: number = 1.5;
/** 气泡图在文字区上方、下方最多超出气泡高的比例；超过时编辑器提示可能压到上下行。 */
export const COMMENT_IMAGE_OVERHANG_TOP: number = 0.38;
export const COMMENT_IMAGE_OVERHANG_BOTTOM: number = 0.6;
export const COMMENT_IMAGE_NONE: string = 'none';
export class CommentImageRepeat {
  static readonly ROUND: string = 'round';
}
export class CommentImageBreak {
  static readonly FULL: string = 'full';
}

/** 这份段评设置用的是气泡图（不是 'none'、也不是空串）。 */
export function commentBubbleHasImage(source: ThemePackageCommentBubble | null | undefined): boolean {
  return !!source && typeof source.image === 'string' && !!source.image && source.image !== COMMENT_IMAGE_NONE;
}

/** 默认拉伸线：左右各“图高 × 0.6”，最多各占图宽的 30%（和强调气泡边框一样）。aspect 是图宽 / 图高。 */
export function defaultCommentImageSlice(aspect: number): ThemePackageBubbleSlice {
  const slice = new ThemePackageBubbleSlice();
  const ratio = aspect > 0 && isFinite(aspect) ? aspect : 3;
  const end = Math.round(Math.min(0.6 / ratio, 0.3) * 100) / 100;
  slice.left = end;
  slice.right = end;
  return slice;
}

/** 默认文字区：左右各“图高 × 0.35”最多 25%，上 12%、下 20%（尾巴一般画在下方）。 */
export function defaultCommentImageText(aspect: number): ThemePackageBubbleSlice {
  const box = new ThemePackageBubbleSlice();
  const ratio = aspect > 0 && isFinite(aspect) ? aspect : 3;
  const end = Math.round(Math.min(0.35 / ratio, 0.25) * 100) / 100;
  box.left = end;
  box.right = end;
  box.top = 0.12;
  box.bottom = 0.2;
  return box;
}

export function commentImageSliceOrDefault(source: ThemePackageCommentBubble, aspect: number): ThemePackageBubbleSlice {
  const slice = normalizeBubbleFrameSlice(source.imageSlice);
  if (!slice) return defaultCommentImageSlice(aspect);
  slice.top = 0;
  slice.bottom = 0;
  return slice;
}

export function commentImageTextOrDefault(source: ThemePackageCommentBubble, aspect: number): ThemePackageBubbleSlice {
  return normalizeBubbleFrameSlice(source.imageText) || defaultCommentImageText(aspect);
}

/** 文字区上方、下方超出气泡高的比例 [上, 下]；编辑器用它提示可能压到上下行。 */
export function commentImageOverhang(text: ThemePackageBubbleSlice): number[] {
  const body = Math.max(0.02, 1 - text.top - text.bottom);
  return [text.top / body, text.bottom / body];
}

const COMMENT_BUBBLE_COLOR: RegExp = /^#(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/;

/** 不认得的形状、图形和颜色都清成空串（沿用），圆角夹到 0–0.5；读包、读本机设置和编辑器都走它。 */
export function normalizeCommentBubble(source: ThemePackageCommentBubble | null | undefined): ThemePackageCommentBubble {
  const result = new ThemePackageCommentBubble();
  if (!source || typeof source !== 'object') return result;
  const text = (value: string | undefined): string => typeof value === 'string' ? value.trim() : '';
  const color = (value: string | undefined): string => {
    const raw = text(value);
    return COMMENT_BUBBLE_COLOR.test(raw) ? raw.toUpperCase() : '';
  };
  const shape = text(source.shape);
  result.shape = COMMENT_BUBBLE_SHAPES.includes(shape) ? shape : '';
  const radius = typeof source.radius === 'number' && isFinite(source.radius) ? source.radius : -1;
  result.radius = radius < 0 ? -1 : Math.round(Math.min(COMMENT_BUBBLE_RADIUS_MAX, radius) * 100) / 100;
  result.fill = color(source.fill);
  result.stroke = color(source.stroke);
  result.text = color(source.text);
  const ornament = text(source.ornament);
  result.ornament = COMMENT_BUBBLE_ORNAMENTS.includes(ornament) ? ornament : '';
  result.ornamentColor = color(source.ornamentColor);
  // 素材引用、本机 URI、'none' 或 pack:<id>，都原样保留；读包时已经校验过引用。
  result.image = limitChars(text(source.image), 2000);
  if (result.image && result.image !== COMMENT_IMAGE_NONE) {
    result.imageSlice = normalizeBubbleFrameSlice(source.imageSlice);
    if (result.imageSlice) {
      result.imageSlice.top = 0;
      result.imageSlice.bottom = 0;
    }
    result.imageText = normalizeBubbleFrameSlice(source.imageText);
    result.imageRepeat = source.imageRepeat === CommentImageRepeat.ROUND ? CommentImageRepeat.ROUND : '';
    result.imageBreak = source.imageBreak === CommentImageBreak.FULL ? CommentImageBreak.FULL : '';
    result.imageTint = source.imageTint === true;
  }
  result.ornamentImage = limitChars(text(source.ornamentImage), 2000);
  const corner = text(source.ornamentCorner);
  result.ornamentCorner = corner === 'topLeft' || corner === 'bottomRight' ? corner : '';
  const size = typeof source.ornamentSize === 'number' && isFinite(source.ornamentSize) ? source.ornamentSize : -1;
  result.ornamentSize = size < 0 ? -1 : Math.round(Math.max(COMMENT_ORNAMENT_SIZE_MIN,
    Math.min(COMMENT_ORNAMENT_SIZE_MAX, size)) * 20) / 20;
  return result;
}

export function commentBubbleIsEmpty(source: ThemePackageCommentBubble | null | undefined): boolean {
  const value = normalizeCommentBubble(source);
  return !value.shape && value.radius < 0 && !value.fill && !value.stroke && !value.text && !value.ornament &&
    !value.ornamentColor && !value.image && !value.ornamentImage && !value.ornamentCorner && value.ornamentSize < 0;
}

/** 气泡图与它的拉伸设置（image 起的六项）从 source 抄到 target。 */
export function copyCommentImage(target: ThemePackageCommentBubble, source: ThemePackageCommentBubble): void {
  target.image = source.image || '';
  target.imageSlice = source.imageSlice ? normalizeBubbleFrameSlice(source.imageSlice) : null;
  target.imageText = source.imageText ? normalizeBubbleFrameSlice(source.imageText) : null;
  target.imageRepeat = source.imageRepeat || '';
  target.imageBreak = source.imageBreak || '';
  target.imageTint = source.imageTint === true;
}

/**
 * 包里某个模式实际用的段评设置：气泡图、角标图各自取这个模式的，没有就用另一种模式的（只给了一种模式时两种都用），
 * 这个模式写了 'none' 时不沿用。其余字段只看这个模式。两种模式都没有任何设置时返回 null。
 */
export function commentBubbleFor(parts: ThemePackageParts | null | undefined,
  dark: boolean): ThemePackageCommentBubble | null {
  if (!parts) return null;
  const ownVariant = dark ? parts.dark : parts.light;
  const otherVariant = dark ? parts.light : parts.dark;
  const own = ownVariant && ownVariant.commentBubble ? normalizeCommentBubble(ownVariant.commentBubble) : null;
  const other = otherVariant && otherVariant.commentBubble ? normalizeCommentBubble(otherVariant.commentBubble) : null;
  if (!own && !other) return null;
  const result = own || new ThemePackageCommentBubble();
  if (!result.image && other && commentBubbleHasImage(other)) copyCommentImage(result, other);
  if (!result.ornamentImage && other && other.ornamentImage) {
    result.ornamentImage = other.ornamentImage;
    if (!result.ornament && other.ornament === 'custom') result.ornament = 'custom';
    if (!result.ornamentCorner) result.ornamentCorner = other.ornamentCorner;
    if (result.ornamentSize < 0) result.ornamentSize = other.ornamentSize;
  }
  return commentBubbleIsEmpty(result) ? null : result;
}

/** 只写设了的字段。 */
export function encodeCommentBubble(source: ThemePackageCommentBubble): Record<string, Object> {
  const value = normalizeCommentBubble(source);
  const record: Record<string, Object> = {};
  if (value.shape) record['shape'] = value.shape;
  if (value.radius >= 0) record['radius'] = value.radius;
  if (value.fill) record['fill'] = value.fill;
  if (value.stroke) record['stroke'] = value.stroke;
  if (value.text) record['text'] = value.text;
  if (value.ornament) record['ornament'] = value.ornament;
  if (value.ornamentColor) record['ornamentColor'] = value.ornamentColor;
  if (value.image) {
    record['image'] = value.image;
    if (value.image !== COMMENT_IMAGE_NONE) {
      if (value.imageSlice) {
        const slice: Record<string, Object> = {};
        slice['left'] = value.imageSlice.left;
        slice['right'] = value.imageSlice.right;
        record['imageSlice'] = slice;
      }
      if (value.imageText) record['imageText'] = JSON.parse(JSON.stringify(value.imageText)) as Object;
      if (value.imageRepeat) record['imageRepeat'] = value.imageRepeat;
      if (value.imageBreak) record['imageBreak'] = value.imageBreak;
      if (value.imageTint) record['imageTint'] = true;
    }
  }
  if (value.ornamentImage) record['ornamentImage'] = value.ornamentImage;
  if (value.ornamentCorner) record['ornamentCorner'] = value.ornamentCorner;
  if (value.ornamentSize >= 0) record['ornamentSize'] = value.ornamentSize;
  return record;
}

export class ThemePackageVariantParts {
  colors: ThemePackagePartColors = new ThemePackagePartColors();
  reader: ThemePackagePartReader = new ThemePackagePartReader();
  emphasis: ThemePackagePartEmphasis = new ThemePackagePartEmphasis();
  // 本机旧记录里没有。
  commentBubble: ThemePackageCommentBubble | null = null;
  /** 标题强调；null 表示主题不设置（标题保持原样）。本机旧记录里没有，旧版本应用不认。 */
  titleEmphasis: ThemePackagePartEmphasis | null = null;
  // 章首装饰，整节不写表示这个模式不设置；本机旧记录里没有。
  chapterHead: ThemePackageChapterHead | null = null;
}

/** 标题强调的气泡样式写成它时，和正文强调用同一套样式与素材。 */
export const TITLE_BUBBLE_SAME_AS_EMPHASIS: string = 'emphasis';
/** 方案自己的标题气泡（包里 titleBubble 那套素材）作为气泡样式时的 ID 后缀：pack:<packageId>:title。 */
export const PACK_TITLE_BUBBLE_SUFFIX: string = ':title';

export function packTitleBubbleStyleId(packThemeIdValue: string): string {
  return `${packThemeIdValue}${PACK_TITLE_BUBBLE_SUFFIX}`;
}

export function isPackTitleBubbleStyle(styleId: string): boolean {
  return isPackThemeId(styleId) && styleId.endsWith(PACK_TITLE_BUBBLE_SUFFIX);
}

export function titleEmphasisIsEmpty(value: ThemePackagePartEmphasis | null | undefined): boolean {
  return !value || !(value.mode || value.bubbleStyle || value.color || value.textColor);
}

/**
 * 章首装饰：章节标题旁的饰图、分段标题第一段（“第十二章”那一行）的颜色，和首字装饰（放大占几行，可垫印章图）。
 * 写在每个模式自己的部件里，字段都可以空着。旧版本应用不认这一节，标题和正文照旧显示。
 */
export class ThemePackageChapterHead {
  /**
   * 饰图：包里是素材引用，运行时是本机 URI。这个模式没写时沿用另一种模式的那张（连同位置和大小，
   * 见 chapterHeadFor）。
   */
  image: string = '';
  /** CHAPTER_HEAD_PLACEMENTS 之一；空串是标题左侧。 */
  placement: string = '';
  /** 饰图大小倍数 0.5–2。左侧时 1 表示和整组标题一样高，上方、下方时 1 表示约一个标题字高。 */
  scale: number = 1;
  /** 分段标题第一段的颜色（可带透明度）；空串和标题同色。读者没开标题分段时不生效。 */
  numberColor: string = '';
  /**
   * 首字装饰占几行：0 不处理，2 或 3。这个模式没设时沿用另一种模式的整套首字设置（行数、印章图、字占比，
   * 颜色没另写时也跟着），见 chapterHeadFor。
   */
  dropCapLines: number = 0;
  /** 首字底下的印章图（包里是素材引用，运行时是本机 URI）；空串只放大不垫图。 */
  dropCapImage: string = '';
  /** 首字颜色（可带透明度）；空串和正文同色。 */
  dropCapColor: string = '';
  /** 垫印章图时字高占印章边长的比例 0.4–0.9。 */
  dropCapRatio: number = DROP_CAP_RATIO_DEFAULT;
}

export const DROP_CAP_RATIO_DEFAULT: number = 0.62;
export const DROP_CAP_RATIO_MIN: number = 0.4;
export const DROP_CAP_RATIO_MAX: number = 0.9;

export function normalizeDropCapRatio(value: number | null | undefined): number {
  if (typeof value !== 'number' || !isFinite(value) || value <= 0) return DROP_CAP_RATIO_DEFAULT;
  return Math.round(Math.max(DROP_CAP_RATIO_MIN, Math.min(DROP_CAP_RATIO_MAX, value)) * 100) / 100;
}

/** side：贴版心左边、上下居中于整组标题；top / bottom：在标题上方、下方单独占一行，跟着标题的对齐方式。 */
export const CHAPTER_HEAD_PLACEMENTS: string[] = ['side', 'top', 'bottom'];
export const CHAPTER_HEAD_PLACEMENT_NAMES: string[] = ['标题左侧', '标题上方', '标题下方'];
/** 方案覆盖里表示“不用章首装饰”（来源主题带了也不显示）。 */
export const CHAPTER_HEAD_NONE: string = 'none';

export function normalizeChapterHead(value: ThemePackageChapterHead | null | undefined): ThemePackageChapterHead {
  const result = new ThemePackageChapterHead();
  if (!value || typeof value !== 'object') return result;
  result.image = typeof value.image === 'string' ? value.image : '';
  result.placement = value.placement === 'top' || value.placement === 'bottom' ? value.placement : '';
  result.scale = normalizeOrnamentScale(value.scale);
  result.numberColor = typeof value.numberColor === 'string' && HEX_COLOR.test(value.numberColor) ?
    value.numberColor.toUpperCase() : '';
  // 本机旧记录里没有首字这几项。只写了印章图没写行数时按 2 行。
  result.dropCapImage = typeof value.dropCapImage === 'string' ? value.dropCapImage : '';
  // 桌面编辑器的工程里行数可能是字符串。
  const capLines = Number(value.dropCapLines);
  result.dropCapLines = capLines === 3 ? 3 : (capLines === 2 || result.dropCapImage ? 2 : 0);
  result.dropCapColor = typeof value.dropCapColor === 'string' && HEX_COLOR.test(value.dropCapColor) ?
    value.dropCapColor.toUpperCase() : '';
  result.dropCapRatio = normalizeDropCapRatio(value.dropCapRatio);
  return result;
}

export function chapterHeadIsEmpty(value: ThemePackageChapterHead | null | undefined): boolean {
  return !value || !(value.image || value.numberColor || value.dropCapLines > 0 || value.dropCapImage ||
    value.dropCapColor);
}

/**
 * 某个模式下实际用的章首装饰：饰图取这个模式的，没有就用另一种模式的（位置、大小跟着那张图）；
 * 序号行颜色各模式用各的。什么都没有时返回 null。
 */
export function chapterHeadFor(parts: ThemePackageParts | null | undefined, dark: boolean): ThemePackageChapterHead | null {
  if (!parts) return null;
  const ownVariant = dark ? parts.dark : parts.light;
  const otherVariant = dark ? parts.light : parts.dark;
  const own = normalizeChapterHead(ownVariant ? ownVariant.chapterHead : null);
  const other = normalizeChapterHead(otherVariant ? otherVariant.chapterHead : null);
  const result = new ThemePackageChapterHead();
  const imageSource = own.image ? own : (other.image ? other : null);
  if (imageSource) {
    result.image = imageSource.image;
    result.placement = imageSource.placement;
    result.scale = imageSource.scale;
  }
  result.numberColor = own.numberColor;
  const capSource = own.dropCapLines > 0 ? own : (other.dropCapLines > 0 ? other : null);
  if (capSource) {
    result.dropCapLines = capSource.dropCapLines;
    result.dropCapImage = capSource.dropCapImage;
    result.dropCapRatio = capSource.dropCapRatio;
    result.dropCapColor = own.dropCapColor || capSource.dropCapColor;
  }
  return chapterHeadIsEmpty(result) ? null : result;
}

export class ThemePackageTtsPanel {
  artwork: string = '';
  skyColor: string = '';
  surfaceColor: string = '';
  glowColor: string = '';
}

/**
 * 首页底栏图标（书架、发现、我的）。SVG 按主题色染色，位图保持原色；选中态图标可选，没给的页签选中时仍用普通图标。
 * listen / footprint 是可选第四个页签“听”“足迹”的图标，可以不给（用基底主题的图标）；旧版本应用会忽略。
 * labels 为 'hidden' 时底栏只显示图标。
 * search / searchSelected 是旧版底栏“搜索”页签的图标：读包时照收但不显示；导出时缺了就用发现的图标补上，
 * 旧版本应用要求四个图标齐全才肯导入。
 */
export class ThemePackageNavigation {
  bookshelf: string = '';
  explore: string = '';
  search: string = '';
  mine: string = '';
  bookshelfSelected: string = '';
  exploreSelected: string = '';
  searchSelected: string = '';
  mineSelected: string = '';
  listen: string = '';
  footprint: string = '';
  listenSelected: string = '';
  footprintSelected: string = '';
  labels: string = '';
}

export const NAVIGATION_ICON_KEYS: string[] = [
  'bookshelf', 'explore', 'search', 'mine', 'bookshelfSelected', 'exploreSelected', 'searchSelected', 'mineSelected',
  'listen', 'footprint', 'listenSelected', 'footprintSelected'
];

/** 一个图标都没有（labels 不算）。 */
export function navigationIsEmpty(navigation: ThemePackageNavigation | null | undefined): boolean {
  if (!navigation) return true;
  const record = navigation as Object as Record<string, string>;
  return !NAVIGATION_ICON_KEYS.some((key: string): boolean => !!record[key]);
}

/**
 * 位图素材的显示区域：图片文件不改，显示时把 (x, y, width, height) 这块放大铺满素材位，多出来的部分裁掉。
 * 动图取景用它保住动画（重新编码只能存单帧）。坐标是相对 imageWidth × imageHeight 的像素，只看比例，
 * 所以按任意缩放的同一张图都能用。image 是它所属的素材引用，跟素材位当前的图对不上时整条作废。
 * 旧版本应用不认这些字段，显示整张图。
 */
export class ThemeImageCrop {
  image: string = '';
  x: number = 0;
  y: number = 0;
  width: number = 0;
  height: number = 0;
  imageWidth: number = 0;
  imageHeight: number = 0;
}

export class ThemePackageBook {
  covers: string[] = [];
  // 深色模式单独的一套封面，可选：空着时深色也用 covers。旧版本应用不认这个字段，两种模式都显示 covers。
  coversDark: string[] = [];
  shelfFrame: string = '';
  // 深色模式单独的书架边框，可选，规则同文件夹插画。旧版本应用不认，两种模式都显示 shelfFrame。
  shelfFrameDark: string = '';
  shelfFolder: string = '';
  // 深色模式单独的文件夹插画，可选：空着时深色也用 shelfFolder。旧版本应用不认，两种模式都显示 shelfFolder。
  shelfFolderDark: string = '';
  // 按 image 对应到 covers 里的某一张；本机旧记录里没有这两个字段。
  coverCrops: ThemeImageCrop[] = [];
  // 同上，对应 coversDark。
  coverCropsDark: ThemeImageCrop[] = [];
  shelfFolderCrop: ThemeImageCrop | null = null;
  shelfFolderCropDark: ThemeImageCrop | null = null;
}

/**
 * 某个模式下实际显示的封面：深色优先用 coversDark，没有就用 covers（老主题包都是这样）；
 * 只给了深色封面时浅色也用它，免得一种模式有主题封面、另一种没有。
 */
export function bookCoversFor(book: ThemePackageBook | null | undefined, dark: boolean): string[] {
  if (!book) return [];
  const light: string[] = Array.isArray(book.covers) ? book.covers : [];
  const night: string[] = Array.isArray(book.coversDark) ? book.coversDark : [];
  if (dark) return night.length > 0 ? night : light;
  return light.length > 0 ? light : night;
}

/** 两套封面都没有。 */
export function bookHasNoCovers(book: ThemePackageBook | null | undefined): boolean {
  return bookCoversFor(book, false).length === 0;
}

/**
 * 写进包的 covers 超过老版本的 8 张上限（只有深色那套时它会写成 covers，一并算）：导出时清单要声明
 * book-covers-16-v1，老版本会提示先更新应用。coversDark 老版本不读，多少张都不用声明。
 */
export function partsUseManyCovers(parts: ThemePackageParts | null | undefined): boolean {
  return !!parts && !!parts.book && bookCoversFor(parts.book, false).length > ThemePackageLimits.LEGACY_MAX_COVERS;
}

/** 某个模式下显示的文件夹插画，规则同封面：深色优先用 shelfFolderDark，没有就用 shelfFolder；只给了深色那张时浅色也用它。 */
export function bookFolderFor(book: ThemePackageBook | null | undefined, dark: boolean): string {
  if (!book) return '';
  const light = book.shelfFolder || '';
  const night = book.shelfFolderDark || '';
  if (dark) return night || light;
  return light || night;
}

/** 某个模式下的书架边框，规则同文件夹插画。 */
export function bookShelfFrameFor(book: ThemePackageBook | null | undefined, dark: boolean): string {
  if (!book) return '';
  const light = book.shelfFrame || '';
  const night = book.shelfFrameDark || '';
  if (dark) return night || light;
  return light || night;
}

/** 封面、边框、文件夹插画一样都没有：整节可以去掉。 */
export function bookIsEmpty(book: ThemePackageBook | null | undefined): boolean {
  return !book || (bookHasNoCovers(book) && !bookShelfFrameFor(book, false) && !bookFolderFor(book, false));
}

/** 书架的四种布局，取值同应用的 bookshelfLayoutMode。 */
export const SHELF_BACKDROP_LAYOUTS: string[] = ['companion', 'tile', 'loose', 'compact'];

/**
 * 某种书架布局专属的首页背景（包里写在 shelfBackdrop.<布局>）：只在书架页、用这种布局时显示，
 * 没写的模式沿用通用首页背景。浅色、深色互不借用。旧版本应用不认这一节，书架照旧显示通用那张。
 */
export class ThemePackageShelfBackdrop {
  layout: string = '';
  light: string = '';
  dark: string = '';
  lightCrop: ThemeImageCrop | null = null;
  darkCrop: ThemeImageCrop | null = null;
}

/** 与 SHELF_BACKDROP_LAYOUTS 一一对应的名称。 */
export const SHELF_BACKDROP_LAYOUT_NAMES: string[] = ['陪伴', '平铺', '宽松', '紧凑'];

/** 认得的书架布局原样返回，其余（含空）返回空串。 */
export function normalizeShelfBackdropLayout(layout: string | null | undefined): string {
  const value = (layout || '').trim().toLowerCase();
  return SHELF_BACKDROP_LAYOUTS.includes(value) ? value : '';
}

export function findShelfBackdrop(list: ThemePackageShelfBackdrop[] | null | undefined,
  layout: string): ThemePackageShelfBackdrop | null {
  if (!layout || !Array.isArray(list)) return null;
  for (const item of list) {
    if (item && item.layout === layout) return item;
  }
  return null;
}

/** 某种布局、某个模式的专属背景；没有时返回空串（由调用方退回通用首页背景）。 */
export function shelfBackdropFor(list: ThemePackageShelfBackdrop[] | null | undefined, layout: string,
  dark: boolean): string {
  const item = findShelfBackdrop(list, normalizeShelfBackdropLayout(layout));
  return item ? ((dark ? item.dark : item.light) || '') : '';
}

export class ThemePackageStartup {
  image: string = '';
  title: string = '';
  subtitle: string = '';
}

/**
 * 气泡边框的拉伸线，都是占原图宽或高的比例：left / right 是两端不拉伸的宽度，top / bottom 是文字行上下
 * 留在外面的高度。阅读页把 top–bottom 之间对齐强调文字那一行，线外的部分照样画出；left–right 之间是中段，
 * 按长度拉伸或平铺，两端按比例缩放保持原样。
 */
export class ThemePackageBubbleSlice {
  left: number = 0;
  right: number = 0;
  top: number = 0;
  bottom: number = 0;
}

export class BubbleFrameRepeat {
  static readonly STRETCH: string = 'stretch';
  static readonly ROUND: string = 'round';
}

export class BubbleFrameBreak {
  /** 换行处每行都画两端。 */
  static readonly FULL: string = 'full';
  /** 换行处不画端头，边框在断开处平切。 */
  static readonly CUT: string = 'cut';
}

export class ThemePackageBubble {
  frame: string = '';
  cap: string = '';
  // 以下四项只对边框有效；缺省时用 bubbleFrameSliceOrDefault 的位置、拉伸、每行两端、保留原色。
  frameSlice: ThemePackageBubbleSlice | null = null;
  frameRepeat: string = '';
  frameBreak: string = '';
  /** 染成气泡底色（强调设置里的底色，浅深各用各的）。 */
  frameTint: boolean = false;
}

/** 拉伸线每一项允许的范围：两端合起来、上下合起来都不能吃掉整张图。 */
export const BUBBLE_FRAME_SLICE_MAX: number = 0.49;

/**
 * 没设拉伸线时的默认位置：上下贴图边，左右各留“图高 × 0.6”，最多各占图宽的 30%。aspect 是原图宽 / 高。
 */
export function defaultBubbleFrameSlice(aspect: number): ThemePackageBubbleSlice {
  const slice = new ThemePackageBubbleSlice();
  const ratio = aspect > 0 && isFinite(aspect) ? aspect : 3;
  const end = Math.min(0.6 / ratio, 0.3);
  slice.left = end;
  slice.right = end;
  return slice;
}

export function normalizeBubbleFrameSlice(slice: ThemePackageBubbleSlice | null | undefined): ThemePackageBubbleSlice | null {
  if (!slice) return null;
  const clamp = (value: number): number =>
    typeof value === 'number' && isFinite(value) ? Math.max(0, Math.min(BUBBLE_FRAME_SLICE_MAX, value)) : 0;
  const result = new ThemePackageBubbleSlice();
  result.left = Math.round(clamp(slice.left) * 10000) / 10000;
  result.right = Math.round(clamp(slice.right) * 10000) / 10000;
  result.top = Math.round(clamp(slice.top) * 10000) / 10000;
  result.bottom = Math.round(clamp(slice.bottom) * 10000) / 10000;
  return result;
}

export function bubbleFrameSliceOrDefault(slice: ThemePackageBubbleSlice | null | undefined,
  aspect: number): ThemePackageBubbleSlice {
  return normalizeBubbleFrameSlice(slice) || defaultBubbleFrameSlice(aspect);
}

function copyBubbleFrame(target: ThemePackageBubble, source: ThemePackageBubble): void {
  target.frame = source.frame;
  target.frameSlice = source.frameSlice ? normalizeBubbleFrameSlice(source.frameSlice) : null;
  target.frameRepeat = source.frameRepeat || '';
  target.frameBreak = source.frameBreak || '';
  target.frameTint = source.frameTint === true;
}

/**
 * 某个模式下实际用的气泡素材：端饰、边框各自取这个模式的，没有就用另一种模式的（只给了一种模式时两种都用它）。
 * 拉伸线、平铺、换行方式、染色跟着所属的那张边框走。两种模式都没有时返回 null。
 */
export function bubbleFor(parts: ThemePackageParts | null | undefined, dark: boolean): ThemePackageBubble | null {
  if (!parts) return null;
  return bubblePairFor(parts.bubble, parts.bubbleDark, dark);
}

/** 标题气泡（titleBubble / titleBubbleDark），规则同 bubbleFor。 */
export function titleBubbleFor(parts: ThemePackageParts | null | undefined, dark: boolean): ThemePackageBubble | null {
  if (!parts) return null;
  return bubblePairFor(parts.titleBubble || null, parts.titleBubbleDark || null, dark);
}

export function titleBubbleDarkDifference(parts: ThemePackageParts | null | undefined): ThemePackageBubble | null {
  return bubblePairDifference(titleBubbleFor(parts, false), titleBubbleFor(parts, true));
}

function bubblePairFor(lightBubble: ThemePackageBubble | null, darkBubble: ThemePackageBubble | null,
  dark: boolean): ThemePackageBubble | null {
  const own = dark ? darkBubble : lightBubble;
  const other = dark ? lightBubble : darkBubble;
  const result = new ThemePackageBubble();
  result.cap = (own && own.cap) || (other && other.cap) || '';
  const frameSource = own && own.frame ? own : (other && other.frame ? other : null);
  if (frameSource) copyBubbleFrame(result, frameSource);
  return result.cap || result.frame ? result : null;
}

function sameBubbleFrame(a: ThemePackageBubble, b: ThemePackageBubble): boolean {
  return a.frame === b.frame && JSON.stringify(normalizeBubbleFrameSlice(a.frameSlice)) ===
    JSON.stringify(normalizeBubbleFrameSlice(b.frameSlice)) && (a.frameRepeat || '') === (b.frameRepeat || '') &&
    (a.frameBreak || '') === (b.frameBreak || '') && (a.frameTint === true) === (b.frameTint === true);
}

/**
 * 写进包的深色气泡：只留与浅色不同的那几项（浅色写成 bubble，见 bubbleFor）。两种模式一样时为 null。
 */
export function bubbleDarkDifference(parts: ThemePackageParts | null | undefined): ThemePackageBubble | null {
  return bubblePairDifference(bubbleFor(parts, false), bubbleFor(parts, true));
}

function bubblePairDifference(light: ThemePackageBubble | null, dark: ThemePackageBubble | null): ThemePackageBubble | null {
  if (!light || !dark) return null;
  const result = new ThemePackageBubble();
  if (dark.cap && dark.cap !== light.cap) result.cap = dark.cap;
  if (dark.frame && !sameBubbleFrame(dark, light)) copyBubbleFrame(result, dark);
  return result.cap || result.frame ? result : null;
}

/** 气泡边框是位图，或只有边框没有端饰：导出时清单要声明 bubble-frame-v1。看的是写成 bubble 的浅色那套。 */
export function partsUseBubbleFrameFeature(parts: ThemePackageParts | null | undefined): boolean {
  const bubble = bubbleFor(parts, false);
  if (!bubble || !bubble.frame) return false;
  if (!bubble.cap) return true;
  const extension = assetPathExtension(bubble.frame) || fileExtensionOf(bubble.frame);
  return kindForExtension(extension) === ThemePackageAssetKinds.IMAGE;
}

/**
 * 气泡端饰或书架边框是位图（浅色、深色任意一张）：导出时清单要声明 bitmap-cap-shelf-frame-v1。
 * 认得深色那套字段的老版本同样只收 SVG，所以深色那张是位图也要声明。
 */
export function partsUseBitmapCapOrShelfFrame(parts: ThemePackageParts | null | undefined): boolean {
  if (!parts) return false;
  const bitmap = (path: string): boolean => !!path &&
    kindForExtension(assetPathExtension(path) || fileExtensionOf(path)) === ThemePackageAssetKinds.IMAGE;
  return (!!parts.bubble && bitmap(parts.bubble.cap)) || (!!parts.bubbleDark && bitmap(parts.bubbleDark.cap)) ||
    (!!parts.book && (bitmap(parts.book.shelfFrame) || bitmap(parts.book.shelfFrameDark)));
}

function fileExtensionOf(path: string): string {
  const match = /\.([A-Za-z0-9]{2,5})$/.exec(path || '');
  if (!match) return '';
  const extension = match[1].toLowerCase();
  return extension === 'jpeg' ? 'jpg' : extension;
}

/** 主题包自带的部件。素材字段存 qytheme-asset:<id> 引用；为空或为 null 的部件回退到基底主题。 */
export class ThemePackageParts {
  light: ThemePackageVariantParts | null = null;
  dark: ThemePackageVariantParts | null = null;
  ttsPanelLight: ThemePackageTtsPanel | null = null;
  ttsPanelDark: ThemePackageTtsPanel | null = null;
  navigation: ThemePackageNavigation | null = null;
  book: ThemePackageBook | null = null;
  startupLight: ThemePackageStartup | null = null;
  startupDark: ThemePackageStartup | null = null;
  bubble: ThemePackageBubble | null = null;
  // 深色模式单独的气泡素材，可选；端饰、边框按项沿用 bubble（见 bubbleFor）。旧版本应用不认，两种模式都用 bubble。
  bubbleDark: ThemePackageBubble | null = null;
  // 标题强调用的端饰与边框（标题气泡），深色那套按项沿用浅色（见 titleBubbleFor）。本机旧记录里没有，旧版本应用不认。
  titleBubble: ThemePackageBubble | null = null;
  titleBubbleDark: ThemePackageBubble | null = null;
  // 深色模式单独的导航图标，可选；没给的图标沿用 navigation，labels 只看 navigation。旧版本应用不认。
  navigationDark: ThemePackageNavigation | null = null;
  // 首页三个页签顶部的背景图；只写了一种模式时另一种模式不显示背景。
  homeBackdropLight: string = '';
  homeBackdropDark: string = '';
  // 包里写在 homeBackdrop.lightCrop / darkCrop；本机旧记录里没有。
  homeBackdropLightCrop: ThemeImageCrop | null = null;
  homeBackdropDarkCrop: ThemeImageCrop | null = null;
  // 按书架布局分别给的背景，每种布局最多一条；本机旧记录里没有。
  shelfBackdrops: ThemePackageShelfBackdrop[] = [];
  logo: string = '';
  preview: string = '';
  radius: Record<string, number> | null = null;
  appFont: string = '';
  appFontFamily: string = '';
}

export class ThemePackageTheme {
  // AppThemeSettings 的 JSON 形式，图片路径替换为 qytheme-asset:<id>；格式 2 的手写包可以没有。
  settingsJson: string = '';
  // 方案排版：LAYOUT_KEYS 列出的阅读设置字段。
  layoutJson: string = '';
  emphasis: ThemePackageEmphasis | null = null;
  fonts: ThemePackageFont[] = [];
  parts: ThemePackageParts | null = null;
}

/**
 * 随主题走的阅读排版字段：正文、标题、缩进、边距、段评气泡大小、正文扩展至状态栏、页眉页脚与进度条、
 * 方案字体绑定，与主题排版页能设置的内容一致（强调规则另在 emphasis 里）。翻页和手势不属于主题。
 * 旧版本导入时按自己的列表取字段，多出的键会被忽略。
 */
export const LAYOUT_KEYS: string[] = [
  'fontSize', 'fontWeight', 'letterSpacing', 'textAlign', 'lineHeight', 'paragraphSpacing', 'paragraphIndent',
  'marginLeft', 'marginRight', 'marginTop', 'marginBottom', 'commentBubbleSize', 'extendToStatusBar',
  'readerHeaderEnabled', 'readerHeaderContentMode', 'readerFooterEnabled', 'readerFooterLeftMode',
  'readerFooterProgressMode', 'readerFooterShowProgressBar', 'readerInfoBarConfig',
  'bodyFontMode', 'bodyFontFamily', 'titleFontMode', 'titleFontFamily', 'titleFontSize', 'titleFontWeight', 'titleStyleRaw'
];

/** 方案设置里可能指向本机图片文件的字段。 */
export const IMAGE_SETTING_KEYS: string[] = [
  'customLightStartupImagePath', 'customDarkStartupImagePath', 'customPreviewImagePath',
  'customLightReaderBackgroundAssetId', 'customDarkReaderBackgroundAssetId'
];

export const RADIUS_KEYS: string[] = ['small', 'medium', 'large', 'card', 'button', 'bubble'];

export class ThemeSourceField {
  key: string = '';
  label: string = '';

  constructor(key: string, label: string) {
    this.key = key;
    this.label = label;
  }
}

export const THEME_SOURCE_FIELDS: ThemeSourceField[] = [
  new ThemeSourceField('startupThemeId', '启动封面'),
  new ThemeSourceField('paletteThemeId', '完整配色'),
  new ThemeSourceField('readerThemeId', '阅读背景'),
  new ThemeSourceField('ttsPanelThemeId', '朗读/有声书面板'),
  new ThemeSourceField('bubbleThemeId', '强调气泡'),
  new ThemeSourceField('navigationThemeId', '导航图标'),
  new ThemeSourceField('bookThemeId', '书籍素材'),
  new ThemeSourceField('homeBackdropThemeId', '首页背景'),
  new ThemeSourceField('typographyThemeId', '字体'),
  new ThemeSourceField('layoutThemeId', '阅读排版'),
  new ThemeSourceField('radiusThemeId', '圆角形状')
];

export function assetRef(id: string): string {
  return `${QYTHEME_ASSET_PREFIX}${id}`;
}

export function assetIdFromRef(value: string): string {
  return typeof value === 'string' && value.startsWith(QYTHEME_ASSET_PREFIX) ?
    value.substring(QYTHEME_ASSET_PREFIX.length) : '';
}

/** 本机文件（file:// 或绝对路径）；内置素材是不带斜杠的资源键。 */
export function isLocalFileReference(value: string): boolean {
  return typeof value === 'string' && (value.startsWith('file://') || value.startsWith('/'));
}

// ---- 主题包的主题 ID ----

const PACKAGE_ID_PATTERN: RegExp = /^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$/;

export function isValidPackageId(value: string): boolean {
  return typeof value === 'string' && PACKAGE_ID_PATTERN.test(value) && !value.includes('..');
}

export function packThemeId(packageId: string): string {
  return `${PACK_THEME_PREFIX}${packageId}`;
}

export function isPackThemeId(themeId: string): boolean {
  return typeof themeId === 'string' && themeId.startsWith(PACK_THEME_PREFIX) &&
    isValidPackageId(themeId.substring(PACK_THEME_PREFIX.length).split(':')[0]);
}

/** pack:<packageId> 或 pack:<packageId>:<后缀> 里的 packageId；不是主题包 ID 时返回空串。 */
export function packageIdOfThemeId(themeId: string): string {
  return isPackThemeId(themeId) ? themeId.substring(PACK_THEME_PREFIX.length).split(':')[0] : '';
}

/** 主题包阅读背景的素材键：pack:<packageId>:light / :dark。 */
export function packReaderBackgroundId(packageId: string, darkMode: boolean): string {
  return `${packThemeId(packageId)}:${darkMode ? 'dark' : 'light'}`;
}

function stripControlChars(value: string): string {
  let result = '';
  for (let i = 0; i < value.length; i++) {
    const code = value.charCodeAt(i);
    if (code < 0x20 || code === 0x7F || (code >= 0x200B && code <= 0x200F) || (code >= 0x202A && code <= 0x202E) ||
      (code >= 0x2066 && code <= 0x2069)) {
      continue;
    }
    result += value.charAt(i);
  }
  return result;
}

function limitChars(value: string, max: number): string {
  const chars = Array.from(value);
  return chars.length > max ? chars.slice(0, max).join('') : value;
}

/** 署名只做展示：去掉换行、控制字符和改变书写方向的字符，限制长度。 */
export function sanitizeAuthor(raw: string): string {
  return limitChars(stripControlChars((raw || '').replace(/\s+/g, ' ')).trim(), ThemePackageLimits.MAX_AUTHOR_LENGTH);
}

export function sanitizeThemeName(raw: string): string {
  return limitChars(stripControlChars((raw || '').replace(/\s+/g, ' ')).trim(), ThemePackageLimits.MAX_NAME_LENGTH);
}

export function sanitizeDescription(raw: string): string {
  return limitChars(stripControlChars((raw || '').replace(/\s+/g, ' ')).trim(),
    ThemePackageLimits.MAX_DESCRIPTION_LENGTH);
}

function sanitizeStartupText(raw: string): string {
  return limitChars(stripControlChars((raw || '').replace(/\s+/g, ' ')).trim(),
    ThemePackageLimits.MAX_STARTUP_TEXT_LENGTH);
}

/** 用于导出文件名：去掉文件系统不允许的字符。 */
export function packageFileName(name: string): string {
  const base = sanitizeThemeName(name).replace(/[\\/:*?"<>|]/g, '_').trim() || '主题';
  return `${base}${QYTHEME_EXTENSION}`;
}

export function assetPath(id: string, extension: string): string {
  return `assets/${id}.${extension}`;
}

const ASSET_PATH_PATTERN: RegExp = /^assets\/([A-Za-z0-9][A-Za-z0-9_-]{0,63})\.([a-z0-9]{2,5})$/;

/** 格式 2 的素材路径：assets/ 下一层、安全字符、带认得的扩展名。返回规范扩展名，不合法时返回空串。 */
export function assetPathExtension(path: string): string {
  const match = ASSET_PATH_PATTERN.exec(path || '');
  if (!match) return '';
  const extension = match[2] === 'jpeg' ? 'jpg' : match[2];
  return kindForExtension(extension) ? extension : '';
}

export function isAssetPathReference(value: string): boolean {
  return typeof value === 'string' && value.startsWith('assets/');
}

function svgHead(head: Uint8Array): boolean {
  let text = '';
  let start = 0;
  if (head.length >= 3 && head[0] === 0xEF && head[1] === 0xBB && head[2] === 0xBF) start = 3;
  for (let i = start; i < head.length; i++) {
    text += String.fromCharCode(head[i]);
  }
  const trimmed = text.replace(/^\s+/, '');
  return trimmed.startsWith('<svg') || trimmed.startsWith('<?xml') || trimmed.startsWith('<!--');
}

/** 根据文件头判断素材类型，返回规范扩展名；无法识别时返回空串。 */
export function sniffAssetExtension(head: Uint8Array): string {
  if (head.length >= 8 && head[0] === 0x89 && head[1] === 0x50 && head[2] === 0x4E && head[3] === 0x47) return 'png';
  if (head.length >= 3 && head[0] === 0xFF && head[1] === 0xD8 && head[2] === 0xFF) return 'jpg';
  if (head.length >= 12 && head[0] === 0x52 && head[1] === 0x49 && head[2] === 0x46 && head[3] === 0x46 &&
    head[8] === 0x57 && head[9] === 0x45 && head[10] === 0x42 && head[11] === 0x50) return 'webp';
  if (head.length >= 6 && head[0] === 0x47 && head[1] === 0x49 && head[2] === 0x46 && head[3] === 0x38) return 'gif';
  if (head.length >= 2 && head[0] === 0x42 && head[1] === 0x4D) return 'bmp';
  if (head.length >= 4) {
    if (head[0] === 0x00 && head[1] === 0x01 && head[2] === 0x00 && head[3] === 0x00) return 'ttf';
    if (head[0] === 0x74 && head[1] === 0x72 && head[2] === 0x75 && head[3] === 0x65) return 'ttf';
    if (head[0] === 0x4F && head[1] === 0x54 && head[2] === 0x54 && head[3] === 0x4F) return 'otf';
    if (head[0] === 0x74 && head[1] === 0x74 && head[2] === 0x63 && head[3] === 0x66) return 'ttc';
  }
  if (svgHead(head)) return 'svg';
  return '';
}

export function kindForExtension(extension: string): string {
  if (IMAGE_EXTENSIONS.includes(extension)) return ThemePackageAssetKinds.IMAGE;
  if (FONT_EXTENSIONS.includes(extension)) return ThemePackageAssetKinds.FONT;
  if (VECTOR_EXTENSIONS.includes(extension)) return ThemePackageAssetKinds.VECTOR;
  return '';
}

export function maxBytesForKind(kind: string): number {
  if (kind === ThemePackageAssetKinds.FONT) return ThemePackageLimits.MAX_FONT_BYTES;
  if (kind === ThemePackageAssetKinds.VECTOR) return ThemePackageLimits.MAX_VECTOR_BYTES;
  return ThemePackageLimits.MAX_IMAGE_BYTES;
}

/**
 * 包内 SVG 必须自包含：不得加载外部内容、脚本或引用。与 theme-framework-check 对内置资源的规则一致。
 * 返回错误说明，合法时返回空串。
 */
export function checkSvgSource(text: string): string {
  if (!text || text.length > ThemePackageLimits.MAX_VECTOR_BYTES) return 'SVG 过大';
  const lower = text.toLowerCase();
  if (!lower.includes('<svg')) return '不是 SVG 文件';
  const banned: string[] = ['<script', '<image', '<use', '<filter', '<foreignobject', 'href=', 'url(', 'javascript:',
    '<!entity', '<iframe', '<embed', '<object'];
  for (const token of banned) {
    if (lower.includes(token)) return `SVG 含有不允许的内容（${token}）`;
  }
  return '';
}

function isHex(value: string, minLength: number, maxLength: number): boolean {
  return typeof value === 'string' && value.length >= minLength && value.length <= maxLength &&
    /^[0-9a-f]+$/.test(value);
}

function parseJsonObject(text: string, label: string): Record<string, Object> {
  if (!text || text.length > ThemePackageLimits.MAX_JSON_BYTES) {
    throw new Error(`主题包的${label}缺失或过大`);
  }
  let parsed: Object;
  try {
    parsed = JSON.parse(text) as Object;
  } catch (_) {
    throw new Error(`主题包的${label}已损坏`);
  }
  if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
    throw new Error(`主题包的${label}已损坏`);
  }
  return parsed as Record<string, Object>;
}

function objectField(record: Record<string, Object>, key: string): Record<string, Object> | null {
  const value = record[key];
  return value && typeof value === 'object' && !Array.isArray(value) ? value as Record<string, Object> : null;
}

function stringField(record: Record<string, Object>, key: string): string {
  const value = record[key];
  return typeof value === 'string' ? value : '';
}

function numberField(record: Record<string, Object>, key: string): number {
  const value = record[key];
  return typeof value === 'number' && isFinite(value) ? value : 0;
}

export function encodeManifest(manifest: ThemePackageManifest): string {
  const record: Record<string, Object> = {};
  record['format'] = manifest.format;
  record['formatVersion'] = manifest.formatVersion;
  record['packageId'] = manifest.packageId;
  record['name'] = manifest.name;
  record['author'] = manifest.author;
  record['exportedAt'] = manifest.exportedAt;
  record['appVersion'] = manifest.appVersion;
  record['requires'] = manifest.requires;
  if (manifest.formatVersion >= 2) {
    if (manifest.version) record['version'] = manifest.version;
    if (manifest.description) record['description'] = manifest.description;
    if (manifest.baseTheme) record['baseTheme'] = manifest.baseTheme;
    if (manifest.credits) record['credits'] = manifest.credits;
  }
  record['assets'] = manifest.assets;
  return JSON.stringify(record, null, 2);
}

/** 校验并规范化 manifest.json。格式版本或必需能力超出本版本时提示更新应用。 */
export function decodeManifest(text: string): ThemePackageManifest {
  const record = parseJsonObject(text, '清单');
  if (stringField(record, 'format') !== QYTHEME_FORMAT) {
    throw new Error('这不是轻页主题包');
  }
  const version = numberField(record, 'formatVersion');
  if (version < 1 || Math.floor(version) !== version) {
    throw new Error('主题包版本无效');
  }
  if (version > QYTHEME_FORMAT_VERSION) {
    throw new Error('这个主题包来自更新版本的应用，请先更新应用再导入');
  }
  const manifest = new ThemePackageManifest();
  manifest.formatVersion = version;
  manifest.packageId = limitChars(stringField(record, 'packageId'), 64);
  manifest.name = sanitizeThemeName(stringField(record, 'name')) || '导入的主题';
  manifest.author = sanitizeAuthor(stringField(record, 'author'));
  manifest.exportedAt = numberField(record, 'exportedAt');
  manifest.appVersion = limitChars(stringField(record, 'appVersion'), 32);
  const requires = record['requires'];
  if (!Array.isArray(requires) || requires.length > 16) {
    throw new Error('主题包清单已损坏');
  }
  for (const item of requires as Object[]) {
    if (typeof item !== 'string') {
      throw new Error('主题包清单已损坏');
    }
    if (!ThemePackageFeatures.KNOWN.includes(item)) {
      throw new Error('这个主题包用到了当前版本不支持的功能，请先更新应用再导入');
    }
    manifest.requires.push(item);
  }
  if (!manifest.requires.includes(ThemePackageFeatures.CUSTOM_SCHEME)) {
    throw new Error('主题包清单已损坏');
  }
  if (version >= 2) {
    if (!isValidPackageId(manifest.packageId)) {
      throw new Error('主题包的 packageId 只能用字母、数字、点、连字符和下划线，且不超过 64 个字符');
    }
    manifest.version = limitChars(stripControlChars(stringField(record, 'version')),
      ThemePackageLimits.MAX_VERSION_LENGTH);
    manifest.description = sanitizeDescription(stringField(record, 'description'));
    manifest.baseTheme = limitChars(stringField(record, 'baseTheme'), 64);
    const credits = objectField(record, 'credits');
    if (credits) {
      manifest.credits = new ThemePackageCredits();
      manifest.credits.packageId = limitChars(stringField(credits, 'packageId'), 64);
      manifest.credits.name = sanitizeThemeName(stringField(credits, 'name'));
      manifest.credits.author = sanitizeAuthor(stringField(credits, 'author'));
    }
  }
  const assets = record['assets'];
  if (assets === undefined || assets === null) {
    if (version < 2) {
      throw new Error('主题包清单已损坏');
    }
    manifest.assetsDeclared = false;
    return manifest;
  }
  if (!Array.isArray(assets)) {
    throw new Error('主题包清单已损坏');
  }
  if (assets.length > maxAssetsFor(manifest.requires)) {
    throw new Error(tooManyAssetsMessage(assets.length, manifest.requires));
  }
  const ids = new Set<string>();
  const paths = new Set<string>();
  for (const item of assets as Object[]) {
    if (!item || typeof item !== 'object') {
      throw new Error('主题包清单已损坏');
    }
    const source = item as Record<string, Object>;
    const asset = new ThemePackageAsset();
    asset.id = stringField(source, 'id');
    asset.kind = stringField(source, 'kind');
    asset.size = numberField(source, 'size');
    asset.sha256 = stringField(source, 'sha256').toLowerCase();
    asset.path = stringField(source, 'path');
    asset.name = limitChars(stripControlChars(stringField(source, 'name')), 60);
    if (version < 2) {
      if (!isHex(asset.id, 16, 64) || ids.has(asset.id) || !isHex(asset.sha256, 64, 64) ||
        !asset.sha256.startsWith(asset.id.substring(0, 16))) {
        throw new Error('主题包清单已损坏');
      }
      const dot = asset.path.lastIndexOf('.');
      const extension = dot > 0 ? asset.path.substring(dot + 1) : '';
      if (asset.path !== assetPath(asset.id, extension) || kindForExtension(extension) !== asset.kind) {
        throw new Error('主题包清单已损坏');
      }
      if (asset.kind === ThemePackageAssetKinds.VECTOR) {
        throw new Error('主题包清单已损坏');
      }
    } else {
      // 手写清单：路径决定类型；摘要与大小可以不写，写了就在导入时核对；ID 由导入方按内容生成。
      const extension = assetPathExtension(asset.path);
      if (!extension || paths.has(asset.path)) {
        throw new Error(`主题包清单里的素材路径不合法：${limitChars(stripControlChars(asset.path), 80)}`);
      }
      const kind = kindForExtension(extension);
      if (asset.kind && asset.kind !== kind) {
        throw new Error('主题包清单已损坏');
      }
      asset.kind = kind;
      if (asset.sha256 && !isHex(asset.sha256, 64, 64)) {
        throw new Error('主题包清单已损坏');
      }
      asset.id = asset.sha256 ? asset.sha256.substring(0, 24) : '';
      if (asset.size < 0 || Math.floor(asset.size) !== asset.size) {
        throw new Error('主题包清单已损坏');
      }
    }
    const maxSize = maxBytesForKind(asset.kind);
    if ((version < 2 && asset.size <= 0) || asset.size > maxSize) {
      throw new Error('主题包素材超出大小上限');
    }
    if (asset.kind === ThemePackageAssetKinds.FONT && !manifest.requires.includes(ThemePackageFeatures.FONTS)) {
      throw new Error('主题包清单已损坏');
    }
    if (asset.id) ids.add(asset.id);
    paths.add(asset.path);
    manifest.assets.push(asset);
  }
  return manifest;
}

export function findAsset(manifest: ThemePackageManifest, id: string): ThemePackageAsset | null {
  for (const asset of manifest.assets) {
    if (asset.id === id) return asset;
  }
  return null;
}

export function findAssetByPath(manifest: ThemePackageManifest, path: string): ThemePackageAsset | null {
  for (const asset of manifest.assets) {
    if (asset.path === path) return asset;
  }
  return null;
}

/** 解析 theme.json 里的素材引用：qytheme-asset:<id>，或格式 2 的 assets/<文件名>。 */
export function resolveAssetRef(manifest: ThemePackageManifest, value: string): ThemePackageAsset | null {
  if (typeof value !== 'string' || !value) return null;
  const id = assetIdFromRef(value);
  if (id) return findAsset(manifest, id);
  if (manifest.formatVersion >= 2 && isAssetPathReference(value)) {
    return findAssetByPath(manifest, value);
  }
  return null;
}

export function encodeTheme(theme: ThemePackageTheme): string {
  const record: Record<string, Object> = {};
  if (theme.settingsJson) record['settings'] = JSON.parse(theme.settingsJson) as Object;
  if (theme.layoutJson) record['layout'] = JSON.parse(theme.layoutJson) as Object;
  if (theme.emphasis) {
    const emphasis: Record<string, Object> = {};
    emphasis['enabled'] = theme.emphasis.enabled;
    emphasis['rules'] = JSON.parse(theme.emphasis.rulesJson) as Object;
    record['emphasis'] = emphasis;
  }
  record['fonts'] = theme.fonts;
  if (theme.parts) record['parts'] = encodeParts(theme.parts);
  return JSON.stringify(record, null, 2);
}

/** 校验 theme.json：只保留认得的字段；引用的素材必须在清单里，且类型对得上。 */
export function decodeTheme(text: string, manifest: ThemePackageManifest): ThemePackageTheme {
  const record = parseJsonObject(text, '主题设置');
  const theme = new ThemePackageTheme();
  const parts = objectField(record, 'parts');
  if (parts) {
    if (!manifest.requires.includes(ThemePackageFeatures.THEME_PARTS) || manifest.formatVersion < 2) {
      throw new Error('主题包清单已损坏');
    }
    theme.parts = decodeParts(parts, manifest);
  }
  const settings = objectField(record, 'settings');
  if (!settings && (!theme.parts || manifest.formatVersion < 2)) {
    throw new Error('主题包的主题设置已损坏');
  }
  if (settings) {
    const settingsRecord = settings;
    for (const key of IMAGE_SETTING_KEYS) {
      const value = settingsRecord[key];
      if (typeof value !== 'string' || !value) continue;
      if (isLocalFileReference(value)) {
        throw new Error('主题包引用了导出设备上的文件，无法导入');
      }
      const asset = resolveAssetRef(manifest, value);
      if (asset) {
        if (asset.kind !== ThemePackageAssetKinds.IMAGE) {
          throw new Error('主题包缺少图片素材');
        }
        settingsRecord[key] = assetRef(asset.id);
      } else if (assetIdFromRef(value) || isAssetPathReference(value)) {
        throw new Error('主题包缺少图片素材');
      } else if (key.endsWith('ImagePath')) {
        // 启动封面只接受包内图片，没有就是空。
        settingsRecord[key] = '';
      }
    }
    if (theme.parts) {
      replaceSelfPackId(settingsRecord, packThemeId(manifest.packageId));
    }
    theme.settingsJson = JSON.stringify(settingsRecord);
  }
  const layout = record['layout'];
  if (layout && typeof layout === 'object' && !Array.isArray(layout)) {
    if (!manifest.requires.includes(ThemePackageFeatures.READER_LAYOUT)) {
      throw new Error('主题包清单已损坏');
    }
    theme.layoutJson = JSON.stringify(pickLayout(layout as Record<string, Object>));
  }
  const emphasis = record['emphasis'];
  if (emphasis && typeof emphasis === 'object' && !Array.isArray(emphasis)) {
    if (!manifest.requires.includes(ThemePackageFeatures.EMPHASIS_RULES)) {
      throw new Error('主题包清单已损坏');
    }
    const emphasisRecord = emphasis as Record<string, Object>;
    const rules = emphasisRecord['rules'];
    if (!Array.isArray(rules) || rules.length > ThemePackageLimits.MAX_RULES) {
      throw new Error('主题包的强调规则已损坏');
    }
    theme.emphasis = new ThemePackageEmphasis();
    theme.emphasis.enabled = emphasisRecord['enabled'] === true;
    theme.emphasis.rulesJson = JSON.stringify(rules);
  }
  const fonts = record['fonts'];
  if (Array.isArray(fonts)) {
    if (fonts.length > ThemePackageLimits.MAX_ASSETS) {
      throw new Error('主题包的字体信息已损坏');
    }
    for (const item of fonts as Object[]) {
      if (!item || typeof item !== 'object') continue;
      const source = item as Record<string, Object>;
      const font = new ThemePackageFont();
      font.family = limitChars(stringField(source, 'family'), 120);
      font.name = limitChars(stripControlChars(stringField(source, 'name')), 60);
      const ref = stringField(source, 'assetId');
      if (!font.family) continue;
      if (ref) {
        const asset = resolveAssetRef(manifest, ref) || findAsset(manifest, ref);
        if (!asset || asset.kind !== ThemePackageAssetKinds.FONT) {
          throw new Error('主题包缺少字体文件');
        }
        font.assetId = asset.id;
      }
      theme.fonts.push(font);
    }
  }
  return theme;
}

/** 方案设置里 pack:self 换成这个包安装后的主题 ID。 */
export function replaceSelfPackId(settings: Record<string, Object>, ownThemeId: string): void {
  if (settings['customBaseThemeId'] === PACK_SELF_THEME_ID) settings['customBaseThemeId'] = ownThemeId;
  for (const modeKey of ['customLightSources', 'customDarkSources']) {
    const sources = objectField(settings, modeKey);
    if (!sources) continue;
    for (const field of THEME_SOURCE_FIELDS) {
      if (sources[field.key] === PACK_SELF_THEME_ID) sources[field.key] = ownThemeId;
    }
  }
  for (const key of ['customLightReaderBackgroundAssetId', 'customDarkReaderBackgroundAssetId']) {
    const value = settings[key];
    if (typeof value === 'string' && value.startsWith(`${PACK_SELF_THEME_ID}:`)) {
      settings[key] = `${ownThemeId}${value.substring(PACK_SELF_THEME_ID.length)}`;
    }
  }
  for (const key of ['customLightEmphasis', 'customDarkEmphasis']) {
    const override = objectField(settings, key);
    if (override && override['bubbleStyle'] === PACK_SELF_THEME_ID) override['bubbleStyle'] = ownThemeId;
    const comment = override ? objectField(override, 'comment') : null;
    if (comment) {
      if (comment['image'] === PACK_SELF_THEME_ID) comment['image'] = ownThemeId;
      if (comment['ornamentImage'] === PACK_SELF_THEME_ID) comment['ornamentImage'] = ownThemeId;
    }
    const title = override ? objectField(override, 'title') : null;
    if (title && title['bubbleStyle'] === `${PACK_SELF_THEME_ID}${PACK_TITLE_BUBBLE_SUFFIX}`) {
      title['bubbleStyle'] = `${ownThemeId}${PACK_TITLE_BUBBLE_SUFFIX}`;
    }
    if (override && override['chapterHead'] === PACK_SELF_THEME_ID) override['chapterHead'] = ownThemeId;
  }
}

/** 导出时的反向替换：方案里指向这个包的来源写成 pack:self。 */
export function replaceOwnPackIdWithSelf(settings: Record<string, Object>, ownThemeId: string): void {
  if (settings['customBaseThemeId'] === ownThemeId) settings['customBaseThemeId'] = PACK_SELF_THEME_ID;
  for (const modeKey of ['customLightSources', 'customDarkSources']) {
    const sources = objectField(settings, modeKey);
    if (!sources) continue;
    for (const field of THEME_SOURCE_FIELDS) {
      if (sources[field.key] === ownThemeId) sources[field.key] = PACK_SELF_THEME_ID;
    }
  }
  for (const key of ['customLightReaderBackgroundAssetId', 'customDarkReaderBackgroundAssetId']) {
    const value = settings[key];
    if (typeof value === 'string' && value.startsWith(`${ownThemeId}:`)) {
      settings[key] = `${PACK_SELF_THEME_ID}${value.substring(ownThemeId.length)}`;
    }
  }
  for (const key of ['customLightEmphasis', 'customDarkEmphasis']) {
    const override = objectField(settings, key);
    if (override && override['bubbleStyle'] === ownThemeId) override['bubbleStyle'] = PACK_SELF_THEME_ID;
    const comment = override ? objectField(override, 'comment') : null;
    if (comment) {
      if (comment['image'] === ownThemeId) comment['image'] = PACK_SELF_THEME_ID;
      if (comment['ornamentImage'] === ownThemeId) comment['ornamentImage'] = PACK_SELF_THEME_ID;
    }
    const title = override ? objectField(override, 'title') : null;
    if (title && title['bubbleStyle'] === `${ownThemeId}${PACK_TITLE_BUBBLE_SUFFIX}`) {
      title['bubbleStyle'] = `${PACK_SELF_THEME_ID}${PACK_TITLE_BUBBLE_SUFFIX}`;
    }
    if (override && override['chapterHead'] === ownThemeId) override['chapterHead'] = PACK_SELF_THEME_ID;
  }
}

// ---- parts 的编解码 ----

const HEX_COLOR: RegExp = /^#(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/;

function colorField(record: Record<string, Object>, key: string, label: string, allowAlpha: boolean): string {
  const value = stringField(record, key).trim();
  if (!value) return '';
  if (!HEX_COLOR.test(value) || (!allowAlpha && value.length !== 7)) {
    throw new Error(`主题包的${label}.${key} 不是合法的颜色（需要 #RRGGBB${allowAlpha ? ' 或 #AARRGGBB' : ''}）`);
  }
  return value.toUpperCase();
}

function partAssetRef(record: Record<string, Object>, key: string, manifest: ThemePackageManifest,
  kinds: string[], label: string): string {
  const value = stringField(record, key).trim();
  if (!value) return '';
  const asset = resolveAssetRef(manifest, value);
  if (!asset) {
    throw new Error(`主题包的${label}.${key} 引用的素材不存在：${limitChars(stripControlChars(value), 80)}`);
  }
  if (!kinds.includes(asset.kind)) {
    const expected = kinds.includes(ThemePackageAssetKinds.VECTOR) && kinds.length === 1 ? 'SVG' :
      (kinds.includes(ThemePackageAssetKinds.FONT) ? '字体' : '图片');
    throw new Error(`主题包的${label}.${key} 需要${expected}素材`);
  }
  return assetRef(asset.id);
}

function decodeVariantParts(record: Record<string, Object>, manifest: ThemePackageManifest,
  label: string): ThemePackageVariantParts {
  const result = new ThemePackageVariantParts();
  const colors = objectField(record, 'colors');
  if (colors) {
    result.colors.pageColor = colorField(colors, 'pageColor', `${label}.colors`, false);
    result.colors.cardColor = colorField(colors, 'cardColor', `${label}.colors`, false);
    result.colors.inputColor = colorField(colors, 'inputColor', `${label}.colors`, false);
    result.colors.primaryTextColor = colorField(colors, 'primaryTextColor', `${label}.colors`, false);
    result.colors.subTextColor = colorField(colors, 'subTextColor', `${label}.colors`, false);
    result.colors.dividerColor = colorField(colors, 'dividerColor', `${label}.colors`, false);
    result.colors.accentColor = colorField(colors, 'accentColor', `${label}.colors`, false);
    result.colors.buttonColor = colorField(colors, 'buttonColor', `${label}.colors`, false);
    result.colors.dangerColor = colorField(colors, 'dangerColor', `${label}.colors`, false);
  }
  const reader = objectField(record, 'reader');
  if (reader) {
    const readerLabel = `${label}.reader`;
    result.reader.backgroundColor = colorField(reader, 'backgroundColor', readerLabel, false);
    result.reader.textColor = colorField(reader, 'textColor', readerLabel, false);
    result.reader.subTextColor = colorField(reader, 'subTextColor', readerLabel, false);
    const tone = stringField(reader, 'contentTone').trim();
    if (tone && tone !== 'light' && tone !== 'dark') {
      throw new Error(`主题包的${readerLabel}.contentTone 只能是 light 或 dark`);
    }
    result.reader.contentTone = tone;
    const mode = stringField(reader, 'backgroundMode').trim();
    if (mode && mode !== 'ornaments' && mode !== 'image' && mode !== 'none') {
      throw new Error(`主题包的${readerLabel}.backgroundMode 只能是 ornaments、image 或 none`);
    }
    result.reader.backgroundMode = mode;
    const ornamentKinds: string[] = [ThemePackageAssetKinds.VECTOR, ThemePackageAssetKinds.IMAGE];
    result.reader.leading = partAssetRef(reader, 'leading', manifest, ornamentKinds, readerLabel);
    result.reader.trailing = partAssetRef(reader, 'trailing', manifest, ornamentKinds, readerLabel);
    result.reader.image = partAssetRef(reader, 'image', manifest, [ThemePackageAssetKinds.IMAGE], readerLabel);
    const fit = stringField(reader, 'imageFit').trim();
    result.reader.imageFit = fit === 'contain' || fit === 'fill' ? fit : 'cover';
    result.reader.leadingScale = normalizeOrnamentScale(numberField(reader, 'leadingScale'));
    result.reader.trailingScale = normalizeOrnamentScale(numberField(reader, 'trailingScale'));
    if (mode === 'image' && !result.reader.image) {
      throw new Error(`主题包的${readerLabel} 整图模式需要 image`);
    }
    if (!mode && (result.reader.leading || result.reader.trailing || result.reader.image)) {
      result.reader.backgroundMode = result.reader.image ? 'image' : 'ornaments';
    }
    if (result.reader.backgroundMode === 'ornaments') {
      if (!result.reader.leading && !result.reader.trailing) {
        throw new Error(`主题包的${readerLabel} 角饰模式至少要有 leading 或 trailing 一张图`);
      }
      if (readerHasSingleCorner(result.reader) &&
        !manifest.requires.includes(ThemePackageFeatures.READER_SINGLE_CORNER)) {
        throw new Error(`主题包的${readerLabel} 只有一张角饰时 requires 要包含 ${ThemePackageFeatures.READER_SINGLE_CORNER}`);
      }
    }
  }
  const emphasis = objectField(record, 'emphasis');
  if (emphasis) {
    const emphasisLabel = `${label}.emphasis`;
    const mode = stringField(emphasis, 'mode').trim();
    if (mode && mode !== 'none' && mode !== 'text' && mode !== 'highlight' && mode !== 'bubble') {
      throw new Error(`主题包的${emphasisLabel}.mode 只能是 none、text、highlight 或 bubble`);
    }
    result.emphasis.mode = mode;
    result.emphasis.bubbleStyle = limitChars(stringField(emphasis, 'bubbleStyle').trim(), 40);
    result.emphasis.color = colorField(emphasis, 'color', emphasisLabel, true);
    result.emphasis.textColor = colorField(emphasis, 'textColor', emphasisLabel, true);
  }
  const title = objectField(record, 'titleEmphasis');
  if (title) {
    const titleLabel = `${label}.titleEmphasis`;
    const mode = stringField(title, 'mode').trim();
    if (mode && mode !== 'none' && mode !== 'text' && mode !== 'highlight' && mode !== 'bubble') {
      throw new Error(`主题包的${titleLabel}.mode 只能是 none、text、highlight 或 bubble`);
    }
    const parsed = new ThemePackagePartEmphasis();
    parsed.mode = mode;
    parsed.bubbleStyle = limitChars(stringField(title, 'bubbleStyle').trim(), 40);
    parsed.color = colorField(title, 'color', titleLabel, true);
    parsed.textColor = colorField(title, 'textColor', titleLabel, true);
    result.titleEmphasis = titleEmphasisIsEmpty(parsed) ? null : parsed;
  }
  const head = objectField(record, 'chapterHead');
  if (head) {
    const headLabel = `${label}.chapterHead`;
    // 位置不认得时按标题左侧处理（以后的版本可能加新位置）；颜色、素材写错照样报错。
    const parsed = new ThemePackageChapterHead();
    parsed.image = partAssetRef(head, 'image', manifest,
      [ThemePackageAssetKinds.VECTOR, ThemePackageAssetKinds.IMAGE], headLabel);
    const placement = stringField(head, 'placement').trim();
    parsed.placement = placement === 'top' || placement === 'bottom' ? placement : '';
    parsed.scale = normalizeOrnamentScale(numberField(head, 'scale'));
    parsed.numberColor = colorField(head, 'numberColor', headLabel, true);
    parsed.dropCapImage = partAssetRef(head, 'dropCapImage', manifest,
      [ThemePackageAssetKinds.VECTOR, ThemePackageAssetKinds.IMAGE], headLabel);
    const capLines = numberField(head, 'dropCapLines');
    parsed.dropCapLines = capLines === 3 ? 3 : (capLines === 2 || parsed.dropCapImage ? 2 : 0);
    parsed.dropCapColor = colorField(head, 'dropCapColor', headLabel, true);
    parsed.dropCapRatio = normalizeDropCapRatio(numberField(head, 'dropCapRatio'));
    result.chapterHead = chapterHeadIsEmpty(parsed) ? null : parsed;
  }
  const comment = objectField(record, 'commentBubble');
  if (comment) {
    const commentLabel = `${label}.commentBubble`;
    // 形状和图形不认得时按沿用处理（以后的版本可能加新样式）；颜色写错照样报错。
    const parsed = new ThemePackageCommentBubble();
    parsed.shape = stringField(comment, 'shape').trim();
    parsed.radius = typeof comment['radius'] === 'number' ? numberField(comment, 'radius') : -1;
    parsed.fill = colorField(comment, 'fill', commentLabel, true);
    parsed.stroke = colorField(comment, 'stroke', commentLabel, true);
    parsed.text = colorField(comment, 'text', commentLabel, true);
    parsed.ornament = stringField(comment, 'ornament').trim();
    parsed.ornamentColor = colorField(comment, 'ornamentColor', commentLabel, true);
    // 气泡图与角标图：SVG 或位图；旧版本应用不认这些字段，照旧画形状，所以不用声明 requires。
    const artwork: string[] = [ThemePackageAssetKinds.VECTOR, ThemePackageAssetKinds.IMAGE];
    parsed.image = stringField(comment, 'image').trim() === COMMENT_IMAGE_NONE ? COMMENT_IMAGE_NONE :
      partAssetRef(comment, 'image', manifest, artwork, commentLabel);
    const readBox = (key: string): ThemePackageBubbleSlice | null => {
      const box = objectField(comment, key);
      if (!box) return null;
      const parsedBox = new ThemePackageBubbleSlice();
      parsedBox.left = typeof box['left'] === 'number' ? numberField(box, 'left') : 0;
      parsedBox.right = typeof box['right'] === 'number' ? numberField(box, 'right') : 0;
      parsedBox.top = typeof box['top'] === 'number' ? numberField(box, 'top') : 0;
      parsedBox.bottom = typeof box['bottom'] === 'number' ? numberField(box, 'bottom') : 0;
      return parsedBox;
    };
    parsed.imageSlice = readBox('imageSlice');
    parsed.imageText = readBox('imageText');
    parsed.imageRepeat = stringField(comment, 'imageRepeat').trim();
    parsed.imageBreak = stringField(comment, 'imageBreak').trim();
    parsed.imageTint = comment['imageTint'] === true;
    parsed.ornamentImage = partAssetRef(comment, 'ornamentImage', manifest, artwork, commentLabel);
    parsed.ornamentCorner = stringField(comment, 'ornamentCorner').trim();
    parsed.ornamentSize = typeof comment['ornamentSize'] === 'number' ? numberField(comment, 'ornamentSize') : -1;
    const normalized = normalizeCommentBubble(parsed);
    result.commentBubble = commentBubbleIsEmpty(normalized) ? null : normalized;
  }
  return result;
}

/** 气泡端饰、书架边框能用的素材：清单声明了 bitmap-cap-shelf-frame-v1 才收位图，否则只收 SVG。 */
function bitmapCapShelfFrameKinds(manifest: ThemePackageManifest): string[] {
  return manifest.requires.includes(ThemePackageFeatures.BITMAP_CAP_SHELF_FRAME) ?
    [ThemePackageAssetKinds.VECTOR, ThemePackageAssetKinds.IMAGE] : [ThemePackageAssetKinds.VECTOR];
}

function decodeBubble(bubble: Record<string, Object>, manifest: ThemePackageManifest,
  label: string = 'parts.bubble', darkVariant: boolean = false, anyArtwork: boolean = false): ThemePackageBubble {
  const result = new ThemePackageBubble();
  // 认得 bubbleDark 的版本都会画位图边框，深色那套不用另外声明。标题气泡是新字段，旧版本整节忽略，素材类型不限。
  const frameFeature = anyArtwork || darkVariant || manifest.requires.includes(ThemePackageFeatures.BUBBLE_FRAME);
  const frameKinds: string[] = frameFeature ? [ThemePackageAssetKinds.VECTOR, ThemePackageAssetKinds.IMAGE] :
    [ThemePackageAssetKinds.VECTOR];
  result.frame = partAssetRef(bubble, 'frame', manifest, frameKinds, label);
  result.cap = partAssetRef(bubble, 'cap', manifest, anyArtwork ?
    [ThemePackageAssetKinds.VECTOR, ThemePackageAssetKinds.IMAGE] : bitmapCapShelfFrameKinds(manifest), label);
  if (!result.cap && !(frameFeature && result.frame)) {
    throw new Error(frameFeature ? `主题包的 ${label} 至少要有 cap 或 frame` : `主题包的 ${label} 需要 cap`);
  }
  const slice = objectField(bubble, 'frameSlice');
  if (slice) {
    const parsed = new ThemePackageBubbleSlice();
    parsed.left = numberField(slice, 'left');
    parsed.right = numberField(slice, 'right');
    parsed.top = numberField(slice, 'top');
    parsed.bottom = numberField(slice, 'bottom');
    result.frameSlice = normalizeBubbleFrameSlice(parsed);
  }
  const repeat = stringField(bubble, 'frameRepeat');
  result.frameRepeat = repeat === BubbleFrameRepeat.ROUND || repeat === BubbleFrameRepeat.STRETCH ? repeat : '';
  const lineBreak = stringField(bubble, 'frameBreak');
  result.frameBreak = lineBreak === BubbleFrameBreak.CUT || lineBreak === BubbleFrameBreak.FULL ? lineBreak : '';
  result.frameTint = bubble['frameTint'] === true;
  return result;
}

/** 只写用到的字段；没有边框时拉伸设置也不写。 */
export function encodeBubble(bubble: ThemePackageBubble): Record<string, Object> {
  const record: Record<string, Object> = {};
  if (bubble.cap) record['cap'] = bubble.cap;
  if (bubble.frame) {
    record['frame'] = bubble.frame;
    const slice = normalizeBubbleFrameSlice(bubble.frameSlice);
    if (slice) record['frameSlice'] = JSON.parse(JSON.stringify(slice)) as Object;
    if (bubble.frameRepeat === BubbleFrameRepeat.ROUND) record['frameRepeat'] = BubbleFrameRepeat.ROUND;
    if (bubble.frameBreak === BubbleFrameBreak.CUT) record['frameBreak'] = BubbleFrameBreak.CUT;
    if (bubble.frameTint) record['frameTint'] = true;
  }
  return record;
}

function decodeTtsPanel(record: Record<string, Object> | null, manifest: ThemePackageManifest,
  label: string): ThemePackageTtsPanel | null {
  if (!record) return null;
  const result = new ThemePackageTtsPanel();
  result.artwork = partAssetRef(record, 'artwork', manifest,
    [ThemePackageAssetKinds.IMAGE, ThemePackageAssetKinds.VECTOR], label);
  result.skyColor = colorField(record, 'skyColor', label, false);
  result.surfaceColor = colorField(record, 'surfaceColor', label, false);
  result.glowColor = colorField(record, 'glowColor', label, true);
  if (!result.artwork || !result.skyColor || !result.surfaceColor || !result.glowColor) {
    throw new Error(`主题包的${label} 需要 artwork、skyColor、surfaceColor 和 glowColor`);
  }
  return result;
}

function decodeStartup(record: Record<string, Object> | null, manifest: ThemePackageManifest,
  label: string): ThemePackageStartup | null {
  if (!record) return null;
  const result = new ThemePackageStartup();
  result.image = partAssetRef(record, 'image', manifest, [ThemePackageAssetKinds.IMAGE], label);
  result.title = sanitizeStartupText(stringField(record, 'title'));
  result.subtitle = sanitizeStartupText(stringField(record, 'subtitle'));
  if (!result.image) {
    throw new Error(`主题包的${label} 需要 image`);
  }
  return result;
}

/** 区域落在图内、宽高为正。允许半个像素的取整误差。 */
export function isValidImageCrop(crop: ThemeImageCrop | null | undefined): boolean {
  if (!crop || typeof crop.image !== 'string' || !crop.image) return false;
  const values = [crop.x, crop.y, crop.width, crop.height, crop.imageWidth, crop.imageHeight];
  if (values.some((value: number): boolean => typeof value !== 'number' || !isFinite(value))) return false;
  if (crop.imageWidth <= 0 || crop.imageHeight <= 0 || crop.imageWidth > 100000 || crop.imageHeight > 100000) return false;
  if (crop.width <= 0 || crop.height <= 0 || crop.x < 0 || crop.y < 0) return false;
  return crop.x + crop.width <= crop.imageWidth + 0.5 && crop.y + crop.height <= crop.imageHeight + 0.5;
}

/** 在一组区域里找属于 image 的那条。 */
export function findImageCrop(crops: ThemeImageCrop[] | null | undefined, image: string): ThemeImageCrop | null {
  if (!image || !Array.isArray(crops)) return null;
  for (const crop of crops) {
    if (crop && crop.image === image) return crop;
  }
  return null;
}

/**
 * 去掉对不上素材位当前图片的区域（换了图、删了封面之后留下的），补齐本机旧记录缺的字段。
 * 解码、导出和编辑器改完素材后都走一遍。
 */
export function tidyImageCrops(parts: ThemePackageParts): void {
  const keep = (crop: ThemeImageCrop | null | undefined, image: string): ThemeImageCrop | null =>
    crop && image && crop.image === image && isValidImageCrop(crop) ? crop : null;
  if (parts.book) {
    const book = parts.book;
    const tidy = (covers: string[], source: ThemeImageCrop[]): ThemeImageCrop[] => {
      const crops: ThemeImageCrop[] = [];
      for (const cover of covers) {
        const crop = keep(findImageCrop(source, cover), cover);
        if (crop) crops.push(crop);
      }
      return crops;
    };
    if (!Array.isArray(book.coversDark)) book.coversDark = [];
    book.coverCrops = tidy(book.covers, book.coverCrops);
    book.coverCropsDark = tidy(book.coversDark, book.coverCropsDark);
    book.shelfFolderCrop = keep(book.shelfFolderCrop, book.shelfFolder);
    if (!book.shelfFolderDark) book.shelfFolderDark = '';
    book.shelfFolderCropDark = keep(book.shelfFolderCropDark, book.shelfFolderDark);
  }
  parts.homeBackdropLightCrop = keep(parts.homeBackdropLightCrop, parts.homeBackdropLight || '');
  parts.homeBackdropDarkCrop = keep(parts.homeBackdropDarkCrop, parts.homeBackdropDark || '');
  // 按固定的布局顺序留下有图的条目，同一布局只留第一条。
  const shelf: ThemePackageShelfBackdrop[] = [];
  for (const layout of SHELF_BACKDROP_LAYOUTS) {
    const item = findShelfBackdrop(parts.shelfBackdrops, layout);
    if (!item || (!item.light && !item.dark)) continue;
    const tidy = new ThemePackageShelfBackdrop();
    tidy.layout = layout;
    tidy.light = item.light || '';
    tidy.dark = item.dark || '';
    tidy.lightCrop = keep(item.lightCrop, tidy.light);
    tidy.darkCrop = keep(item.darkCrop, tidy.dark);
    shelf.push(tidy);
  }
  parts.shelfBackdrops = shelf;
}

function decodeImageCrop(value: Object | undefined, manifest: ThemePackageManifest, label: string): ThemeImageCrop | null {
  if (value === undefined || value === null) return null;
  if (typeof value !== 'object' || Array.isArray(value)) throw new Error(`主题包的${label} 需要是对象`);
  const record = value as Record<string, Object>;
  const crop = new ThemeImageCrop();
  crop.image = partAssetRef(record, 'image', manifest, [ThemePackageAssetKinds.IMAGE], label);
  crop.x = numberField(record, 'x');
  crop.y = numberField(record, 'y');
  crop.width = numberField(record, 'width');
  crop.height = numberField(record, 'height');
  crop.imageWidth = numberField(record, 'imageWidth');
  crop.imageHeight = numberField(record, 'imageHeight');
  if (!isValidImageCrop(crop)) {
    throw new Error(`主题包的${label} 需要 image、落在 imageWidth × imageHeight 之内的 x、y、width、height`);
  }
  return crop;
}

function encodeImageCrop(crop: ThemeImageCrop): Record<string, Object> {
  const record: Record<string, Object> = {};
  record['image'] = crop.image;
  record['x'] = crop.x;
  record['y'] = crop.y;
  record['width'] = crop.width;
  record['height'] = crop.height;
  record['imageWidth'] = crop.imageWidth;
  record['imageHeight'] = crop.imageHeight;
  return record;
}

export function decodeParts(record: Record<string, Object>, manifest: ThemePackageManifest): ThemePackageParts {
  const parts = new ThemePackageParts();
  const light = objectField(record, 'light');
  const dark = objectField(record, 'dark');
  if (light) parts.light = decodeVariantParts(light, manifest, 'parts.light');
  if (dark) parts.dark = decodeVariantParts(dark, manifest, 'parts.dark');
  const tts = objectField(record, 'ttsPanel');
  if (tts) {
    parts.ttsPanelLight = decodeTtsPanel(objectField(tts, 'light'), manifest, 'parts.ttsPanel.light');
    parts.ttsPanelDark = decodeTtsPanel(objectField(tts, 'dark'), manifest, 'parts.ttsPanel.dark');
    if (!parts.ttsPanelLight && !parts.ttsPanelDark) {
      throw new Error('主题包的 parts.ttsPanel 至少要有 light 或 dark');
    }
  }
  const navigation = objectField(record, 'navigation');
  if (navigation) {
    parts.navigation = new ThemePackageNavigation();
    const icon: string[] = [ThemePackageAssetKinds.VECTOR, ThemePackageAssetKinds.IMAGE];
    const result = parts.navigation as Object as Record<string, string>;
    for (const key of NAVIGATION_ICON_KEYS) {
      result[key] = partAssetRef(navigation, key, manifest, icon, 'parts.navigation');
    }
    parts.navigation.labels = stringField(navigation, 'labels').trim() === 'hidden' ? 'hidden' : '';
    if (!parts.navigation.bookshelf || !parts.navigation.explore || !parts.navigation.mine) {
      throw new Error('主题包的 parts.navigation 需要 bookshelf、explore、mine 三个图标');
    }
    // 深色那套每个图标都可选，没给的沿用上面这套；没有 navigation 时整节不读。
    const navigationDark = objectField(record, 'navigationDark');
    if (navigationDark) {
      const dark = new ThemePackageNavigation();
      const darkResult = dark as Object as Record<string, string>;
      for (const key of NAVIGATION_ICON_KEYS) {
        darkResult[key] = partAssetRef(navigationDark, key, manifest, icon, 'parts.navigationDark');
      }
      parts.navigationDark = navigationIsEmpty(dark) ? null : dark;
    }
  }
  const book = objectField(record, 'book');
  if (book) {
    parts.book = new ThemePackageBook();
    const decodeCovers = (key: string): string[] => {
      const refs: string[] = [];
      const covers = book[key];
      if (covers === undefined) return refs;
      if (!Array.isArray(covers) || covers.length > ThemePackageLimits.MAX_COVERS) {
        throw new Error(`主题包的 parts.book.${key} 最多 ${ThemePackageLimits.MAX_COVERS} 张`);
      }
      for (let i = 0; i < covers.length; i++) {
        const holder: Record<string, Object> = {};
        holder['cover'] = (covers as Object[])[i];
        const ref = partAssetRef(holder, 'cover', manifest, [ThemePackageAssetKinds.IMAGE], `parts.book.${key}[${i}]`);
        if (ref) refs.push(ref);
      }
      return refs;
    };
    const decodeCoverCrops = (key: string): ThemeImageCrop[] => {
      const crops: ThemeImageCrop[] = [];
      const source = book[key];
      if (source === undefined) return crops;
      if (!Array.isArray(source) || source.length > ThemePackageLimits.MAX_COVERS) {
        throw new Error(`主题包的 parts.book.${key} 最多 ${ThemePackageLimits.MAX_COVERS} 条`);
      }
      for (let i = 0; i < source.length; i++) {
        const crop = decodeImageCrop((source as Object[])[i], manifest, `parts.book.${key}[${i}]`);
        if (crop) crops.push(crop);
      }
      return crops;
    };
    parts.book.covers = decodeCovers('covers');
    parts.book.coversDark = decodeCovers('coversDark');
    if (parts.book.covers.length > ThemePackageLimits.LEGACY_MAX_COVERS &&
      !manifest.requires.includes(ThemePackageFeatures.BOOK_COVERS_16)) {
      throw new Error(`主题包的 parts.book.covers 超过 ${ThemePackageLimits.LEGACY_MAX_COVERS} 张时 requires 要包含 ` +
        ThemePackageFeatures.BOOK_COVERS_16);
    }
    const shelfFrameKinds = bitmapCapShelfFrameKinds(manifest);
    parts.book.shelfFrame = partAssetRef(book, 'shelfFrame', manifest, shelfFrameKinds, 'parts.book');
    parts.book.shelfFrameDark = partAssetRef(book, 'shelfFrameDark', manifest, shelfFrameKinds, 'parts.book');
    parts.book.shelfFolder = partAssetRef(book, 'shelfFolder', manifest, [ThemePackageAssetKinds.IMAGE], 'parts.book');
    parts.book.shelfFolderDark = partAssetRef(book, 'shelfFolderDark', manifest, [ThemePackageAssetKinds.IMAGE],
      'parts.book');
    parts.book.coverCrops = decodeCoverCrops('coverCrops');
    parts.book.coverCropsDark = decodeCoverCrops('coverCropsDark');
    parts.book.shelfFolderCrop = decodeImageCrop(book['shelfFolderCrop'], manifest, 'parts.book.shelfFolderCrop');
    parts.book.shelfFolderCropDark = decodeImageCrop(book['shelfFolderCropDark'], manifest,
      'parts.book.shelfFolderCropDark');
    if (bookIsEmpty(parts.book)) {
      parts.book = null;
    }
  }
  const startup = objectField(record, 'startup');
  if (startup) {
    parts.startupLight = decodeStartup(objectField(startup, 'light'), manifest, 'parts.startup.light');
    parts.startupDark = decodeStartup(objectField(startup, 'dark'), manifest, 'parts.startup.dark');
    if (!parts.startupLight && !parts.startupDark) {
      throw new Error('主题包的 parts.startup 至少要有 light 或 dark');
    }
  }
  const bubble = objectField(record, 'bubble');
  if (bubble) {
    parts.bubble = decodeBubble(bubble, manifest);
  }
  const bubbleDark = objectField(record, 'bubbleDark');
  if (bubbleDark) {
    parts.bubbleDark = decodeBubble(bubbleDark, manifest, 'parts.bubbleDark', true);
  }
  const titleBubble = objectField(record, 'titleBubble');
  if (titleBubble) {
    parts.titleBubble = decodeBubble(titleBubble, manifest, 'parts.titleBubble', true, true);
  }
  const titleBubbleDark = objectField(record, 'titleBubbleDark');
  if (titleBubbleDark) {
    parts.titleBubbleDark = decodeBubble(titleBubbleDark, manifest, 'parts.titleBubbleDark', true, true);
  }
  const homeBackdrop = objectField(record, 'homeBackdrop');
  if (homeBackdrop) {
    const image: string[] = [ThemePackageAssetKinds.IMAGE];
    parts.homeBackdropLight = partAssetRef(homeBackdrop, 'light', manifest, image, 'parts.homeBackdrop');
    parts.homeBackdropDark = partAssetRef(homeBackdrop, 'dark', manifest, image, 'parts.homeBackdrop');
    if (!parts.homeBackdropLight && !parts.homeBackdropDark) {
      throw new Error('主题包的 parts.homeBackdrop 至少要有 light 或 dark');
    }
    parts.homeBackdropLightCrop = decodeImageCrop(homeBackdrop['lightCrop'], manifest, 'parts.homeBackdrop.lightCrop');
    parts.homeBackdropDarkCrop = decodeImageCrop(homeBackdrop['darkCrop'], manifest, 'parts.homeBackdrop.darkCrop');
  }
  parts.logo = partAssetRef(record, 'logo', manifest, [ThemePackageAssetKinds.VECTOR, ThemePackageAssetKinds.IMAGE],
    'parts');
  parts.preview = partAssetRef(record, 'preview', manifest, [ThemePackageAssetKinds.IMAGE], 'parts');
  const shelfBackdrop = objectField(record, 'shelfBackdrop');
  if (shelfBackdrop) {
    const image: string[] = [ThemePackageAssetKinds.IMAGE];
    for (const layout of SHELF_BACKDROP_LAYOUTS) {
      const entry = objectField(shelfBackdrop, layout);
      if (!entry) continue;
      const label = `parts.shelfBackdrop.${layout}`;
      const item = new ThemePackageShelfBackdrop();
      item.layout = layout;
      item.light = partAssetRef(entry, 'light', manifest, image, label);
      item.dark = partAssetRef(entry, 'dark', manifest, image, label);
      if (!item.light && !item.dark) {
        throw new Error(`主题包的 ${label} 至少要有 light 或 dark`);
      }
      item.lightCrop = decodeImageCrop(entry['lightCrop'], manifest, `${label}.lightCrop`);
      item.darkCrop = decodeImageCrop(entry['darkCrop'], manifest, `${label}.darkCrop`);
      parts.shelfBackdrops.push(item);
    }
  }
  const radius = objectField(record, 'radius');
  if (radius) {
    const result: Record<string, number> = {};
    for (const key of RADIUS_KEYS) {
      const value = radius[key];
      if (value === undefined) continue;
      if (typeof value !== 'number' || !isFinite(value) || value < 0 || value > 48) {
        throw new Error(`主题包的 parts.radius.${key} 需要 0 到 48 之间的数字`);
      }
      result[key] = Math.round(value);
    }
    parts.radius = result;
  }
  const typography = objectField(record, 'typography');
  if (typography) {
    parts.appFont = partAssetRef(typography, 'appFont', manifest, [ThemePackageAssetKinds.FONT], 'parts.typography');
    parts.appFontFamily = limitChars(stripControlChars(stringField(typography, 'appFontFamily')), 120);
    if (parts.appFont && !manifest.requires.includes(ThemePackageFeatures.FONTS)) {
      throw new Error('主题包清单已损坏');
    }
  }
  tidyImageCrops(parts);
  return parts;
}

function encodeVariantParts(variant: ThemePackageVariantParts): Record<string, Object> {
  const record: Record<string, Object> = {};
  record['colors'] = JSON.parse(JSON.stringify(variant.colors)) as Object;
  record['reader'] = JSON.parse(JSON.stringify(variant.reader)) as Object;
  record['emphasis'] = JSON.parse(JSON.stringify(variant.emphasis)) as Object;
  if (variant.commentBubble && !commentBubbleIsEmpty(variant.commentBubble)) {
    record['commentBubble'] = encodeCommentBubble(variant.commentBubble);
  }
  const title = variant.titleEmphasis;
  if (title && !titleEmphasisIsEmpty(title)) {
    const titleRecord: Record<string, Object> = {};
    if (title.mode) titleRecord['mode'] = title.mode;
    if (title.bubbleStyle) titleRecord['bubbleStyle'] = title.bubbleStyle;
    if (title.color) titleRecord['color'] = title.color;
    if (title.textColor) titleRecord['textColor'] = title.textColor;
    record['titleEmphasis'] = titleRecord;
  }
  const head = variant.chapterHead ? normalizeChapterHead(variant.chapterHead) : null;
  if (head && !chapterHeadIsEmpty(head)) {
    const headRecord: Record<string, Object> = {};
    if (head.image) {
      headRecord['image'] = head.image;
      if (head.placement) headRecord['placement'] = head.placement;
      if (head.scale !== 1) headRecord['scale'] = head.scale;
    }
    if (head.numberColor) headRecord['numberColor'] = head.numberColor;
    if (head.dropCapLines > 0) {
      headRecord['dropCapLines'] = head.dropCapLines;
      if (head.dropCapImage) {
        headRecord['dropCapImage'] = head.dropCapImage;
        if (head.dropCapRatio !== DROP_CAP_RATIO_DEFAULT) headRecord['dropCapRatio'] = head.dropCapRatio;
      }
    }
    if (head.dropCapColor) headRecord['dropCapColor'] = head.dropCapColor;
    record['chapterHead'] = headRecord;
  }
  return record;
}

export function encodeParts(parts: ThemePackageParts): Record<string, Object> {
  const record: Record<string, Object> = {};
  if (parts.light) record['light'] = encodeVariantParts(parts.light);
  if (parts.dark) record['dark'] = encodeVariantParts(parts.dark);
  if (parts.ttsPanelLight || parts.ttsPanelDark) {
    const tts: Record<string, Object> = {};
    if (parts.ttsPanelLight) tts['light'] = JSON.parse(JSON.stringify(parts.ttsPanelLight)) as Object;
    if (parts.ttsPanelDark) tts['dark'] = JSON.parse(JSON.stringify(parts.ttsPanelDark)) as Object;
    record['ttsPanel'] = tts;
  }
  if (parts.navigation) {
    const navigation = JSON.parse(JSON.stringify(parts.navigation)) as ThemePackageNavigation;
    // 旧版本应用还有“搜索”页签，要求四个图标都在：用发现的图标顶上。
    if (!navigation.search) {
      navigation.search = navigation.explore;
      if (!navigation.searchSelected) navigation.searchSelected = navigation.exploreSelected;
    }
    record['navigation'] = navigation as Object;
    if (parts.navigationDark && !navigationIsEmpty(parts.navigationDark)) {
      const dark: Record<string, Object> = {};
      const source = parts.navigationDark as Object as Record<string, string>;
      for (const key of NAVIGATION_ICON_KEYS) {
        if (source[key]) dark[key] = source[key];
      }
      record['navigationDark'] = dark;
    }
  }
  if (parts.book) {
    const book: Record<string, Object> = {};
    // 只有深色封面时写成 covers：显示效果一样（浅色本来就借用它），旧版本应用也认得。
    const onlyDark = parts.book.covers.length === 0;
    const covers = bookCoversFor(parts.book, false);
    const coversDark: string[] = onlyDark ? [] : (parts.book.coversDark || []);
    const encodeCrops = (list: string[], source: ThemeImageCrop[]): Record<string, Object>[] => {
      const crops: Record<string, Object>[] = [];
      for (const cover of list) {
        const crop = findImageCrop(source, cover);
        if (isValidImageCrop(crop)) crops.push(encodeImageCrop(crop as ThemeImageCrop));
      }
      return crops;
    };
    book['covers'] = covers.slice();
    if (coversDark.length > 0) book['coversDark'] = coversDark.slice();
    // 书架边框、文件夹插画同理：只有深色那张时写成 shelfFrame / shelfFolder。
    const shelfFrame = bookShelfFrameFor(parts.book, false);
    const shelfFrameDark = parts.book.shelfFrame ? (parts.book.shelfFrameDark || '') : '';
    if (shelfFrame) book['shelfFrame'] = shelfFrame;
    if (shelfFrameDark && shelfFrameDark !== shelfFrame) book['shelfFrameDark'] = shelfFrameDark;
    const onlyDarkFolder = !parts.book.shelfFolder;
    const shelfFolder = bookFolderFor(parts.book, false);
    const shelfFolderDark = onlyDarkFolder ? '' : (parts.book.shelfFolderDark || '');
    if (shelfFolder) book['shelfFolder'] = shelfFolder;
    if (shelfFolderDark) book['shelfFolderDark'] = shelfFolderDark;
    const coverCrops = encodeCrops(covers, onlyDark ? parts.book.coverCropsDark : parts.book.coverCrops);
    if (coverCrops.length > 0) book['coverCrops'] = coverCrops;
    const coverCropsDark = encodeCrops(coversDark, parts.book.coverCropsDark);
    if (coverCropsDark.length > 0) book['coverCropsDark'] = coverCropsDark;
    const folderCrop = onlyDarkFolder ? parts.book.shelfFolderCropDark : parts.book.shelfFolderCrop;
    if (folderCrop && folderCrop.image === shelfFolder && isValidImageCrop(folderCrop)) {
      book['shelfFolderCrop'] = encodeImageCrop(folderCrop);
    }
    const folderCropDark = parts.book.shelfFolderCropDark;
    if (shelfFolderDark && folderCropDark && folderCropDark.image === shelfFolderDark && isValidImageCrop(folderCropDark)) {
      book['shelfFolderCropDark'] = encodeImageCrop(folderCropDark);
    }
    record['book'] = book;
  }
  if (parts.startupLight || parts.startupDark) {
    const startup: Record<string, Object> = {};
    if (parts.startupLight) startup['light'] = JSON.parse(JSON.stringify(parts.startupLight)) as Object;
    if (parts.startupDark) startup['dark'] = JSON.parse(JSON.stringify(parts.startupDark)) as Object;
    record['startup'] = startup;
  }
  // 浅色那套写成 bubble（只给了深色时就是深色那套），深色只写不同的那几项。
  const lightBubble = bubbleFor(parts, false);
  if (lightBubble) record['bubble'] = encodeBubble(lightBubble);
  const darkBubble = bubbleDarkDifference(parts);
  if (darkBubble) record['bubbleDark'] = encodeBubble(darkBubble);
  const lightTitleBubble = titleBubbleFor(parts, false);
  if (lightTitleBubble) record['titleBubble'] = encodeBubble(lightTitleBubble);
  const darkTitleBubble = titleBubbleDarkDifference(parts);
  if (darkTitleBubble) record['titleBubbleDark'] = encodeBubble(darkTitleBubble);
  if (parts.homeBackdropLight || parts.homeBackdropDark) {
    const homeBackdrop: Record<string, Object> = {};
    if (parts.homeBackdropLight) homeBackdrop['light'] = parts.homeBackdropLight;
    if (parts.homeBackdropDark) homeBackdrop['dark'] = parts.homeBackdropDark;
    const lightCrop = parts.homeBackdropLightCrop;
    if (lightCrop && lightCrop.image === parts.homeBackdropLight && isValidImageCrop(lightCrop)) {
      homeBackdrop['lightCrop'] = encodeImageCrop(lightCrop);
    }
    const darkCrop = parts.homeBackdropDarkCrop;
    if (darkCrop && darkCrop.image === parts.homeBackdropDark && isValidImageCrop(darkCrop)) {
      homeBackdrop['darkCrop'] = encodeImageCrop(darkCrop);
    }
    record['homeBackdrop'] = homeBackdrop;
  }
  const shelfBackdrop: Record<string, Object> = {};
  for (const layout of SHELF_BACKDROP_LAYOUTS) {
    const item = findShelfBackdrop(parts.shelfBackdrops, layout);
    if (!item || (!item.light && !item.dark)) continue;
    const entry: Record<string, Object> = {};
    if (item.light) entry['light'] = item.light;
    if (item.dark) entry['dark'] = item.dark;
    if (item.lightCrop && item.lightCrop.image === item.light && isValidImageCrop(item.lightCrop)) {
      entry['lightCrop'] = encodeImageCrop(item.lightCrop);
    }
    if (item.darkCrop && item.darkCrop.image === item.dark && isValidImageCrop(item.darkCrop)) {
      entry['darkCrop'] = encodeImageCrop(item.darkCrop);
    }
    shelfBackdrop[layout] = entry;
  }
  if (Object.keys(shelfBackdrop).length > 0) record['shelfBackdrop'] = shelfBackdrop;
  if (parts.logo) record['logo'] = parts.logo;
  if (parts.preview) record['preview'] = parts.preview;
  if (parts.radius) record['radius'] = parts.radius;
  if (parts.appFont || parts.appFontFamily) {
    const typography: Record<string, Object> = {};
    if (parts.appFont) typography['appFont'] = parts.appFont;
    if (parts.appFontFamily) typography['appFontFamily'] = parts.appFontFamily;
    record['typography'] = typography;
  }
  return record;
}

/** parts 里引用到的全部素材引用（去重，顺序稳定）。 */
export function partsAssetRefs(parts: ThemePackageParts): string[] {
  const refs: string[] = [];
  const add = (value: string): void => {
    if (value && !refs.includes(value)) refs.push(value);
  };
  for (const variant of [parts.light, parts.dark]) {
    if (!variant) continue;
    add(variant.reader.leading);
    add(variant.reader.trailing);
    add(variant.reader.image);
    const comment = variant.commentBubble;
    if (comment) {
      if (comment.image && comment.image !== COMMENT_IMAGE_NONE) add(comment.image);
      add(comment.ornamentImage || '');
    }
    if (variant.chapterHead) {
      add(variant.chapterHead.image || '');
      add(variant.chapterHead.dropCapImage || '');
    }
  }
  for (const tts of [parts.ttsPanelLight, parts.ttsPanelDark]) {
    if (tts) add(tts.artwork);
  }
  if (parts.navigation) {
    // 本机旧版记录里没有选中态字段。
    const navigation = parts.navigation as Object as Record<string, string>;
    for (const key of NAVIGATION_ICON_KEYS) add(navigation[key] || '');
  }
  if (parts.navigationDark) {
    const navigation = parts.navigationDark as Object as Record<string, string>;
    for (const key of NAVIGATION_ICON_KEYS) add(navigation[key] || '');
  }
  if (parts.book) {
    for (const cover of parts.book.covers) add(cover);
    // 本机旧版记录里没有深色封面字段。
    for (const cover of parts.book.coversDark || []) add(cover);
    add(parts.book.shelfFrame);
    add(parts.book.shelfFrameDark || '');
    add(parts.book.shelfFolder);
    add(parts.book.shelfFolderDark || '');
  }
  for (const startup of [parts.startupLight, parts.startupDark]) {
    if (startup) add(startup.image);
  }
  for (const bubble of [parts.bubble, parts.bubbleDark, parts.titleBubble || null, parts.titleBubbleDark || null]) {
    if (!bubble) continue;
    add(bubble.frame);
    add(bubble.cap);
  }
  // 本机旧版记录里没有这两个字段。
  add(parts.homeBackdropLight || '');
  add(parts.homeBackdropDark || '');
  for (const item of parts.shelfBackdrops || []) {
    add(item.light || '');
    add(item.dark || '');
  }
  add(parts.logo);
  add(parts.preview);
  add(parts.appFont);
  return refs;
}

/** 把 parts 里的素材引用按映射表换掉（导出时换成 assets/ 路径，安装时换成本机 URI）。 */
export function mapPartsAssetRefs(parts: ThemePackageParts, map: (ref: string) => string): ThemePackageParts {
  const copy = JSON.parse(JSON.stringify(parts)) as ThemePackageParts;
  const swap = (value: string): string => value ? map(value) : '';
  for (const variant of [copy.light, copy.dark]) {
    if (!variant) continue;
    variant.reader.leading = swap(variant.reader.leading);
    variant.reader.trailing = swap(variant.reader.trailing);
    variant.reader.image = swap(variant.reader.image);
    const comment = variant.commentBubble;
    if (comment) {
      // 本机旧记录里没有这两个字段。
      if (comment.image && comment.image !== COMMENT_IMAGE_NONE) comment.image = swap(comment.image);
      comment.ornamentImage = swap(comment.ornamentImage || '');
    }
    // 本机旧记录里没有章首装饰。
    if (variant.chapterHead) {
      variant.chapterHead.image = swap(variant.chapterHead.image || '');
      variant.chapterHead.dropCapImage = swap(variant.chapterHead.dropCapImage || '');
    } else {
      variant.chapterHead = null;
    }
  }
  for (const tts of [copy.ttsPanelLight, copy.ttsPanelDark]) {
    if (tts) tts.artwork = swap(tts.artwork);
  }
  if (copy.navigation) {
    const navigation = copy.navigation as Object as Record<string, string>;
    for (const key of NAVIGATION_ICON_KEYS) navigation[key] = swap(navigation[key] || '');
  }
  if (copy.navigationDark) {
    const navigation = copy.navigationDark as Object as Record<string, string>;
    for (const key of NAVIGATION_ICON_KEYS) navigation[key] = swap(navigation[key] || '');
  } else {
    copy.navigationDark = null;
  }
  if (copy.book) {
    copy.book.covers = copy.book.covers.map((cover: string): string => swap(cover));
    copy.book.coversDark = (copy.book.coversDark || []).map((cover: string): string => swap(cover));
    copy.book.shelfFrame = swap(copy.book.shelfFrame);
    copy.book.shelfFrameDark = swap(copy.book.shelfFrameDark || '');
    copy.book.shelfFolder = swap(copy.book.shelfFolder);
    copy.book.shelfFolderDark = swap(copy.book.shelfFolderDark || '');
    // 本机旧记录里没有这两个字段。
    const swapCrop = (crop: ThemeImageCrop): ThemeImageCrop => {
      crop.image = swap(crop.image);
      return crop;
    };
    copy.book.coverCrops = (copy.book.coverCrops || []).map(swapCrop);
    copy.book.coverCropsDark = (copy.book.coverCropsDark || []).map(swapCrop);
    if (copy.book.shelfFolderCrop) copy.book.shelfFolderCrop.image = swap(copy.book.shelfFolderCrop.image);
    else copy.book.shelfFolderCrop = null;
    if (copy.book.shelfFolderCropDark) copy.book.shelfFolderCropDark.image = swap(copy.book.shelfFolderCropDark.image);
    else copy.book.shelfFolderCropDark = null;
  }
  for (const startup of [copy.startupLight, copy.startupDark]) {
    if (startup) startup.image = swap(startup.image);
  }
  if (copy.bubble) {
    copy.bubble.frame = swap(copy.bubble.frame);
    copy.bubble.cap = swap(copy.bubble.cap);
  }
  if (copy.bubbleDark) {
    copy.bubbleDark.frame = swap(copy.bubbleDark.frame);
    copy.bubbleDark.cap = swap(copy.bubbleDark.cap);
  } else {
    copy.bubbleDark = null;
  }
  // 本机旧记录里没有标题气泡。
  for (const key of ['titleBubble', 'titleBubbleDark']) {
    const holder = copy as Object as Record<string, ThemePackageBubble | null | undefined>;
    const bubble = holder[key];
    if (bubble) {
      bubble.frame = swap(bubble.frame);
      bubble.cap = swap(bubble.cap);
    } else {
      holder[key] = null;
    }
  }
  copy.homeBackdropLight = swap(copy.homeBackdropLight || '');
  copy.homeBackdropDark = swap(copy.homeBackdropDark || '');
  if (copy.homeBackdropLightCrop) copy.homeBackdropLightCrop.image = swap(copy.homeBackdropLightCrop.image);
  else copy.homeBackdropLightCrop = null;
  if (copy.homeBackdropDarkCrop) copy.homeBackdropDarkCrop.image = swap(copy.homeBackdropDarkCrop.image);
  else copy.homeBackdropDarkCrop = null;
  copy.shelfBackdrops = (copy.shelfBackdrops || []).map((item: ThemePackageShelfBackdrop): ThemePackageShelfBackdrop => {
    item.light = swap(item.light || '');
    item.dark = swap(item.dark || '');
    if (item.lightCrop) item.lightCrop.image = swap(item.lightCrop.image);
    else item.lightCrop = null;
    if (item.darkCrop) item.darkCrop.image = swap(item.darkCrop.image);
    else item.darkCrop = null;
    return item;
  });
  copy.logo = swap(copy.logo);
  copy.preview = swap(copy.preview);
  copy.appFont = swap(copy.appFont);
  return copy;
}

/** 导入预览里列出的部件名称。 */
export function describeParts(parts: ThemePackageParts): string[] {
  const items: string[] = [];
  if (parts.light || parts.dark) {
    const modes: string[] = [];
    if (parts.light) modes.push('浅色');
    if (parts.dark) modes.push('深色');
    items.push(`${modes.join('与')}配色`);
  }
  const readerModes: string[] = [];
  for (const variant of [parts.light, parts.dark]) {
    if (variant && variant.reader.backgroundMode && variant.reader.backgroundMode !== 'none') {
      const reader = variant.reader;
      readerModes.push(reader.backgroundMode !== 'image' ? '角饰' :
        (reader.leading || reader.trailing ? '整图+角饰' : '整图'));
    }
  }
  if (readerModes.length > 0) items.push(`阅读背景（${readerModes.join('、')}）`);
  if (parts.ttsPanelLight || parts.ttsPanelDark) items.push('朗读/有声书面板插画');
  if (parts.navigation) items.push(parts.navigationDark ? '导航图标（含深色）' : '导航图标');
  if (parts.book) {
    const book: string[] = [];
    const lightCovers = bookCoversFor(parts.book, false).length;
    const darkCovers = parts.book.covers.length > 0 ? (parts.book.coversDark || []).length : 0;
    if (lightCovers > 0 && darkCovers > 0) book.push(`封面 浅色 ${lightCovers} 张、深色 ${darkCovers} 张`);
    else if (lightCovers > 0) book.push(`封面 ${lightCovers} 张`);
    if (parts.book.shelfFrame && parts.book.shelfFrameDark) book.push('书架边框（浅色、深色）');
    else if (bookShelfFrameFor(parts.book, false)) book.push('书架边框');
    if (parts.book.shelfFolder && parts.book.shelfFolderDark) book.push('文件夹插画（浅色、深色）');
    else if (bookFolderFor(parts.book, false)) book.push('文件夹插画');
    items.push(book.join('、'));
  }
  if (parts.startupLight || parts.startupDark) items.push('启动封面');
  const bubble = bubbleFor(parts, false);
  if (bubble) {
    const name = bubble.cap && bubble.frame ? '强调气泡端饰与边框' : (bubble.frame ? '强调气泡边框' : '强调气泡端饰');
    items.push(bubbleDarkDifference(parts) ? `${name}（含深色）` : name);
  }
  if ((parts.light && parts.light.titleEmphasis) || (parts.dark && parts.dark.titleEmphasis) || titleBubbleFor(parts, false)) {
    const titleBubble = titleBubbleFor(parts, false);
    items.push(titleBubble ? (titleBubbleDarkDifference(parts) ? '标题强调与标题气泡（含深色）' : '标题强调与标题气泡') :
      '标题强调');
  }
  const lightHead = chapterHeadFor(parts, false);
  const darkHead = chapterHeadFor(parts, true);
  if (lightHead || darkHead) {
    const hasImage = !!((lightHead && lightHead.image) || (darkHead && darkHead.image));
    const hasColor = !!((lightHead && lightHead.numberColor) || (darkHead && darkHead.numberColor));
    const hasCap = !!((lightHead && lightHead.dropCapLines > 0) || (darkHead && darkHead.dropCapLines > 0));
    const names: string[] = [];
    if (hasImage) names.push('标题饰图');
    if (hasColor) names.push('序号行颜色');
    if (hasCap) names.push('首字装饰');
    items.push(`章首装饰（${names.join('、')}）`);
  }
  if ((parts.light && parts.light.commentBubble) || (parts.dark && parts.dark.commentBubble)) {
    items.push(commentBubbleHasImage(commentBubbleFor(parts, false)) || commentBubbleHasImage(commentBubbleFor(parts, true)) ?
      '段评气泡（含气泡图）' : '段评气泡');
  }
  if (parts.homeBackdropLight || parts.homeBackdropDark) {
    const modes: string[] = [];
    if (parts.homeBackdropLight) modes.push('浅色');
    if (parts.homeBackdropDark) modes.push('深色');
    items.push(`首页背景（${modes.join('、')}）`);
  }
  const shelfLayouts: string[] = [];
  for (const item of parts.shelfBackdrops || []) {
    if (item.light || item.dark) shelfLayouts.push(SHELF_BACKDROP_LAYOUT_NAMES[SHELF_BACKDROP_LAYOUTS.indexOf(item.layout)] || '');
  }
  if (shelfLayouts.length > 0) items.push(`书架背景（${shelfLayouts.join('、')}布局）`);
  if (parts.logo) items.push('主题标识');
  if (parts.radius) items.push('圆角');
  if (parts.appFont || parts.appFontFamily) items.push('界面字体');
  return items;
}

/** 从阅读设置取出随主题走的排版字段。 */
export function pickLayout(source: Record<string, Object>): Record<string, Object> {
  const layout: Record<string, Object> = {};
  for (const key of LAYOUT_KEYS) {
    const value = source[key];
    // Structured title settings must travel as complete JSON, never a truncated short label.
    if (key === 'titleStyleRaw' && typeof value === 'string' && value.length > 8000) continue;
    if (typeof value === 'number' ? isFinite(value) : (typeof value === 'string' || typeof value === 'boolean')) {
      layout[key] = typeof value === 'string' ?
        limitChars(value, key === 'readerInfoBarConfig' || key === 'titleStyleRaw' ? 8000 : 200) : value;
    }
  }
  return layout;
}

/** 把排版字段写回阅读设置；类型与目标字段不同的值忽略，交给阅读设置的规范化处理范围。 */
export function applyLayout(target: Record<string, Object>, layout: Record<string, Object>): void {
  for (const key of LAYOUT_KEYS) {
    const value = layout[key];
    if (value === undefined || value === null) continue;
    if (typeof target[key] === typeof value) {
      target[key] = value;
    }
  }
}

export class SourceRestriction {
  // 被替换掉的部件，用于预览提示，例如「深色 · 强调气泡（月鹤）」。
  replaced: string[] = [];
  // 来自更新版本、本机没有的部件。
  unknown: string[] = [];
}

/**
 * 导入方无权使用的部件来源换成可用的主题。canUse 判断主题是否免费或已获得，known 判断本机是否认得这个主题 ID，
 * themeName 用于提示文案，fallback 是替代用的免费主题。
 */
export function restrictSources(settings: Record<string, Object>, canUse: (themeId: string) => boolean,
  known: (themeId: string) => boolean, themeName: (themeId: string) => string,
  fallback: string): SourceRestriction {
  const result = new SourceRestriction();
  const base = settings['customBaseThemeId'];
  if (typeof base !== 'string' || !known(base) || !canUse(base)) {
    settings['customBaseThemeId'] = fallback;
  }
  const modes: string[] = ['customLightSources', 'customDarkSources'];
  for (const modeKey of modes) {
    const sources = settings[modeKey];
    if (!sources || typeof sources !== 'object' || Array.isArray(sources)) {
      continue;
    }
    const record = sources as Record<string, Object>;
    const modeLabel = modeKey === 'customLightSources' ? '浅色' : '深色';
    for (const field of THEME_SOURCE_FIELDS) {
      const value = record[field.key];
      if (typeof value !== 'string' || !value) continue;
      if (!known(value)) {
        record[field.key] = fallback;
        result.unknown.push(`${modeLabel} · ${field.label}`);
      } else if (!canUse(value)) {
        record[field.key] = fallback;
        result.replaced.push(`${modeLabel} · ${field.label}（${themeName(value)}）`);
      }
    }
  }
  return result;
}

/**
 * 主题包里没写的部件取自 baseTheme，导入后整套基底资源都会随包生效。导入方没有这套主题时，与部件来源同一规则换成
 * fallback，否则只写一个 baseTheme 就能拿到付费主题的封面、角饰和图标。主题包 ID 作基底、或本机不认得的主题也换成
 * fallback（后者记进 unknown）。会直接改写 manifest.baseTheme。
 */
export function restrictBaseTheme(manifest: ThemePackageManifest, canUse: (themeId: string) => boolean,
  known: (themeId: string) => boolean, themeName: (themeId: string) => string, fallback: string): SourceRestriction {
  const result = new SourceRestriction();
  const base = (manifest.baseTheme || '').trim();
  if (!base || base === fallback) {
    manifest.baseTheme = fallback;
    return result;
  }
  if (isPackThemeId(base)) {
    manifest.baseTheme = fallback;
  } else if (!known(base)) {
    manifest.baseTheme = fallback;
    result.unknown.push('包里没设计的部件（基底主题）');
  } else if (!canUse(base)) {
    manifest.baseTheme = fallback;
    result.replaced.push(`包里没设计的部件（基底主题：${themeName(base)}）`);
  }
  return result;
}

export class RuleMergeResult {
  rulesJson: string = '[]';
  added: number = 0;
  skipped: number = 0;
}

/** 包内强调规则追加到已有规则之后：表达式相同的跳过，新加的规则换新 ID，避免与已有规则冲突。 */
export function mergeRules(existingJson: string, incomingJson: string, idSeed: number): RuleMergeResult {
  const existing = parseRuleArray(existingJson);
  const incoming = parseRuleArray(incomingJson);
  const patterns = new Set<string>();
  for (const rule of existing) {
    patterns.add(ruleString(rule, 'pattern').trim());
  }
  const result = new RuleMergeResult();
  const merged: Record<string, Object>[] = existing.slice();
  for (const rule of incoming) {
    const pattern = ruleString(rule, 'pattern').trim();
    if (!pattern || patterns.has(pattern) || merged.length >= ThemePackageLimits.MAX_RULES) {
      result.skipped++;
      continue;
    }
    patterns.add(pattern);
    const copy: Record<string, Object> = {};
    for (const key of Object.keys(rule)) {
      copy[key] = rule[key];
    }
    copy['id'] = `rule_${idSeed}_${result.added}`;
    copy['expanded'] = false;
    merged.push(copy);
    result.added++;
  }
  result.rulesJson = JSON.stringify(merged);
  return result;
}

function parseRuleArray(text: string): Record<string, Object>[] {
  if (!text) return [];
  try {
    const parsed = JSON.parse(text) as Object;
    const list = Array.isArray(parsed) ? parsed as Object[] :
      (parsed && typeof parsed === 'object' && Array.isArray((parsed as Record<string, Object>)['rules']) ?
        (parsed as Record<string, Object>)['rules'] as Object[] : []);
    const rules: Record<string, Object>[] = [];
    for (const item of list) {
      if (item && typeof item === 'object' && !Array.isArray(item)) {
        rules.push(item as Record<string, Object>);
      }
    }
    return rules;
  } catch (_) {
    return [];
  }
}

function ruleString(rule: Record<string, Object>, key: string): string {
  const value = rule[key];
  return typeof value === 'string' ? value : '';
}

/**
 * 把排版和规则里的字体名从导出设备的名字换成本机安装后的名字。
 * 没能安装的自定义字体退回跟随全局字体，并记下字体显示名用于提示。
 */
export function remapFonts(layout: Record<string, Object> | null, rules: Record<string, Object>[],
  installed: Map<string, string>, displayNames: Map<string, string>): string[] {
  const missing: string[] = [];
  const remap = (holder: Record<string, Object>, modeKey: string, familyKey: string): void => {
    if (holder[modeKey] !== 'custom') return;
    const family = typeof holder[familyKey] === 'string' ? holder[familyKey] as string : '';
    const next = installed.get(family);
    if (next) {
      holder[familyKey] = next;
      return;
    }
    holder[modeKey] = 'global';
    holder[familyKey] = '';
    const name = displayNames.get(family) || family;
    if (name && !missing.includes(name)) missing.push(name);
  };
  if (layout) {
    remap(layout, 'bodyFontMode', 'bodyFontFamily');
    remap(layout, 'titleFontMode', 'titleFontFamily');
  }
  for (const rule of rules) {
    remap(rule, 'fontMode', 'fontFamily');
  }
  return missing;
}
