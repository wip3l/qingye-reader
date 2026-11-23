import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';

/**
 * 阅读背景整图的显示方式。
 * - fit：cover 等比铺满并裁切、contain 完整显示、fill 拉伸铺满、tile 按原始像素大小从左上角平铺。
 * - position：只对 cover 有效，0~100，沿被裁掉的那条轴取景（图比屏幕瘦是上→下，比屏幕胖是左→右），50 居中。
 * - gap：只对 contain 有效，空白处 blur 用这张图模糊铺满垫底，color 露出主题底色。
 */
export class ReaderBackgroundDisplay {
  static readonly FIT_COVER: string = 'cover';
  static readonly FIT_CONTAIN: string = 'contain';
  static readonly FIT_FILL: string = 'fill';
  static readonly FIT_TILE: string = 'tile';
  static readonly GAP_BLUR: string = 'blur';
  static readonly GAP_COLOR: string = 'color';
  static readonly FITS: string[] = ['cover', 'contain', 'fill', 'tile'];
  static readonly FIT_LABELS: string[] = ['裁切铺满', '完整显示', '拉伸铺满', '平铺'];
  /** 模糊垫底的模糊半径（vp）；自绘纹理按同样的观感换算成 sigma。 */
  static readonly BLUR_RADIUS: number = 36;

  fit: string = 'cover';
  position: number = 50;
  gap: string = 'color';

  static of(fit: string, position: number, gap: string): ReaderBackgroundDisplay {
    const item = new ReaderBackgroundDisplay();
    item.fit = ReaderBackgroundDisplay.normalizeFit(fit);
    item.position = ReaderBackgroundDisplay.normalizePosition(position);
    item.gap = ReaderBackgroundDisplay.normalizeGap(gap);
    return item;
  }

  static normalizeFit(fit: string): string {
    return ReaderBackgroundDisplay.FITS.indexOf(fit) >= 0 ? fit : 'cover';
  }

  static normalizePosition(position: number): number {
    if (typeof position !== 'number' || !Number.isFinite(position)) return 50;
    return Math.max(0, Math.min(100, Math.round(position)));
  }

  static normalizeGap(gap: string): string {
    return gap === 'blur' ? 'blur' : 'color';
  }

  /**
   * cover 时被裁掉的那条轴：'v' 上下被裁（图比视口瘦），'h' 左右被裁，'' 比例几乎一致不裁。
   * 宽高比相差不到 2% 时当作不裁，免得出现一根几乎拖不动的取景条。
   */
  static croppedAxis(imageAspect: number, viewportWidth: number, viewportHeight: number): string {
    if (imageAspect <= 0 || viewportWidth <= 0 || viewportHeight <= 0) return '';
    const viewportAspect = viewportWidth / viewportHeight;
    if (Math.abs(imageAspect - viewportAspect) / viewportAspect < 0.02) return '';
    return imageAspect < viewportAspect ? 'v' : 'h';
  }

  /** cover 下图片的显示矩形（相对视口左上角，单位同入参）；position 沿被裁轴取景。 */
  static coverRect(imageAspect: number, viewportWidth: number, viewportHeight: number,
    position: number): number[] {
    if (imageAspect <= 0 || viewportWidth <= 0 || viewportHeight <= 0) {
      return [0, 0, viewportWidth, viewportHeight];
    }
    const width = Math.max(viewportWidth, viewportHeight * imageAspect);
    const height = width / imageAspect;
    const ratio = ReaderBackgroundDisplay.normalizePosition(position) / 100;
    return [(viewportWidth - width) * ratio, (viewportHeight - height) * ratio, width, height];
  }
}

class StoredBackgroundDisplay {
  fit: string = 'cover';
  position: number = 50;
  gap: string = 'color';
}

/**
 * 读者给主题包整图阅读背景改的显示方式，按主题（主题包 themeId）记，浅色、深色两张图共用。
 * 只存本机、不进云同步和数据备份：同一个主题在手机、折叠屏、平板上要的效果本来就不同。
 * 没有记录时用主题作者的设定。改动后递增 AppStorage 的 REVISION_KEY，阅读页靠它重新解析主题。
 */
