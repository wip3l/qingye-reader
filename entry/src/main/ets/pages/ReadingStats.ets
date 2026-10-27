import { promptAction, SymbolGlyphModifier } from '@kit.ArkUI';
import preferences from '@ohos.data.preferences';
import deviceInfo from '@ohos.deviceInfo';
import { HdsListItem, HdsSwipeActionOptions } from '@kit.UIDesignKit';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { syncSystemBars } from '../utils/SystemBars';
import { appDb, ReadStatsDeviceOption } from '../model/data/AppDatabase';
import { readStatsTracker } from '../core/stats/ReadStatsTracker';
import { ReadStatsDevice } from '../core/stats/ReadStatsDevice';
import { ReadStatsSummary, ReadStatsRank, ReadStatsBar } from '../core/stats/ReadStatsSummary';
import { AccountSessionStore } from '../account/AccountSessionStore';
import { HdsFeedback } from '../utils/HdsFeedback';
import { BookCover } from '../components/book/BookCover';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { PageScaffold } from '../components/common/PageScaffold';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';
import { PopupMenuAction } from '../components/common/PopupMenuAction';
import { ReadStatsPosterSnapshot, ReadStatsPosterSession } from '../core/stats/ReadStatsPosterModel';

const STATS_MODES: string[] = ['day', 'week', 'month', 'year', 'all'];
const STATS_MODE_LABELS: string[] = ['日', '周', '月', '年', '全部'];

interface ReadingStatsMetricDisplay {
  label: string;
  text: string;
}

/** 首项为页头，总览和排行共用一个惰性列表。 */
class ReadStatsListDataSource implements IDataSource {
  private rows: ReadStatsRank[] = [new ReadStatsRank()];
  private listeners: DataChangeListener[] = [];
  totalCount(): number { return this.rows.length; }
  getData(index: number): ReadStatsRank { return this.rows[index]; }
  registerDataChangeListener(listener: DataChangeListener): void { this.listeners.push(listener); }
  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((item: DataChangeListener): boolean => item !== listener);
  }
  update(rows: ReadStatsRank[]): void {
    this.rows = [new ReadStatsRank(), ...rows];
    this.listeners.forEach((listener: DataChangeListener): void => listener.onDataReloaded());
  }
}

@Entry
@Component
struct ReadingStatsPage {
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @StorageProp('readingStatsCloudRevision') @Watch('onCloudStatsChanged') cloudStatsRevision: number = 0;
  @StorageProp('accountUserId') @Watch('onStatsAccountChanged') statsAccountId: string = '';
  @State mode: string = 'week';
  @State anchorTs: number = Date.now();
  @State loading: boolean = true;
  @State errorMessage: string = '';
  @State summary: ReadStatsSummary = new ReadStatsSummary();
  @State selectedDevice: string = '';
  @State devices: ReadStatsDeviceOption[] = [];
  @State localDeviceId: string = '';
  @State selectedBar: string = '';
  @State showItemActionMenu: boolean = false;
  @State actionBookKey: string = '';
  @State contextMenuX: number = 16;
  @State contextMenuY: number = 96;
  private source: ReadStatsListDataSource = new ReadStatsListDataSource();
  private requestVersion: number = 0;
  private alive: boolean = true;
  private ownerId: string = '';
  private selectionWrite: Promise<void> = Promise.resolve();
  private viewReady: boolean = false;
  private initializationVersion: number = 0;
  private openingShare: boolean = false;

  aboutToAppear(): void { this.alive = true; this.initialize(); this.syncBars(); }
  aboutToDisappear(): void { this.alive = false; this.requestVersion++; this.initializationVersion++; }
  onPageShow(): void { this.syncBars(); }
  private onCloudStatsChanged(): void {
    if (this.alive && this.viewReady) this.loadStats();
  }
  private onStatsAccountChanged(): void {
    if (!this.alive || !this.viewReady || this.ownerId === this.statsAccountId) return;
    this.requestVersion++;
    this.ownerId = this.statsAccountId;
    this.selectedDevice = '';
    this.devices = [];
    this.summary = new ReadStatsSummary();
    this.source.update([]);
    this.initialize();
  }
  onBackPress(): boolean {
    if (!this.showItemActionMenu) return false;
    this.showItemActionMenu = false;
    return true;
  }

