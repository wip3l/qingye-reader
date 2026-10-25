import { syncSystemBars } from '../utils/SystemBars';
import { ReaderSettingsStore } from '../utils/ReaderSettingsStore';
import { ReaderFontHelper, ReaderFontItem } from '../utils/ReaderFontHelper';
import { ReaderSystemFontHelper } from '../utils/ReaderSystemFontHelper';
import { ReaderFontBootstrap } from '../utils/ReaderFontBootstrap';
import picker from '@ohos.file.picker';
import fs from '@ohos.file.fs';
import fileUri from '@ohos.file.fileuri';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { HdsFeedback } from '../utils/HdsFeedback';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { PageScaffold } from '../components/common/PageScaffold';
import { CloudAutoSync, CloudRemoteFont } from '../account/CloudAutoSync';

class ReaderCustomFontItem {
  familyName: string = '';
  filePath: string = '';
  sourceName: string = '';
}

class ReaderCustomFontData {
  fonts: ReaderCustomFontItem[] = [];
}

@Entry
@Component
struct CustomFontManagerPage {
  @StorageLink('readerFontFamily') readerFontFamily: string = '';
  @StorageLink('readerFontFilePath') readerFontFilePath: string = '';
  @StorageLink('readerFontSourceName') readerFontSourceName: string = '系统默认';
  @StorageLink('readerFontMode') readerFontMode: string = 'device';
  @StorageLink('readerSystemFontFamily') readerSystemFontFamily: string = '';
  @StorageLink('readerCustomFontsRaw') readerCustomFontsRaw: string = '';
  @StorageLink('cloudRemoteFontsRaw') cloudRemoteFontsRaw: string = '';
  @StorageLink('readerActiveFontFamily') readerActiveFontFamily: string = '';
  @StorageLink('readerFontRegistered') readerFontRegistered: boolean = false;
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageLink('appLightButtonColor') appLightButtonColor: string = '#007DFF';
  @StorageLink('appDarkButtonColor') appDarkButtonColor: string = '#3F8CFF';

  @State customFonts: ReaderCustomFontItem[] = [];
  @State refreshingCloudFonts: boolean = false;
  @State cloudFontError: string = '';
  @State downloadingCloudFontId: string = '';
  @State cloudFontDownloadStatus: string = '';

  aboutToAppear(): void {
    this.refreshSystemFontFamily();
    this.refreshFontLists();
    this.syncBars();
  }

  onPageShow(): void {
    this.refreshSystemFontFamily();
    this.refreshFontLists();
    this.syncBars();
  }

