import { ThemeRuntime } from './ThemeRuntime';

/** 弹窗里按钮的作用：取消/次要、确认、删除类。 */
export type DialogButtonRole = 'cancel' | 'primary' | 'danger';

/**
 * 居中弹窗的统一配色。弹窗表面是系统沉浸光感材质，里面的按钮和选项行都用半透明底，
 * 不用实色块，否则会把材质盖成一块平板：
 * - 取消/次要：中性淡底 + 正文色；
 * - 确认：强调色淡底 + 强调色字；
 * - 删除类：危险色淡底 + 危险色字。
 */
export class DialogStyle {
  static readonly BUTTON_HEIGHT: number = 42;

  static fill(role: DialogButtonRole, darkMode: boolean): string {
    if (role === 'primary') return ThemeRuntime.accentSurfaceColor(darkMode);
    if (role === 'danger') return DialogStyle.tint(ThemeRuntime.dangerColor(darkMode), darkMode);
    return ThemeRuntime.softFillColor(darkMode);
  }

  static text(role: DialogButtonRole, darkMode: boolean): string {
    if (role === 'primary') return ThemeRuntime.accentColor(darkMode);
    if (role === 'danger') return ThemeRuntime.dangerColor(darkMode);
    return ThemeRuntime.primaryTextColor(darkMode);
  }

  /** 选项行、输入框等弹窗内的块：和取消按钮同一种中性淡底。 */
  static rowFill(darkMode: boolean): string {
    return ThemeRuntime.softFillColor(darkMode);
  }

  /** 选项行里图标的圆底。 */
  static iconFill(darkMode: boolean): string {
    return ThemeRuntime.accentSurfaceColor(darkMode);
  }

  /** 任意颜色的淡底，透明度与强调色淡底一致（浅色 12%、深色 20%）。 */
  static tint(color: string, darkMode: boolean): string {
    const rgb = DialogStyle.rgbOf(color);
    if (!rgb) return ThemeRuntime.softFillColor(darkMode);
    return `#${darkMode ? '33' : '1F'}${rgb}`;
  }

  private static rgbOf(color: string): string {
    const value = (color || '').trim();
    if (/^#[0-9a-fA-F]{6}$/.test(value)) return value.substring(1);
    if (/^#[0-9a-fA-F]{8}$/.test(value)) return value.substring(3);
    return '';
  }
}