  private async initialize(): Promise<void> {
    const initialization = ++this.initializationVersion;
    try {
      const context = getContext(this);
      await AccountSessionStore.load(context);
      this.ownerId = AccountSessionStore.isLoggedIn() ? AccountSessionStore.account().userId : '';
      const ownerId = this.ownerId;
      const store = await preferences.getPreferences(context, 'reading_stats_view');
      const mode = await store.get('mode', 'week');
      const device = await store.get(`device:${this.ownerId}`, '');
      const localId = await ReadStatsDevice.id(context);
      if (!this.alive || initialization !== this.initializationVersion) return;
      const currentOwner = AccountSessionStore.isLoggedIn() ? AccountSessionStore.account().userId : '';
      if (currentOwner !== ownerId) { await this.initialize(); return; }
      this.localDeviceId = localId;
      this.mode = typeof mode === 'string' && STATS_MODES.includes(mode) ? mode : 'week';
      this.selectedDevice = typeof device === 'string' ? device : '';
      this.viewReady = true;
      await this.loadStats();
    } catch (error) {
      if (!this.alive) return;
      this.loading = false;
      this.errorMessage = '读取统计失败，请重试';
      console.warn('初始化阅读统计失败:', error);
    }
  }
  private async saveSelection(): Promise<void> {
    const mode = this.mode;
    const deviceId = this.selectedDevice;
    const ownerId = this.ownerId;
    this.selectionWrite = this.selectionWrite.catch(() => {}).then(async (): Promise<void> => {
      const store = await preferences.getPreferences(getContext(this), 'reading_stats_view');
      await store.put('mode', mode);
      await store.put(`device:${ownerId}`, deviceId);
      await store.flush();
    });
    try { await this.selectionWrite; } catch (error) { console.warn('保存统计筛选失败:', error); }
  }
  async loadStats(): Promise<void> {
    const version = ++this.requestVersion;
    const mode = this.mode;
    const anchor = this.anchorTs;
    const ownerId = this.ownerId;
    let deviceId = this.selectedDevice;
    this.loading = true;
    this.errorMessage = '';
    this.selectedBar = '';
    this.summary = new ReadStatsSummary();
    this.source.update([]);
    try {
      await appDb.init(getContext(this));
      await readStatsTracker.flushAndWait();
      const devices = await appDb.getReadStatsDevices(ownerId);
      if (!devices.some((item: ReadStatsDeviceOption): boolean => item.deviceId === this.localDeviceId)) {
        const local = new ReadStatsDeviceOption();
        local.deviceId = this.localDeviceId;
        local.deviceName = ReadStatsDevice.displayName();
        devices.unshift(local);
      }
      if (deviceId && !devices.some((item: ReadStatsDeviceOption): boolean => item.deviceId === deviceId)) deviceId = '';
      const range = ReadStatsSummary.range(mode, anchor);
      const rows = await appDb.getReadStatsByDayRange(range.startKey, range.endKey, deviceId, ownerId);
      if (!this.alive || version !== this.requestVersion || ownerId !== this.ownerId) return;
      this.devices = devices;
      this.selectedDevice = deviceId;
      this.summary = ReadStatsSummary.calculate(rows, mode, anchor, Date.now());
      this.source.update(this.summary.items);
    } catch (error) {
      if (!this.alive || version !== this.requestVersion) return;
      this.errorMessage = '读取统计失败，请重试';
      console.warn('读取阅读统计失败:', error);
    } finally {
      if (this.alive && version === this.requestVersion) this.loading = false;
    }
  }

