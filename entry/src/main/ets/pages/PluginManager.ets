import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import fs from '@ohos.file.fs';
import { HttpClient } from '@legado/sourceengine';
import {
  InstalledPluginRecord,
  PluginInstallPreview,
  PluginPanelOpenSpec,
  PluginRegistry
} from '@legado/pluginengine';
import { PageScaffold } from '../components/common/PageScaffold';
import { AdaptiveSwitch } from '../components/AdaptiveSwitch';
import { ImmersiveMaterialSurface } from '../components/ImmersiveMaterialSurface';
import { PopupMenuAction } from '../components/common/PopupMenuAction';
import { PluginSandboxWebView } from '../components/plugin/PluginSandboxWebView';
import { AppPluginHost } from '../core/plugin/AppPluginHost';
import { PluginCapabilities, PluginPermissionRow } from '../core/plugin/PluginCapabilities';
import { copyFile, selectDocuments } from '../platform/Files';
import { fileUri } from '../platform/FileUri';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { HdsFeedback } from '../utils/HdsFeedback';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';
import { syncSystemBars } from '../utils/SystemBars';

const ADD_BUTTON_SIZE: number = 52;

/**
 * 实验室 › 插件 › 插件管理：已装插件的卡片（启用开关、能力标签、工具面板与设置入口），
 * 右下角悬浮“＋”弹出“从链接安装 / 从文件导入”，导入后先弹安装确认（签名、会提供什么、需要的权限）。
 * 只在插件总开关开着时可进入；单个插件的启用不再弹须知。
 */