  refreshSystemFontFamily(): string {
    const family = ReaderSystemFontHelper.applyToStorage(this.getUIContext());
    this.readerSystemFontFamily = family;
    return family;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      PageScaffold({ title: '自定义字体', content: () => {
        this.pageContent()
      } })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  pageContent() {
    this.uploadPanel()

    this.sectionTitle('已上传字体')
    if (this.customFonts.length > 0) {
      Column({ space: 1 }) {
        ForEach(this.customFonts, (item: ReaderCustomFontItem) => {
          this.fontItem(item)
        }, (item: ReaderCustomFontItem): string => item.filePath)
      }
      .width('100%')
      .backgroundColor(this.cardColor())
    } else {
      this.emptyPanel()
    }

    this.cloudFontsPanel()
  }

  remoteFonts(): CloudRemoteFont[] {
    return CloudAutoSync.parseRemoteFonts(this.cloudRemoteFontsRaw);
  }

  async refreshFontLists(): Promise<void> {
    if (this.refreshingCloudFonts || this.downloadingCloudFontId) return;
    this.refreshingCloudFonts = true;
    this.cloudFontError = '';
    try {
      await this.reloadCustomFonts();
      await CloudAutoSync.reconcile(getContext(this));
      // 对账可能移除其他设备已删除的字体，同步更新本机列表。
      this.loadCustomFonts();
    } catch (error) {
      this.cloudFontError = error instanceof Error && error.message ? error.message : '获取云端字体失败，请重试';
    } finally {
      this.refreshingCloudFonts = false;
    }
  }

  async downloadCloudFont(font: CloudRemoteFont): Promise<void> {
    if (this.downloadingCloudFontId) return;
    this.downloadingCloudFontId = font.id;
    this.cloudFontDownloadStatus = '准备下载';
    this.cloudFontError = '';
    try {
      const filePath = await CloudAutoSync.ensureFontDownloaded(getContext(this), font,
        (done: number, total: number): void => {
          this.cloudFontDownloadStatus = total > 0 ?
            `下载中 ${Math.min(100, Math.floor(done * 100 / total))}%` : '下载中';
        },
        (seconds: number): void => {
          this.cloudFontDownloadStatus = `${seconds} 秒后继续下载`;
        });
      this.loadCustomFonts();
      const imported = this.customFonts.find((item: ReaderCustomFontItem): boolean => item.filePath === filePath);
      if (!imported) throw new Error('字体已下载，但导入未完成，请重试');
      if (this.registerCustomFont(imported)) {
        HdsFeedback.showToast('已下载并导入，可在字体设置中选择');
      } else {
        HdsFeedback.showToast('字体已导入，但注册失败，请检查字体文件');
      }
    } catch (error) {
      this.cloudFontError = error instanceof Error && error.message ? error.message : '云端字体下载失败，请重试';
      HdsFeedback.showToast(this.cloudFontError);
    } finally {
      this.downloadingCloudFontId = '';
      this.cloudFontDownloadStatus = '';
    }
  }

  cloudFontSize(bytes: number): string {
    return bytes >= 1048576 ? `${(bytes / 1048576).toFixed(1)} MB` : `${Math.max(1, Math.ceil(bytes / 1024))} KB`;
  }

  async reloadCustomFonts(): Promise<void> {
    this.loadCustomFonts();
    try {
      await this.scanCustomFontDir();
    } catch (e) {
      console.warn('扫描自定义字体失败:', e);
    }
    this.syncSelectedCustomFont();
    this.registerCustomFonts();
  }

  loadCustomFonts(): void {
    const raw = (this.readerCustomFontsRaw || '').trim();
    if (!raw) {
      this.customFonts = [];
      return;
    }
    try {
      const parsed = JSON.parse(raw) as ReaderCustomFontData | ReaderCustomFontItem[];
      const source = Array.isArray(parsed) ? parsed as ReaderCustomFontItem[] : ((parsed as ReaderCustomFontData).fonts || []);
      this.customFonts = this.cleanCustomFonts(source);
      this.saveCustomFonts(this.customFonts);
    } catch (e) {
      this.customFonts = [];
    }
  }

  saveCustomFonts(fonts: ReaderCustomFontItem[]): void {
    const data = new ReaderCustomFontData();
    data.fonts = this.cleanCustomFonts(fonts);
    this.customFonts = data.fonts;
    this.readerCustomFontsRaw = JSON.stringify(data);
    this.saveFontSettings();
  }

  cleanCustomFonts(source: ReaderCustomFontItem[]): ReaderCustomFontItem[] {
    const result: ReaderCustomFontItem[] = [];
    for (const item of source) {
      if (!item || !item.filePath || !this.fontFileExists(item.filePath)) {
        continue;
      }
      const fontItem = new ReaderCustomFontItem();
      fontItem.filePath = (item.filePath || '').trim();
      fontItem.sourceName = ReaderFontHelper.resolveDisplayName(item.sourceName, fontItem.filePath);
      fontItem.familyName = this.normalizedFontFamily(fontItem.filePath);
      if (fontItem.familyName && fontItem.filePath && !this.hasCustomFont(result, fontItem.familyName, fontItem.filePath)) {
        result.push(fontItem);
      }
    }
    return result;
  }

  async scanCustomFontDir(): Promise<void> {
    const dir = `${getContext(this).filesDir}/reader_fonts`;
    let names: string[] = [];
    try {
      names = await fs.listFile(dir);
    } catch (e) {
      return;
    }
    names.sort();
    const next = this.customFonts.slice();
    let changed = false;
    for (const name of names) {
      if (!this.isFontFile(name)) {
        continue;
      }
      const migratedName = this.ensureAsciiStoredFontName(dir, name);
      const filePath = `${dir}/${migratedName}`;
      const familyName = this.familyNameForPath(filePath);
      const existingIndex = this.findCustomFontIndexByFilePath(next, filePath);
      if (familyName && existingIndex >= 0 && next[existingIndex].familyName !== familyName) {
        next[existingIndex].familyName = familyName;
        if (this.readerFontFilePath === filePath) {
          this.readerFontFamily = familyName;
        }
        changed = true;
      } else if (existingIndex >= 0) {
        const displayName = ReaderFontHelper.resolveDisplayName(next[existingIndex].sourceName, filePath);
        if (next[existingIndex].sourceName !== displayName) {
          next[existingIndex].sourceName = displayName;
          changed = true;
        }
      } else if (familyName && !this.hasCustomFont(next, familyName, filePath)) {
        const oldPath = `${dir}/${name}`;
        const oldIndex = this.findCustomFontIndexByFilePath(next, oldPath);
        if (oldIndex >= 0) {
          next[oldIndex].familyName = familyName;
          next[oldIndex].filePath = filePath;
          next[oldIndex].sourceName = ReaderFontHelper.resolveDisplayName(next[oldIndex].sourceName, filePath);
          if (this.readerFontFilePath === oldPath) {
            this.readerFontFilePath = filePath;
            this.readerFontFamily = familyName;
          }
          changed = true;
          continue;
        }
        const item = new ReaderCustomFontItem();
        item.familyName = familyName;
        item.filePath = filePath;
        item.sourceName = ReaderFontHelper.resolveDisplayName(name, filePath);
        next.push(item);
        changed = true;
      }
    }
    if (changed) {
      this.saveCustomFonts(next);
    }
  }

  async pickCustomFont(): Promise<void> {
    try {
      const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      options.fileSuffixFilters = ['字体文件|.ttf', '字体文件|.otf', '字体文件|.ttc'];
      options.maxSelectNumber = 1;
      const result = await new picker.DocumentViewPicker(getContext(this)).select(options);
      if (!result || result.length === 0) {
        return;
      }
      const sourceUri = result[0];
      const context = getContext(this);
      const dir = `${context.filesDir}/reader_fonts`;
      await this.ensureDir(dir);
      const sourceName = await this.resolvePickedFontName(sourceUri);
      const destName = await this.uniqueFontFileName(dir, this.asciiStoredFontName(sourceName, Date.now()));
      const destPath = `${dir}/${destName}`;
      const copySource = sourceUri.startsWith('/') ? fileUri.getUriFromPath(sourceUri) : sourceUri;
      await fs.copy(copySource, fileUri.getUriFromPath(destPath));
      const familyName = this.familyNameForPath(destPath);

      const item = new ReaderCustomFontItem();
      item.familyName = familyName;
      item.filePath = destPath;
      item.sourceName = ReaderFontHelper.resolveDisplayName(sourceName, destPath);
      const next = this.customFonts.slice();
      next.push(item);
      this.saveCustomFonts(next);
      CloudAutoSync.schedule(getContext(this));
      if (this.registerCustomFont(item)) {
        HdsFeedback.showToast('已上传字体，可返回阅读设置选择');
      } else {
        HdsFeedback.showToast('字体已保存，但注册失败');
      }
    } catch (e) {
      console.error('上传字体失败:', e);
      HdsFeedback.showToast('上传字体失败');
    }
  }

  deleteCustomFont(item: ReaderCustomFontItem): void {
    const next = this.customFonts.filter((fontItem: ReaderCustomFontItem) =>
      fontItem.familyName !== item.familyName && fontItem.filePath !== item.filePath);
    this.saveCustomFonts(next);
    if (this.readerFontFilePath === item.filePath || this.readerFontFamily === item.familyName) {
      this.refreshSystemFontFamily();
      this.readerFontMode = ReaderSettingsStore.FONT_MODE_DEVICE;
      this.readerFontFamily = '';
      this.readerFontFilePath = '';
      this.readerFontSourceName = '系统默认';
      this.readerActiveFontFamily = '';
      this.readerFontRegistered = false;
      this.applyApplicationFont();
    }
    this.saveFontSettings();
    // The cloud copy is matched by the file's fingerprint, so record it before the file is gone.
    CloudAutoSync.onFontDeleted(getContext(this), item.filePath).catch((error: Error) => {
      console.warn('记录云端字体删除失败:', error.message);
    }).finally(() => {
      try {
        fs.unlinkSync(item.filePath);
      } catch (e) {
        console.warn('删除字体文件失败:', e);
      }
    });
    HdsFeedback.showToast('已删除字体');
  }

  registerCustomFonts(): void {
    for (const item of this.customFonts) {
      this.registerCustomFont(item);
    }
  }

  registerCustomFont(item: ReaderCustomFontItem): string {
    if (!item.filePath) {
      return '';
    }
    const fontItem = new ReaderFontItem();
    fontItem.familyName = item.familyName;
    fontItem.filePath = item.filePath;
    fontItem.sourceName = item.sourceName;
    const oldPath = item.filePath;
    const oldFamilyName = item.familyName;
    const result = ReaderFontHelper.registerFont(this.getUIContext(), fontItem);
    if (result.registered) {
      item.filePath = result.filePath;
      item.familyName = this.familyNameForPath(result.filePath);
      if (this.readerFontFilePath === item.filePath || this.readerFontFilePath === oldPath ||
        this.readerFontFamily === item.familyName || this.readerFontFamily === oldFamilyName) {
        this.readerFontFilePath = item.filePath;
        this.readerFontFamily = item.familyName;
        this.readerActiveFontFamily = result.familyName;
        this.readerFontRegistered = true;
      }
      return result.familyName;
    }
    return '';
  }

  applyApplicationFont(): void {
    ReaderFontBootstrap.applyApplicationFont(getContext(this), 'custom-font-manager');
  }

  async ensureDir(path: string): Promise<void> {
    try {
      await fs.mkdir(path, true);
    } catch (e) {
    }
  }

  fontExt(uri: string): string {
    const lower = uri.toLowerCase();
    if (lower.includes('.otf')) return '.otf';
    if (lower.includes('.ttc')) return '.ttc';
    return '.ttf';
  }

  isFontFile(name: string): boolean {
    const lower = (name || '').toLowerCase();
    return lower.endsWith('.ttf') || lower.endsWith('.otf') || lower.endsWith('.ttc');
  }

  fontFileExists(path: string): boolean {
    try {
      return fs.accessSync(path);
    } catch (e) {
      return false;
    }
  }

  familyNameFromFontFileName(name: string): string {
    const index = name.lastIndexOf('.');
    return index > 0 ? name.substring(0, index) : name;
  }

  familyNameForPath(filePath: string): string {
    return ReaderFontHelper.normalizeFontFamily(filePath);
  }

  normalizedFontFamily(filePath: string): string {
    return ReaderFontHelper.normalizeFontFamily(filePath);
  }

  previewFontFamily(item: ReaderCustomFontItem): string {
    if (item && item.filePath === this.readerFontFilePath && this.readerActiveFontFamily) {
      return this.readerActiveFontFamily;
    }
    return '';
  }

  syncSelectedCustomFont(): void {
    if (!this.readerFontFilePath) {
      return;
    }
    const index = this.findCustomFontIndexByFilePath(this.customFonts, this.readerFontFilePath);
    if (index < 0) {
      return;
    }
    const item = this.customFonts[index];
    this.readerFontFamily = item.familyName;
    this.readerFontSourceName = ReaderFontHelper.resolveDisplayName(item.sourceName, item.filePath);
    this.readerFontMode = 'custom';
    this.saveFontSettings();
  }

  saveFontSettings(): void {
    ReaderSettingsStore.saveFontSettings(
      getContext(this),
      this.readerFontFamily,
      this.readerFontFilePath,
      this.readerFontSourceName,
      this.readerFontMode,
      this.readerSystemFontFamily,
      this.readerCustomFontsRaw
    ).catch((e: Error) => {
      console.warn('保存阅读字体设置失败:', e);
    });
  }

  async uniqueFontFileName(dir: string, sourceName: string): Promise<string> {
    const safeName = this.sanitizeFontFileName(sourceName || `custom${this.fontExt(sourceName)}`);
    const dotIndex = safeName.lastIndexOf('.');
    const base = dotIndex > 0 ? safeName.substring(0, dotIndex) : safeName;
    const ext = dotIndex > 0 ? safeName.substring(dotIndex) : this.fontExt(safeName);
    let candidate = `${base}${ext}`;
    let index = 1;
    while (this.fontFileExists(`${dir}/${candidate}`)) {
      candidate = `${base}_${index}${ext}`;
      index++;
    }
    return candidate;
  }

  ensureAsciiStoredFontName(dir: string, name: string): string {
    if (this.isAsciiSafeFileName(name)) {
      return name;
    }
    const targetName = this.uniqueAsciiStoredFontName(dir, name);
    try {
      fs.renameSync(`${dir}/${name}`, `${dir}/${targetName}`);
      return targetName;
    } catch (e) {
      console.warn('迁移字体文件名失败:', e);
      return name;
    }
  }

  uniqueAsciiStoredFontName(dir: string, sourceName: string): string {
    const ext = this.fontExt(sourceName);
    const base = this.asciiStoredFontName(sourceName, 0).replace(ext, '');
    let candidate = `${base}${ext}`;
    let index = 1;
    while (this.fontFileExists(`${dir}/${candidate}`)) {
      candidate = `${base}_${index}${ext}`;
      index++;
    }
    return candidate;
  }

  asciiStoredFontName(sourceName: string, salt: number): string {
    const ext = this.fontExt(sourceName);
    let hash = salt & 0x7fffffff;
    for (let i = 0; i < sourceName.length; i++) {
      hash = ((hash * 31) + sourceName.charCodeAt(i)) & 0x7fffffff;
    }
    return `reader_font_${hash}${ext}`;
  }

  isAsciiSafeFileName(name: string): boolean {
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

  sanitizeFontFileName(name: string): string {
    const source = this.fileNameFromUri(name || 'custom.ttf');
    const ext = this.fontExt(source);
    const rawBase = this.familyNameFromFontFileName(source).trim() || 'custom';
    const invalidChars = ['/', '\\', ':', '*', '?', '"', '<', '>', '|'];
    let base = '';
    for (let i = 0; i < rawBase.length; i++) {
      const ch = rawBase.charAt(i);
      base += invalidChars.includes(ch) ? '_' : ch;
    }
    base = base.trim() || 'custom';
    return `${base}${ext}`;
  }

  fileNameFromUri(uri: string): string {
    const withoutQuery = String(uri || '').split('?')[0].split('#')[0];
    const decoded = decodeURIComponent(withoutQuery);
    const index = Math.max(decoded.lastIndexOf('/'), decoded.lastIndexOf('\\'));
    return index >= 0 ? decoded.substring(index + 1) : decoded || '自定义字体';
  }

  async resolvePickedFontName(uri: string): Promise<string> {
    const queryName = this.uriQueryFileName(uri);
    if (queryName && !ReaderFontHelper.isInternalFontName(queryName)) {
      return queryName;
    }
    const pathName = this.fileNameFromUri(uri);
    if (this.isFontFile(pathName) && !ReaderFontHelper.isInternalFontName(pathName)) {
      return pathName;
    }
    let file: fs.File | null = null;
    try {
      file = await fs.open(uri, fs.OpenMode.READ_ONLY);
      const name = String(file.name || '').trim();
      if (name && this.isFontFile(name) && !ReaderFontHelper.isInternalFontName(name)) return name;
    } catch (_) {
    } finally {
      if (file) {
        try { await fs.close(file); } catch (_) {}
      }
    }
    return queryName || pathName;
  }

  uriQueryFileName(uri: string): string {
    const queryIndex = String(uri || '').indexOf('?');
    if (queryIndex < 0) return '';
    const parts = String(uri).substring(queryIndex + 1).split('&');
    for (const part of parts) {
      const separator = part.indexOf('=');
      if (separator < 0) continue;
      const key = part.substring(0, separator).toLowerCase();
      if (key !== 'displayname' && key !== 'filename' && key !== 'name') continue;
      try {
        const value = decodeURIComponent(part.substring(separator + 1)).trim();
        if (value && this.isFontFile(value)) return value;
      } catch (_) {}
    }
    return '';
  }

  hasCustomFont(fonts: ReaderCustomFontItem[], familyName: string, filePath: string): boolean {
    for (const item of fonts) {
      if (item.familyName === familyName || item.filePath === filePath) {
        return true;
      }
    }
    return false;
  }

  findCustomFontIndexByFilePath(fonts: ReaderCustomFontItem[], filePath: string): number {
    for (let i = 0; i < fonts.length; i++) {
      if (fonts[i].filePath === filePath) {
        return i;
      }
    }
    return -1;
  }

  pageColor(): string {
    return ThemeRuntime.pageColor(this.appDarkMode);
  }

  cardColor(): string {
    return ThemeRuntime.cardColor(this.appDarkMode);
  }

  primaryTextColor(): string {
    return ThemeRuntime.primaryTextColor(this.appDarkMode);
  }

  subTextColor(): string {
    return ThemeRuntime.subTextColor(this.appDarkMode);
  }

  inputColor(): string {
    return ThemeRuntime.inputColor(this.appDarkMode);
  }

  buttonColor(): string {
    return ThemeRuntime.buttonColor(this.appDarkMode);
  }

  syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, this.pageColor());
  }