  private periodOptions(): SelectOption[] {
    return STATS_MODE_LABELS.map((label: string): SelectOption => ({ value: label }));
  }
  private deviceOptions(): SelectOption[] {
    const options: SelectOption[] = [{ value: '全部设备' }];
    this.devices.forEach((item: ReadStatsDeviceOption): void => { options.push({ value: this.deviceLabel(item) }); });
    return options;
  }
  private deviceLabel(item: ReadStatsDeviceOption): string {
    if (item.deviceId === this.localDeviceId) return '本机';
    const label = item.deviceName || '未命名设备';
    const duplicates = this.devices.filter((device: ReadStatsDeviceOption): boolean =>
      device.deviceId !== this.localDeviceId && (device.deviceName || '未命名设备') === label);
    return duplicates.length > 1 ? `${label} · ${item.deviceId.slice(0, 4)}` : label;
  }
  private deviceIndex(): number {
    return this.selectedDevice ? this.devices.findIndex((item: ReadStatsDeviceOption): boolean => item.deviceId === this.selectedDevice) + 1 : 0;
  }
  private deviceTitle(): string {
    if (!this.selectedDevice) return this.devices.length > 1 ? '全部设备' : '本机';
    const item = this.devices.find((device: ReadStatsDeviceOption): boolean => device.deviceId === this.selectedDevice);
    return item ? this.deviceLabel(item) : '本机';
  }

