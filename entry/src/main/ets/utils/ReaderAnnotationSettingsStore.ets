import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';
import { BookAnnotationStyles } from '../model/reader/BookAnnotation';

/** 划线的本机偏好：新划线沿用上一次的颜色和样式；划线后是否弹面板；是否显示笔记标记。 */
export class ReaderAnnotationSettings {
  lastColor: string = BookAnnotationStyles.DEFAULT_COLOR;
  lastStyle: string = BookAnnotationStyles.SOLID;
  autoPanel: boolean = true;
  showNoteDot: boolean = true;

  clone(): ReaderAnnotationSettings {
    const copy = new ReaderAnnotationSettings();
    copy.lastColor = this.lastColor;
    copy.lastStyle = this.lastStyle;
    copy.autoPanel = this.autoPanel;
    copy.showNoteDot = this.showNoteDot;
    return copy;
  }
}

export class ReaderAnnotationSettingsStore {
  private static readonly STORE_NAME: string = 'reader_annotation_settings';
  private static cached: ReaderAnnotationSettings | null = null;

  static async load(context: Context): Promise<ReaderAnnotationSettings> {
    if (ReaderAnnotationSettingsStore.cached) return ReaderAnnotationSettingsStore.cached.clone();
    const settings = new ReaderAnnotationSettings();
    try {
      const store = await preferences.getPreferences(context, ReaderAnnotationSettingsStore.STORE_NAME);
      const color = await store.get('lastColor', settings.lastColor);
      const style = await store.get('lastStyle', settings.lastStyle);
      const autoPanel = await store.get('autoPanel', settings.autoPanel);
      const showNoteDot = await store.get('showNoteDot', settings.showNoteDot);
      settings.lastColor = BookAnnotationStyles.normalizeColor(typeof color === 'string' ? color : '');
      settings.lastStyle = BookAnnotationStyles.normalizeStyle(typeof style === 'string' ? style : '');
      settings.autoPanel = typeof autoPanel === 'boolean' ? autoPanel : true;
      settings.showNoteDot = typeof showNoteDot === 'boolean' ? showNoteDot : true;
    } catch (error) {
      console.warn('读取划线设置失败:', error);
    }
    ReaderAnnotationSettingsStore.cached = settings.clone();
    return settings;
  }

  static async save(context: Context, settings: ReaderAnnotationSettings): Promise<void> {
    ReaderAnnotationSettingsStore.cached = settings.clone();
    try {
      const store = await preferences.getPreferences(context, ReaderAnnotationSettingsStore.STORE_NAME);
      await store.put('lastColor', settings.lastColor);
      await store.put('lastStyle', settings.lastStyle);
      await store.put('autoPanel', settings.autoPanel);
      await store.put('showNoteDot', settings.showNoteDot);
      await store.flush();
    } catch (error) {
      console.warn('保存划线设置失败:', error);
    }
  }
}