@Entry
@Component
struct PluginManagerPage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  @StorageProp('pluginRegistryRevision') @Watch('reloadList') pluginRegistryRevision: number = 1;

  @State plugins: InstalledPluginRecord[] = [];
  @State loaded: boolean = false;
  @State busyMessage: string = '';
  @State showUrlImport: boolean = false;
  @State showAddMenu: boolean = false;
  @State importUrlInput: string = '';

  @State showPreviewSheet: boolean = false;
  @State activePreview: PluginInstallPreview | null = null;

  @State showToolPanelSheet: boolean = false;
  @State activePanelPluginId: string = '';
  @State activePanelTitle: string = '';
  @State activePanelPath: string = '';
  @State activePanelInitJson: string = '{}';

  private unsubscribePanel: (() => void) | null = null;

  aboutToAppear(): void {
    AppPluginHost.install(getContext(this));
    this.syncBars();
    this.unsubscribePanel = AppPluginHost.subscribePanelOpen((spec: PluginPanelOpenSpec) => {
      this.openPanel(spec.pluginId, spec.title, spec.panelPath, JSON.stringify(spec.initialData ?? {}));
    });
    this.reloadList();
  }

  aboutToDisappear(): void {
    if (this.unsubscribePanel) {
      this.unsubscribePanel();
      this.unsubscribePanel = null;
    }
  }

  onPageShow(): void {
    this.syncBars();
    this.reloadList();
  }

  onBackPress(): boolean {
    if (this.showAddMenu) {
      this.showAddMenu = false;
      return true;
    }
    return false;
  }

  private syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, ThemeRuntime.pageColor(this.appDarkMode));
  }

  private reloadList(): void {
    PluginRegistry.getInstance().ensureInitialized().then(() => {
      this.plugins = PluginRegistry.getInstance().listAll();
      this.loaded = true;
    }).catch(() => {
      this.loaded = true;
    });
  }

  private enabledCount(): number {
    return this.plugins.filter((rec: InstalledPluginRecord): boolean => rec.enabled).length;
  }

  private hasTtsPlugin(): boolean {
    return this.plugins.some((rec: InstalledPluginRecord): boolean => !!rec.manifest.contributes.tts);
  }

  // ---- 导入 ----

  private async pickLocalPluginFile(): Promise<void> {
    if (this.busyMessage) return;
    try {
      const picked = await selectDocuments(getContext(this) as common.UIAbilityContext, {
        maxSelectNumber: 1,
        fileSuffixFilters: ['插件包|.qyplugin,.zip']
      });
      if (!picked || picked.length === 0) return;
      await this.prepareImportFromUri(picked[0]);
    } catch (e) {
      HdsFeedback.showToast(e instanceof Error ? e.message : '选择插件文件失败');
    }
  }

  private pathFromUri(value: string): string {
    if (value.startsWith('file://')) {
      try {
        return new fileUri.FileUri(value).path;
      } catch (_) {
        return decodeURIComponent(value.substring(7));
      }
    }
    return value;
  }

  private localPathExists(path: string): boolean {
    try {
      return !!path && fs.accessSync(path);
    } catch (_) {
      return false;
    }
  }

  private async prepareImportFromUri(externalUri: string): Promise<void> {
    const ctx = getContext(this);
    const tempZip = `${ctx.cacheDir}/plugin_import_${Date.now()}.zip`;
    this.busyMessage = '正在校验插件包…';
    try {
      if (!fs.accessSync(ctx.cacheDir)) {
        fs.mkdirSync(ctx.cacheDir, true);
      }
      const sourcePath = this.pathFromUri(externalUri);
      let copiedLocal = false;
      if (this.localPathExists(sourcePath)) {
        try {
          fs.copyFileSync(sourcePath, tempZip);
          copiedLocal = true;
        } catch (_) {
          copiedLocal = false;
        }
      }
      if (!copiedLocal) {
        const srcUri = externalUri.startsWith('/') ? fileUri.getUriFromPath(externalUri) : externalUri;
        await copyFile(srcUri, fileUri.getUriFromPath(tempZip));
      }
      await this.showPreview(tempZip);
    } catch (e) {
      HdsFeedback.showToast(e instanceof Error ? e.message : '插件包校验失败');
    } finally {
      this.busyMessage = '';
      this.removeQuietly(tempZip);
    }
  }

  private async downloadAndPrepareFromUrl(): Promise<void> {
    const targetUrl = this.importUrlInput.trim();
    if (!/^https?:\/\//i.test(targetUrl)) {
      HdsFeedback.showToast('请输入以 http:// 或 https:// 开头的插件地址');
      return;
    }
    this.showUrlImport = false;
    const ctx = getContext(this);
    const tempZip = `${ctx.cacheDir}/plugin_dl_${Date.now()}.zip`;
    this.busyMessage = '正在下载并校验插件包…';
    try {
      if (!fs.accessSync(ctx.cacheDir)) {
        fs.mkdirSync(ctx.cacheDir, true);
      }
      const client = new HttpClient(25000);
      const bin = await client.executeBinary({
        url: targetUrl,
        method: 'GET',
        headers: {},
        connectTimeout: 20000,
        readTimeout: 25000
      }, 32 * 1024 * 1024);
      if (!bin.success || bin.statusCode < 200 || bin.statusCode >= 300 || bin.data.byteLength === 0) {
        throw new Error(bin.error || `下载失败（HTTP ${bin.statusCode}）`);
      }
      const fd = fs.openSync(tempZip, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
      try {
        const ab = bin.data.buffer.slice(bin.data.byteOffset, bin.data.byteOffset + bin.data.byteLength);
        fs.writeSync(fd.fd, ab);
      } finally {
        fs.closeSync(fd);
      }
      await this.showPreview(tempZip);
    } catch (e) {
      HdsFeedback.showToast(e instanceof Error ? e.message : '从链接安装插件失败');
    } finally {
      this.busyMessage = '';
      this.removeQuietly(tempZip);
    }
  }

  private async showPreview(zipPath: string): Promise<void> {
    const preview = await PluginRegistry.getInstance().prepareInstall(zipPath);
    this.activePreview = preview;
    this.showPreviewSheet = true;
  }

  private removeQuietly(path: string): void {
    try {
      if (fs.accessSync(path)) fs.unlinkSync(path);
    } catch (_) {
    }
  }

  private async confirmInstallPreview(): Promise<void> {
    const preview = this.activePreview;
    if (!preview) return;
    this.activePreview = null;
    this.showPreviewSheet = false;
    this.busyMessage = preview.isUpgrade ? '正在更新插件…' : '正在安装插件…';
    try {
      const rec = await PluginRegistry.getInstance().commitInstall(preview);
      this.reloadList();
      HdsFeedback.showToast(preview.isUpgrade
        ? `已更新 ${rec.manifest.name} 到 v${rec.manifest.version}`
        : `已安装 ${rec.manifest.name}`);
    } catch (e) {
      HdsFeedback.showToast(e instanceof Error ? e.message : '安装插件失败');
    } finally {
      this.busyMessage = '';
    }
  }

  private cancelInstallPreview(): void {
    const preview = this.activePreview;
    this.activePreview = null;
    this.showPreviewSheet = false;
    if (preview) {
      PluginRegistry.getInstance().discardInstall(preview).catch(() => {});
    }
  }

  // ---- 卡片动作 ----

  private openPanel(pluginId: string, title: string, panelPath: string, initJson: string): void {
    this.activePanelPluginId = pluginId;
    this.activePanelTitle = title;
    this.activePanelPath = panelPath;
    this.activePanelInitJson = initJson;
    this.showToolPanelSheet = true;
  }

  private openFirstTool(rec: InstalledPluginRecord): void {
    const tools = rec.manifest.contributes.tools || [];
    if (tools.length === 0) return;
    if (!rec.enabled) {
      HdsFeedback.showToast('先启用这个插件');
      return;
    }
    const t = tools[0];
    this.openPanel(rec.manifest.id, t.title, t.panel, JSON.stringify({ toolId: t.id }));
  }

  private openDetail(pluginId: string): void {
    router.pushUrl({ url: 'pages/PluginDetail', params: { pluginId: pluginId } }).catch(() => {});
  }

  private setEnabled(rec: InstalledPluginRecord, isOn: boolean): void {
    if (rec.enabled === isOn) return;
    PluginRegistry.getInstance().setPluginEnabled(rec.manifest.id, isOn).then(() => {
      this.reloadList();
    }).catch((e: Object) => {
      HdsFeedback.showToast(e instanceof Error ? e.message : '切换状态失败');
      this.reloadList();
    });
  }

  // ---- 界面 ----

  /** 插件自带图标优先；没有就画一个带拼图符号的主题色块。 */
  @Builder
  pluginIcon(path: string, size: number) {
    if (path && this.localPathExists(path)) {
      Image(fileUri.getUriFromPath(path))
        .width(size)
        .height(size)
        .objectFit(ImageFit.Cover)
        .borderRadius(size * 0.28)
    } else {
      Stack() {
        SymbolGlyph($r('sys.symbol.puzzle'))
          .fontSize(size * 0.5)
          .fontColor([Color.White])
      }
      .width(size)
      .height(size)
      .borderRadius(size * 0.28)
      .linearGradient({
        angle: 150,
        colors: [[ThemeRuntime.accentColor(this.appDarkMode), 0], [ThemeRuntime.buttonColor(this.appDarkMode), 1]]
      })
    }
  }

  @Builder
  chip(text: string, warn: boolean) {
    Row({ space: 4 }) {
      if (warn) {
        SymbolGlyph($r('sys.symbol.exclamationmark_shield_fill'))
          .fontSize(13)
          .fontColor([ThemeRuntime.warningColor(this.appDarkMode)])
      }
      Text(text)
        .fontSize(12)
        .fontColor(warn ? ThemeRuntime.warningColor(this.appDarkMode) : ThemeRuntime.primaryTextColor(this.appDarkMode))
        .maxLines(1)
    }
    .padding({ left: 10, right: 10, top: 5, bottom: 5 })
    .margin({ right: 6, bottom: 6 })
    .borderRadius(14)
    .backgroundColor(warn ? `#22${ThemeRuntime.warningColor(this.appDarkMode).substring(1)}` :
      ThemeRuntime.inputColor(this.appDarkMode))
  }

  @Builder
  cardAction(symbol: Resource, label: string, onTap: () => void) {
    Row({ space: 6 }) {
      SymbolGlyph(symbol)
        .fontSize(16)
        .fontColor([ThemeRuntime.accentColor(this.appDarkMode)])
      Text(label)
        .fontSize(AppFontSize.BODY)
        .fontColor(ThemeRuntime.accentColor(this.appDarkMode))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1)
    .height(46)
    .justifyContent(FlexAlign.Center)
    .accessibilityGroup(true)
    .accessibilityText(label)
    .onClick(() => onTap())
  }

  @Builder
  pluginCard(rec: InstalledPluginRecord) {
    Column() {
      Row({ space: AppSpacing.MD }) {
        this.pluginIcon(PluginCapabilities.iconPath(rec.installDir, rec.manifest), 48)
        Column({ space: 2 }) {
          Text(rec.manifest.name)
            .fontSize(AppFontSize.BODY_LARGE)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(`${rec.manifest.author || rec.manifest.id} · v${rec.manifest.version} · ${PluginCapabilities.runtimeLabel(rec.manifest.runtime)}`)
            .fontSize(AppFontSize.CAPTION)
            .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .onClick(() => this.openDetail(rec.manifest.id))

        AdaptiveSwitch({
          isOn: rec.enabled,
          onChange: (isOn: boolean) => this.setEnabled(rec, isOn)
        })
      }
      .width('100%')
      .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.LG })

      if (rec.manifest.description) {
        Text(rec.manifest.description)
          .fontSize(AppFontSize.BODY)
          .lineHeight(20)
          .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.SM })
          .onClick(() => this.openDetail(rec.manifest.id))
      }

      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(PluginCapabilities.supported(rec.manifest), (label: string) => {
          this.chip(label, false)
        }, (label: string) => label)
        if (PluginCapabilities.unsupported(rec.manifest).length > 0) {
          this.chip(`另有 ${PluginCapabilities.unsupported(rec.manifest).length} 项本应用不支持`, false)
        }
        if (!rec.signer) {
          this.chip('未签名', true)
        }
      }
      .width('100%')
      .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.MD, bottom: AppSpacing.SM })

      Divider()
        .strokeWidth(0.5)
        .color(ThemeRuntime.hairlineColor(this.appDarkMode))
      Row() {
        if ((rec.manifest.contributes.tools || []).length > 0) {
          this.cardAction($r('sys.symbol.square_grid_2x2'), (rec.manifest.contributes.tools || [])[0].title,
            () => this.openFirstTool(rec))
          Divider()
            .vertical(true)
            .height(20)
            .strokeWidth(0.5)
            .color(ThemeRuntime.hairlineColor(this.appDarkMode))
        }
        this.cardAction($r('sys.symbol.gearshape'), '设置', () => this.openDetail(rec.manifest.id))
      }
      .width('100%')
    }
    .width('100%')
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(ThemeRuntime.cardColor(this.appDarkMode))
    .opacity(rec.enabled ? 1 : 0.72)
  }

  @Builder
  urlImportCard() {
    Column({ space: AppSpacing.SM }) {
      Text('从链接安装')
        .fontSize(AppFontSize.BODY_LARGE)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
      TextInput({ placeholder: 'https://…/插件.qyplugin', text: this.importUrlInput })
        .height(42)
        .type(InputType.URL)
        .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
        .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
        .onChange((v: string) => {
          this.importUrlInput = v;
        })
        .onSubmit(() => {
          this.downloadAndPrepareFromUrl();
        })
      Row({ space: AppSpacing.SM }) {
        Button('取消')
          .height(38)
          .layoutWeight(1)
          .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
          .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
          .onClick(() => {
            this.showUrlImport = false;
          })
        Button('下载并校验')
          .height(38)
          .layoutWeight(1)
          .fontColor(ThemeRuntime.onAccentColor(ThemeRuntime.buttonColor(this.appDarkMode)))
          .backgroundColor(ThemeRuntime.buttonColor(this.appDarkMode))
          .onClick(() => {
            this.downloadAndPrepareFromUrl();
          })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(AppSpacing.LG)
    .borderRadius(ThemeRuntime.cardRadius())
    .backgroundColor(ThemeRuntime.cardColor(this.appDarkMode))
  }

  @Builder
  pageContent() {
    Column({ space: AppSpacing.MD }) {
      if (this.showUrlImport) {
        this.urlImportCard()
      }

      if (this.busyMessage) {
        Row({ space: AppSpacing.SM }) {
          LoadingProgress().width(20).height(20).color(ThemeRuntime.accentColor(this.appDarkMode))
          Text(this.busyMessage)
            .fontSize(AppFontSize.BODY)
            .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
        }
        .width('100%')
        .padding(AppSpacing.MD)
        .borderRadius(ThemeRuntime.mediumRadius())
        .backgroundColor(ThemeRuntime.cardColor(this.appDarkMode))
      }

      if (this.plugins.length === 0) {
        if (this.loaded) {
          Column({ space: AppSpacing.SM }) {
            Text('还没有安装插件')
              .fontSize(AppFontSize.BODY_LARGE)
              .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
            Text('点右下角的“＋”，从文件或链接添加 .qyplugin 插件包。只安装你信任的来源。')
              .fontSize(AppFontSize.CAPTION)
              .lineHeight(18)
              .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
              .textAlign(TextAlign.Center)
          }
          .width('100%')
          .padding(AppSpacing.XXL)
          .borderRadius(ThemeRuntime.cardRadius())
          .backgroundColor(ThemeRuntime.cardColor(this.appDarkMode))
        }
      } else {
        Row() {
          Text('已安装')
            .fontSize(AppFontSize.CAPTION)
            .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
            .layoutWeight(1)
          Text(`${this.plugins.length} 个 · ${this.enabledCount()} 个启用`)
            .fontSize(AppFontSize.CAPTION)
            .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
        }
        .width('100%')
        .padding({ left: AppSpacing.SM, right: AppSpacing.SM })

        ForEach(this.plugins, (rec: InstalledPluginRecord) => {
          this.pluginCard(rec)
        }, (rec: InstalledPluginRecord) => `${rec.manifest.id}:${rec.updatedAt}:${rec.enabled}`)

        if (this.hasTtsPlugin()) {
          Row({ space: AppSpacing.SM }) {
            SymbolGlyph($r('sys.symbol.info_circle'))
              .fontSize(16)
              .fontColor([ThemeRuntime.accentColor(this.appDarkMode)])
            Text('插件启用后，它的音色会并入“朗读 › 音色管理”的自定义音色，名字后带插件名；停用就不再显示。')
              .fontSize(AppFontSize.CAPTION)
              .lineHeight(18)
              .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
              .layoutWeight(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
          .padding(AppSpacing.MD)
          .borderRadius(ThemeRuntime.mediumRadius())
          .backgroundColor(`#1A${ThemeRuntime.accentColor(this.appDarkMode).substring(1)}`)
        }
      }
    }
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.MD })
  }

  /** 右下角悬浮“＋”，样式与书源页的新增按钮一致，点开向上弹出安装方式。 */
  @Builder
  addPluginFloatingButton() {
    Stack() {
      ImmersiveMaterialSurface({
        surfaceWidth: ADD_BUTTON_SIZE,
        surfaceHeight: ADD_BUTTON_SIZE,
        darkMode: this.appDarkMode,
        fallbackColor: ThemeRuntime.cardColor(this.appDarkMode),
        glowColor: `#40${ThemeRuntime.accentColor(this.appDarkMode).substring(1)}`
      }) {
        SymbolGlyph($r('sys.symbol.plus'))
          .fontSize(25)
          .fontColor([ThemeRuntime.accentColor(this.appDarkMode)])
      }
    }
    .width(ADD_BUTTON_SIZE)
    .height(ADD_BUTTON_SIZE)
    .margin({ right: AppSpacing.XXL, bottom: this.navBarHeight + 22 })
    .accessibilityText('安装插件')
    .accessibilityRole(AccessibilityRoleType.BUTTON)
    .onClick(() => {
      this.showAddMenu = true;
    })
    .bindPopup(this.showAddMenu, ImmersiveMaterialRuntime.popupMenuOptions(this.immersiveLightLevel, (): void => {
      this.addMenu()
    }, Placement.TopRight, this.appDarkMode, ThemeRuntime.accentColor(this.appDarkMode), () => {
      this.showAddMenu = false;
    }))
  }

  @Builder
  addMenu() {
    Column() {
      PopupMenuAction($r('sys.symbol.arrow_right_up_and_square'), '从链接安装',
        ThemeRuntime.primaryTextColor(this.appDarkMode), () => {
          this.showAddMenu = false;
          this.importUrlInput = '';
          this.showUrlImport = true;
        })
      PopupMenuAction($r('sys.symbol.download'), '从文件导入', ThemeRuntime.primaryTextColor(this.appDarkMode), () => {
        this.showAddMenu = false;
        this.pickLocalPluginFile();
      })
    }
    .width(180)
    .padding(ImmersiveMaterialRuntime.POPUP_MENU_PADDING)
  }

  @Builder
  sheetRow(row: PluginPermissionRow) {
    Row({ space: AppSpacing.MD }) {
      Stack() {
        if (row.kind === 'tts') {
          SymbolGlyph($r('sys.symbol.speaker_wave_2')).fontSize(16).fontColor([ThemeRuntime.accentColor(this.appDarkMode)])
        } else if (row.kind === 'tool') {
          SymbolGlyph($r('sys.symbol.square_grid_2x2')).fontSize(16).fontColor([ThemeRuntime.accentColor(this.appDarkMode)])
        } else if (row.kind === 'network') {
          SymbolGlyph($r('sys.symbol.wifi')).fontSize(16).fontColor([ThemeRuntime.accentColor(this.appDarkMode)])
        } else if (row.kind === 'storage') {
          SymbolGlyph($r('sys.symbol.key')).fontSize(16).fontColor([ThemeRuntime.accentColor(this.appDarkMode)])
        } else if (row.kind === 'web') {
          SymbolGlyph($r('sys.symbol.lock_shield')).fontSize(16).fontColor([ThemeRuntime.accentColor(this.appDarkMode)])
        } else {
          SymbolGlyph($r('sys.symbol.checkmark_shield')).fontSize(16).fontColor([ThemeRuntime.accentColor(this.appDarkMode)])
        }
      }
      .width(30)
      .height(30)
      .borderRadius(9)
      .backgroundColor(`#1A${ThemeRuntime.accentColor(this.appDarkMode).substring(1)}`)

      Column({ space: 2 }) {
        Text(row.title)
          .fontSize(AppFontSize.BODY)
          .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
        if (row.detail) {
          Text(row.detail)
            .fontSize(row.kind === 'network' ? 11 : AppFontSize.CAPTION)
            .lineHeight(row.kind === 'network' ? 17 : 18)
            .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
            .wordBreak(WordBreak.BREAK_ALL)
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ left: AppSpacing.MD, right: AppSpacing.MD, top: 10, bottom: 10 })
  }

  @Builder
  sheetGroup(rows: PluginPermissionRow[]) {
    Column() {
      ForEach(rows, (row: PluginPermissionRow, index: number) => {
        if (index > 0) {
          Divider().strokeWidth(0.5).color(ThemeRuntime.hairlineColor(this.appDarkMode))
        }
        this.sheetRow(row)
      }, (row: PluginPermissionRow) => `${row.kind}:${row.title}`)
    }
    .width('100%')
    .borderRadius(ThemeRuntime.mediumRadius())
    .clip(true)
    .backgroundColor(ThemeRuntime.cardColor(this.appDarkMode))
  }

  @Builder
  sheetLabel(text: string) {
    Text(text)
      .fontSize(AppFontSize.CAPTION)
      .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
      .width('100%')
      .margin({ top: AppSpacing.MD })
  }

  private sizeText(bytes: number): string {
    if (bytes < 1024 * 1024) return `${Math.max(1, Math.round(bytes / 1024))} KB`;
    return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
  }

  @Builder
  previewSheetContent() {
    Column({ space: AppSpacing.SM }) {
      if (this.activePreview) {
        Row({ space: AppSpacing.MD }) {
          this.pluginIcon(PluginCapabilities.iconPath(this.activePreview.packageRootDir, this.activePreview.manifest), 56)
          Column({ space: 1 }) {
            Text(this.activePreview.isUpgrade ? '更新插件' : '安装插件')
              .fontSize(AppFontSize.CAPTION)
              .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
            Text(this.activePreview.manifest.name)
              .fontSize(AppFontSize.TITLE)
              .fontWeight(FontWeight.Medium)
              .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(`${this.activePreview.manifest.author || this.activePreview.manifest.id} · ` +
              (this.activePreview.isUpgrade ?
                `v${this.activePreview.previousVersion} → v${this.activePreview.manifest.version}` :
                `v${this.activePreview.manifest.version}`) +
              ` · ${this.sizeText(this.activePreview.uncompressedBytes)}`)
              .fontSize(AppFontSize.CAPTION)
              .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')

        if (!this.activePreview.signed || this.activePreview.trustNotes.length > 0) {
          Row({ space: AppSpacing.SM }) {
            SymbolGlyph($r('sys.symbol.exclamationmark_shield_fill'))
              .fontSize(17)
              .fontColor([ThemeRuntime.warningColor(this.appDarkMode)])
            Text(!this.activePreview.signed ?
              '未签名：无法确认作者身份。以后更新这个插件时，也无法核对新版是不是同一作者发布的。' :
              this.activePreview.trustNotes.join('\n'))
              .fontSize(AppFontSize.CAPTION)
              .lineHeight(18)
              .fontColor(ThemeRuntime.warningColor(this.appDarkMode))
              .layoutWeight(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
          .padding(AppSpacing.MD)
          .margin({ top: AppSpacing.SM })
          .borderRadius(ThemeRuntime.mediumRadius())
          .backgroundColor(`#22${ThemeRuntime.warningColor(this.appDarkMode).substring(1)}`)
        }

        if (this.activePreview.addedPermissions.length > 0 || this.activePreview.addedDomains.length > 0) {
          Text('这次更新新增：' + this.activePreview.addedPermissions.concat(this.activePreview.addedDomains).join('、'))
            .fontSize(AppFontSize.CAPTION)
            .fontColor(ThemeRuntime.dangerColor(this.appDarkMode))
            .width('100%')
            .margin({ top: AppSpacing.SM })
        }

        if (PluginCapabilities.provides(this.activePreview.manifest).length > 0) {
          this.sheetLabel('会提供')
          this.sheetGroup(PluginCapabilities.provides(this.activePreview.manifest))
        }
        if (PluginCapabilities.unsupported(this.activePreview.manifest).length > 0) {
          Text(`这个插件还包含本应用暂不支持的能力：${PluginCapabilities.unsupported(this.activePreview.manifest).join('、')}，装上后这部分不会生效。`)
            .fontSize(AppFontSize.CAPTION)
            .lineHeight(18)
            .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
            .width('100%')
            .margin({ top: AppSpacing.SM })
        }
        if (PluginCapabilities.permissions(this.activePreview.manifest).length > 0) {
          this.sheetLabel('需要的权限')
          this.sheetGroup(PluginCapabilities.permissions(this.activePreview.manifest))
        }

        Row({ space: AppSpacing.MD }) {
          Button('取消')
            .layoutWeight(1)
            .height(46)
            .fontColor(ThemeRuntime.accentColor(this.appDarkMode))
            .backgroundColor(`#1A${ThemeRuntime.accentColor(this.appDarkMode).substring(1)}`)
            .onClick(() => {
              this.cancelInstallPreview();
            })
          Button(this.activePreview.isUpgrade ? '更新' : '安装')
            .layoutWeight(1)
            .height(46)
            .fontColor(ThemeRuntime.onAccentColor(ThemeRuntime.buttonColor(this.appDarkMode)))
            .backgroundColor(ThemeRuntime.buttonColor(this.appDarkMode))
            .onClick(() => {
              this.confirmInstallPreview();
            })
        }
        .width('100%')
        .margin({ top: AppSpacing.LG })
      }
    }
    .width('100%')
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.MD, bottom: AppSpacing.XL })
  }

  @Builder
  toolPanelSheetContent() {
    Column() {
      Row() {
        Text(this.activePanelTitle || '插件面板')
          .fontSize(AppFontSize.BODY_LARGE)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
          .layoutWeight(1)
        Button('关闭')
          .height(30)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.showToolPanelSheet = false;
          })
      }
      .width('100%')
      .padding({ left: AppSpacing.LG, right: AppSpacing.MD, top: AppSpacing.SM, bottom: AppSpacing.SM })

      PluginSandboxWebView({
        pluginId: this.activePanelPluginId,
        panelPath: this.activePanelPath,
        initialDataJson: this.activePanelInitJson,
        darkMode: this.appDarkMode,
        onCloseRequest: () => {
          this.showToolPanelSheet = false;
        }
      })
        .layoutWeight(1)
        .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeRuntime.pageColor(this.appDarkMode))
  }

  build() {
    Stack() {
      PageScaffold({
        title: '插件管理',
        // 给右下角悬浮“＋”让出位置，最后一张卡片的按钮不被挡住。
        bottomInset: ADD_BUTTON_SIZE + 44,
        content: () => {
          this.pageContent();
        }
      })

      if (!this.busyMessage) {
        Stack({ alignContent: Alignment.BottomEnd }) {
          this.addPluginFloatingButton()
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.Transparent)
      }

      // 一个组件只认最后一个 bindSheet：安装确认与工具面板各挂一个节点，免得后者把前者顶掉。
      Column()
        .width(1)
        .height(1)
        .position({ x: 0, y: 0 })
        .hitTestBehavior(HitTestMode.None)
        .bindSheet($$this.showPreviewSheet, this.previewSheetContent(), {
          height: SheetSize.FIT_CONTENT,
          backgroundColor: ThemeRuntime.pageColor(this.appDarkMode),
          onDisappear: () => {
            if (this.activePreview) {
              this.cancelInstallPreview();
            }
          }
        })

      Column()
        .width(1)
        .height(1)
        .position({ x: 0, y: 0 })
        .hitTestBehavior(HitTestMode.None)
        .bindSheet($$this.showToolPanelSheet, this.toolPanelSheetContent(), {
          height: '82%',
          showClose: false,
          backgroundColor: ThemeRuntime.pageColor(this.appDarkMode)
        })
    }
    .width('100%')
    .height('100%')
  }
}
