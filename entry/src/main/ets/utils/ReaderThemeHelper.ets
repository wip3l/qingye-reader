import { ThemeRuntime } from '../theme/ThemeRuntime';
import { ThemeAssetRegistry } from '../theme/ThemeAssetRegistry';
import { ReaderBackgroundDisplay, ReaderBackgroundDisplayStore } from './ReaderBackgroundDisplay';

export class ReaderThemeItem {
  name: string = '';
  backgroundColor: string = '';
  textColor: string = '';
  subTextColor: string = '';
  backgroundAssetId: string = '';
  backgroundImageUri: string = '';
  /** ReaderBackgroundDisplay.FITS 之一。 */
  backgroundImageFit: string = 'cover';
  /** cover 时沿被裁轴的取景位置，0~100。 */
  backgroundImagePosition: number = 50;
  /** contain 时空白处：blur 模糊垫底、color 主题底色。 */
  backgroundImageGap: string = 'color';
  /** 主题包整图背景所属的 themeId，读者在这台设备上改的显示方式按它记；其他背景为空串。 */
  backgroundDisplayKey: string = '';
  contentTone: string = 'light';
}

export class ReaderThemeHelper {
  static readonly CUSTOM_THEME_INDEX: number = 3;
  static readonly APP_THEME_INDEX: number = 4;
  static readonly LIGHT_CUSTOM_BACKGROUND_COLOR: string = '#F5F5F5';
  static readonly LIGHT_CUSTOM_TEXT_COLOR: string = '#333333';
  static readonly DARK_CUSTOM_BACKGROUND_COLOR: string = '#1F2329';
  static readonly DARK_CUSTOM_TEXT_COLOR: string = '#D8D8D8';

  static normalizeIndex(index: number): number {
    const value = Math.round(index);
    return value >= 0 && value <= ReaderThemeHelper.APP_THEME_INDEX ? value : 0;
  }

  static lightThemes(customBackgroundColor: string, customTextColor: string,
    customBackgroundImageUri: string = '', customBackgroundImageFit: string = 'cover',
    customImagePosition: number = 50, customImageGap: string = 'color'): ReaderThemeItem[] {
    return [
      ReaderThemeHelper.theme('米黄', '#F7F1E3', '#2F261D', '#7A6F63'),
      ReaderThemeHelper.theme('素白', '#FFFFFF', '#333333', '#777777'),
      ReaderThemeHelper.theme('青绿', '#E9F3E5', '#26352A', '#657769'),
      ReaderThemeHelper.theme('自定义', customBackgroundColor || ReaderThemeHelper.LIGHT_CUSTOM_BACKGROUND_COLOR,
        customTextColor || ReaderThemeHelper.LIGHT_CUSTOM_TEXT_COLOR,
        ReaderThemeHelper.derivedSubTextColor(false, customTextColor), '', '',
        ReaderBackgroundDisplay.of(customBackgroundImageFit, customImagePosition, customImageGap),
        customBackgroundImageUri),
      ReaderThemeHelper.applicationTheme(false)
    ];
  }

  static darkThemes(customBackgroundColor: string, customTextColor: string,
    customBackgroundImageUri: string = '', customBackgroundImageFit: string = 'cover',
    customImagePosition: number = 50, customImageGap: string = 'color'): ReaderThemeItem[] {
    return [
      ReaderThemeHelper.theme('夜间', '#1F2329', '#D8D8D8', '#9AA0A6'),
      ReaderThemeHelper.theme('墨灰', '#14161A', '#C8CCD3', '#8A8F98'),
      ReaderThemeHelper.theme('深蓝', '#101826', '#D5DFEA', '#8FA2B8'),
      ReaderThemeHelper.theme('自定义', customBackgroundColor || ReaderThemeHelper.DARK_CUSTOM_BACKGROUND_COLOR,
        customTextColor || ReaderThemeHelper.DARK_CUSTOM_TEXT_COLOR,
        ReaderThemeHelper.derivedSubTextColor(true, customTextColor), '', '',
        ReaderBackgroundDisplay.of(customBackgroundImageFit, customImagePosition, customImageGap),
        customBackgroundImageUri),
      ReaderThemeHelper.applicationTheme(true)
    ];
  }

