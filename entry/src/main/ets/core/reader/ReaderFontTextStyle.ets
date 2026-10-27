import { text } from '@kit.ArkGraphics2D';
import { ReaderFontWeight } from './ReaderFontWeight';

/** Native text bindings distinguish an absent field from a field containing undefined. */
export class ReaderFontTextStyle {
  static resolve(original: text.TextStyle, requestedWeight: number): text.TextStyle {
    const family = original.fontFamilies && original.fontFamilies.length > 0 ? original.fontFamilies[0] : '';
    const weight = ReaderFontWeight.layoutWeight(family, requestedWeight);
    const style: text.TextStyle = {
      fontSize: original.fontSize ?? 20,
      fontFamilies: original.fontFamilies ?? [],
      color: original.color ?? { alpha: 255, red: 32, green: 33, blue: 36 },
      fontWeight: Math.max(0, Math.min(8, Math.round(weight / 100) - 1)),
      fontVariations: [{ axis: 'wght', value: weight }],
      letterSpacing: original.letterSpacing ?? 0,
      halfLeading: original.halfLeading ?? false,
      // Explicit transparent background also prevents a preceding highlighted span from leaking into this span.
      backgroundRect: original.backgroundRect ?? { color: { alpha: 0, red: 0, green: 0, blue: 0 },
        leftTopRadius: 0, rightTopRadius: 0, leftBottomRadius: 0, rightBottomRadius: 0 },
      textShadows: original.textShadows ?? [],
      decoration: original.decoration ?? { textDecoration: text.TextDecorationType.NONE }
    };
    if (original.heightOnly !== undefined) style.heightOnly = original.heightOnly;
    if (original.heightScale !== undefined) style.heightScale = original.heightScale;
    if (original.locale !== undefined) style.locale = original.locale;
    return style;
  }
}
