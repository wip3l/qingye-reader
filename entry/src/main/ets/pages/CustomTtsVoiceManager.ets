import { router } from '@kit.ArkUI';
import picker from '@ohos.file.picker';
import fs from '@ohos.file.fs';
import { util } from '@kit.ArkTS';
import { HttpTTS, HttpClient } from '@legado/sourceengine';
import { syncSystemBars } from '../utils/SystemBars';
import { SystemTtsReader, TtsVoiceOption } from '../utils/SystemTtsReader';
import { TtsSettings, TtsSettingsStore } from '../utils/TtsSettingsStore';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { PageScaffold } from '../components/common/PageScaffold';
import { ImmersiveHeaderAction } from '../components/ImmersiveHeaderAction';
import { TtsVoiceCatalog } from '../utils/TtsVoiceCatalog';
import { TtsVoiceAvailability } from '../utils/TtsVoiceAvailability';
import { AccountCommerceApi } from '../account/AccountCommerceApi';
import { AccountSessionStore } from '../account/AccountSessionStore';
import { TtsVoiceInfo } from '../account/AccountCommerceModels';
import { FormDraftStore } from '../utils/FormDraftStore';
import deviceInfo from '@ohos.deviceInfo';
import { HdsListItem, HdsSwipeActionOptions } from '@kit.UIDesignKit';
import { SymbolGlyphModifier } from '@kit.ArkUI';
import { HdsFeedback } from '../utils/HdsFeedback';
import { SystemDialogSession } from '../utils/SystemDialogSession';
import { AdaptiveSwitch } from '../components/AdaptiveSwitch';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { CollapsingHeader } from '../utils/CollapsingHeader';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';
import { ImmersiveMaterialSurface } from '../components/ImmersiveMaterialSurface';
import { PopupMenuAction } from '../components/common/PopupMenuAction';

class ManagedTtsVoiceEntry {
  key: string = '';
  title: string = '';
  description: string = '';
  cloud: boolean = false;
  protectedVoice: boolean = false;
  systemVoice: TtsVoiceOption = TtsVoiceCatalog.defaultVoice();
  cloudVoice: TtsVoiceInfo = new TtsVoiceInfo();
}

class TtsBatchVoiceEntry {
  key: string = '';
  title: string = '';
  kind: string = '';
  protectedVoice: boolean = false;
}

class VoiceEditFormDraft {
  editingVoiceId: string = '';
  name: string = '';
  url: string = '';
  contentType: string = '';
  concurrentRate: string = '';
  loginUrl: string = '';
  loginUi: string = '';
  loginCheckJs: string = '';
  header: string = '';
  jsLib: string = '';
  jsEngine: string = '';
  enabledCookieJar: boolean = false;
}

const CUSTOM_TTS_IMPORT_FILE_LIMIT_BYTES: number = 2 * 1024 * 1024;

@Entry
@Component
struct CustomTtsVoiceManagerPage {
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  @State headerCollapse: number = 0;
  @StorageLink('ttsCustomVoiceId') ttsCustomVoiceId: string = '';
  @StorageLink('ttsCustomVoices') ttsCustomVoices: string = '';
  @StorageLink('ttsPerson') ttsPerson: number = 0;
  @StorageLink('ttsOnline') ttsOnline: number = 1;
  @StorageLink('ttsStyle') ttsStyle: string = '';
  @StorageLink('ttsLanguage') ttsLanguage: string = 'zh-CN';
  @StorageLink('ttsSpeed') ttsSpeed: number = 1;
  @StorageLink('ttsInstalledVoiceKeys') ttsInstalledVoiceKeys: string = '';
  @StorageLink('ttsCloudVoiceId') ttsCloudVoiceId: string = '';
  @StorageLink('ttsDisabledVoiceKeys') ttsDisabledVoiceKeys: string = '';
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageLink('appLightAccentColor') appLightAccentColor: string = '#007DFF';
  @StorageLink('appDarkAccentColor') appDarkAccentColor: string = '#4E9BFF';
  @StorageLink('appLightButtonColor') appLightButtonColor: string = '#007DFF';
  @StorageLink('appDarkButtonColor') appDarkButtonColor: string = '#3F8CFF';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;

  @State voices: HttpTTS[] = [];
  @State systemVoices: TtsVoiceOption[] = [TtsVoiceCatalog.defaultVoice()];
  @State cloudVoices: TtsVoiceInfo[] = [];
  @State loadingCatalog: boolean = false;
  @State catalogError: string = '';
  @State downloadingVoiceKey: string = '';
  @State downloadProgress: string = '';
  private catalogRevision: number = 0;
  private pageAlive: boolean = false;
  @State searchText: string = '';
  @State selectionMode: boolean = false;
  @State selectedVoiceIds: string[] = [];
  @State showAddDialog: boolean = false;
  private importUrlDialogSession: SystemDialogSession = new SystemDialogSession();
  private editVoiceDialogSession: SystemDialogSession = new SystemDialogSession();
  @State @Watch('onSystemDialogFlagChanged') showImportUrlDialog: boolean = false;
  @State @Watch('syncShowEditDialog') showEditDialog: boolean = false;
  @State importUrl: string = '';
  @State isImporting: boolean = false;
  @State isBatchOperating: boolean = false;
  @State editingVoiceId: string = '';
  @State editName: string = '';
  @State editUrl: string = '';
  @State editContentType: string = '';
  @State editConcurrentRate: string = '';
  @State editLoginUrl: string = '';
  @State editLoginUi: string = '';
  @State editLoginCheckJs: string = '';
  @State editHeader: string = '';
  @State editJsLib: string = '';
  @State editJsEngine: string = '';
  @State editEnabledCookieJar: boolean = false;
  @State showVoiceActionMenu: boolean = false;
  @State actionVoiceId: string = '';
  @State contextMenuX: number = 16;
  @State contextMenuY: number = 96;
  @State contextViewportWidth: number = 360;
  @State contextViewportHeight: number = 720;
  private voiceSelectionAreas: Map<string, number[]> = new Map<string, number[]>();
  private voiceDragVisited: Set<string> = new Set<string>();
  private voiceDragSelectValue: boolean = true;
  private voiceListScroller: Scroller = new Scroller();
  private voiceSelectionDragging: boolean = false;
  private voiceSelectionLastX: number = 0;
  private voiceSelectionLastY: number = 0;
  private voiceSelectionAutoScrollId: number = -1;
  private voiceSelectionAutoDirection: number = 0;
  private voiceSelectionViewportTop: number = 0;
  private voiceSelectionViewportBottom: number = 0;
  private voiceFirstVisibleIndex: number = 0;
  private voiceLastVisibleIndex: number = 0;
  private voiceSelectionSuppressClickUntil: number = 0;

  aboutToAppear(): void {
    this.syncBars();
    this.pageAlive = true;
    this.restorePersistentVoiceEditDraft();
  }

  onPageShow(): void {
    this.syncBars();
    this.pageAlive = true;
    this.loadSettings();
    this.loadVoiceCatalog();
  }

