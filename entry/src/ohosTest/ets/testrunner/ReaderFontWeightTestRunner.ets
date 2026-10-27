import { TestRunner, abilityDelegatorRegistry } from '@kit.TestKit';
import { drawing, text } from '@kit.ArkGraphics2D';
import { image } from '@kit.ImageKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { ReaderFontHelper } from '../../../main/ets/utils/ReaderFontHelper';
import { ReaderFontWeight } from '../../../main/ets/core/reader/ReaderFontWeight';
import { ReaderFontStroke } from '../../../main/ets/core/reader/ReaderFontStroke';
import { ReaderFontTextStyle } from '../../../main/ets/core/reader/ReaderFontTextStyle';
import { ReaderV2DocumentParser } from '../../../main/ets/core/reader/ReaderV2Document';
import { ReaderV2LayoutInput, ReaderV2LayoutSnapshot } from '../../../main/ets/core/reader/ReaderV2LayoutSnapshot';
import { ReaderV2Paginator } from '../../../main/ets/core/reader/ReaderV2Paginator';
import { ReaderV2SpanStyleRange } from '../../../main/ets/core/reader/ReaderV2Style';

/** Explicit local font fixture in app cache; never changes books, preferences or installed font selections. */
export default class ReaderFontWeightTestRunner implements TestRunner {
  onPrepare(): void {}