export class ReaderBackgroundDisplayStore {
  static readonly STORE_NAME: string = 'reader_background_display';
  static readonly REVISION_KEY: string = 'readerBackgroundDisplayRevision';
  private static readonly OVERRIDES_KEY: string = 'overrides';
  private static overrides: Map<string, ReaderBackgroundDisplay> = new Map<string, ReaderBackgroundDisplay>();
  private static writes: Promise<void> = Promise.resolve();
  private static editRevision: number = 0;

  static async load(context: Context): Promise<void> {
    const revision = ReaderBackgroundDisplayStore.editRevision;
    const store = await preferences.getPreferences(context, ReaderBackgroundDisplayStore.STORE_NAME);
    const raw = await store.get(ReaderBackgroundDisplayStore.OVERRIDES_KEY, '');
    // 启动途中已经改过，就不拿旧值盖回去。
    if (revision !== ReaderBackgroundDisplayStore.editRevision) return;
    ReaderBackgroundDisplayStore.overrides = ReaderBackgroundDisplayStore.parse(typeof raw === 'string' ? raw : '');
    ReaderBackgroundDisplayStore.bump();
  }

  static override(themeId: string): ReaderBackgroundDisplay | null {
    if (!themeId) return null;
    return ReaderBackgroundDisplayStore.overrides.get(themeId) ?? null;
  }

  /** 拖动取景途中先换内存里的值让阅读页跟着动，不写盘；松手时再 save。 */
  static preview(themeId: string, display: ReaderBackgroundDisplay): void {
    if (!themeId) return;
    ++ReaderBackgroundDisplayStore.editRevision;
    ReaderBackgroundDisplayStore.overrides.set(themeId,
      ReaderBackgroundDisplay.of(display.fit, display.position, display.gap));
    ReaderBackgroundDisplayStore.bump();
  }

  /** display 为 null 时删掉记录，回到主题作者的设定。 */
  static save(context: Context, themeId: string, display: ReaderBackgroundDisplay | null): Promise<void> {
    if (!themeId) return Promise.resolve();
    ++ReaderBackgroundDisplayStore.editRevision;
    if (display) {
      ReaderBackgroundDisplayStore.overrides.set(themeId,
        ReaderBackgroundDisplay.of(display.fit, display.position, display.gap));
    } else {
      ReaderBackgroundDisplayStore.overrides.delete(themeId);
    }
    ReaderBackgroundDisplayStore.bump();
    const raw = ReaderBackgroundDisplayStore.stringify();
    const write = ReaderBackgroundDisplayStore.writes.then(async (): Promise<void> => {
      const store = await preferences.getPreferences(context, ReaderBackgroundDisplayStore.STORE_NAME);
      await store.put(ReaderBackgroundDisplayStore.OVERRIDES_KEY, raw);
      await store.flush();
    });
    ReaderBackgroundDisplayStore.writes = write.catch(() => {});
    return write;
  }

  private static bump(): void {
    const current = AppStorage.get<number>(ReaderBackgroundDisplayStore.REVISION_KEY) ?? 0;
    AppStorage.setOrCreate<number>(ReaderBackgroundDisplayStore.REVISION_KEY, current + 1);
  }

  private static parse(raw: string): Map<string, ReaderBackgroundDisplay> {
    const result = new Map<string, ReaderBackgroundDisplay>();
    if (!raw.trim()) return result;
    try {
      const parsed = JSON.parse(raw) as Record<string, StoredBackgroundDisplay>;
      if (!parsed || typeof parsed !== 'object') return result;
      for (const key of Object.keys(parsed)) {
        const item = parsed[key];
        if (!key || !item || typeof item !== 'object') continue;
        result.set(key, ReaderBackgroundDisplay.of(item.fit, item.position, item.gap));
      }
    } catch (error) {
      console.warn('读取阅读背景显示方式失败:', error);
    }
    return result;
  }

  private static stringify(): string {
    const output: Record<string, StoredBackgroundDisplay> = {};
    ReaderBackgroundDisplayStore.overrides.forEach((value: ReaderBackgroundDisplay, key: string) => {
      const item = new StoredBackgroundDisplay();
      item.fit = value.fit;
      item.position = value.position;
      item.gap = value.gap;
      output[key] = item;
    });
    return JSON.stringify(output);
  }
}