  onPageHide(): void {
    this.pageAlive = false;
    this.catalogRevision++;
    this.loadingCatalog = false;
    this.showAddDialog = false;
    this.closeVoiceActions();
    this.stopVoiceSelectionAutoScroll();
    this.persistVoiceEditDraftNow();
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      PageScaffold({ title: '音色管理', scrollable: false, edgeToEdge: true,
        externalCollapse: this.headerCollapse, content: (): void => { this.managerContent(); },
        actions: (): void => { this.managerActions(); } })

      if (!this.selectionMode && !this.isImporting && !this.isBatchOperating) {
        this.addVoiceFloatingButton()
      }

      Column()
        .width(1)
        .height(1)
        .position({ x: this.contextMenuX, y: this.contextMenuY })
        .hitTestBehavior(HitTestMode.None)
        .bindPopup(this.showVoiceActionMenu, ImmersiveMaterialRuntime.popupMenuOptions(this.immersiveLightLevel, (): void => {
          this.voiceActionMenu()
        }, Placement.BottomLeft, this.appDarkMode, this.accentColor(), () => {
          this.showVoiceActionMenu = false;
        }))
    }
    .width('100%')
    .height('100%')
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      const width = Number(newValue.width);
      const height = Number(newValue.height);
      if (Number.isFinite(width) && width > 0) this.contextViewportWidth = width;
      if (Number.isFinite(height) && height > 0) this.contextViewportHeight = height;
    })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  managerActions() {
    ImmersiveHeaderAction({
      label: this.selectionMode ? '取消' : '批量',
      accessibilityLabel: this.selectionMode ? '退出音色批量管理' : '批量管理音色',
      onTap: () => { this.selectionMode ? this.exitSelectionMode() : this.enterSelectionMode(); }
    })
      .margin({ right: AppSpacing.XL })
  }

  @Builder
  managerContent() {
    Column() {
      List({ space: AppSpacing.MD, scroller: this.voiceListScroller }) {
        ListItem() {
          Column() {
            this.searchBar()
            if (this.selectionMode) { this.selectionHeader() }
          }.width('100%').padding({ top: PageScaffold.BAR_HEIGHT + this.statusBarHeight })
        }
        if (this.nativeVoices(false).length > 0) {
          ListItem() { this.voiceSectionTitle('系统音色') }
        }
        ForEach(this.nativeVoices(false), (entry: ManagedTtsVoiceEntry) => {
          if (entry.protectedVoice || this.selectionMode) {
            ListItem() { this.nativeVoiceRow(entry) }
          } else if (deviceInfo.sdkApiVersion >= 26) {
            HdsListItem({ customItemBuilder: (): void => { this.nativeVoiceRow(entry); },
              swipeActionOptions: this.nativeSwipeActions(entry) })
          } else {
            ListItem() { this.nativeVoiceRow(entry) }
              .swipeAction({ end: { builder: (): void => { this.nativeSwipeButton(entry); } }, edgeEffect: SwipeEdgeEffect.Spring })
          }
        }, (entry: ManagedTtsVoiceEntry): string => `${entry.key}:${this.nativeEnabled(entry)}:${this.selectionMode}`)
        if (this.nativeVoices(true).length > 0 || this.loadingCatalog || this.catalogError) {
          ListItem() { this.voiceSectionTitle('云端音色') }
        }
        if (this.loadingCatalog || this.catalogError) {
          ListItem() {
            Row({ space: AppSpacing.MD }) {
              if (this.loadingCatalog) { LoadingProgress().width(20).height(20).color(this.accentColor()) }
              Text(this.loadingCatalog ? '正在加载音色' : this.catalogError).fontSize(AppFontSize.CAPTION)
                .fontColor(this.subTextColor()).layoutWeight(1)
              if (!this.loadingCatalog) {
                Button('重试').fontSize(AppFontSize.CAPTION).onClick(() => { this.loadVoiceCatalog(); })
              }
            }.width('100%').padding(AppSpacing.XL)
          }
        }
        ForEach(this.nativeVoices(true), (entry: ManagedTtsVoiceEntry) => {
          if (this.selectionMode) {
            ListItem() { this.nativeVoiceRow(entry) }
          } else if (deviceInfo.sdkApiVersion >= 26) {
            HdsListItem({ customItemBuilder: (): void => { this.nativeVoiceRow(entry); },
              swipeActionOptions: this.nativeSwipeActions(entry) })
          } else {
            ListItem() { this.nativeVoiceRow(entry) }
              .swipeAction({ end: { builder: (): void => { this.nativeSwipeButton(entry); } }, edgeEffect: SwipeEdgeEffect.Spring })
          }
        }, (entry: ManagedTtsVoiceEntry): string => `${entry.key}:${this.nativeEnabled(entry)}:${this.selectionMode}`)
        ListItem() { this.voiceSectionTitle('自定义音色') }
        ForEach(this.filteredVoices(), (voice: HttpTTS) => {
          if (deviceInfo.sdkApiVersion >= 26 && !this.selectionMode) {
            HdsListItem({ customItemBuilder: (): void => { this.voiceListItem(voice); },
              swipeActionOptions: this.voiceSwipeActions(voice) })
          } else if (!this.selectionMode) {
            ListItem() { this.voiceListItem(voice) }
              .swipeAction({ end: { builder: (): void => { this.voiceFallbackSwipeActions(voice); } }, edgeEffect: SwipeEdgeEffect.Spring })
          } else {
            ListItem() { this.voiceListItem(voice) }
          }
        }, (voice: HttpTTS): string => this.voiceKey(voice))
        if (this.filteredVoices().length === 0) {
          ListItem() {
            Text(this.searchText ? '未找到匹配的自定义音色' : '点击右下角“+”添加自定义音色')
              .fontSize(AppFontSize.CAPTION).fontColor(this.subTextColor()).width('100%').padding(AppSpacing.XL)
          }
        }
        ListItem() {
          Row().height(this.selectionMode ? AppSpacing.XL : this.voiceListBottomInset())
            .hitTestBehavior(HitTestMode.None)
        }
      }.width('100%').layoutWeight(1).scrollBar(BarState.Off)
        // HdsListItem 必须直接挂在 List 下；在自定义组件上设置 margin 会生成 __Common__ 包装并阻断侧滑。
        .padding({ left: AppSpacing.XL, right: AppSpacing.XL })
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .onScrollIndex((start: number, end: number) => {
          this.voiceFirstVisibleIndex = Math.max(0, start - 1);
          this.voiceLastVisibleIndex = Math.max(0, end - 1);
        })
        .onAreaChange((_oldValue: Area, area: Area) => {
          this.voiceSelectionViewportTop = Number(area.globalPosition.y);
          this.voiceSelectionViewportBottom = this.voiceSelectionViewportTop + Number(area.height);
        })
        .onDidScroll((yOffset: number) => {
          this.headerCollapse = CollapsingHeader.next(this.headerCollapse, yOffset,
            this.voiceListScroller.currentOffset().yOffset);
        })
        .onScrollStop(() => {
          const target = CollapsingHeader.settle(this.headerCollapse, this.voiceListScroller.currentOffset().yOffset);
          if (target !== this.headerCollapse) {
            this.getUIContext().animateTo({ duration: 200, curve: Curve.FastOutSlowIn }, () => { this.headerCollapse = target; });
          }
        })
      if (this.selectionMode) { this.batchBar() }
    }.width('100%').height('100%').constraintSize({ maxWidth: 760 })
  }

  @Builder
  voiceSectionTitle(title: string) {
    Text(title).fontSize(AppFontSize.BODY_LARGE).fontWeight(FontWeight.Medium).fontColor(this.primaryTextColor())
      .width('100%').padding({ top: AppSpacing.MD })
  }

  nativeVoices(cloud: boolean, filtered: boolean = true): ManagedTtsVoiceEntry[] {
    const entries: ManagedTtsVoiceEntry[] = [];
    if (cloud) {
      for (const voice of this.cloudVoices) {
        const entry = new ManagedTtsVoiceEntry();
        entry.cloud = true;
        entry.cloudVoice = voice;
        entry.key = TtsVoiceAvailability.cloudKey(voice.id);
        entry.title = voice.name;
        entry.description = `${voice.tier === 'PREMIUM' ? '精品' : '标准'}${voice.description ? ' · ' + voice.description : ''}`;
        entries.push(entry);
      }
    } else {
      for (const voice of this.systemVoices) {
        const entry = new ManagedTtsVoiceEntry();
        entry.systemVoice = voice;
        entry.key = TtsVoiceAvailability.systemKey(voice.id, voice.online, voice.language, voice.style);
        entry.protectedVoice = TtsVoiceCatalog.isDefault(voice);
        entry.title = entry.protectedVoice ? '系统默认音色' : voice.name;
        entry.description = entry.protectedVoice ? '始终启用' : TtsVoiceCatalog.voiceTitle(voice);
        entries.push(entry);
      }
    }
    const keyword = filtered ? this.searchText.trim().toLowerCase() : '';
    return entries.filter((entry: ManagedTtsVoiceEntry): boolean => !keyword ||
      `${entry.title} ${entry.description}`.toLowerCase().includes(keyword));
  }

  nativeEnabled(entry: ManagedTtsVoiceEntry): boolean {
    return entry.protectedVoice || TtsVoiceAvailability.isEnabled(this.ttsDisabledVoiceKeys, entry.key);
  }

  nativeSelected(entry: ManagedTtsVoiceEntry): boolean {
    if (entry.cloud) return this.ttsCloudVoiceId === entry.cloudVoice.id;
    return !this.ttsCloudVoiceId && !this.ttsCustomVoiceId && entry.key ===
      TtsVoiceAvailability.systemKey(this.ttsPerson, this.ttsOnline, this.ttsLanguage, this.ttsStyle);
  }

  @Builder
  nativeVoiceRow(entry: ManagedTtsVoiceEntry) {
    Row({ space: AppSpacing.MD }) {
      if (this.selectionMode) { this.voiceSelectionSafeArea(entry.key) }
      Column({ space: AppSpacing.XS }) {
        Text(entry.title).fontSize(AppFontSize.BODY_LARGE).fontWeight(FontWeight.Medium)
          .fontColor(this.primaryTextColor()).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.downloadingVoiceKey === entry.key ? (this.downloadProgress || '下载中') :
          `${entry.description}${entry.protectedVoice ? '' : (this.nativeEnabled(entry) ? ' · 已启用' : ' · 已禁用')}`)
          .fontSize(AppFontSize.CAPTION).fontColor(this.subTextColor()).maxLines(3)
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      if (entry.protectedVoice) {
        Text('默认').fontSize(AppFontSize.CAPTION).fontColor(this.subTextColor())
      }
      if (!this.selectionMode && this.nativeSelected(entry)) {
        SymbolGlyph($r('sys.symbol.checkmark')).fontSize(18).fontColor([this.accentColor()])
      }
    }.width('100%').constraintSize({ minHeight: 72 }).padding(AppSpacing.XL)
      .backgroundColor(this.cardColor()).borderRadius(ThemeRuntime.cardRadius())
      .opacity(this.nativeEnabled(entry) ? 1 : 0.5)
      .onAreaChange((_oldValue: Area, area: Area) => { this.rememberVoiceSelectionArea(entry.key, area); })
      .onClick(() => {
        if (this.selectionMode) {
          if (Date.now() < this.voiceSelectionSuppressClickUntil || this.isBatchOperating) return;
          this.setSelectionKey(entry.key, !this.selectedVoiceIds.includes(entry.key));
        } else { this.selectNativeVoice(entry); }
      })
  }

  private nativeSwipeActions(entry: ManagedTtsVoiceEntry): HdsSwipeActionOptions {
    if (entry.protectedVoice) return { icons: [] };
    return { icons: [{
      icon: new SymbolGlyphModifier(this.nativeEnabled(entry) ? $r('sys.symbol.minus_circle') : $r('sys.symbol.checkmark_circle')),
      backgroundColor: this.buttonColor(),
      iconOptions: { accessibilityText: this.nativeEnabled(entry) ? '禁用音色' : '启用音色' },
      onAction: (): void => { this.toggleNativeVoice(entry); }
    }] };
  }

  @Builder
  nativeSwipeButton(entry: ManagedTtsVoiceEntry) {
    Button(this.nativeEnabled(entry) ? '禁用' : '启用').height('100%').width(72)
      .backgroundColor(this.buttonColor()).fontColor(ThemeRuntime.onAccentColor(this.buttonColor()))
      .onClick(() => { this.toggleNativeVoice(entry); })
  }

  toggleNativeVoice(entry: ManagedTtsVoiceEntry): void {
    if (entry.protectedVoice) return;
    const enabled = !this.nativeEnabled(entry);
    const selected = this.nativeSelected(entry);
    this.ttsDisabledVoiceKeys = TtsVoiceAvailability.setEnabled(this.ttsDisabledVoiceKeys, entry.key, enabled);
    if (!enabled && selected) this.clearCustomVoiceSelection();
    this.saveSettings();
    HdsFeedback.showToast(!enabled && selected ? '音色已禁用，已切换为系统默认音色' : (enabled ? '音色已启用' : '音色已禁用'));
  }

  async selectNativeVoice(entry: ManagedTtsVoiceEntry): Promise<void> {
    if (!this.nativeEnabled(entry)) { HdsFeedback.showToast('请先左滑启用该音色'); return; }
    if (this.downloadingVoiceKey) { HdsFeedback.showToast('正在下载音色，请稍候'); return; }
    if (entry.cloud) {
      if (!AccountSessionStore.isLoggedIn()) { HdsFeedback.showToast('请先登录华为账号后使用云端音色'); return; }
      this.ttsCloudVoiceId = entry.cloudVoice.id;
      this.ttsCustomVoiceId = '';
    } else {
      let voice = entry.systemVoice;
      if (!voice.available) {
        if (!voice.downloadable) { HdsFeedback.showToast('该系统音色当前不可用'); return; }
        const selectionRevision = this.catalogRevision;
        this.downloadingVoiceKey = entry.key;
        this.downloadProgress = '准备中';
        try {
          await SystemTtsReader.downloadVoice(voice, {
            onStart: (_message: string): void => {},
            onProgress: (progress: string): void => { if (this.pageAlive) this.downloadProgress = progress; }
          });
          const installedKey = TtsVoiceCatalog.installedKey(voice);
          const settings = TtsSettingsStore.fromStorage();
          const keys = settings.installedVoiceKeys.split('\n').filter((key: string): boolean => !!key);
          if (!keys.includes(installedKey)) keys.push(installedKey);
          settings.installedVoiceKeys = keys.join('\n');
          await TtsSettingsStore.save(getContext(this), settings);
          this.systemVoices = TtsVoiceCatalog.applyInstalledOverrides(this.systemVoices, settings.installedVoiceKeys);
          voice = TtsVoiceCatalog.markInstalled(voice);
        } catch (error) {
          if (this.pageAlive) HdsFeedback.showToast(`音色下载失败：${this.shortErrorMessage(error as Object)}`);
          return;
        } finally { this.downloadingVoiceKey = ''; this.downloadProgress = ''; }
        if (!this.pageAlive || selectionRevision !== this.catalogRevision || !this.nativeEnabled(entry)) return;
      }
      this.ttsPerson = voice.id;
      this.ttsOnline = voice.online;
      this.ttsStyle = voice.style;
      this.ttsLanguage = voice.language;
      this.ttsCloudVoiceId = '';
      this.ttsCustomVoiceId = '';
    }
    this.saveSettings();
    HdsFeedback.showToast(`已选择 ${entry.title}`);
  }

  async loadVoiceCatalog(): Promise<void> {
    if (this.loadingCatalog) return;
    const revision = ++this.catalogRevision;
    this.loadingCatalog = true;
    this.catalogError = '';
    // 两个来源独立加载，云端失败时系统与自定义音色仍然可管理。
    let systemFailed = false;
    let cloudFailed = false;
    const results = await Promise.all([
      SystemTtsReader.listAvailableVoices().catch((): TtsVoiceOption[] => { systemFailed = true; return []; }),
      AccountCommerceApi.fetchTtsCatalog().catch(() => { cloudFailed = true; return null; })
    ]);
    if (!this.pageAlive || revision !== this.catalogRevision) return;
    const systems = results[0] as TtsVoiceOption[];
    this.systemVoices = TtsVoiceCatalog.applyInstalledOverrides(TtsVoiceCatalog.mergeWithDefault(systems), this.ttsInstalledVoiceKeys);
    const catalog = results[1];
    if (catalog) this.cloudVoices = catalog.voices;
    this.catalogError = systemFailed && cloudFailed ? '系统与云端音色加载失败' :
      (systemFailed ? '系统音色加载失败' : (cloudFailed ? '云端音色加载失败' : ''));
    this.loadingCatalog = false;
  }

  private voiceSwipeActions(voice: HttpTTS): HdsSwipeActionOptions {
    return { icons: [
      {
        icon: new SymbolGlyphModifier(voice.enabled ? $r('sys.symbol.minus_circle') : $r('sys.symbol.checkmark_circle')),
        backgroundColor: this.buttonColor(),
        iconOptions: { accessibilityText: voice.enabled ? '禁用音色' : '启用音色' },
        onAction: () => this.toggleVoiceState(voice)
      },
      { icon: new SymbolGlyphModifier($r('sys.symbol.trash')), backgroundColor: ThemeRuntime.dangerColor(this.appDarkMode), iconOptions: { accessibilityText: '删除音色' }, onAction: () => this.deleteVoice(voice) }
    ] };
  }

  @Builder
  voiceFallbackSwipeActions(voice: HttpTTS) {
    Row() {
      this.voiceDisableSwipeAction(voice)
      this.voiceDeleteSwipeAction(voice)
    }
    .height('100%')
  }

  loadSettings(): void {
    TtsSettingsStore.load(getContext(this)).then((settings: TtsSettings) => {
      if (!this.pageAlive) return;
      this.ttsCustomVoiceId = settings.customVoiceId;
      this.ttsCustomVoices = settings.customVoices;
      this.ttsPerson = settings.person;
      this.ttsOnline = settings.online;
      this.ttsStyle = settings.style;
      this.ttsLanguage = settings.language;
      this.ttsSpeed = settings.speed;
      this.ttsInstalledVoiceKeys = settings.installedVoiceKeys;
      this.ttsCloudVoiceId = settings.cloudVoiceId;
      this.ttsDisabledVoiceKeys = settings.disabledVoiceKeys;
      this.voices = SystemTtsReader.parseCustomVoices(settings.customVoices);
      this.pruneSelectedVoices();
    }).catch((error: Error) => {
      console.warn('加载自定义音色失败:', error);
      if (!this.pageAlive) return;
      this.voices = SystemTtsReader.parseCustomVoices(this.ttsCustomVoices);
    });
  }

  saveSettings(): void {
    this.ttsCustomVoices = SystemTtsReader.serializeCustomVoices(this.voices);
    const settings = new TtsSettings();
    settings.person = this.ttsPerson;
    settings.online = this.ttsOnline;
    settings.style = this.ttsStyle;
    settings.language = this.ttsLanguage;
    settings.speed = this.ttsSpeed;
    settings.installedVoiceKeys = this.ttsInstalledVoiceKeys;
    settings.customVoiceId = this.ttsCustomVoiceId;
    settings.customVoices = this.ttsCustomVoices;
    settings.cloudVoiceId = this.ttsCloudVoiceId;
    settings.disabledVoiceKeys = this.ttsDisabledVoiceKeys;
    TtsSettingsStore.applyToStorage(settings);
    TtsSettingsStore.save(getContext(this), settings).catch((error: Error) => {
      console.warn('保存音色设置失败:', error);
      HdsFeedback.showToast('保存失败，请重试');
    });
  }

  filteredVoices(): HttpTTS[] {
    const keyword = this.searchText.trim().toLowerCase();
    if (!keyword) {
      return this.voices;
    }
    return this.voices.filter((voice: HttpTTS) =>
      (voice.name || '').toLowerCase().includes(keyword) ||
      (voice.url || '').toLowerCase().includes(keyword));
  }

  // 列表底部避让：右下角悬浮新增按钮（52 高，底边距 navBarHeight+22）必须完整让出，
  // 否则最后一条卡片被按钮盖住，左滑露出的操作键无法点按。
  voiceListBottomInset(): number {
    return Math.max(20, this.navBarHeight + 88);
  }

  toggleVoiceEnabled(voice: HttpTTS, enabled: boolean): void {
    this.voices = this.voices.map((item: HttpTTS) => {
      if (String(item.id) === String(voice.id)) {
        item.enabled = enabled;
      }
      return item;
    });
    if (!enabled && this.isCurrentVoice(voice)) {
      this.clearCustomVoiceSelection();
    }
    this.saveSettings();
  }

  toggleVoiceState(voice: HttpTTS): void {
    const enabled = !voice.enabled;
    this.toggleVoiceEnabled(voice, enabled);
    HdsFeedback.showToast(enabled ? '音色已启用' : '音色已禁用');
  }

  deleteVoice(voice: HttpTTS): void {
    this.getUIContext().showAlertDialog({
      title: '删除音色',
      message: `确定删除自定义音色“${voice.name || '未命名音色'}”吗？删除后无法撤销。`,
      primaryButton: { value: '取消', action: (): void => {} },
      secondaryButton: { value: '删除', fontColor: ThemeRuntime.dangerColor(this.appDarkMode),
        action: (): void => { if (this.pageAlive) this.confirmDeleteVoice(voice); } }
    });
  }

  private confirmDeleteVoice(voice: HttpTTS): void {
    if (!this.voices.some((item: HttpTTS): boolean => String(item.id) === String(voice.id))) return;
    const id = String(voice.id);
    if (this.isCurrentVoice(voice)) {
      this.clearCustomVoiceSelection();
    }
    this.voices = this.voices.filter((item: HttpTTS) => String(item.id) !== id);
    this.selectedVoiceIds = this.selectedVoiceIds.filter((selectedId: string) => selectedId !== this.customSelectionKey(id));
    this.saveSettings();
    HdsFeedback.showToast('音色已删除');
  }

  clearCustomVoiceSelection(): void {
    this.ttsCloudVoiceId = '';
    this.ttsCustomVoiceId = '';
    this.ttsPerson = 0;
    this.ttsOnline = 1;
    this.ttsStyle = '';
    this.ttsLanguage = 'zh-CN';
  }

  enterSelectionMode(): void {
    this.showAddDialog = false;
    this.selectionMode = true;
    this.headerCollapse = 0;
    this.voiceListScroller.scrollTo({ xOffset: 0, yOffset: 0 });
    this.selectedVoiceIds = [];
  }

  exitSelectionMode(): void {
    this.stopVoiceSelectionAutoScroll();
    this.selectionMode = false;
    this.headerCollapse = 0;
    this.voiceListScroller.scrollTo({ xOffset: 0, yOffset: 0 });
    this.selectedVoiceIds = [];
  }

  customSelectionKey(id: string): string {
    return `custom:${id}`;
  }

  batchVoices(filtered: boolean = false): TtsBatchVoiceEntry[] {
    const entries: TtsBatchVoiceEntry[] = [];
    for (const voice of this.nativeVoices(false, filtered).concat(this.nativeVoices(true, filtered))) {
      const entry = new TtsBatchVoiceEntry();
      entry.key = voice.key;
      entry.title = voice.title;
      entry.kind = voice.cloud ? '云端音色' : '系统音色';
      entry.protectedVoice = voice.protectedVoice;
      entries.push(entry);
    }
    for (const voice of filtered ? this.filteredVoices() : this.voices) {
      const entry = new TtsBatchVoiceEntry();
      entry.key = this.customSelectionKey(String(voice.id));
      entry.title = voice.name || '未命名音色';
      entry.kind = '自定义音色';
      entries.push(entry);
    }
    return entries;
  }

  isVoiceSelected(voice: HttpTTS): boolean {
    return this.selectedVoiceIds.includes(this.customSelectionKey(String(voice.id)));
  }

  setSelectionKey(key: string, selected: boolean): void {
    if (this.isBatchOperating) return;
    if (selected) {
      if (!this.selectedVoiceIds.includes(key)) this.selectedVoiceIds = this.selectedVoiceIds.concat([key]);
    } else {
      this.selectedVoiceIds = this.selectedVoiceIds.filter((item: string): boolean => item !== key);
    }
  }

  toggleVoiceSelected(voice: HttpTTS): void {
    this.setSelectionKey(this.customSelectionKey(String(voice.id)), !this.isVoiceSelected(voice));
  }

  isAllSelected(): boolean {
    const visible = this.batchVoices(true);
    return visible.length > 0 && visible.every((voice: TtsBatchVoiceEntry): boolean => this.selectedVoiceIds.includes(voice.key));
  }

  toggleAllVoices(): void {
    if (this.isBatchOperating) return;
    const visibleIds = this.batchVoices(true).map((voice: TtsBatchVoiceEntry): string => voice.key);
    if (this.isAllSelected()) {
      this.selectedVoiceIds = this.selectedVoiceIds.filter((id: string): boolean => !visibleIds.includes(id));
    } else {
      this.selectedVoiceIds = this.selectedVoiceIds.concat(visibleIds.filter((id: string): boolean => !this.selectedVoiceIds.includes(id)));
    }
  }

  pruneSelectedVoices(): void {
    const ids = this.batchVoices().map((voice: TtsBatchVoiceEntry): string => voice.key);
    this.selectedVoiceIds = this.selectedVoiceIds.filter((id: string): boolean => ids.includes(id));
  }

  showBatchResult(action: string, count: number, blocked: string[]): void {
    const summary = `已${action} ${count} 个音色`;
    if (blocked.length === 0) { HdsFeedback.showToast(summary); return; }
    this.getUIContext().showAlertDialog({
      title: `批量${action}结果`,
      message: `${summary}\n\n以下音色无法${action}：\n${blocked.join('\n')}`,
      confirm: { value: '知道了', action: (): void => {} }
    });
  }

  batchSetEnabled(enabled: boolean): void {
    if (this.selectedVoiceIds.length === 0 || this.isBatchOperating) return;
    const selected = this.batchVoices().filter((voice: TtsBatchVoiceEntry): boolean => this.selectedVoiceIds.includes(voice.key));
    const blocked: string[] = [];
    let count = 0;
    let resetCurrent = false;
    this.isBatchOperating = true;
    try {
      for (const entry of selected) {
        if (!enabled && entry.protectedVoice) {
          blocked.push(`${entry.title}（默认音色始终启用）`);
          continue;
        }
        if (entry.kind !== '自定义音色') {
          const currentKey = this.ttsCloudVoiceId ? TtsVoiceAvailability.cloudKey(this.ttsCloudVoiceId) :
            TtsVoiceAvailability.systemKey(this.ttsPerson, this.ttsOnline, this.ttsLanguage, this.ttsStyle);
          if (!enabled && !this.ttsCustomVoiceId && entry.key === currentKey) resetCurrent = true;
          this.ttsDisabledVoiceKeys = TtsVoiceAvailability.setEnabled(this.ttsDisabledVoiceKeys, entry.key, enabled);
        }
        count++;
      }
      this.voices = this.voices.map((voice: HttpTTS): HttpTTS => {
        if (this.isVoiceSelected(voice)) {
          voice.enabled = enabled;
          if (!enabled && this.isCurrentVoice(voice)) resetCurrent = true;
        }
        return voice;
      });
      if (resetCurrent) this.clearCustomVoiceSelection();
      if (count > 0) this.saveSettings();
      this.showBatchResult(enabled ? '启用' : '禁用', count, blocked);
    } finally { this.isBatchOperating = false; }
  }

  batchDelete(): void {
    if (this.selectedVoiceIds.length === 0 || this.isBatchOperating) return;
    const selected = this.batchVoices().filter((voice: TtsBatchVoiceEntry): boolean => this.selectedVoiceIds.includes(voice.key));
    const blocked = selected.filter((voice: TtsBatchVoiceEntry): boolean => voice.kind !== '自定义音色')
      .map((voice: TtsBatchVoiceEntry): string => `${voice.title}（${voice.kind}，仅自定义音色可删除）`);
    const customVoices = selected.filter((voice: TtsBatchVoiceEntry): boolean => voice.kind === '自定义音色');
    if (customVoices.length === 0) {
      this.getUIContext().showAlertDialog({
        title: '无法删除所选音色',
        message: `仅自定义音色可以删除，当前选择中没有自定义音色。未删除任何音色。\n\n${blocked.join('\n')}`,
        confirm: { value: '知道了', action: (): void => {} }
      });
      return;
    }
    // 固定确认弹窗中的删除范围，确认后不重新读取可能已经变化的勾选项。
    const deletable = customVoices.map((voice: TtsBatchVoiceEntry): string => voice.key);
    const names = customVoices.map((voice: TtsBatchVoiceEntry): string => voice.title).join('\n');
    const restrictions = blocked.length > 0 ? `\n\n以下音色无法删除，将保留：\n${blocked.join('\n')}` : '';
    this.getUIContext().showAlertDialog({
      title: '批量删除音色',
      message: `确定删除以下 ${deletable.length} 个自定义音色吗？删除后无法撤销。\n\n${names}${restrictions}`,
      primaryButton: { value: '取消', action: (): void => {} },
      secondaryButton: { value: `删除 ${deletable.length} 个`, fontColor: ThemeRuntime.dangerColor(this.appDarkMode),
        action: (): void => { if (this.pageAlive) this.confirmBatchDelete(deletable); } }
    });
  }

  private confirmBatchDelete(deletable: string[]): void {
    if (this.isBatchOperating) return;
    this.isBatchOperating = true;
    try {
      const count = this.voices.filter((voice: HttpTTS): boolean => deletable.includes(this.customSelectionKey(String(voice.id)))).length;
      if (deletable.includes(this.customSelectionKey(this.ttsCustomVoiceId))) this.clearCustomVoiceSelection();
      this.voices = this.voices.filter((voice: HttpTTS): boolean => !deletable.includes(this.customSelectionKey(String(voice.id))));
      this.selectedVoiceIds = this.selectedVoiceIds.filter((key: string): boolean => !deletable.includes(key));
      if (count > 0) this.saveSettings();
      if (this.selectedVoiceIds.length === 0) this.exitSelectionMode();
      HdsFeedback.showToast(`已删除 ${count} 个音色`);
    } finally { this.isBatchOperating = false; }
  }

  openEditDialog(voice: HttpTTS): void {
    FormDraftStore.removePersistent(getContext(this), 'custom_tts:edit');
    this.editingVoiceId = String(voice.id);
    this.editName = voice.name || '';
    this.editUrl = voice.url || '';
    this.editContentType = voice.contentType || '';
    this.editConcurrentRate = voice.concurrentRate || '';
    this.editLoginUrl = voice.loginUrl || '';
    this.editLoginUi = voice.loginUi || '';
    this.editLoginCheckJs = voice.loginCheckJs || '';
    this.editHeader = voice.header || '';
    this.editJsLib = voice.jsLib || voice.jsEngine || '';
    this.editJsEngine = voice.jsEngine || voice.jsLib || '';
    this.editEnabledCookieJar = voice.enabledCookieJar === true;
    this.showEditDialog = true;
    this.saveVoiceEditDraft();
  }

  openCreateVoiceDialog(): void {
    FormDraftStore.removePersistent(getContext(this), 'custom_tts:edit');
    this.editingVoiceId = '';
    this.editName = '';
    this.editUrl = '';
    this.editContentType = '';
    this.editConcurrentRate = '';
    this.editLoginUrl = '';
    this.editLoginUi = '';
    this.editLoginCheckJs = '';
    this.editHeader = '';
    this.editJsLib = '';
    this.editJsEngine = '';
    this.editEnabledCookieJar = false;
    this.showEditDialog = true;
    this.saveVoiceEditDraft();
  }

  closeEditDialog(): void {
    this.showEditDialog = false;
    this.editingVoiceId = '';
    FormDraftStore.removePersistent(getContext(this), 'custom_tts:edit');
  }

  restoreVoiceEditDraft(rawValue: string = ''): void {
    const raw = rawValue || FormDraftStore.get('custom_tts:edit');
    if (!raw) return;
    try {
      const draft = JSON.parse(raw) as VoiceEditFormDraft;
      this.editingVoiceId = draft.editingVoiceId;
      this.editName = draft.name;
      this.editUrl = draft.url;
      this.editContentType = draft.contentType;
      this.editConcurrentRate = draft.concurrentRate;
      this.editLoginUrl = draft.loginUrl;
      this.editLoginUi = draft.loginUi;
      this.editLoginCheckJs = draft.loginCheckJs;
      this.editHeader = draft.header;
      this.editJsLib = draft.jsLib;
      this.editJsEngine = draft.jsEngine;
      this.editEnabledCookieJar = draft.enabledCookieJar;
      this.showEditDialog = true;
    } catch (_) {
      FormDraftStore.removePersistent(getContext(this), 'custom_tts:edit');
    }
  }

  async restorePersistentVoiceEditDraft(): Promise<void> {
    const raw = await FormDraftStore.load(getContext(this), 'custom_tts:edit');
    this.restoreVoiceEditDraft(raw);
  }

  saveVoiceEditDraft(): void {
    if (!this.showEditDialog) return;
    const draft = new VoiceEditFormDraft();
    draft.editingVoiceId = this.editingVoiceId;
    draft.name = this.editName;
    draft.url = this.editUrl;
    draft.contentType = this.editContentType;
    draft.concurrentRate = this.editConcurrentRate;
    draft.loginUrl = this.editLoginUrl;
    draft.loginUi = this.editLoginUi;
    draft.loginCheckJs = this.editLoginCheckJs;
    draft.header = this.editHeader;
    draft.jsLib = this.editJsLib;
    draft.jsEngine = this.editJsEngine;
    draft.enabledCookieJar = this.editEnabledCookieJar;
    FormDraftStore.persistSoon(getContext(this), 'custom_tts:edit', JSON.stringify(draft));
  }

  persistVoiceEditDraftNow(): void {
    if (!this.showEditDialog) return;
    const draft = new VoiceEditFormDraft();
    draft.editingVoiceId = this.editingVoiceId;
    draft.name = this.editName;
    draft.url = this.editUrl;
    draft.contentType = this.editContentType;
    draft.concurrentRate = this.editConcurrentRate;
    draft.loginUrl = this.editLoginUrl;
    draft.loginUi = this.editLoginUi;
    draft.loginCheckJs = this.editLoginCheckJs;
    draft.header = this.editHeader;
    draft.jsLib = this.editJsLib;
    draft.jsEngine = this.editJsEngine;
    draft.enabledCookieJar = this.editEnabledCookieJar;
    FormDraftStore.persist(getContext(this), 'custom_tts:edit', JSON.stringify(draft));
  }

  saveEditedVoice(): void {
    const name = this.editName.trim();
    const url = this.editUrl.trim();
    if (!name) {
      HdsFeedback.showToast('请输入音色名称');
      return;
    }
    if (!url) {
      HdsFeedback.showToast('请输入音色 URL');
      return;
    }
    const targetId = this.editingVoiceId;
    if (!targetId) {
      const voice = new HttpTTS();
      voice.id = Date.now();
      voice.name = name;
      voice.url = url;
      voice.contentType = this.editContentType.trim();
      voice.concurrentRate = this.editConcurrentRate.trim();
      voice.loginUrl = this.editLoginUrl.trim();
      voice.loginUi = this.editLoginUi.trim();
      voice.loginCheckJs = this.editLoginCheckJs.trim();
      voice.header = this.editHeader.trim();
      voice.jsLib = this.editJsLib.trim() || this.editJsEngine.trim();
      voice.jsEngine = this.editJsEngine.trim() || voice.jsLib;
      voice.enabledCookieJar = this.editEnabledCookieJar;
      voice.lastUpdateTime = Date.now();
      this.voices = [...this.voices, voice];
      this.saveSettings();
      this.closeEditDialog();
      HdsFeedback.showToast('已新建音色');
      return;
    }
    this.voices = this.voices.map((voice: HttpTTS) => {
      if (String(voice.id) === targetId) {
        voice.name = name;
        voice.url = url;
        voice.contentType = this.editContentType.trim();
        voice.concurrentRate = this.editConcurrentRate.trim();
        voice.loginUrl = this.editLoginUrl.trim();
        voice.loginUi = this.editLoginUi.trim();
        voice.loginCheckJs = this.editLoginCheckJs.trim();
        voice.header = this.editHeader.trim();
        voice.jsLib = this.editJsLib.trim() || this.editJsEngine.trim();
        voice.jsEngine = this.editJsEngine.trim() || voice.jsLib;
        voice.enabledCookieJar = this.editEnabledCookieJar;
        voice.lastUpdateTime = Date.now();
      }
      return voice;
    });
    this.saveSettings();
    this.closeEditDialog();
    HdsFeedback.showToast('已保存音色');
  }

  async importFromUrl(): Promise<void> {
    const url = this.importUrl.trim();
    if (!url) {
      HdsFeedback.showToast('请输入音色 JSON URL');
      return;
    }
    if (this.isImporting) {
      return;
    }
    this.isImporting = true;
    try {
      const response = await new HttpClient(15000).execute({
        url,
        method: 'GET',
        headers: {},
        maxResponseBytes: CUSTOM_TTS_IMPORT_FILE_LIMIT_BYTES
      });
      if (!response.success) {
        throw new Error(response.error || `HTTP ${response.statusCode}`);
      }
      this.importFromJson(response.body);
      this.showImportUrlDialog = false;
      this.showAddDialog = false;
    } catch (error) {
      HdsFeedback.showToast(`导入失败：${this.shortErrorMessage(error as Object)}`);
    } finally {
      this.isImporting = false;
    }
  }

  async importFromFile(): Promise<void> {
    if (this.isImporting) {
      return;
    }
    try {
      const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = ['JSON|.json', '文本|.txt'];
      const result: Array<string> = await new picker.DocumentViewPicker().select(options);
      if (!result || result.length === 0) {
        return;
      }
      this.isImporting = true;
      const content = await this.readTextFile(result[0]);
      this.importFromJson(content);
      this.showAddDialog = false;
    } catch (error) {
      HdsFeedback.showToast(`导入失败：${this.shortErrorMessage(error as Object)}`);
    } finally {
      this.isImporting = false;
    }
  }

  importFromJson(content: string): void {
    const incoming = SystemTtsReader.parseCustomVoices(content);
    if (incoming.length === 0) {
      HdsFeedback.showToast('未识别到有效自定义音色');
      return;
    }
    const merged = this.voices.slice();
    let changed = 0;
    for (const voice of incoming) {
      this.ensureUniqueVoiceId(voice, merged);
      const index = merged.findIndex((item: HttpTTS) => String(item.id) === String(voice.id) ||
        ((item.name || '') === (voice.name || '') && (item.url || '') === (voice.url || '')));
      if (index >= 0) {
        merged[index] = voice;
      } else {
        merged.push(voice);
      }
      changed++;
    }
    this.voices = merged;
    this.saveSettings();
    HdsFeedback.showToast(`已导入 ${changed} 个自定义音色`);
  }

  ensureUniqueVoiceId(voice: HttpTTS, existing: HttpTTS[]): void {
    if (!existing.some((item: HttpTTS) => item.id === voice.id && (item.url || '') !== (voice.url || ''))) {
      return;
    }
    let id = Date.now();
    while (existing.some((item: HttpTTS) => item.id === id)) {
      id++;
    }
    voice.id = id;
  }

  async readTextFile(filePath: string): Promise<string> {
    let file: fs.File | null = null;
    try {
      const stat = await fs.stat(filePath);
      if (stat.size <= 0) {
        return '';
      }
      if (stat.size > CUSTOM_TTS_IMPORT_FILE_LIMIT_BYTES) {
        throw new Error('文件过大，请选择 2MB 以内的音色文件');
      }
      file = await fs.open(filePath, fs.OpenMode.READ_ONLY);
      const buffer = new ArrayBuffer(stat.size);
      await fs.read(file.fd, buffer, { offset: 0, length: stat.size });
      return util.TextDecoder.create('utf-8').decodeWithStream(new Uint8Array(buffer), { stream: false })
        .replace(/^\uFEFF/, '');
    } finally {
      if (file) {
        await fs.close(file);
      }
    }
  }

  shortErrorMessage(error: Object | undefined): string {
    if (!error) {
      return '未知错误';
    }
    const anyError = error as Record<string, Object>;
    const message = anyError['message'];
    return message === undefined ? String(error) : String(message);
  }

  isCurrentVoice(voice: HttpTTS): boolean {
    return (this.ttsCustomVoiceId || '') === String(voice.id);
  }

  voiceKey(voice: HttpTTS): string {
    return `${voice.id}_${voice.name || ''}_${voice.enabled ? '1' : '0'}_${this.selectionMode ? 'select' : 'normal'}`;
  }

  rememberVoiceSelectionArea(key: string, area: Area): void {
    const position = area.globalPosition;
    this.voiceSelectionAreas.set(key, [Number(position.x), Number(position.y),
      Number(position.x) + Number(area.width), Number(position.y) + Number(area.height)]);
  }

  @Builder
  voiceSelectionSafeArea(key: string) {
    Stack({ alignContent: Alignment.Center }) {
      Toggle({ type: ToggleType.Checkbox, isOn: this.selectedVoiceIds.includes(key) })
        .selectedColor(this.buttonColor())
        .hitTestBehavior(HitTestMode.None)
    }
    .width(56)
    .height(64)
    .margin({ left: -10, right: AppSpacing.XXS })
    .priorityGesture(
      GestureGroup(GestureMode.Exclusive,
        PanGesture({ direction: PanDirection.Vertical, distance: 2 })
          .onActionStart((event: GestureEvent) => this.beginVoiceSlideSelection(event))
          .onActionUpdate((event: GestureEvent) => this.updateVoiceSlideSelection(event))
          .onActionEnd(() => this.endVoiceSlideSelection())
          .onActionCancel(() => this.endVoiceSlideSelection()),
        TapGesture().onAction(() => {
          if (!this.isBatchOperating) {
            this.voiceSelectionSuppressClickUntil = Date.now() + 240;
            this.setSelectionKey(key, !this.selectedVoiceIds.includes(key));
          }
        })
      ),
      GestureMask.IgnoreInternal
    )
  }

  beginVoiceSlideSelection(event: GestureEvent): void {
    if (!this.selectionMode || this.isBatchOperating) return;
    this.voiceDragVisited.clear();
    const voice = this.voiceAtGesture(event);
    if (!voice) return;
    this.voiceSelectionDragging = true;
    this.captureVoiceSelectionPoint(event);
    this.voiceDragSelectValue = !this.selectedVoiceIds.includes(voice);
    this.applyVoiceSlideSelection(voice);
    this.updateVoiceSelectionAutoScroll();
  }

  updateVoiceSlideSelection(event: GestureEvent): void {
    if (!this.selectionMode || this.isBatchOperating) return;
    this.captureVoiceSelectionPoint(event);
    this.applyVoiceSlideSelection(this.voiceAtGesture(event));
    this.updateVoiceSelectionAutoScroll();
  }

  endVoiceSlideSelection(): void {
    this.voiceSelectionSuppressClickUntil = Date.now() + 240;
    this.voiceSelectionDragging = false;
    this.voiceDragVisited.clear();
    this.stopVoiceSelectionAutoScroll();
  }

  voiceAtGesture(event: GestureEvent): string | null {
    const finger = event.fingerList.length > 0 ? event.fingerList[0] : undefined;
    if (!finger) return null;
    return this.voiceAtPoint(finger.globalX, finger.globalY);
  }

  voiceAtPoint(globalX: number, globalY: number): string | null {
    for (const voice of this.batchVoices(true)) {
      const area = this.voiceSelectionAreas.get(voice.key);
      if (area && globalX >= area[0] && globalX <= area[2] &&
        globalY >= area[1] && globalY <= area[3]) return voice.key;
    }
    return null;
  }

  applyVoiceSlideSelection(voice: string | null): void {
    if (!voice) return;
    const id = voice;
    if (this.voiceDragVisited.has(id)) return;
    this.voiceDragVisited.add(id);
    this.setSelectionKey(voice, this.voiceDragSelectValue);
  }

  captureVoiceSelectionPoint(event: GestureEvent): void {
    const finger = event.fingerList.length > 0 ? event.fingerList[0] : undefined;
    if (!finger) return;
    this.voiceSelectionLastX = finger.globalX;
    this.voiceSelectionLastY = finger.globalY;
  }

  updateVoiceSelectionAutoScroll(): void {
    if (!this.voiceSelectionDragging || this.voiceSelectionViewportBottom <= this.voiceSelectionViewportTop) {
      this.stopVoiceSelectionAutoScroll();
      return;
    }
    const edgeSize = 72;
    let direction = 0;
    if (this.voiceSelectionLastY <= this.voiceSelectionViewportTop + edgeSize) direction = -1;
    if (this.voiceSelectionLastY >= this.voiceSelectionViewportBottom - edgeSize) direction = 1;
    if (direction === this.voiceSelectionAutoDirection && this.voiceSelectionAutoScrollId >= 0) return;
    this.stopVoiceSelectionAutoScroll();
    if (direction === 0 || this.voiceSelectionReachedBoundary(direction)) return;
    this.voiceSelectionAutoDirection = direction;
    this.voiceSelectionAutoScrollId = setInterval(() => {
      if (!this.voiceSelectionDragging || this.voiceSelectionReachedBoundary(direction)) {
        this.stopVoiceSelectionAutoScroll();
        return;
      }
      this.voiceListScroller.scrollBy(0, direction * 12);
      setTimeout(() => {
        if (!this.voiceSelectionDragging) return;
        this.applyVoiceSlideSelection(this.voiceAtPoint(
          this.voiceSelectionLastX, this.voiceSelectionLastY));
      }, 0);
    }, 24);
  }

  voiceSelectionReachedBoundary(direction: number): boolean {
    if (direction < 0) return this.voiceFirstVisibleIndex <= 0;
    // 三个分组标题和首尾占位同样计入 List 索引；只在列表真正到底时停止。
    return this.voiceListScroller.isAtEnd();
  }

  stopVoiceSelectionAutoScroll(): void {
    if (this.voiceSelectionAutoScrollId >= 0) {
      clearInterval(this.voiceSelectionAutoScrollId);
      this.voiceSelectionAutoScrollId = -1;
    }
    this.voiceSelectionAutoDirection = 0;
  }

  openVoiceActions(voice: HttpTTS, event?: GestureEvent): void {
    const finger = event && event.fingerList.length > 0 ? event.fingerList[0] : undefined;
    if (finger) {
      this.contextMenuX = finger.globalX;
      this.contextMenuY = finger.globalY;
    }
    this.actionVoiceId = String(voice.id);
    this.showVoiceActionMenu = true;
  }

  closeVoiceActions(): void {
    this.showVoiceActionMenu = false;
    this.actionVoiceId = '';
  }

  actionVoice(): HttpTTS | null {
    return this.voices.find((voice: HttpTTS) => String(voice.id) === this.actionVoiceId) || null;
  }

  openActionVoiceEdit(): void {
    const voice = this.actionVoice();
    if (!voice) return;
    this.closeVoiceActions();
    this.openEditDialog(voice);
  }

  toggleActionVoiceEnabled(): void {
    const voice = this.actionVoice();
    if (!voice) return;
    this.closeVoiceActions();
    this.toggleVoiceState(voice);
  }

  deleteActionVoice(): void {
    const voice = this.actionVoice();
    if (!voice) return;
    this.closeVoiceActions();
    this.deleteVoice(voice);
  }

  enterActionVoiceSelection(): void {
    const id = this.actionVoiceId;
    if (!id) return;
    this.closeVoiceActions();
    this.showAddDialog = false;
    this.enterSelectionMode();
    this.selectedVoiceIds = [this.customSelectionKey(id)];
  }

  syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, this.pageColor());
  }

  pageColor(): string {
    return ThemeRuntime.pageColor(this.appDarkMode);
  }

  cardColor(): string {
    return ThemeRuntime.cardColor(this.appDarkMode);
  }

  inputColor(): string {
    return ThemeRuntime.inputColor(this.appDarkMode);
  }

  primaryTextColor(): string {
    return ThemeRuntime.primaryTextColor(this.appDarkMode);
  }

  subTextColor(): string {
    return ThemeRuntime.subTextColor(this.appDarkMode);
  }

  accentColor(): string {
    return ThemeRuntime.accentColor(this.appDarkMode);
  }

  buttonColor(): string {
    return ThemeRuntime.buttonColor(this.appDarkMode);
  }

  @Builder
  addVoiceFloatingButton() {
    Stack() {
      ImmersiveMaterialSurface({
        surfaceWidth: 52,
        surfaceHeight: 52,
        darkMode: this.appDarkMode,
        fallbackColor: this.cardColor(),
        glowColor: `#40${this.accentColor().substring(1)}`
      }) {
        SymbolGlyph($r('sys.symbol.plus'))
          .fontSize(25)
          .fontColor([this.accentColor()])
      }
    }
    .width(52)
    .height(52)
    .margin({ right: AppSpacing.XXL, bottom: this.navBarHeight + 22 })
    .accessibilityText('新增自定义音色')
    .onClick(() => {
      this.showAddDialog = true;
    })
    .accessibilityRole(AccessibilityRoleType.BUTTON)
    .bindPopup(this.showAddDialog, ImmersiveMaterialRuntime.popupMenuOptions(this.immersiveLightLevel, (): void => {
      this.addDialog()
    }, Placement.TopRight, this.appDarkMode, this.accentColor(), () => {
      this.showAddDialog = false;
    }))
  }

  @Builder
  searchBar() {
    Row() {
      TextInput({ placeholder: '搜索音色', text: this.searchText })
        .layoutWeight(1)
        .height(40)
        .borderRadius(20)
        .backgroundColor(this.inputColor())
        .fontColor(this.primaryTextColor())
        .placeholderColor(this.subTextColor())
        .padding({ left: AppSpacing.XL, right: AppSpacing.XL })
        .onChange((value: string) => {
          this.searchText = value;
          this.pruneSelectedVoices();
        })
    }
    .width('100%')
    .padding({ top: AppSpacing.MD, bottom: AppSpacing.MD })
  }

  @Builder
  selectionHeader() {
    Row() {
      Text(this.isAllSelected() ? '☑' : '☐')
        .fontSize(AppFontSize.TITLE)
        .fontColor(this.accentColor())
        .width(28)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.toggleAllVoices();
        })
      Text(`已选择 ${this.selectedVoiceIds.length} 个音色`)
        .fontSize(AppFontSize.BODY)
        .fontColor(this.subTextColor())
        .margin({ left: AppSpacing.MD })
        .layoutWeight(1)
      Text(this.isAllSelected() ? '取消全选' : '全选')
        .fontSize(AppFontSize.BODY)
        .fontColor(this.accentColor())
        .onClick(() => {
          this.toggleAllVoices();
        })
    }
    .width('100%')
    .height(42)
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL })
  }

  @Builder
  voiceListItem(voice: HttpTTS) {
    Row() {
      if (this.selectionMode) {
        this.voiceSelectionSafeArea(this.customSelectionKey(String(voice.id)))
      }

      Column() {
        Text(voice.name || '未命名音色')
          .fontSize(AppFontSize.BODY_LARGE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.primaryTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text('自定义音色')
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
          .margin({ top: AppSpacing.XS })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(voice.enabled ? (this.isCurrentVoice(voice) ? '当前使用' : '已启用') : '已禁用')
          .fontSize(AppFontSize.CAPTION)
          .fontColor(voice.enabled ? ThemeRuntime.successColor(this.appDarkMode) : this.subTextColor())
          .margin({ top: AppSpacing.XS })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(AppSpacing.LG)
    .backgroundColor(this.cardColor())
    .borderRadius(ThemeRuntime.cardRadius())
    .opacity(voice.enabled ? 1 : 0.45)
    .onAreaChange((_oldValue: Area, area: Area) => { this.rememberVoiceSelectionArea(this.customSelectionKey(String(voice.id)), area); })
    .gesture(
      LongPressGesture({ repeat: false })
        .onAction((event: GestureEvent) => {
          if (!this.selectionMode && !this.isBatchOperating) {
            this.openVoiceActions(voice, event);
          }
        })
    )
    .onClick(() => {
      if (this.selectionMode) {
        if (Date.now() < this.voiceSelectionSuppressClickUntil) return;
        this.toggleVoiceSelected(voice);
      } else if (voice.enabled === false) {
        HdsFeedback.showToast('请先左滑启用该音色');
      } else {
        this.ttsCustomVoiceId = String(voice.id);
        this.ttsCloudVoiceId = '';
        this.saveSettings();
        HdsFeedback.showToast(`已选择 ${voice.name || '自定义音色'}`);
      }
    })
  }

  @Builder
  voiceDisableSwipeAction(voice: HttpTTS) {
    Column({ space: AppSpacing.XS }) {
      SymbolGlyph(voice.enabled ? $r('sys.symbol.minus_circle') : $r('sys.symbol.checkmark_circle'))
        .fontSize(22)
        .fontColor(['#FFFFFF'])
      Text(voice.enabled ? '禁用' : '启用')
        .fontSize(AppFontSize.CAPTION)
        .fontColor('#FFFFFF')
    }
    .width(64)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.buttonColor())
    .onClick(() => {
      if (!this.selectionMode) this.toggleVoiceState(voice);
    })
  }

  @Builder
  voiceDeleteSwipeAction(voice: HttpTTS) {
    Column({ space: AppSpacing.XS }) {
      SymbolGlyph($r('sys.symbol.trash'))
        .fontSize(22)
        .fontColor(['#FFFFFF'])
      Text('删除')
        .fontSize(AppFontSize.CAPTION)
        .fontColor('#FFFFFF')
    }
    .width(64)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(ThemeRuntime.dangerColor(this.appDarkMode))
    .onClick(() => {
      if (!this.selectionMode) this.deleteVoice(voice);
    })
  }

  @Builder
  voiceActionMenu() {
    Scroll() {
      Column() {
        this.voiceContextActionItem($r('sys.symbol.square_and_pencil'), '编辑', this.primaryTextColor(),
          () => this.openActionVoiceEdit())
        this.voiceContextActionItem(this.actionVoice()?.enabled ? $r('sys.symbol.minus_circle') :
          $r('sys.symbol.checkmark_circle'), this.actionVoice()?.enabled ? '禁用' : '启用', this.primaryTextColor(),
          () => this.toggleActionVoiceEnabled())
        this.voiceContextActionItem($r('sys.symbol.list_bullet'), '多选', this.primaryTextColor(),
          () => this.enterActionVoiceSelection())
        this.voiceContextActionItem($r('sys.symbol.trash'), '删除', ThemeRuntime.dangerColor(this.appDarkMode), () => this.deleteActionVoice())

      }
      .width('100%')
    }
    .width(176)
    .constraintSize({ maxHeight: ImmersiveMaterialRuntime.popupMenuMaxHeight() })
    .scrollBar(BarState.Off)
    .padding(ImmersiveMaterialRuntime.POPUP_MENU_PADDING)
  }

  @Builder
  voiceContextActionItem(icon: Resource, label: string, color: string, action: () => void) {
    PopupMenuAction(icon, label, color, action)
  }

  @Builder
  batchBar() {
    Row() {
      Button('启用')
        .layoutWeight(1)
        .height(42)
        .enabled(this.selectedVoiceIds.length > 0 && !this.isBatchOperating)
        .backgroundColor(this.buttonColor())
        .fontColor(ThemeRuntime.onAccentColor())
        .onClick(() => {
          this.batchSetEnabled(true);
        })
      Button('禁用')
        .layoutWeight(1)
        .height(42)
        .margin({ left: AppSpacing.MD })
        .enabled(this.selectedVoiceIds.length > 0 && !this.isBatchOperating)
        .backgroundColor(this.inputColor())
        .fontColor(this.primaryTextColor())
        .onClick(() => {
          this.batchSetEnabled(false);
        })
      Button('删除')
        .layoutWeight(1)
        .height(42)
        .margin({ left: AppSpacing.MD })
        .enabled(this.selectedVoiceIds.length > 0 && !this.isBatchOperating)
        .backgroundColor(ThemeRuntime.dangerColor(this.appDarkMode))
        .fontColor(ThemeRuntime.onAccentColor())
        .onClick(() => {
          this.batchDelete();
        })
    }
    .width('100%')
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.MD, bottom: this.navBarHeight + AppSpacing.LG })
    .backgroundColor(this.cardColor())
  }

  @Builder
  addDialog() {
    Scroll() {
      Column() {
        this.addVoiceMenuItem('手动新建', () => {
          this.showAddDialog = false;
          this.openCreateVoiceDialog();
        })
        this.addVoiceMenuItem('从 URL 导入', () => {
          this.showAddDialog = false;
          this.importUrl = '';
          this.openImportUrlDialog();
        })
        this.addVoiceMenuItem('从文件导入', () => {
          this.showAddDialog = false;
          this.importFromFile();
        })

      }
      .width('100%')
    }
    .width(176)
    .constraintSize({ maxHeight: ImmersiveMaterialRuntime.popupMenuMaxHeight() })
    .scrollBar(BarState.Off)
    .padding(ImmersiveMaterialRuntime.POPUP_MENU_PADDING)
  }

  @Builder
  addVoiceMenuItem(label: string, action: () => void) {
    PopupMenuAction(undefined, label, this.primaryTextColor(), action)
  }

  onSystemDialogFlagChanged(): void {
    if (!this.showImportUrlDialog) this.importUrlDialogSession.close(this.getUIContext());
  }

  openImportUrlDialog(): void {
    this.showImportUrlDialog = true;
    this.importUrlDialogSession.open(this.getUIContext(), (): void => {
      this.importUrlDialogContent();
    }, {
      autoCancel: true,
      maskColor: ThemeRuntime.scrimColor(this.appDarkMode),
      warnTag: '显示音色URL导入弹窗失败:'
    });
  }

  @Builder
  importUrlDialogContent() {
    Column() {
      Text('从URL导入')
        .fontSize(AppFontSize.SUBTITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ bottom: AppSpacing.LG })
      TextInput({ placeholder: '音色 JSON URL', text: this.importUrl })
        .width('100%')
        .height(44)
        .backgroundColor(this.inputColor())
        .fontColor(this.primaryTextColor())
        .placeholderColor(this.subTextColor())
        .onChange((value: string) => {
          this.importUrl = value;
        })
      Row({ space: AppSpacing.MD }) {
        Button('取消')
          .layoutWeight(1)
          .height(42)
          .backgroundColor(this.inputColor())
          .fontColor(this.primaryTextColor())
          .onClick(() => {
            this.showImportUrlDialog = false;
          })
        Button(this.isImporting ? '导入中' : '导入')
          .layoutWeight(1)
          .height(42)
          .backgroundColor(this.buttonColor())
          .fontColor(ThemeRuntime.onAccentColor())
          .enabled(!this.isImporting)
          .onClick(() => {
            this.importFromUrl();
          })
      }
      .width('100%')
      .margin({ top: AppSpacing.LG })
    }    .padding(AppSpacing.XXL)
  }


  @Builder
  editVoiceDialog() {
    Column() {
      Text(this.editingVoiceId ? '编辑自定义音色' : '新建自定义音色')
        .fontSize(AppFontSize.SUBTITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ bottom: AppSpacing.LG })

      Scroll() {
        Column({ space: AppSpacing.MD }) {
          this.editInput('名称', '音色名称', this.editName, (value: string) => {
            this.editName = value;
          })
          this.editInput('URL', '请求 URL', this.editUrl, (value: string) => {
            this.editUrl = value;
          })
          this.editInput('请求头', 'header，可留空', this.editHeader, (value: string) => {
            this.editHeader = value;
          })
          this.editInput('内容类型', 'contentType，可留空，如 audio/.*', this.editContentType, (value: string) => {
            this.editContentType = value;
          })
          this.editInput('并发率', 'concurrentRate，可留空', this.editConcurrentRate, (value: string) => {
            this.editConcurrentRate = value;
          })
          this.editInput('登录URL', 'loginUrl，可留空', this.editLoginUrl, (value: string) => {
            this.editLoginUrl = value;
          })
          this.editInput('登录UI', 'loginUi，可留空', this.editLoginUi, (value: string) => {
            this.editLoginUi = value;
          })
          this.editInput('登录检查JS', 'loginCheckJs，可留空', this.editLoginCheckJs, (value: string) => {
            this.editLoginCheckJs = value;
          })
          this.editInput('JS库', 'jsLib，可留空', this.editJsLib, (value: string) => {
            this.editJsLib = value;
          })
          this.editInput('JS引擎', 'jsEngine，兼容旧字段，可留空', this.editJsEngine, (value: string) => {
            this.editJsEngine = value;
          })
          Row() {
            Text('启用 CookieJar')
              .fontSize(AppFontSize.BODY_LARGE)
              .fontColor(this.primaryTextColor())
              .layoutWeight(1)
            AdaptiveSwitch({
              isOn: this.editEnabledCookieJar,
              onChange: (value: boolean) => {
                this.editEnabledCookieJar = value;
                this.saveVoiceEditDraft();
              }
            })
          }
          .width('100%')
          .padding({ top: AppSpacing.XS, bottom: AppSpacing.XS })
        }
        .width('100%')
      }
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .width('100%')
      .height(420)

      Row({ space: AppSpacing.MD }) {
        Button('取消')
          .layoutWeight(1)
          .height(42)
          .backgroundColor(this.inputColor())
          .fontColor(this.primaryTextColor())
          .onClick(() => {
            this.closeEditDialog();
          })
        Button('保存')
          .layoutWeight(1)
          .height(42)
          .backgroundColor(this.buttonColor())
          .fontColor(ThemeRuntime.onAccentColor())
          .onClick(() => {
            this.saveEditedVoice();
          })
      }
      .width('100%')
      .margin({ top: AppSpacing.LG })
    }
    .width('100%')
    .padding(AppSpacing.XXL)
  }

  syncShowEditDialog(): void {
    this.editVoiceDialogSession.sync(this.getUIContext(), this.showEditDialog, (): void => {
      this.editVoiceDialog();
    }, {
      autoCancel: false,
      maskColor: ThemeRuntime.scrimColor(this.appDarkMode),
      warnTag: '显示编辑音色弹窗失败:'
    });
  }

  @Builder
  editInput(label: string, placeholder: string, value: string, onChange: (value: string) => void) {
    Column() {
      Text(label)
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
        .width('100%')
        .margin({ bottom: AppSpacing.XS })
      TextInput({ placeholder, text: value })
        .width('100%')
        .height(42)
        .backgroundColor(this.inputColor())
        .fontColor(this.primaryTextColor())
        .placeholderColor(this.subTextColor())
        .onChange((nextValue: string) => {
          onChange(nextValue);
          this.saveVoiceEditDraft();
        })
    }
    .width('100%')
  }
}