  @Builder
  sectionTitle(title: string) {
    Text(title)
      .fontSize(AppFontSize.BODY)
      .fontColor(this.subTextColor())
      .width('100%')
      .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.XXL, bottom: AppSpacing.MD })
  }

  @Builder
  uploadPanel() {
    Row() {
      Column() {
        Text('上传字体')
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.primaryTextColor())
        Text('支持 ttf / otf / ttc，上传后会出现在阅读设置的字体下拉框中')
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
          .margin({ top: AppSpacing.XS })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Text('+')
        .fontSize(AppFontSize.HEADLINE)
        .fontColor(ThemeRuntime.onAccentColor())
        .textAlign(TextAlign.Center)
        .width(40)
        .height(40)
        .borderRadius(20)
        .backgroundColor(this.buttonColor())
    }
    .width('100%')
    .constraintSize({ minHeight: 72 })
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG, bottom: AppSpacing.LG })
    .backgroundColor(this.cardColor())
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.pickCustomFont();
    })
  }

  @Builder
  emptyPanel() {
    Column() {
      Text('还没有上传字体')
        .fontSize(AppFontSize.BODY_LARGE)
        .fontColor(this.subTextColor())
      Text('点击上方上传按钮添加字体文件')
        .fontSize(AppFontSize.BODY)
        .fontColor(this.subTextColor())
        .margin({ top: AppSpacing.SM })
    }
    .width('100%')
    .padding({ top: 28, bottom: 28 })
    .backgroundColor(this.cardColor())
  }

  @Builder
  cloudFontsPanel() {
    Row() {
      Text('云端待下载')
        .fontSize(AppFontSize.BODY)
        .fontColor(this.subTextColor())
        .layoutWeight(1)
      Text(this.refreshingCloudFonts ? '刷新中' : '刷新')
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.buttonColor())
        .padding({ left: AppSpacing.MD, top: AppSpacing.SM, bottom: AppSpacing.SM })
        .enabled(!this.refreshingCloudFonts && !this.downloadingCloudFontId)
        .accessibilityText('刷新云端待下载字体')
        .accessibilityRole(AccessibilityRoleType.BUTTON)
        .onClick(() => this.refreshFontLists())
    }
    .width('100%')
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.XL, bottom: AppSpacing.SM })

    if (this.cloudFontError) {
      Text(this.cloudFontError)
        .fontSize(AppFontSize.CAPTION)
        .fontColor(ThemeRuntime.dangerColor(this.appDarkMode))
        .width('100%')
        .padding({ left: AppSpacing.XL, right: AppSpacing.XL, bottom: AppSpacing.MD })
    }
    if (this.remoteFonts().length > 0) {
      Column({ space: 1 }) {
        ForEach(this.remoteFonts(), (font: CloudRemoteFont) => {
          this.cloudFontItem(font)
        }, (font: CloudRemoteFont): string => font.id)
      }
      .width('100%')
      .backgroundColor(this.cardColor())
    } else {
      Column({ space: AppSpacing.SM }) {
        Text(this.refreshingCloudFonts ? '正在获取云端字体' :
          (this.cloudFontError ? '暂时无法获取云端字体' : '暂无待下载的云端字体'))
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.subTextColor())
        Text('已同步至云端但尚未下载到本机的字体会显示在这里')
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: 28, bottom: 28 })
      .backgroundColor(this.cardColor())
    }
  }

  @Builder
  cloudFontItem(font: CloudRemoteFont) {
    Row({ space: AppSpacing.MD }) {
      Column({ space: AppSpacing.XS }) {
        Text(font.name)
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.primaryTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.downloadingCloudFontId === font.id ? this.cloudFontDownloadStatus :
          `${this.cloudFontSize(font.bytes)} · 点击下载并导入`)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      SymbolGlyph($r('sys.symbol.download'))
        .fontSize(20)
        .fontColor([this.downloadingCloudFontId ? this.subTextColor() : this.buttonColor()])
    }
    .width('100%')
    .constraintSize({ minHeight: 68 })
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.MD, bottom: AppSpacing.MD })
    .backgroundColor(this.cardColor())
    .alignItems(VerticalAlign.Center)
    .enabled(!this.downloadingCloudFontId)
    .accessibilityText(`${font.name}，${this.downloadingCloudFontId === font.id ?
      this.cloudFontDownloadStatus : '下载并导入'}`)
    .accessibilityRole(AccessibilityRoleType.BUTTON)
    .onClick(() => this.downloadCloudFont(font))
  }

  @Builder
  fontItem(item: ReaderCustomFontItem) {
    Row() {
      Column() {
        Text(item.sourceName || item.familyName)
          .fontSize(AppFontSize.BODY_LARGE)
          .fontFamily(this.previewFontFamily(item))
          .fontColor(this.primaryTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(item.filePath)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: AppSpacing.XS })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Text('删除')
        .fontSize(AppFontSize.BODY)
        .fontColor(ThemeRuntime.onAccentColor())
        .textAlign(TextAlign.Center)
        .width(54)
        .height(32)
        .borderRadius(16)
        .backgroundColor(ThemeRuntime.dangerColor(this.appDarkMode))
        .onClick(() => {
          this.deleteCustomFont(item);
        })
    }
    .width('100%')
    .constraintSize({ minHeight: 68 })
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.MD, bottom: AppSpacing.MD })
    .backgroundColor(this.cardColor())
    .alignItems(VerticalAlign.Center)
  }
}
