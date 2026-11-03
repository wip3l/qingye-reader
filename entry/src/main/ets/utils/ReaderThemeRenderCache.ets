import { ReaderThemeHelper, ReaderThemeItem } from './ReaderThemeHelper';
import { ReaderCustomThemeHelper } from './ReaderCustomThemeHelper';
import { ThemeRuntime } from '../theme/ThemeRuntime';

/** One reader's resolved theme. Compare source values before parsing custom schemes or cloning theme packs. */
export class ReaderThemeRenderCache {
  private cached: ReaderThemeItem | null = null;
  private dark: boolean = false;
  private index: number = -1;
  private revision: number = -1;
  private raw: string = '';
  private lightBackground: string = '';
  private lightText: string = '';
  private darkBackground: string = '';
  private darkText: string = '';
  private regexRevision: number = -1;
  private regexResolved: boolean = false;
  private regexDark: boolean = false;
  private mode: string = '';
  private bubble: string = '';

  theme(dark: boolean, index: number, revision: number, raw: string, lightBackground: string,
    lightText: string, darkBackground: string, darkText: string): ReaderThemeItem {
    if (this.cached && this.dark === dark && this.index === index && this.revision === revision &&
      this.raw === raw && this.lightBackground === lightBackground && this.lightText === lightText &&
      this.darkBackground === darkBackground && this.darkText === darkText) return this.cached;
    const schemes = ReaderCustomThemeHelper.parse(raw, lightBackground, lightText, darkBackground, darkText);
    const selected = ReaderCustomThemeHelper.selected(schemes, dark);
    const resolved = ReaderThemeHelper.themeAt(dark, index, selected.backgroundColor, selected.textColor,
      selected.backgroundType === 'image' ? selected.backgroundImageUri : '', selected.backgroundImageFit);
    this.dark = dark;
    this.index = index;
    this.revision = revision;
    this.raw = raw;
    this.lightBackground = lightBackground;
    this.lightText = lightText;
    this.darkBackground = darkBackground;
    this.darkText = darkText;
    this.cached = resolved;
    return resolved;
  }

  private resolveRegex(dark: boolean, revision: number): void {
    if (this.regexResolved && this.regexRevision === revision && this.regexDark === dark) return;
    const mode = ThemeRuntime.regexEmphasisModeFor(dark);
    const bubble = ThemeRuntime.regexBubbleStyleFor(dark);
    this.regexDark = dark;
    this.regexRevision = revision;
    this.regexResolved = true;
    this.mode = mode;
    this.bubble = bubble;
  }

  emphasisMode(dark: boolean, revision: number): string {
    this.resolveRegex(dark, revision);
    return this.mode;
  }

  bubbleStyle(dark: boolean, revision: number): string {
    this.resolveRegex(dark, revision);
    return this.bubble;
  }
}
