import { font, UIContext } from '@kit.ArkUI';
import fs from '@ohos.file.fs';
import fileUri from '@ohos.file.fileuri';
import graphicsText from '@ohos.graphics.text';
import { drawing } from '@kit.ArkGraphics2D';
import { ReaderFontMetadata } from '../core/reader/ReaderFontMetadata';
import { ReaderFontWeight } from '../core/reader/ReaderFontWeight';

export class ReaderFontItem {
  familyName: string = '';
  filePath: string = '';
  sourceName: string = '';
}

export class ReaderFontRegisterResult {
  familyName: string = '';
  filePath: string = '';
  registered: boolean = false;
  arkUiRegistered: boolean = false;
  legacyRegistered: boolean = false;
  graphicsTextRegistered: boolean = false;
  arkUiSource: string = '';
  legacySource: string = '';
  graphicsTextSource: string = '';
  errorSummary: string = '';
}

class ReaderGraphicsFontRecord {
  familyName: string = '';
  filePath: string = '';
}

class ReaderFontNameRecord {
  filePath: string = '';
  displayName: string = '';
}

export class ReaderFontHelper {
  private static registeredGraphicsFonts: ReaderGraphicsFontRecord[] = [];
  private static fontNameCache: ReaderFontNameRecord[] = [];
  static normalizeFontFamily(filePath: string): string {
    return ReaderFontHelper.stableFontFamily(filePath);
  }

  static stableFontFamily(filePath: string): string {
    const seed = ReaderFontHelper.fileNameFromPath(filePath);
    let hash = 0;
    for (let i = 0; i < filePath.length; i++) {
      hash = ((hash * 31) + filePath.charCodeAt(i)) & 0x7fffffff;
    }
    return `ReaderCustomFont_${ReaderFontHelper.sanitizeFontToken(seed)}_${hash}`;
  }

  static runtimeFontFamily(filePath: string): string {
    return ReaderFontHelper.stableFontFamily(filePath);
  }

  static registerFont(uiContext: UIContext | null, item: ReaderFontItem): ReaderFontRegisterResult {
    const result = new ReaderFontRegisterResult();
    if (!item || !item.filePath || !ReaderFontHelper.fontFileExists(item.filePath)) {
      return result;
    }
    const preparedPath = ReaderFontHelper.ensureAsciiFontPath(item.filePath);
    result.filePath = preparedPath;
    result.familyName = ReaderFontHelper.runtimeFontFamily(preparedPath);
    const errors: string[] = [];

    const sources = ReaderFontHelper.fontSources(preparedPath);
    for (const familySrc of sources) {
      if (uiContext) {
        try {
          uiContext.getFont().registerFont({
            familyName: result.familyName,
            familySrc: familySrc
          });
          result.arkUiRegistered = true;
          result.arkUiSource = familySrc;
          console.info(`当前 UIContext 注册阅读字体成功: ${result.familyName}, ${familySrc}`);
          break;
        } catch (e) {
          errors.push(`UIContext ${familySrc}: ${JSON.stringify(e)}`);
          console.warn(`当前 UIContext 注册阅读字体失败: ${familySrc}`, e);
        }
      }
    }

    for (const familySrc of sources) {
      try {
        font.registerFont({
          familyName: result.familyName,
          familySrc: familySrc
        });
        result.legacyRegistered = true;
        result.legacySource = familySrc;
        console.info(`全局注册阅读字体成功: ${result.familyName}, ${familySrc}`);
        break;
      } catch (e) {
        errors.push(`legacy ${familySrc}: ${JSON.stringify(e)}`);
        console.warn(`全局注册阅读字体失败: ${familySrc}`, e);
      }
    }
    result.graphicsTextRegistered = ReaderFontHelper.registerGraphicsTextFont(result.familyName, preparedPath, result);
    result.registered = result.arkUiRegistered;
    result.errorSummary = errors.join(' | ');
    return result;
  }

  static registerGraphicsTextFont(
    familyName: string,
    filePath: string,
    result?: ReaderFontRegisterResult
  ): boolean {
    if (ReaderFontHelper.hasRegisteredGraphicsFamily(familyName, filePath)) {
      return true;
    }
    ReaderFontHelper.unloadGraphicsFamily(familyName);
    for (const familySrc of ReaderFontHelper.fontSources(filePath)) {
      if (!familySrc.startsWith('file://')) {
        continue;
      }
      try {
        graphicsText.FontCollection.getGlobalInstance().loadFontSyncWithCheck(familyName, familySrc);
        ReaderFontHelper.rememberGraphicsFamily(familyName, filePath);
        if (result) {
          result.graphicsTextSource = familySrc;
        }
        console.info(`graphics.text 注册阅读字体成功: ${familyName}, ${familySrc}`);
        return true;
      } catch (e) {
        try {
          graphicsText.FontCollection.getGlobalInstance().loadFontSync(familyName, familySrc);
          ReaderFontHelper.rememberGraphicsFamily(familyName, filePath);
          if (result) {
            result.graphicsTextSource = familySrc;
          }
          console.info(`graphics.text 注册阅读字体成功: ${familyName}, ${familySrc}`);
          return true;
        } catch (err) {
          console.warn(`graphics.text 注册阅读字体失败: ${familySrc}`, err);
        }
      }
    }
    return false;
  }