  async onRun(): Promise<void> {
    const delegator = abilityDelegatorRegistry.getAbilityDelegator();
    try {
      const dir = delegator.getAppContext().getApplicationContext().cacheDir;
      const fixture = await delegator.getAppContext().createModuleContext('entry_test').resourceManager
        .getRawFileContent('reader-font-fixture.ttf');
      const fixtureFile = fs.openSync(`${dir}/reader-font-fixture.ttf`, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try { fs.writeSync(fixtureFile.fd, fixture.buffer as ArrayBuffer); } finally { fs.closeSync(fixtureFile); }
      const family = 'ReaderStrokeFixture';
      if (!ReaderFontHelper.registerGraphicsTextFont(family, `${dir}/reader-font-fixture.ttf`) ||
        !ReaderFontWeight.isStatic(family)) throw new Error('Expected a static TTF fixture in app cache');
      await this.verifyPreviewBackground(family);
      await this.verifyIndependentWeights(family);
      const content = '乖乖小熊的打工日记：今天也要认真读书。\n微风吹过窗边，细细的笔画依然清晰。ABC 123，标点与换行。\n' +
        '正则文字改变大小和颜色，普通文字保持原样。'.repeat(28);
      const document = ReaderV2DocumentParser.parse(content, 0, '');
      const regex = new ReaderV2SpanStyleRange(5, 12);
      regex.fontFamily = family;
      regex.fontSizePx = 60;
      regex.color = 0xFF2266AA;
      let baseline = '';
      let previousInk = 0;
      for (const weight of [400, 401, 450, 500, 600, 900]) {
        const input = new ReaderV2LayoutInput();
        input.viewportWidthPx = 820;
        input.viewportHeightPx = 1120;
        input.marginLeftPx = 30; input.marginRightPx = 30;
        input.marginTopPx = 30; input.marginBottomPx = 30;
        input.fontSizePx = 48; input.fontWeight = weight;
        input.bodyFontFamily = family; input.titleFontFamily = family;
        input.lineSpacingPx = 12; input.paragraphSpacingPx = 16;
        const started = Date.now();
        const pages = ReaderV2Paginator.paginate(document, ReaderV2LayoutSnapshot.create(input), [regex]);
        const paginationMs = Date.now() - started;
        const identity = pages.pages.map(page => `${page.displayStart}:${page.displayEnd}:` +
          page.fragments.map(fragment => `${fragment.paragraphX},${fragment.paragraphY},${fragment.displayStart},${fragment.displayEnd}`).join('|')).join('/');
        if (!baseline) baseline = identity;
        if (identity !== baseline) throw new Error(`Pagination changed at ${weight}`);
        const pixels = new Uint8Array(820 * 1120 * 4); pixels.fill(255);
        const bitmap = image.createPixelMapSync(pixels.buffer as ArrayBuffer, {
          size: { width: 820, height: 1120 }, editable: true, pixelFormat: image.PixelMapFormat.RGBA_8888
        });
        const canvas = new drawing.Canvas(bitmap);
        let count = 0;
        for (const fragment of pages.pages[0].fragments) {
          if (!fragment.paragraph) continue;
          canvas.save();
          canvas.clipRect(fragment.clipRect, drawing.ClipOp.INTERSECT, true);
          fragment.paragraph.paint(canvas, fragment.paragraphX, fragment.paragraphY);
          ReaderFontStroke.paint(canvas, fragment.fontStrokes, fragment.paragraphX, fragment.paragraphY);
          canvas.restore();
          count += fragment.fontStrokes.length;
        }
        if (weight > 400 && count === 0) throw new Error('Missing outline runs');
        const output = new ArrayBuffer(bitmap.getPixelBytesNumber());
        await bitmap.readPixelsToBuffer(output);
        const rgba = new Uint8Array(output);
        let ink = 0;
        for (let index = 0; index < rgba.length; index += 4) ink += 765 - rgba[index] - rgba[index + 1] - rgba[index + 2];
        if (ink <= previousInk) throw new Error(`No progressive thickening at ${weight}`);
        // Rasterization is quantized, but a one-unit adjustment must not redraw an opaque fill.
        if (weight === 401 && ink > previousInk * 1.03) throw new Error('Abrupt jump at first weight step');
        previousInk = ink;
        const packer = image.createImagePacker();
        try {
          const bytes = await packer.packToData(bitmap, { format: 'image/png', quality: 100 });
          const file = fs.openSync(`${dir}/reader-weight-${weight}.png`, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
          try { fs.writeSync(file.fd, bytes); } finally { fs.closeSync(file); }
          const encoded = new util.Base64Helper().encodeToStringSync(new Uint8Array(bytes));
          for (let chunk = 0; chunk < encoded.length; chunk += 4000) {
            await delegator.print(`FONT_IMAGE ${weight} ${chunk} ${encoded.substring(chunk, chunk + 4000)}\n`);
          }
        } finally { await packer.release(); await bitmap.release(); }
        await delegator.print(`FONT_WEIGHT ${weight} ink=${ink} runs=${count} paginationMs=${paginationMs} pages=${pages.pages.length}\n`);
      }
      ReaderFontHelper.unloadGraphicsFamily(family);
      await delegator.finishTest('PASS ReaderFontWeight: stable pagination and native renders saved in cache', 0);
    } catch (error) {
      await delegator.finishTest(`FAIL ReaderFontWeight: ${(error as Error).message}`, -1);
    }
  }

  private async verifyPreviewBackground(family: string): Promise<void> {
    const delegator = abilityDelegatorRegistry.getAbilityDelegator();
    for (const legacy of [true, false]) {
      const original: text.TextStyle = { fontSize: 58, fontFamilies: [family],
        color: { alpha: 255, red: 40, green: 80, blue: 180 }, halfLeading: false };
      const style = ReaderFontTextStyle.resolve(original, 400);
      if (legacy) style.backgroundRect = original.backgroundRect;
      const builder = new text.ParagraphBuilder({ textStyle: style, maxLines: 2 },
        text.FontCollection.getGlobalInstance());
      builder.pushStyle(style);
      builder.addText('这是一段阅读正文预览，文字会跟随当前正文字体设置显示。');
      builder.popStyle();
      const paragraph = builder.build();
      paragraph.layoutSync(780);
      const pixels = new Uint8Array(820 * 240 * 4); pixels.fill(255);
      const bitmap = image.createPixelMapSync(pixels.buffer as ArrayBuffer, {
        size: { width: 820, height: 240 }, editable: true, pixelFormat: image.PixelMapFormat.RGBA_8888
      });
      try {
        paragraph.paint(new drawing.Canvas(bitmap), 20, 20);
        const buffer = new ArrayBuffer(bitmap.getPixelBytesNumber());
        await bitmap.readPixelsToBuffer(buffer);
        const rgba = new Uint8Array(buffer);
        let black = 0;
        for (let i = 0; i < rgba.length; i += 4) {
          if (rgba[i] < 10 && rgba[i + 1] < 10 && rgba[i + 2] < 10) black++;
        }
        await delegator.print(`PREVIEW_BACKGROUND legacy=${legacy} blackPixels=${black}\n`);
        if (!legacy && black !== 0) throw new Error('Body preview has an unexpected black background');
        const packer = image.createImagePacker();
        try {
          const bytes = await packer.packToData(bitmap, { format: 'image/png', quality: 100 });
          const encoded = new util.Base64Helper().encodeToStringSync(new Uint8Array(bytes));
          for (let chunk = 0; chunk < encoded.length; chunk += 4000) {
            await delegator.print(`PREVIEW_IMAGE ${legacy ? 'before' : 'after'} ${chunk} ${encoded.substring(chunk, chunk + 4000)}\n`);
          }
        } finally { await packer.release(); }
      } finally { await bitmap.release(); }
    }
  }

  private async verifyIndependentWeights(family: string): Promise<void> {
    const document = ReaderV2DocumentParser.parse('标题\n正文正则尾文', 0, '标题');
    const input = new ReaderV2LayoutInput();
    input.viewportWidthPx = 820; input.viewportHeightPx = 1120;
    input.fontSizePx = 48; input.titleFontSizePx = 48;
    input.bodyFontFamily = family; input.titleFontFamily = family;
    input.fontWeight = 400; input.titleFontWeight = 900;
    const start = document.displayText.indexOf('正则');
    const rule = new ReaderV2SpanStyleRange(start, start + 2);
    rule.fontFamily = family; rule.fontSizePx = 48; rule.fontWeight = 700;
    const pages = ReaderV2Paginator.paginate(document, ReaderV2LayoutSnapshot.create(input), [rule]);
    let titleStrokes = 0;
    let regexStrokes = 0;
    for (const page of pages.pages) {
      for (const fragment of page.fragments) {
        for (const stroke of fragment.fontStrokes) {
          const range = stroke.run.getStringRange();
          const absoluteStart = fragment.displayStart + range.start;
          const absoluteEnd = fragment.displayStart + range.end;
          if (absoluteStart < 2) { titleStrokes++; continue; }
          if (absoluteStart < start || absoluteEnd > start + 2) throw new Error('Rule outline leaked outside its match');
          regexStrokes++;
        }
      }
    }
    if (titleStrokes === 0 || regexStrokes === 0) throw new Error('Missing independent title/rule outline');
    await abilityDelegatorRegistry.getAbilityDelegator().print(`INDEPENDENT_WEIGHTS title=${titleStrokes} regex=${regexStrokes}\n`);
  }
}