  static themes(darkMode: boolean, customBackgroundColor: string, customTextColor: string,
    customBackgroundImageUri: string = '', customBackgroundImageFit: string = 'cover',
    customImagePosition: number = 50, customImageGap: string = 'color'): ReaderThemeItem[] {
    return darkMode ?
      ReaderThemeHelper.darkThemes(customBackgroundColor, customTextColor, customBackgroundImageUri,
        customBackgroundImageFit, customImagePosition, customImageGap) :
      ReaderThemeHelper.lightThemes(customBackgroundColor, customTextColor, customBackgroundImageUri,
        customBackgroundImageFit, customImagePosition, customImageGap);
  }

  static themeAt(darkMode: boolean, index: number, customBackgroundColor: string, customTextColor: string,
    customBackgroundImageUri: string = '', customBackgroundImageFit: string = 'cover',
    customImagePosition: number = 50, customImageGap: string = 'color'): ReaderThemeItem {
    const items = ReaderThemeHelper.themes(darkMode, customBackgroundColor, customTextColor,
      customBackgroundImageUri, customBackgroundImageFit, customImagePosition, customImageGap);
    return items[ReaderThemeHelper.normalizeIndex(index)] || items[0];
  }

  private static applicationTheme(darkMode: boolean): ReaderThemeItem {
    const assetId = ThemeRuntime.readerBackgroundAssetId(darkMode);
    // 主题包的整图背景走用户图片的那条路（铺满、按填充方式裁切）；素材键照样带上，
    // 整图模式也可以有角饰，ReaderThemeBackground 和自绘纹理把角饰叠在整图上。
    const packImage = ThemeAssetRegistry.readerBackgroundImage(assetId);
    const displayKey = packImage ? ThemeAssetRegistry.readerBackgroundPackThemeId(assetId) : '';
    const item = ReaderThemeHelper.theme(
      '应用主题',
      ThemeRuntime.readerBackgroundColor(darkMode),
      ThemeRuntime.readerTextColor(darkMode),
      ThemeRuntime.readerSubTextColor(darkMode),
      assetId,
      ThemeRuntime.readerContentTone(darkMode),
      packImage ? ReaderThemeHelper.packDisplay(assetId, displayKey) :
        ReaderBackgroundDisplay.of(ThemeRuntime.readerBackgroundImageFit(darkMode), 50, 'color'),
      packImage
    );
    item.backgroundDisplayKey = displayKey;
    return item;
  }

  /** 主题作者给这张整图定的显示方式（主题包只有 fit 一项）。 */
  static packDefaultDisplay(assetId: string): ReaderBackgroundDisplay {
    return ReaderBackgroundDisplay.of(ThemeAssetRegistry.readerBackgroundImageFit(assetId), 50, 'color');
  }

  /** 读者在这台设备上改过就用读者的，否则用主题作者的。 */
  private static packDisplay(assetId: string, displayKey: string): ReaderBackgroundDisplay {
    return ReaderBackgroundDisplayStore.override(displayKey) ?? ReaderThemeHelper.packDefaultDisplay(assetId);
  }

  private static theme(name: string, backgroundColor: string, textColor: string, subTextColor: string,
    backgroundAssetId: string = '', contentTone: string = '', display: ReaderBackgroundDisplay | null = null,
    backgroundImageUri: string = ''): ReaderThemeItem {
    const item = new ReaderThemeItem();
    item.name = name;
    item.backgroundColor = backgroundColor;
    item.textColor = textColor;
    item.subTextColor = subTextColor;
    item.backgroundAssetId = backgroundAssetId;
    item.backgroundImageUri = backgroundImageUri;
    if (display) {
      item.backgroundImageFit = display.fit;
      item.backgroundImagePosition = display.position;
      item.backgroundImageGap = display.gap;
    }
    item.contentTone = contentTone || (ReaderThemeHelper.isDarkColor(backgroundColor) ? 'dark' : 'light');
    return item;
  }

  private static isDarkColor(color: string): boolean {
    const value = (color || '').trim();
    if (!/^#[0-9a-fA-F]{6}$/.test(value)) {
      return false;
    }
    const red = parseInt(value.substring(1, 3), 16);
    const green = parseInt(value.substring(3, 5), 16);
    const blue = parseInt(value.substring(5, 7), 16);
    return red * 0.299 + green * 0.587 + blue * 0.114 < 128;
  }

  private static derivedSubTextColor(darkMode: boolean, textColor: string): string {
    const normalized = (textColor || '').trim();
    if (!/^#[0-9a-fA-F]{6}$/.test(normalized)) {
      return darkMode ? '#9AA0A6' : '#777777';
    }
    return darkMode ? '#9AA0A6' : '#777777';
  }
}