  static hasRegisteredGraphicsFamily(familyName: string, filePath: string): boolean {
    for (const item of ReaderFontHelper.registeredGraphicsFonts) {
      if (item.familyName === familyName && item.filePath === filePath) {
        return true;
      }
    }
    return false;
  }

  static rememberGraphicsFamily(familyName: string, filePath: string): void {
    const next: ReaderGraphicsFontRecord[] = [];
    for (const item of ReaderFontHelper.registeredGraphicsFonts) {
      if (item.familyName !== familyName) {
        next.push(item);
      }
    }
    const record = new ReaderGraphicsFontRecord();
    record.familyName = familyName;
    record.filePath = filePath;
    next.push(record);
    ReaderFontHelper.registeredGraphicsFonts = next;
    ReaderFontHelper.registerWeightSupport(familyName, filePath);
  }

  private static registerWeightSupport(familyName: string, filePath: string): void {
    try {
      const size = Number(fs.statSync(filePath).size);
      const file = fs.openSync(filePath, fs.OpenMode.READ_ONLY);
      let metadata: ReaderFontMetadata;
      try {
        metadata = ReaderFontMetadata.inspect(size, (offset: number, length: number): Uint8Array =>
          ReaderFontHelper.readFontBytes(file.fd, offset, length));
      } finally {
        fs.closeSync(file);
      }
      if (!metadata.known) return;
      if (metadata.variableWeight) {
        ReaderFontWeight.registerVariable(familyName, metadata.minWeight, metadata.maxWeight);
      } else {
        const face = drawing.Typeface.makeFromFile(filePath);
        if (face) ReaderFontWeight.registerStatic(familyName, face.getFamilyName());
      }
    } catch (error) {
      console.warn(`读取字体字重能力失败: ${filePath}`, error);
    }
  }

  static unloadGraphicsFamily(familyName: string): void {
    ReaderFontWeight.unregister(familyName);
    try {
      graphicsText.FontCollection.getGlobalInstance().unloadFontSync(familyName);
    } catch (e) {
    }
    const next: ReaderGraphicsFontRecord[] = [];
    for (const item of ReaderFontHelper.registeredGraphicsFonts) {
      if (item.familyName !== familyName) {
        next.push(item);
      }
    }
    ReaderFontHelper.registeredGraphicsFonts = next;
  }

  static fontSources(filePath: string): string[] {
    const result: string[] = [];
    ReaderFontHelper.pushUnique(result, `file://${filePath}`);
    ReaderFontHelper.pushUnique(result, filePath);
    try {
      ReaderFontHelper.pushUnique(result, fileUri.getUriFromPath(filePath));
    } catch (e) {
      console.warn('生成阅读字体 file uri 失败:', e);
    }
    return result;
  }

  static pushUnique(result: string[], value: string): void {
    if (!value) {
      return;
    }
    for (const item of result) {
      if (item === value) {
        return;
      }
    }
    result.push(value);
  }

  static fontFileExists(path: string): boolean {
    try {
      return fs.accessSync(path);
    } catch (e) {
      return false;
    }
  }

  static ensureAsciiFontPath(filePath: string): string {
    const name = ReaderFontHelper.fileNameFromPath(filePath);
    if (ReaderFontHelper.isAsciiSafeFileName(name) || !ReaderFontHelper.fontFileExists(filePath)) {
      return filePath;
    }
    const dirIndex = Math.max(filePath.lastIndexOf('/'), filePath.lastIndexOf('\\'));
    if (dirIndex < 0) {
      return filePath;
    }
    const dir = filePath.substring(0, dirIndex);
    let targetPath = `${dir}/${ReaderFontHelper.asciiStoredFontName(name, 0)}`;
    let index = 1;
    while (ReaderFontHelper.fontFileExists(targetPath)) {
      targetPath = `${dir}/${ReaderFontHelper.asciiStoredFontName(name, index)}`;
      index++;
    }
    try {
      fs.renameSync(filePath, targetPath);
      return targetPath;
    } catch (e) {
      console.warn('迁移阅读字体文件名失败:', e);
      return filePath;
    }
  }

  static fileNameFromPath(path: string): string {
    const decoded = decodeURIComponent(path || '');
    const index = Math.max(decoded.lastIndexOf('/'), decoded.lastIndexOf('\\'));
    return index >= 0 ? decoded.substring(index + 1) : decoded || 'font';
  }