  @Builder
  filters() {
    Row() {
      Column() {
        Select(this.periodOptions())
          .selected(STATS_MODES.indexOf(this.mode)).value(STATS_MODE_LABELS[STATS_MODES.indexOf(this.mode)])
          .font({ size: AppFontSize.BODY_LARGE, weight: FontWeight.Medium }).fontColor(this.primaryTextColor())
          .backgroundColor(this.cardColor()).borderRadius(ThemeRuntime.buttonRadius()).height(44)
          .optionFontColor(this.primaryTextColor()).selectedOptionFontColor(this.accentColor())
          .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.appDarkMode))
          .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode))
          .attributeModifier(ImmersiveMaterialRuntime.selectMenuModifier(this.immersiveLightLevel))
          .onSelect((index: number): void => {
            this.mode = STATS_MODES[index]; this.saveSelection(); this.loadStats();
          })
      }.alignItems(HorizontalAlign.Start)
      Blank()
      Column() {
        if (this.devices.length > 1) {
          Select(this.deviceOptions()).selected(this.deviceIndex()).value(this.deviceTitle())
            .font({ size: AppFontSize.BODY, weight: FontWeight.Medium }).fontColor(this.primaryTextColor())
            .backgroundColor(this.cardColor()).borderRadius(ThemeRuntime.buttonRadius()).height(44)
            .constraintSize({ maxWidth: 180 })
            .optionFontColor(this.primaryTextColor()).selectedOptionFontColor(this.accentColor())
            .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.appDarkMode))
            .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode))
            .attributeModifier(ImmersiveMaterialRuntime.selectMenuModifier(this.immersiveLightLevel))
            .onSelect((index: number): void => {
              this.selectedDevice = index === 0 ? '' : this.devices[index - 1].deviceId;
              this.saveSelection(); this.loadStats();
            })
        } else {
          Text('本机').fontSize(AppFontSize.BODY).fontColor(this.primaryTextColor()).height(44)
            .padding({ left: 18, right: 18 }).backgroundColor(this.cardColor()).borderRadius(ThemeRuntime.buttonRadius())
        }
      }.alignItems(HorizontalAlign.End)
    }.width('100%').margin({ bottom: AppSpacing.LG })
  }
  @Builder
  periodSelector() {
    Row() {
      if (this.mode !== 'all') {
        Button({ type: ButtonType.Normal }) {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(18).fontColor([this.subTextColor()])
        }.width(44).height(44).backgroundColor(Color.Transparent).accessibilityText('上一个统计周期')
          .onClick((): void => this.shiftPeriod(-1))
      }
      Text(this.periodTitle()).fontSize(AppFontSize.BODY).fontWeight(FontWeight.Medium)
        .fontColor(this.primaryTextColor()).layoutWeight(1).textAlign(TextAlign.Center).maxLines(2)
      if (this.mode !== 'all') {
        Button({ type: ButtonType.Normal }) {
          SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(18).fontColor([this.subTextColor()])
        }.width(44).height(44).backgroundColor(Color.Transparent).enabled(this.canGoForward())
          .opacity(this.canGoForward() ? 1 : 0.25).accessibilityText('下一个统计周期')
          .onClick((): void => this.shiftPeriod(1))
      }
    }.width('100%').constraintSize({ minHeight: 44 }).margin({ bottom: AppSpacing.MD })
  }
  @Builder
  metric($$: ReadingStatsMetricDisplay) {
    Column({ space: AppSpacing.SM }) {
      Text($$.text).fontSize(AppFontSize.BODY_LARGE).fontWeight(FontWeight.Medium).fontColor(this.primaryTextColor()).maxLines(2)
      Text($$.label).fontSize(AppFontSize.CAPTION).fontColor(this.subTextColor())
    }.layoutWeight(1).alignItems(HorizontalAlign.Start)
  }
  @Builder
  summaryCard() {
    Column({ space: AppSpacing.XL }) {
      Text('阅读总时长').fontSize(AppFontSize.BODY).fontColor(this.subTextColor())
      Text(this.loading || this.errorMessage ? '—' : ReadStatsSummary.duration(this.summary.totalMs))
        .fontSize(AppFontSize.DISPLAY).fontWeight(FontWeight.Bold).fontColor(this.primaryTextColor()).maxLines(2)
      Row({ space: AppSpacing.MD }) {
        this.metric({ label: '阅读书籍', text: this.loading || this.errorMessage ? '—' : `${this.summary.items.length} 本` })
        this.metric({ label: '阅读天数', text: this.loading || this.errorMessage ? '—' : `${this.summary.activeDays} 天` })
        this.metric({ label: '日均时长', text: this.loading || this.errorMessage ? '—' : ReadStatsSummary.duration(this.summary.averageMs) })
      }.width('100%')
    }.width('100%').alignItems(HorizontalAlign.Start).padding(AppSpacing.XXL)
      .borderRadius(ThemeRuntime.cardRadius()).backgroundColor(ThemeRuntime.accentSurfaceColor(this.appDarkMode))
  }
  private barHeight(bar: ReadStatsBar): number {
    const max = Math.max(1, ...this.summary.bars.map((item: ReadStatsBar): number => item.durationMs));
    return bar.durationMs > 0 ? Math.max(2, bar.durationMs / max * 120) : 0;
  }
  private chartTicks(): ReadStatsBar[] {
    const bars = this.summary.bars;
    if (bars.length <= 7) return bars;
    const ticks: ReadStatsBar[] = [];
    for (let index = 0; index < 6; index++) ticks.push(bars[Math.round(index * (bars.length - 1) / 5)]);
    return ticks;
  }
  private chartDetail(): string {
    const chosen = this.summary.bars.find((bar: ReadStatsBar): boolean => bar.key === this.selectedBar);
    if (chosen) return `${chosen.key} · ${ReadStatsSummary.duration(chosen.durationMs)}`;
    return this.mode === 'all' ? '按年汇总 · 点击查看时长' : this.mode === 'year' ? '按月汇总 · 点击查看时长' : '按天汇总 · 点击查看时长';
  }
  @Builder
  trendCard() {
    Column({ space: AppSpacing.LG }) {
      Row() {
        Text('阅读趋势').fontSize(AppFontSize.BODY_LARGE).fontWeight(FontWeight.Medium).fontColor(this.primaryTextColor())
        Blank()
        Text('时长').fontSize(AppFontSize.CAPTION).fontColor(this.subTextColor())
      }.width('100%')
      Row({ space: 3 }) {
        ForEach(this.summary.bars, (bar: ReadStatsBar) => {
          Column() {
            Row().width('70%').height(this.barHeight(bar)).borderRadius({ topLeft: 3, topRight: 3 })
              .backgroundColor(this.accentColor()).opacity(this.selectedBar === bar.key ? 1 : 0.65)
          }.height(124).justifyContent(FlexAlign.End).layoutWeight(1)
            .accessibilityText(`${bar.key}，${ReadStatsSummary.duration(bar.durationMs)}`)
            .onClick((): void => { this.selectedBar = bar.key; })
        }, (bar: ReadStatsBar): string => `${bar.key}:${bar.durationMs}`)
      }.width('100%')
      Row() {
        ForEach(this.chartTicks(), (bar: ReadStatsBar) => {
          Text(bar.label).fontSize(AppFontSize.CAPTION).fontColor(this.subTextColor()).maxLines(1)
        }, (bar: ReadStatsBar): string => bar.key)
      }.width('100%').justifyContent(FlexAlign.SpaceBetween)
      Text(this.chartDetail()).fontSize(AppFontSize.CAPTION).fontColor(this.subTextColor()).maxLines(2)
    }.width('100%').alignItems(HorizontalAlign.Start).padding(AppSpacing.XL)
      .backgroundColor(this.cardColor()).borderRadius(ThemeRuntime.cardRadius()).margin({ top: AppSpacing.LG })
  }
  @Builder
  headerContent() {
    Column() {
      this.filters()
      this.periodSelector()
      this.summaryCard()
      if (!this.loading && !this.errorMessage && this.summary.totalMs > 0 && this.mode !== 'day') { this.trendCard() }
      Text(this.selectedDevice === ReadStatsDevice.LEGACY_ID ? '历史导入 · 原设备来源未留存' : '阅读与听书合并计时')
        .fontSize(AppFontSize.CAPTION).fontColor(this.subTextColor()).margin({ top: AppSpacing.LG, bottom: AppSpacing.LG })
      Row() {
        Text('书籍排行').fontSize(AppFontSize.BODY_LARGE).fontWeight(FontWeight.Medium).fontColor(this.primaryTextColor())
        Blank()
        Text('按阅读时长').fontSize(AppFontSize.CAPTION).fontColor(this.subTextColor())
      }.width('100%').padding({ top: AppSpacing.SM, bottom: AppSpacing.LG })
      if (this.loading) {
        Row({ space: AppSpacing.MD }) {
          LoadingProgress().width(22).height(22).color(this.accentColor())
          Text('正在统计阅读时长').fontSize(AppFontSize.BODY).fontColor(this.subTextColor())
        }.height(120).width('100%').justifyContent(FlexAlign.Center)
      } else if (this.errorMessage) {
        Column({ space: AppSpacing.MD }) {
          Text(this.errorMessage).fontSize(AppFontSize.BODY).fontColor(this.subTextColor())
          Button('重试').fontColor(this.primaryTextColor()).backgroundColor(this.cardColor())
            .onClick((): void => { this.initialize(); })
        }.height(120).width('100%').justifyContent(FlexAlign.Center)
      } else if (this.summary.items.length === 0) {
        Column({ space: AppSpacing.LG }) {
          SymbolGlyph($r('sys.symbol.book')).fontSize(30).fontColor([this.subTextColor()])
          Text('该时段暂无阅读记录').fontSize(AppFontSize.BODY).fontColor(this.subTextColor())
        }.height(140).width('100%').justifyContent(FlexAlign.Center).backgroundColor(this.cardColor())
          .borderRadius(ThemeRuntime.cardRadius())
      }
    }.width('100%').padding({ top: AppSpacing.LG })
  }
  @Builder
  bookRow(item: ReadStatsRank) {
    Row({ space: AppSpacing.MD }) {
      Text(`${item.rank}`.padStart(2, '0')).fontSize(AppFontSize.CAPTION).fontColor(this.subTextColor()).width(22)
      BookCover({ bookUrl: item.bookUrl, name: item.name, author: item.author,
        coverUrl: item.coverUrl, placeholderColor: this.accentColor() }).width(40).height(56)
      Column({ space: AppSpacing.SM }) {
        Row({ space: AppSpacing.MD }) {
          Text(item.name).fontSize(AppFontSize.BODY_LARGE).fontWeight(FontWeight.Medium)
            .fontColor(this.primaryTextColor()).layoutWeight(1).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(ReadStatsSummary.duration(item.durationMs)).fontSize(AppFontSize.CAPTION)
            .fontColor(this.primaryTextColor()).constraintSize({ maxWidth: 100 }).maxLines(2)
        }.width('100%')
        Row({ space: AppSpacing.SM }) {
          Text(`${item.author}${!item.onShelf ? `${item.author ? ' · ' : ''}本机未上架` : ''}`)
            .fontSize(AppFontSize.CAPTION).fontColor(this.subTextColor()).layoutWeight(1).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(item.percent < 1 ? '<1%' : `${Math.round(item.percent)}%`).fontSize(AppFontSize.CAPTION).fontColor(this.subTextColor())
        }.width('100%')
        Stack({ alignContent: Alignment.Start }) {
          Row().width('100%').height(3).backgroundColor(this.softColor())
          Row().width(`${item.percent}%`).height(3).backgroundColor(this.accentColor())
        }.width('100%').borderRadius(2).clip(true)
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
    }.width('100%').padding(AppSpacing.XL).backgroundColor(this.cardColor())
      .borderRadius(ThemeRuntime.cardRadius()).alignItems(VerticalAlign.Center)
      .gesture(LongPressGesture({ repeat: false }).onAction((event: GestureEvent): void => {
        const finger = event.fingerList.length > 0 ? event.fingerList[0] : undefined;
        if (finger) { this.contextMenuX = finger.globalX; this.contextMenuY = finger.globalY; }
        this.actionBookKey = item.bookKey;
        this.showItemActionMenu = true;
      }))
  }
  private itemSwipeActions(item: ReadStatsRank): HdsSwipeActionOptions {
    return { icons: [{ icon: new SymbolGlyphModifier($r('sys.symbol.trash')),
      backgroundColor: ThemeRuntime.dangerColor(this.appDarkMode),
      iconOptions: { accessibilityText: '删除记录' }, onAction: () => this.confirmDeleteItem(item) }] };
  }
  @Builder
  deleteSwipeButton(item: ReadStatsRank) {
    Button('删除').height('100%').width(64).backgroundColor(ThemeRuntime.dangerColor(this.appDarkMode))
      .onClick((): void => { this.confirmDeleteItem(item); })
  }
  @Builder
  itemActionMenu() {
    Column() {
      PopupMenuAction($r('sys.symbol.trash'), '删除记录', ThemeRuntime.dangerColor(this.appDarkMode), (): void => {
        const item = this.summary.items.find((book: ReadStatsRank): boolean => book.bookKey === this.actionBookKey);
        this.showItemActionMenu = false;
        if (item) this.confirmDeleteItem(item);
      })
    }.width(176).padding(ImmersiveMaterialRuntime.POPUP_MENU_PADDING)
  }
  async confirmDeleteItem(item: ReadStatsRank): Promise<void> {
    const range = ReadStatsSummary.range(this.mode, this.anchorTs);
    const deviceId = this.selectedDevice;
    const ownerId = this.ownerId;
    try {
      const confirmation = await promptAction.showDialog({ title: '删除阅读记录',
        message: `删除“${item.name}”在 ${this.periodTitle()}、${this.deviceTitle()} 范围内已获取的阅读记录？开启同步后会同步删除，尚未上传的其他设备记录不受影响。不会删除书籍。`,
        buttons: [{ text: '取消', color: this.subTextColor() }, { text: '删除', color: ThemeRuntime.dangerColor(this.appDarkMode) }] });
      if (confirmation.index !== 1) return;
      await readStatsTracker.flushAndWait();
      await appDb.deleteReadStatsSelection(item.bookKey, range.startKey, range.endKey, deviceId, ownerId);
      if (this.alive) await this.loadStats();
      HdsFeedback.showToast('记录已删除');
    } catch (error) { console.warn('删除阅读记录失败:', error); HdsFeedback.showToast('删除失败，请重试'); }
  }
  private shiftPeriod(step: number): void {
    if (step > 0 && !this.canGoForward()) return;
    this.anchorTs = ReadStatsSummary.shift(this.mode, this.anchorTs, step);
    this.loadStats();
  }
  private canGoForward(): boolean {
    return this.mode !== 'all' && ReadStatsSummary.range(this.mode,
      ReadStatsSummary.shift(this.mode, this.anchorTs, 1)).startTs <= Date.now();
  }
  private periodTitle(): string {
    const d = new Date(this.anchorTs);
    if (this.mode === 'all') return '全部阅读记录';
    if (this.mode === 'year') return `${d.getFullYear()}年`;
    if (this.mode === 'month') return `${d.getFullYear()}年${d.getMonth() + 1}月`;
    if (this.mode === 'day') return `${d.getFullYear()}年${d.getMonth() + 1}月${d.getDate()}日`;
    const range = ReadStatsSummary.range(this.mode, this.anchorTs);
    const start = new Date(range.startTs);
    const end = new Date(range.endTs);
    return `${start.getFullYear()}年${start.getMonth() + 1}月${start.getDate()}日 — ` +
      `${start.getFullYear() !== end.getFullYear() ? `${end.getFullYear()}年` : ''}${end.getMonth() + 1}月${end.getDate()}日`;
  }
  pageColor(): string { return ThemeRuntime.pageColor(this.appDarkMode); }
  private async shareStatistics(): Promise<void> {
    if (this.loading || this.errorMessage || this.openingShare) return;
    if (this.summary.totalMs <= 0) {
      this.getUIContext().getPromptAction().showToast({ message: '该时段暂无阅读记录' });
      return;
    }
    if (this.ownerId !== (AccountSessionStore.isLoggedIn() ? AccountSessionStore.account().userId : '')) return;
    const account = AccountSessionStore.account();
    this.openingShare = true;
    ReadStatsPosterSession.put(ReadStatsPosterSnapshot.capture(this.summary, this.ownerId, this.mode,
      this.periodTitle(), this.deviceTitle(), this.ownerId ? account.displayName : '', this.ownerId ? account.avatarUrl : ''));
    try { await this.getUIContext().getRouter().pushUrl({ url: 'pages/ReadingStatsShare' }); }
    catch (_) {
      ReadStatsPosterSession.take();
      this.getUIContext().getPromptAction().showToast({ message: '打开分享页面失败，请重试' });
    } finally { this.openingShare = false; }
  }
  @Builder
  shareAction() {
    Button() {
      SymbolGlyph($r('sys.symbol.share')).fontSize(22).fontColor([this.primaryTextColor()])
    }.width(44).height(44).backgroundColor(Color.Transparent).accessibilityText('分享阅读统计')
      .enabled(!this.loading && !this.errorMessage)
      .onClick((): void => { this.shareStatistics(); })
  }
  cardColor(): string { return ThemeRuntime.cardColor(this.appDarkMode); }
  softColor(): string { return ThemeRuntime.inputColor(this.appDarkMode); }
  primaryTextColor(): string { return ThemeRuntime.primaryTextColor(this.appDarkMode); }
  subTextColor(): string { return ThemeRuntime.subTextColor(this.appDarkMode); }
  accentColor(): string { return ThemeRuntime.accentColor(this.appDarkMode); }
  syncBars(): void { syncSystemBars(getContext(this), this.appDarkMode, this.pageColor()); }
  @Builder
  pageContent() {
    List({ space: AppSpacing.SM }) {
      LazyForEach(this.source, (item: ReadStatsRank) => {
        if (!item.bookKey) {
          ListItem() { this.headerContent() }
            .padding({ left: AppSpacing.XL, right: AppSpacing.XL }).clip(false)
        } else if (deviceInfo.sdkApiVersion >= 26) {
          HdsListItem({ customItemBuilder: (): void => { this.bookRow(item) }, swipeActionOptions: this.itemSwipeActions(item) })
            .margin({ left: AppSpacing.XL, right: AppSpacing.XL })
        } else {
          ListItem() { this.bookRow(item) }
            .margin({ left: AppSpacing.XL, right: AppSpacing.XL })
            .swipeAction({ end: { builder: (): void => { this.deleteSwipeButton(item) } }, edgeEffect: SwipeEdgeEffect.Spring })
        }
      }, (item: ReadStatsRank): string => item.bookKey ? `${item.bookKey}:${item.durationMs}:${item.percent}:${item.rank}:${item.name}:${item.onShelf}` : 'header')
    }.width('100%').height('100%').cachedCount(4).scrollBar(BarState.Off)
      // Keep horizontal gutters inside the items: List clips at its padded viewport,
      // which otherwise cuts off the Select shadows at both content edges.
      .padding({ bottom: this.navBarHeight + AppSpacing.XXL })
      .constraintSize({ maxWidth: 760 }).align(Alignment.Top)
  }
  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      PageScaffold({ title: '阅读统计', scrollable: false, collapsible: false,
        actions: (): void => { this.shareAction() }, content: (): void => { this.pageContent() } })
      Column().width(1).height(1).position({ x: this.contextMenuX, y: this.contextMenuY }).hitTestBehavior(HitTestMode.None)
        .bindPopup(this.showItemActionMenu, ImmersiveMaterialRuntime.popupMenuOptions(this.immersiveLightLevel,
          (): void => { this.itemActionMenu() }, Placement.BottomLeft, this.appDarkMode, this.accentColor(),
          (): void => { this.showItemActionMenu = false; }))
    }.width('100%').height('100%').backgroundColor(this.pageColor())
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