  /**
   * Internal font files deliberately use ASCII reader_font_* / cloud_UUID names so that all
   * ArkUI font loaders can open them. Those storage names must never leak into
   * the settings UI. For old records that already lost their sourceName, read
   * the OpenType `name` table and recover the embedded font name.
   */
  static resolveDisplayName(sourceName: string, filePath: string): string {
    const source = (sourceName || '').trim();
    if (source && !ReaderFontHelper.isInternalFontName(source)) {
      return source;
    }
    const embeddedName = ReaderFontHelper.embeddedFontName(filePath);
    if (embeddedName) {
      return embeddedName;
    }
    const fileName = ReaderFontHelper.fileNameFromPath(filePath);
    return ReaderFontHelper.isInternalFontName(fileName) ? '自定义字体' : fileName;
  }

  static isInternalFontName(value: string): boolean {
    const name = ReaderFontHelper.fileNameFromPath((value || '').trim()).toLowerCase();
    return /^reader_font(?:_[0-9]+)?(?:_[0-9]+)?(?:\.(?:ttf|otf|ttc))?$/.test(name) ||
      /^cloud_[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\.(?:ttf|otf|ttc)$/.test(name);
  }

  static embeddedFontName(filePath: string): string {
    if (!filePath || !ReaderFontHelper.fontFileExists(filePath)) {
      return '';
    }
    for (const cached of ReaderFontHelper.fontNameCache) {
      if (cached.filePath === filePath) {
        return cached.displayName;
      }
    }
    let displayName = '';
    try {
      displayName = ReaderFontHelper.readEmbeddedFontName(filePath);
    } catch (e) {
      console.warn(`读取字体名称失败: ${filePath}`, e);
    }
    const record = new ReaderFontNameRecord();
    record.filePath = filePath;
    record.displayName = displayName;
    ReaderFontHelper.fontNameCache.push(record);
    return displayName;
  }

  private static readEmbeddedFontName(filePath: string): string {
    const stat = fs.statSync(filePath);
    const fileSize = Number(stat.size);
    if (!Number.isSafeInteger(fileSize) || fileSize < 12) {
      return '';
    }
    const file = fs.openSync(filePath, fs.OpenMode.READ_ONLY);
    try {
      const firstHeader = ReaderFontHelper.readFontBytes(file.fd, 0, Math.min(16, fileSize));
      if (firstHeader.length < 12) {
        return '';
      }
      let fontOffset = 0;
      if (ReaderFontHelper.byteTag(firstHeader, 0) === 'ttcf') {
        if (firstHeader.length < 16) {
          return '';
        }
        fontOffset = ReaderFontHelper.uint32(firstHeader, 12);
      }
      if (fontOffset < 0 || fontOffset + 12 > fileSize) {
        return '';
      }
      const offsetHeader = ReaderFontHelper.readFontBytes(file.fd, fontOffset, 12);
      if (offsetHeader.length < 12) {
        return '';
      }
      const tableCount = ReaderFontHelper.uint16(offsetHeader, 4);
      if (tableCount <= 0 || tableCount > 4096) {
        return '';
      }
      const directoryLength = tableCount * 16;
      if (fontOffset + 12 + directoryLength > fileSize) {
        return '';
      }
      const directory = ReaderFontHelper.readFontBytes(file.fd, fontOffset + 12, directoryLength);
      let nameOffset = -1;
      let nameLength = 0;
      for (let i = 0; i < tableCount; i++) {
        const recordOffset = i * 16;
        if (ReaderFontHelper.byteTag(directory, recordOffset) === 'name') {
          nameOffset = ReaderFontHelper.uint32(directory, recordOffset + 8);
          nameLength = ReaderFontHelper.uint32(directory, recordOffset + 12);
          break;
        }
      }
      if (nameOffset < 0 || nameLength < 6 || nameLength > 4 * 1024 * 1024 ||
        nameOffset + nameLength > fileSize) {
        return '';
      }
      const nameTable = ReaderFontHelper.readFontBytes(file.fd, nameOffset, nameLength);
      return ReaderFontHelper.bestNameFromTable(nameTable);
    } finally {
      fs.closeSync(file);
    }
  }

  private static readFontBytes(fd: number, offset: number, length: number): Uint8Array {
    if (length <= 0) {
      return new Uint8Array(0);
    }
    const buffer = new ArrayBuffer(length);
    const readLength = fs.readSync(fd, buffer, { offset: offset, length: length });
    if (readLength <= 0) {
      return new Uint8Array(0);
    }
    return new Uint8Array(buffer, 0, readLength);
  }

  private static bestNameFromTable(table: Uint8Array): string {
    if (table.length < 6) {
      return '';
    }
    const count = ReaderFontHelper.uint16(table, 2);
    const stringsOffset = ReaderFontHelper.uint16(table, 4);
    if (count <= 0 || count > 4096 || 6 + count * 12 > table.length || stringsOffset >= table.length) {
      return '';
    }
    let bestName = '';
    let bestScore = -1;
    for (let i = 0; i < count; i++) {
      const recordOffset = 6 + i * 12;
      const platformId = ReaderFontHelper.uint16(table, recordOffset);
      const languageId = ReaderFontHelper.uint16(table, recordOffset + 4);
      const nameId = ReaderFontHelper.uint16(table, recordOffset + 6);
      const length = ReaderFontHelper.uint16(table, recordOffset + 8);
      const valueOffset = stringsOffset + ReaderFontHelper.uint16(table, recordOffset + 10);
      if ((nameId !== 1 && nameId !== 4 && nameId !== 6 && nameId !== 16) || length <= 0 ||
        valueOffset < 0 || valueOffset + length > table.length) {
        continue;
      }
      const value = ReaderFontHelper.decodeFontName(table, valueOffset, length, platformId);
      if (!value) {
        continue;
      }
      let score = nameId === 4 ? 400 : (nameId === 16 ? 350 : (nameId === 1 ? 300 : 200));
      if (platformId === 0 || platformId === 3) {
        score += 20;
      }
      if (languageId === 0x0804 || languageId === 0x0404 || languageId === 0x0C04 || languageId === 0x1004) {
        score += 40;
      } else if (languageId === 0x0409 || languageId === 0) {
        score += 10;
      }
      if (score > bestScore) {
        bestScore = score;
        bestName = value;
      }
    }
    return bestName;
  }

  private static decodeFontName(bytes: Uint8Array, offset: number, length: number, platformId: number): string {
    let result = '';
    if (platformId === 0 || platformId === 3) {
      for (let i = 0; i + 1 < length; i += 2) {
        const code = (bytes[offset + i] << 8) | bytes[offset + i + 1];
        if (code !== 0) {
          result += String.fromCharCode(code);
        }
      }
    } else {
      for (let i = 0; i < length; i++) {
        const code = bytes[offset + i];
        if (code !== 0) {
          result += String.fromCharCode(code);
        }
      }
    }
    result = result.replace(/[\u0000-\u001F]+/g, ' ').replace(/\s+/g, ' ').trim();
    return result.length <= 128 ? result : '';
  }

  private static byteTag(bytes: Uint8Array, offset: number): string {
    if (offset < 0 || offset + 4 > bytes.length) {
      return '';
    }
    return String.fromCharCode(bytes[offset], bytes[offset + 1], bytes[offset + 2], bytes[offset + 3]);
  }

  private static uint16(bytes: Uint8Array, offset: number): number {
    if (offset < 0 || offset + 2 > bytes.length) {
      return 0;
    }
    return (bytes[offset] << 8) | bytes[offset + 1];
  }

  private static uint32(bytes: Uint8Array, offset: number): number {
    if (offset < 0 || offset + 4 > bytes.length) {
      return 0;
    }
    return bytes[offset] * 0x1000000 + bytes[offset + 1] * 0x10000 +
      bytes[offset + 2] * 0x100 + bytes[offset + 3];
  }

  static fontExt(uri: string): string {
    const lower = (uri || '').toLowerCase();
    if (lower.includes('.otf')) return '.otf';
    if (lower.includes('.ttc')) return '.ttc';
    return '.ttf';
  }

  static asciiStoredFontName(sourceName: string, salt: number): string {
    const ext = ReaderFontHelper.fontExt(sourceName);
    let hash = salt & 0x7fffffff;
    for (let i = 0; i < sourceName.length; i++) {
      hash = ((hash * 31) + sourceName.charCodeAt(i)) & 0x7fffffff;
    }
    return `reader_font_${hash}${ext}`;
  }

  static isAsciiSafeFileName(name: string): boolean {
    if (!name || name.includes('/') || name.includes('\\')) {
      return false;
    }
    for (let i = 0; i < name.length; i++) {
      const code = name.charCodeAt(i);
      if (code < 33 || code > 126) {
        return false;
      }
    }
    return true;
  }

  static sanitizeFontToken(value: string): string {
    let token = '';
    for (let i = 0; i < value.length; i++) {
      const ch = value.charAt(i);
      const code = value.charCodeAt(i);
      const isDigit = code >= 48 && code <= 57;
      const isUpper = code >= 65 && code <= 90;
      const isLower = code >= 97 && code <= 122;
      token += (isDigit || isUpper || isLower) ? ch : '_';
    }
    while (token.includes('__')) {
      token = token.replace('__', '_');
    }
    token = token.replace(/^_+|_+$/g, '');
    return token || 'font';
  }
}
