import { promptAction, SymbolGlyphModifier } from '@kit.ArkUI';
import preferences from '@ohos.data.preferences';
import deviceInfo from '@ohos.deviceInfo';
import { HdsListItem, HdsSwipeActionOptions } from '@kit.UIDesignKit';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { syncSystemBars } from '../utils/SystemBars';
import { appDb, ReadStatsDeviceOption } from '../model/data/AppDatabase';
import { readStatsTracker } from '../core/stats/ReadStatsTracker';
import { ReadStatsDevice } from '../core/stats/ReadStatsDevice';
import { ReadStatsSummary, ReadStatsRank, ReadStatsBar, ReadWorkMergeGroup, ReadWorkMergeMember,
  ReadWorkMerges, READ_STATS_SORTS, READ_STATS_SORT_LABELS } from '../core/stats/ReadStatsSummary';
import { ReadWorkMergeStore } from '../utils/ReadWorkMergeStore';
import { ReadStatsFold } from '../core/stats/ReadStatsFold';
import { AccountSessionStore } from '../account/AccountSessionStore';
import { HdsFeedback } from '../utils/HdsFeedback';
import { ListDissolve } from '../utils/ListDissolve';
import { DeleteParticleBurst, DeleteParticleLayer } from '../components/common/DeleteParticles';
import { BookCover } from '../components/book/BookCover';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { PageScaffold } from '../components/common/PageScaffold';
import { CollapsingHeader } from '../utils/CollapsingHeader';
import { ImmersiveHeaderAction } from '../components/ImmersiveHeaderAction';
import { ImmersiveMaterialSurface } from '../components/ImmersiveMaterialSurface';
import { AdaptiveSwitch } from '../components/AdaptiveSwitch';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';
import { PopupMenuAction } from '../components/common/PopupMenuAction';
import { ReadStatsPosterSnapshot, ReadStatsPosterSession } from '../core/stats/ReadStatsPosterModel';
import { ReadStatsSettingsStore } from '../utils/ReadStatsSettingsStore';

const STATS_MODES: string[] = ['day', 'week', 'month', 'year', 'all'];
const STATS_MODE_LABELS: string[] = ['日', '周', '月', '年', '全部'];
/** 多选底部胶囊：宽、高，以及列表末尾为它多留的高度（胶囊 + 上方范围说明 + 间距）。 */
const SELECTION_DOCK_WIDTH: number = 252;
const SELECTION_DOCK_HEIGHT: number = 54;
const SELECTION_DOCK_SPACE: number = 104;

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
  /** 删掉一本书的那一行，走 onDataDelete 让 List 播补位动画。 */
  remove(bookKey: string): void {
    const index = this.rows.findIndex((row: ReadStatsRank): boolean => !!row.bookKey && row.bookKey === bookKey);
    if (index < 0) return;
    this.rows.splice(index, 1);
    this.listeners.forEach((listener: DataChangeListener): void => listener.onDataDelete(index));
  }
}

@Entry
@Component
struct ReadingStatsPage {
  @StorageProp('applicationFontFamily') applicationFontFamily: string = '';
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @State headerCollapse: number = 0;
  private headerScroller: Scroller = new Scroller();
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
  @State showMoreMenu: boolean = false;
  /** 书籍排行的排序依据，见 READ_STATS_SORTS；“日”视图下按天数会退回按时长，见 ReadStatsSummary.effectiveSort。 */
  @State sortKey: string = 'duration';
  @State showSortMenu: boolean = false;
  @StorageProp('readStatsRecording') statsRecording: boolean = true;
  @StorageProp('readStatsCountListening') statsCountListening: boolean = true;
  @State actionBookKey: string = '';
  @State contextMenuX: number = 16;
  @State contextMenuY: number = 96;
  /** 合并面板与“已合并的记录”面板共用一个半模态，recordSheetMode 取 merge / merged。 */
  @State showRecordSheet: boolean = false;
  @State recordSheetMode: string = 'merge';
  @State mergeSourceKey: string = '';
  @State mergeTargetKey: string = '';
  @State mergeMainKey: string = '';
  @State mergeKeyword: string = '';
  @State mergedSheetKey: string = '';
  /** 排行里书名相同却分成几行的第一组，见 ReadStatsSummary.sameTitleItems。 */
  @State sameTitleRows: ReadStatsRank[] = [];
  /** 合并关系变了加一，让“已合并的记录”面板重读。 */
  @State mergeRevision: number = 0;
  /** 排行多选：勾选的行按 bookKey 记；多选时页头只留排行标题，底部浮出“合并 / 删除”胶囊，左滑删除关掉。 */
  @State selecting: boolean = false;
  @State selectedKeys: string[] = [];
  /** “合并所选”面板（recordSheetMode 为 mergeMany）里参与合并的各行 workKey。 */
  @State mergeSelection: string[] = [];
  private merges: ReadWorkMergeGroup[] = [];
  private ignoredTitles: string[] = [];
  private fold: ((text: string) => string) | null = null;
  private source: ReadStatsListDataSource = new ReadStatsListDataSource();
  /** 正在消散的书 key，见 ListDissolve。 */
  @State dissolvingBookKeys: string[] = [];
  @State deleteParticleBursts: DeleteParticleBurst[] = [];
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
    this.selecting = false;
    this.selectedKeys = [];
    this.ownerId = this.statsAccountId;
    this.selectedDevice = '';
    this.devices = [];
    this.summary = new ReadStatsSummary();
    this.source.update([]);
    this.initialize();
  }
  onBackPress(): boolean {
    if (this.showRecordSheet) { this.showRecordSheet = false; return true; }
    if (this.showMoreMenu) { this.showMoreMenu = false; return true; }
    if (this.showSortMenu) { this.showSortMenu = false; return true; }
    if (this.showItemActionMenu) { this.showItemActionMenu = false; return true; }
    if (!this.selecting) return false;
    this.exitSelection();
    return true;
  }
  /** 从长按菜单进入时把那一行先勾上；从“选择”进入时传空。 */
  private enterSelection(bookKey: string): void {
    this.selectedKeys = bookKey ? [bookKey] : [];
    this.selecting = true;
    this.source.update(this.rankedItems());
  }
  private exitSelection(): void {
    if (!this.selecting) return;
    this.selecting = false;
    this.selectedKeys = [];
    this.source.update(this.rankedItems());
  }
  private toggleSelected(bookKey: string): void {
    this.selectedKeys = this.selectedKeys.includes(bookKey) ?
      this.selectedKeys.filter((key: string): boolean => key !== bookKey) : [...this.selectedKeys, bookKey];
  }
  private allSelected(): boolean {
    return this.summary.items.length > 0 && this.selectedKeys.length >= this.summary.items.length;
  }
  private toggleAllSelected(): void {
    this.selectedKeys = this.allSelected() ? [] : this.summary.items.map((item: ReadStatsRank): string => item.bookKey);
  }
  /** 勾选的行，按当前排行顺序。 */
  private selectedRows(): ReadStatsRank[] {
    return this.rankedItems().filter((item: ReadStatsRank): boolean => this.selectedKeys.includes(item.bookKey));
  }
  private pageTitle(): string {
    if (!this.selecting) return '阅读统计';
    return this.selectedKeys.length > 0 ? `已选 ${this.selectedKeys.length} 条` : '选择记录';
  }
  private handleBack(): void {
    if (this.selecting) { this.exitSelection(); return; }
    this.getUIContext().getRouter().back();
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
      const sort = await store.get('sort', 'duration');
      const localId = await ReadStatsDevice.id(context);
      if (!this.alive || initialization !== this.initializationVersion) return;
      const currentOwner = AccountSessionStore.isLoggedIn() ? AccountSessionStore.account().userId : '';
      if (currentOwner !== ownerId) { await this.initialize(); return; }
      this.localDeviceId = localId;
      this.mode = typeof mode === 'string' && STATS_MODES.includes(mode) ? mode : 'week';
      this.selectedDevice = typeof device === 'string' ? device : '';
      this.sortKey = typeof sort === 'string' && READ_STATS_SORTS.includes(sort) ? sort : 'duration';
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
  private chooseSort(sort: string): void {
    this.showSortMenu = false;
    if (sort === this.sortKey) return;
    this.sortKey = sort;
    this.source.update(this.rankedItems());
    this.selectionWrite = this.selectionWrite.catch(() => {}).then(async (): Promise<void> => {
      const store = await preferences.getPreferences(getContext(this), 'reading_stats_view');
      await store.put('sort', sort);
      await store.flush();
    });
    this.selectionWrite.catch((error: Error) => { console.warn('保存排行排序失败:', error); });
  }
  private shownSort(): string { return ReadStatsSummary.effectiveSort(this.sortKey, this.mode); }
  private rankedItems(): ReadStatsRank[] {
    return ReadStatsSummary.sortItems(this.summary.items, this.sortKey, this.mode);
  }
  /** 第二行右侧：按时长排显示占比，按最近阅读、阅读天数排显示排序依据。 */
  private rowMetric(item: ReadStatsRank): string {
    const sort = this.shownSort();
    if (sort === 'recent') {
      const label = ReadStatsSummary.recentLabel(item, this.mode, Date.now());
      if (label) return label;
    } else if (sort === 'days') {
      return `读了 ${item.readDays} 天`;
    }
    return item.percent < 1 ? '<1%' : `${Math.round(item.percent)}%`;
  }
  private rowMetricHighlighted(): boolean {
    const sort = this.shownSort();
    return sort === 'recent' || sort === 'days';
  }
  /** quiet 为 true 时原位重读：不清空列表、不显示加载中，删除记录补位后用，避免列表整个闪一下。 */
  async loadStats(quiet: boolean = false): Promise<void> {
    const version = ++this.requestVersion;
    const mode = this.mode;
    const anchor = this.anchorTs;
    const ownerId = this.ownerId;
    let deviceId = this.selectedDevice;
    this.errorMessage = '';
    if (!quiet) {
      this.loading = true;
      this.sameTitleRows = [];
      this.selectedBar = '';
      this.summary = new ReadStatsSummary();
      this.source.update([]);
    }
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
      const fold = await ReadStatsFold.load(getContext(this));
      const merges = await ReadWorkMergeStore.load(getContext(this));
      const ignoredTitles = await ReadWorkMergeStore.loadIgnoredTitles(getContext(this));
      if (!this.alive || version !== this.requestVersion || ownerId !== this.ownerId) return;
      this.devices = devices;
      this.selectedDevice = deviceId;
      this.fold = fold;
      this.merges = merges;
      this.ignoredTitles = ignoredTitles;
      this.summary = ReadStatsSummary.calculate(rows, mode, anchor, Date.now(), fold, merges);
      this.sameTitleRows = ReadStatsSummary.sameTitleItems(this.summary.items, fold, ignoredTitles);
      this.mergeRevision++;
      if (this.selecting) {
        // 重读后行可能合并、消失，勾选只留还在的行；没有记录可选就退出多选。
        const keys = this.summary.items.map((item: ReadStatsRank): string => item.bookKey);
        this.selectedKeys = this.selectedKeys.filter((key: string): boolean => keys.includes(key));
        if (keys.length === 0) { this.selecting = false; this.selectedKeys = []; }
      }
      this.source.update(this.rankedItems());
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
          .font({ size: AppFontSize.BODY_LARGE, weight: FontWeight.Medium, family: this.applicationFontFamily }).fontColor(this.primaryTextColor())
          .optionFont({ family: this.applicationFontFamily })
          .selectedOptionFont({ family: this.applicationFontFamily })
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
            .font({ size: AppFontSize.BODY, weight: FontWeight.Medium, family: this.applicationFontFamily }).fontColor(this.primaryTextColor())
            .optionFont({ family: this.applicationFontFamily })
            .selectedOptionFont({ family: this.applicationFontFamily })
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
      // 多选时收起筛选、总览和图表，只留排行：时段和设备在多选期间不能换，删除范围始终是进入时那一个。
      if (!this.selecting) {
        this.filters()
        if (!this.statsRecording) { this.pausedBanner() }
        this.periodSelector()
        this.summaryCard()
        if (!this.loading && !this.errorMessage && this.summary.totalMs > 0 && this.mode !== 'day') { this.trendCard() }
        Text(this.statsCaption())
          .fontSize(AppFontSize.CAPTION).fontColor(this.subTextColor()).margin({ top: AppSpacing.LG, bottom: AppSpacing.LG })
      }
      Row() {
        Text('书籍排行').fontSize(AppFontSize.BODY_LARGE).fontWeight(FontWeight.Medium).fontColor(this.primaryTextColor())
        Blank()
        if (!this.selecting && !this.loading && !this.errorMessage && this.summary.items.length > 0) {
          Text('选择').fontSize(AppFontSize.BODY).fontWeight(FontWeight.Medium).fontColor(this.accentColor())
            .height(32).padding({ left: AppSpacing.MD, right: AppSpacing.SM }).accessibilityText('多选阅读记录')
            .onClick((): void => this.enterSelection(''))
        }
        Row({ space: AppSpacing.XS }) {
          Text(`按${READ_STATS_SORT_LABELS[READ_STATS_SORTS.indexOf(this.shownSort())]}`)
            .fontSize(AppFontSize.CAPTION).fontColor(this.subTextColor())
          SymbolGlyph($r('sys.symbol.chevron_down')).fontSize(12).fontColor([this.subTextColor()])
        }.height(32).padding({ left: AppSpacing.SM }).accessibilityText('书籍排行排序')
          .onClick((): void => { this.showSortMenu = !this.showSortMenu; })
          .bindPopup(this.showSortMenu, ImmersiveMaterialRuntime.popupMenuOptions(this.immersiveLightLevel,
            (): void => { this.sortMenu(); }, Placement.BottomRight, this.appDarkMode, this.accentColor(),
            (): void => { this.showSortMenu = false; }))
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
      } else if (this.sameTitleRows.length > 1 && !this.selecting) {
        this.sameTitleHint()
      }
    }.width('100%').padding({ top: AppSpacing.LG })
  }
  @Builder
  sortMenu() {
    Column() {
      ForEach(READ_STATS_SORTS, (sort: string, index: number) => {
        this.sortMenuRow(sort, READ_STATS_SORT_LABELS[index])
      }, (sort: string): string => sort)
    }.width(200).padding(ImmersiveMaterialRuntime.POPUP_MENU_PADDING)
  }
  /** 选中状态在这里读 this.sortKey，不靠传值。 */
  @Builder
  sortMenuRow(sort: string, label: string) {
    Row({ space: 10 }) {
      Column({ space: 2 }) {
        Text(label).fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.shownSort() === sort ? this.accentColor() : this.primaryTextColor())
          .fontWeight(this.shownSort() === sort ? FontWeight.Medium : FontWeight.Normal)
        if (sort === 'days' && this.mode === 'day') {
          Text('“日”视图下都是 1 天').fontSize(AppFontSize.MICRO).fontColor(this.subTextColor())
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      if (this.shownSort() === sort) {
        SymbolGlyph($r('sys.symbol.checkmark')).fontSize(16).fontColor([this.accentColor()])
      }
    }.width('100%').constraintSize({ minHeight: 44 }).padding({ left: 12, right: 12 })
      .borderRadius(ImmersiveMaterialRuntime.POPUP_MENU_RADIUS - ImmersiveMaterialRuntime.POPUP_MENU_PADDING)
      .stateStyles({ normal: { .backgroundColor(Color.Transparent) }, pressed: { .backgroundColor('#1A808080') } })
      .opacity(sort === 'days' && this.mode === 'day' ? 0.38 : 1)
      .enabled(!(sort === 'days' && this.mode === 'day'))
      .onClick((): void => this.chooseSort(sort))
  }
  /** 书名相同却分成几行时提示一次合并；点叉记住这个书名不是同一本，不再提示。 */
  @Builder
  sameTitleHint() {
    Row({ space: AppSpacing.MD }) {
      Text(`“${this.sameTitleRows[0].name}”有 ${this.sameTitleRows.length} 条记录，可能是同一本`)
        .fontSize(AppFontSize.CAPTION).fontColor(this.primaryTextColor()).layoutWeight(1).maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text('合并').fontSize(AppFontSize.BODY).fontWeight(FontWeight.Medium).fontColor(this.accentColor())
        .height(36).padding({ left: AppSpacing.MD, right: AppSpacing.MD })
        .onClick((): void => this.openMergeSheet(this.sameTitleRows[0].workKey, this.sameTitleRows[1].workKey))
      SymbolGlyph($r('sys.symbol.xmark')).fontSize(14).fontColor([this.subTextColor()])
        .width(36).height(36).accessibilityText('不是同一本，不再提示')
        .onClick((): void => this.ignoreSameTitle())
    }.width('100%').padding({ left: AppSpacing.LG, right: AppSpacing.XS, top: AppSpacing.XS, bottom: AppSpacing.XS })
      .backgroundColor(this.cardColor()).borderRadius(ThemeRuntime.cardRadius())
      .border({ width: 1, color: this.accentColor(), style: BorderStyle.Dashed })
  }
  private ignoreSameTitle(): void {
    if (this.sameTitleRows.length === 0) return;
    const title = ReadStatsSummary.titleKey(this.sameTitleRows[0].name, this.fold);
    this.ignoredTitles = [...this.ignoredTitles, title];
    this.sameTitleRows = ReadStatsSummary.sameTitleItems(this.summary.items, this.fold, this.ignoredTitles);
    ReadWorkMergeStore.saveIgnoredTitles(getContext(this), this.ignoredTitles).catch((error: Error): void => {
      console.warn('保存同名提示设置失败:', error);
    });
  }

  private itemByWork(workKey: string): ReadStatsRank | undefined {
    return this.summary.items.find((item: ReadStatsRank): boolean => item.workKey === workKey);
  }
  /** 一行里在当前时段有记录的各部作品；没合并过的就是它自己。 */
  private editionsOf(item: ReadStatsRank | undefined): ReadStatsRank[] {
    if (!item) return [];
    return item.editions.length > 0 ? item.editions : [item];
  }
  /** 一行对应的合并成员：合并过的取整组（含当前时段没有记录的），否则是它自己。 */
  private membersOf(item: ReadStatsRank): ReadWorkMergeMember[] {
    const group = item.mergedWorks > 0 ? ReadWorkMerges.find(this.merges, item.workKey) : undefined;
    if (group) return group.members;
    const member = new ReadWorkMergeMember();
    member.work = item.workKey;
    member.name = item.name;
    member.author = item.author;
    return [member];
  }
  openMergeSheet(sourceKey: string, targetKey: string = ''): void {
    this.mergeSourceKey = sourceKey;
    this.mergeKeyword = '';
    this.recordSheetMode = 'merge';
    this.chooseMergeTarget(targetKey);
    this.showRecordSheet = true;
  }
  /** 定下合并目标，显示用的那部默认取书架上时长最多的，都不在架就取时长最多的。 */
  chooseMergeTarget(targetKey: string): void {
    this.mergeTargetKey = targetKey;
    this.mergeMainKey = targetKey ? this.defaultMergeMain() : '';
  }
  private defaultMergeMain(): string {
    const options = this.mergeMainOptions();
    const onShelf = options.filter((item: ReadStatsRank): boolean => item.onShelf);
    const pool = onShelf.length > 0 ? onShelf : options;
    let best = '';
    let bestMs = -1;
    for (const item of pool) {
      if (item.durationMs > bestMs) { best = item.workKey; bestMs = item.durationMs; }
    }
    return best;
  }
  /** 多选里“合并”：所选各行一起并成一条，显示用的那部同样默认书架上时长最多的。 */
  openMergeSelectionSheet(): void {
    const rows = this.selectedRows();
    if (rows.length < 2) return;
    this.mergeSelection = rows.map((item: ReadStatsRank): string => item.workKey);
    this.recordSheetMode = 'mergeMany';
    this.mergeMainKey = this.defaultMergeMain();
    this.showRecordSheet = true;
  }
  mergeSelectionRows(): ReadStatsRank[] {
    const rows: ReadStatsRank[] = [];
    this.mergeSelection.forEach((key: string): void => {
      const item = this.itemByWork(key);
      if (item) rows.push(item);
    });
    return rows;
  }
  confirmMergeSelection(): void {
    const rows = this.mergeSelectionRows();
    if (rows.length < 2 || !this.mergeMainKey) return;
    const members: ReadWorkMergeMember[] = [];
    rows.forEach((item: ReadStatsRank): void => { members.push(...this.membersOf(item)); });
    const next = ReadWorkMerges.combine(this.merges, members, this.mergeMainKey);
    this.showRecordSheet = false;
    this.selecting = false;
    this.selectedKeys = [];
    this.saveMerges(next, `已把 ${rows.length} 条合并为一条，长按可以拆开`);
  }
  mergeSourceRows(): ReadStatsRank[] {
    const item = this.itemByWork(this.mergeSourceKey);
    return item ? [item] : [];
  }
  mergeTargetRows(): ReadStatsRank[] {
    const item = this.mergeTargetKey ? this.itemByWork(this.mergeTargetKey) : undefined;
    return item ? [item] : [];
  }
  mergeMainOptions(): ReadStatsRank[] {
    if (this.recordSheetMode === 'mergeMany') {
      const options: ReadStatsRank[] = [];
      this.mergeSelectionRows().forEach((item: ReadStatsRank): void => { options.push(...this.editionsOf(item)); });
      return options;
    }
    if (!this.mergeTargetKey) return [];
    return [...this.editionsOf(this.itemByWork(this.mergeSourceKey)), ...this.editionsOf(this.itemByWork(this.mergeTargetKey))];
  }
  private sameTitleAsSource(item: ReadStatsRank): boolean {
    const source = this.itemByWork(this.mergeSourceKey);
    const title = source ? ReadStatsSummary.titleKey(source.name, this.fold) : '';
    return !!title && ReadStatsSummary.titleKey(item.name, this.fold) === title;
  }
  private mergeMatches(): ReadStatsRank[] {
    const keyword = this.mergeKeyword.trim().toLowerCase();
    const matches = this.summary.items.filter((item: ReadStatsRank): boolean => item.workKey !== this.mergeSourceKey &&
      (!keyword || item.name.toLowerCase().includes(keyword) || item.author.toLowerCase().includes(keyword)));
    const same = matches.filter((item: ReadStatsRank): boolean => this.sameTitleAsSource(item));
    return [...same, ...matches.filter((item: ReadStatsRank): boolean => !same.includes(item))];
  }
  /** 候选一次只建前 30 行，全部时段可能有几百本，其余靠搜索找。 */
  mergeCandidates(): ReadStatsRank[] { return this.mergeMatches().slice(0, 30); }
  mergeCandidateNote(): string {
    const total = this.mergeMatches().length;
    if (total === 0) return this.mergeKeyword.trim() ? '没有匹配的记录' : `${this.periodTitle()}内没有其他记录，换到“全部”再试`;
    return total > 30 ? '还有更多记录，输入书名或作者查找' : '';
  }
  mergeResultText(): string {
    let total = 0;
    this.mergeMainOptions().forEach((item: ReadStatsRank): void => { total += item.durationMs; });
    return `合并后${this.periodTitle()}共 ${ReadStatsSummary.duration(total)}。对所有时间段和设备生效，原记录不改动，随时可以拆开。`;
  }
  private async saveMerges(next: ReadWorkMergeGroup[], toast: string): Promise<void> {
    try {
      await ReadWorkMergeStore.save(getContext(this), next);
      this.merges = next;
      if (!this.alive) return;
      await this.loadStats(true);
      HdsFeedback.showToast(toast);
    } catch (error) {
      console.warn('保存阅读记录合并关系失败:', error);
      HdsFeedback.showToast('保存失败，请重试');
    }
  }
  confirmMerge(): void {
    const source = this.itemByWork(this.mergeSourceKey);
    const target = this.itemByWork(this.mergeTargetKey);
    if (!source || !target || !this.mergeMainKey) return;
    const next = ReadWorkMerges.combine(this.merges, [...this.membersOf(source), ...this.membersOf(target)], this.mergeMainKey);
    this.showRecordSheet = false;
    this.saveMerges(next, '已合并为一条，长按可以拆开');
  }
  /** “已合并的记录”面板里的成员；读 mergeRevision 让拆出后刷新。 */
  mergedMembers(): ReadWorkMergeMember[] {
    const group = this.mergeRevision >= 0 ? ReadWorkMerges.find(this.merges, this.mergedSheetKey) : undefined;
    if (!group) return [];
    return [...group.members.filter((member: ReadWorkMergeMember): boolean => member.work === group.main),
      ...group.members.filter((member: ReadWorkMergeMember): boolean => member.work !== group.main)];
  }
  private mergedEdition(member: ReadWorkMergeMember): ReadStatsRank | undefined {
    const group = ReadWorkMerges.find(this.merges, member.work);
    const item = group ? this.itemByWork(group.main) : undefined;
    return this.editionsOf(item).find((edition: ReadStatsRank): boolean => edition.workKey === member.work);
  }
  /** work 传空串整组拆开。拆到不足两部时面板关掉。 */
  splitMerged(work: string): void {
    const group = ReadWorkMerges.find(this.merges, this.mergedSheetKey);
    if (!group) return;
    const next = ReadWorkMerges.remove(this.merges, group.main, work);
    const kept = group.members.find((member: ReadWorkMergeMember): boolean => member.work !== work);
    const rest = work && kept ? ReadWorkMerges.find(next, kept.work) : undefined;
    if (rest) this.mergedSheetKey = rest.main; else this.showRecordSheet = false;
    this.saveMerges(next, '已拆开');
  }

  @Builder
  sheetCaption(text: string) {
    Text(text).fontSize(AppFontSize.CAPTION).fontColor(this.subTextColor()).width('100%')
      .padding({ left: AppSpacing.XS, right: AppSpacing.XS, top: AppSpacing.MD })
  }
  /** kind：source 只展示；candidate 点按选为目标；target 点按重选；main 点按定为显示用的那部。选中状态在这里读，不按值传。 */
  @Builder
  mergeOptionRow(item: ReadStatsRank, kind: string) {
    Row({ space: AppSpacing.LG }) {
      BookCover({ bookUrl: item.bookUrl, name: item.name, author: item.author,
        coverUrl: item.coverUrl, placeholderColor: this.accentColor() }).width(30).height(42)
      Column({ space: AppSpacing.XS }) {
        Row({ space: AppSpacing.MD }) {
          Text(item.name).fontSize(AppFontSize.BODY).fontWeight(FontWeight.Medium).fontColor(this.primaryTextColor())
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
          if (kind === 'candidate' && this.sameTitleAsSource(item)) {
            this.recordChip('同名')
          }
          Text(ReadStatsSummary.duration(item.durationMs)).fontSize(AppFontSize.CAPTION).fontColor(this.primaryTextColor())
        }.width('100%')
        Text(`${item.author}${!item.onShelf ? `${item.author ? ' · ' : ''}本机未上架` : ''}` +
          `${item.mergedWorks > 0 ? ` · 已合并 ${item.mergedWorks} 条` : ''}`)
          .fontSize(AppFontSize.CAPTION).fontColor(this.subTextColor()).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      if (kind === 'target') {
        Text('重选').fontSize(AppFontSize.BODY).fontColor(this.accentColor())
      } else if (kind === 'main' && this.mergeMainKey === item.workKey) {
        SymbolGlyph($r('sys.symbol.checkmark')).fontSize(16).fontColor([this.accentColor()])
      }
    }.width('100%').padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.MD, bottom: AppSpacing.MD })
      .backgroundColor(this.cardColor()).borderRadius(ThemeRuntime.cardRadius())
      .border({ width: 1.5, color: kind === 'main' && this.mergeMainKey === item.workKey ? this.accentColor() : Color.Transparent })
      .onClick((): void => {
        if (kind === 'candidate') this.chooseMergeTarget(item.workKey);
        else if (kind === 'target') this.chooseMergeTarget('');
        else if (kind === 'main') this.mergeMainKey = item.workKey;
      })
  }
  @Builder
  recordChip(text: string) {
    Text(text).fontSize(AppFontSize.MICRO).fontColor(this.accentColor()).maxLines(1)
      .padding({ left: AppSpacing.SM, right: AppSpacing.SM, top: 1, bottom: 1 })
      .border({ width: 1, color: this.accentColor(), radius: 10 })
  }
  @Builder
  mergedMemberRow(member: ReadWorkMergeMember) {
    Row({ space: AppSpacing.LG }) {
      BookCover({ bookUrl: this.mergedEdition(member)?.bookUrl ?? '', name: member.name, author: member.author,
        coverUrl: this.mergedEdition(member)?.coverUrl ?? '', placeholderColor: this.accentColor() }).width(30).height(42)
      Column({ space: AppSpacing.XS }) {
        Text(member.name || '书名未留存').fontSize(AppFontSize.BODY).fontWeight(FontWeight.Medium)
          .fontColor(this.primaryTextColor()).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        Text(`${member.author ? `${member.author} · ` : ''}` + (this.mergedEdition(member) ?
          ReadStatsSummary.duration(this.mergedEdition(member)?.durationMs ?? 0) : '该时段无记录'))
          .fontSize(AppFontSize.CAPTION).fontColor(this.subTextColor()).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Text('拆出').fontSize(AppFontSize.BODY).fontColor(this.accentColor()).height(36)
        .padding({ left: AppSpacing.MD, right: AppSpacing.XS })
        .onClick((): void => this.splitMerged(member.work))
    }.width('100%').padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.MD, bottom: AppSpacing.MD })
      .backgroundColor(this.cardColor()).borderRadius(ThemeRuntime.cardRadius())
  }
  @Builder
  sheetButton(text: string, primary: boolean, enabled: boolean, action: () => void) {
    Button(text).layoutWeight(1).height(44).fontSize(AppFontSize.BODY_LARGE)
      .fontColor(primary ? ThemeRuntime.onAccentColor(this.accentColor()) : this.primaryTextColor())
      .backgroundColor(primary ? this.accentColor() : this.cardColor())
      .enabled(enabled).opacity(enabled ? 1 : 0.4).onClick(action)
  }
  @Builder
  recordSheet() {
    Column() {
      Text(this.recordSheetMode === 'merged' ? '已合并的记录' : '合并阅读记录')
        .fontSize(AppFontSize.TITLE).fontWeight(FontWeight.Bold).fontColor(this.primaryTextColor()).width('100%')
        .padding({ left: AppSpacing.XXL, right: AppSpacing.XXL, top: AppSpacing.XL, bottom: AppSpacing.XS })
      List({ space: AppSpacing.SM }) {
        if (this.recordSheetMode === 'mergeMany') {
          ListItem() { this.sheetCaption(`把这 ${this.mergeSelection.length} 条记录并成一条，合并后显示为`) }
          ForEach(this.mergeMainOptions(), (item: ReadStatsRank) => {
            ListItem() { this.mergeOptionRow(item, 'main') }
          }, (item: ReadStatsRank): string => `many:${item.workKey}`)
          ListItem() {
            Text(this.mergeResultText()).fontSize(AppFontSize.CAPTION).fontColor(this.subTextColor()).width('100%')
              .padding(AppSpacing.LG).backgroundColor(this.softColor()).borderRadius(ThemeRuntime.cardRadius())
          }
        } else if (this.recordSheetMode === 'merged') {
          ListItem() { this.sheetCaption('这一行由下面几条记录合成，显示第一条的书名和封面') }
          ForEach(this.mergedMembers(), (member: ReadWorkMergeMember) => {
            ListItem() { this.mergedMemberRow(member) }
          }, (member: ReadWorkMergeMember): string => `${member.work}:${this.mergeRevision}`)
        } else {
          ListItem() { this.sheetCaption('把这条记录') }
          ForEach(this.mergeSourceRows(), (item: ReadStatsRank) => {
            ListItem() { this.mergeOptionRow(item, 'source') }
          }, (item: ReadStatsRank): string => `source:${item.workKey}`)
          ListItem() { this.sheetCaption('合并到') }
          if (!this.mergeTargetKey) {
            ListItem() {
              TextInput({ text: this.mergeKeyword, placeholder: '搜索书名或作者' })
                .height(40).fontSize(AppFontSize.BODY).fontColor(this.primaryTextColor())
                .placeholderColor(this.subTextColor()).backgroundColor(this.cardColor()).caretColor(this.accentColor())
                .onChange((value: string): void => { this.mergeKeyword = value; })
            }
            ForEach(this.mergeCandidates(), (item: ReadStatsRank) => {
              ListItem() { this.mergeOptionRow(item, 'candidate') }
            }, (item: ReadStatsRank): string => `candidate:${item.workKey}`)
            if (this.mergeCandidateNote().length > 0) {
              ListItem() { this.sheetCaption(this.mergeCandidateNote()) }
            }
          } else {
            ForEach(this.mergeTargetRows(), (item: ReadStatsRank) => {
              ListItem() { this.mergeOptionRow(item, 'target') }
            }, (item: ReadStatsRank): string => `target:${item.workKey}`)
            ListItem() { this.sheetCaption('合并后显示为') }
            ForEach(this.mergeMainOptions(), (item: ReadStatsRank) => {
              ListItem() { this.mergeOptionRow(item, 'main') }
            }, (item: ReadStatsRank): string => `main:${item.workKey}`)
            ListItem() {
              Text(this.mergeResultText()).fontSize(AppFontSize.CAPTION).fontColor(this.subTextColor()).width('100%')
                .padding(AppSpacing.LG).backgroundColor(this.softColor()).borderRadius(ThemeRuntime.cardRadius())
            }
          }
        }
      }.width('100%').layoutWeight(1).scrollBar(BarState.Off)
        .padding({ left: AppSpacing.XL, right: AppSpacing.XL })
      Row({ space: AppSpacing.LG }) {
        if (this.recordSheetMode === 'mergeMany') {
          this.sheetButton('取消', false, true, (): void => { this.showRecordSheet = false; })
          this.sheetButton('合并', true, !!this.mergeMainKey, (): void => this.confirmMergeSelection())
        } else if (this.recordSheetMode === 'merge') {
          this.sheetButton('取消', false, true, (): void => { this.showRecordSheet = false; })
          this.sheetButton('合并', true, !!this.mergeTargetKey && !!this.mergeMainKey, (): void => this.confirmMerge())
        } else {
          this.sheetButton('全部拆开', false, true, (): void => this.splitMerged(''))
          this.sheetButton('完成', true, true, (): void => { this.showRecordSheet = false; })
        }
      }.width('100%').padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG,
        bottom: this.navBarHeight + AppSpacing.XL })
    }.width('100%').height('100%')
  }
  recordSheetOptions(): SheetOptions {
    return ImmersiveMaterialRuntime.applySheetMaterial(this.immersiveLightLevel, {
      detents: ['70%', SheetSize.LARGE],
      dragBar: true,
      showClose: false,
      onDisappear: (): void => { this.showRecordSheet = false; }
    }, this.appDarkMode, this.accentColor());
  }
  @Builder
  bookRow(item: ReadStatsRank) {
    Row({ space: AppSpacing.MD }) {
      if (this.selecting) {
        this.selectMark(item)
      }
      // 只有按时长排才是名次；其他排序不显示数字，免得被看成名次。
      if (this.shownSort() === 'duration') {
        Text(`${item.rank}`.padStart(2, '0')).fontSize(AppFontSize.CAPTION).fontColor(this.subTextColor()).width(22)
      }
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
          if (item.mergedWorks > 0) {
            this.recordChip(`已合并 ${item.mergedWorks} 条`)
          }
          Text(this.rowMetric(item)).fontSize(AppFontSize.CAPTION)
            .fontColor(this.rowMetricHighlighted() ? this.accentColor() : this.subTextColor())
            .fontWeight(this.rowMetricHighlighted() ? FontWeight.Medium : FontWeight.Normal)
        }.width('100%')
        Stack({ alignContent: Alignment.Start }) {
          Row().width('100%').height(3).backgroundColor(this.softColor())
          Row().width(`${item.percent}%`).height(3).backgroundColor(this.accentColor())
        }.width('100%').borderRadius(2).clip(true)
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
    }.width('100%').padding(AppSpacing.XL)
      .backgroundColor(this.isRowSelected(item) ? ThemeRuntime.accentSurfaceColor(this.appDarkMode) : this.cardColor())
      .border({ width: this.selecting ? 1.5 : 0, color: this.isRowSelected(item) ? this.accentColor() : Color.Transparent })
      .borderRadius(ThemeRuntime.cardRadius()).alignItems(VerticalAlign.Center)
      .opacity(ListDissolve.opacity(this.isStatsRowDissolving(item)))
      .scale(ListDissolve.scale(this.isStatsRowDissolving(item)))
      .blur(ListDissolve.blur(this.isStatsRowDissolving(item)))
      .hitTestBehavior(this.isStatsRowDissolving(item) ? HitTestMode.None : HitTestMode.Default)
      .id(this.statsRowElementId(item.bookKey))
      .onClick((): void => {
        if (this.selecting) this.toggleSelected(item.bookKey); else this.openShelfBook(item);
      })
      .gesture(LongPressGesture({ repeat: false }).onAction((event: GestureEvent): void => {
        if (this.selecting) return;
        const finger = event.fingerList.length > 0 ? event.fingerList[0] : undefined;
        if (finger) { this.contextMenuX = finger.globalX; this.contextMenuY = finger.globalY; }
        this.actionBookKey = item.bookKey;
        this.showItemActionMenu = true;
      }))
  }
  isRowSelected(item: ReadStatsRank): boolean {
    return this.selecting && this.selectedKeys.includes(item.bookKey);
  }
  /** 勾选状态在这里读 this.selectedKeys，不按值传。 */
  @Builder
  selectMark(item: ReadStatsRank) {
    Stack() {
      if (this.isRowSelected(item)) {
        SymbolGlyph($r('sys.symbol.checkmark')).fontSize(14).fontWeight(FontWeight.Bold)
          .fontColor([ThemeRuntime.onAccentColor(this.accentColor())])
      }
    }.width(22).height(22).borderRadius(11)
      .backgroundColor(this.isRowSelected(item) ? this.accentColor() : Color.Transparent)
      .border({ width: this.isRowSelected(item) ? 0 : 1.5, color: this.subTextColor(), radius: 11 })
      .accessibilityText(this.isRowSelected(item) ? '已选' : '未选')
  }
  /** 本机书架上的书按进度回到阅读页；未上架的行已标“本机未上架”，点按不做事。 */
  openShelfBook(item: ReadStatsRank): void {
    if (!item.onShelf || !item.bookUrl) return;
    this.getUIContext().getRouter().pushUrl({ url: 'pages/ReadBook', params: { bookUrl: item.bookUrl } })
      .catch((error: Error) => {
        console.error('从阅读统计打开书籍失败:', error);
      });
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
      PopupMenuAction($r('sys.symbol.checkmark_circle'), '多选', this.primaryTextColor(), (): void => {
        const key = this.actionBookKey;
        this.showItemActionMenu = false;
        this.enterSelection(key);
      })
      PopupMenuAction($r('sys.symbol.rectangle_on_rectangle'), '合并到其他记录…', this.primaryTextColor(), (): void => {
        const item = this.actionItem();
        this.showItemActionMenu = false;
        if (item) this.openMergeSheet(item.workKey);
      })
      if (this.actionItemMerged()) {
        PopupMenuAction($r('sys.symbol.list_bullet'), '查看已合并的记录', this.primaryTextColor(), (): void => {
          const item = this.actionItem();
          this.showItemActionMenu = false;
          if (!item) return;
          this.mergedSheetKey = item.workKey;
          this.recordSheetMode = 'merged';
          this.showRecordSheet = true;
        })
      }
      PopupMenuAction($r('sys.symbol.trash'), '删除记录', ThemeRuntime.dangerColor(this.appDarkMode), (): void => {
        const item = this.actionItem();
        this.showItemActionMenu = false;
        if (item) this.confirmDeleteItem(item);
      })
    }.width(224).padding(ImmersiveMaterialRuntime.POPUP_MENU_PADDING)
  }
  private actionItem(): ReadStatsRank | undefined {
    return this.summary.items.find((book: ReadStatsRank): boolean => book.bookKey === this.actionBookKey);
  }
  actionItemMerged(): boolean {
    const item = this.actionItem();
    return !!item && item.mergedWorks > 0;
  }
  confirmDeleteItem(item: ReadStatsRank): Promise<void> {
    return this.deleteRows([item], '删除阅读记录',
      `删除“${item.name}”在 ${this.periodTitle()}、${this.deviceTitle()} 范围内已获取的阅读记录？` +
        '开启同步后会同步删除，尚未上传的其他设备记录不受影响。不会删除书籍。', '记录已删除');
  }
  confirmDeleteSelected(): Promise<void> {
    const items = this.selectedRows();
    if (items.length === 0) return Promise.resolve();
    let total = 0;
    items.forEach((item: ReadStatsRank): void => { total += item.durationMs; });
    const names = items.slice(0, 2).map((item: ReadStatsRank): string => `“${item.name}”`).join('、');
    const books = items.length > 2 ? `${names}等 ${items.length} 本` : names;
    return this.deleteRows(items, `删除 ${items.length} 条阅读记录？`,
      `${books}，共 ${ReadStatsSummary.duration(total)}。只删 ${this.periodTitle()}、${this.deviceTitle()} 范围内已获取的记录，` +
        '开启同步后会同步删除，尚未上传的其他设备记录不受影响。不会删除书籍。', `已删除 ${items.length} 条记录`);
  }
  /** 单条和多选删除共用：确认后各行一起消散，删完补位、退出多选，再原位重读排名和图表。 */
  private async deleteRows(items: ReadStatsRank[], title: string, message: string, toast: string): Promise<void> {
    const range = ReadStatsSummary.range(this.mode, this.anchorTs);
    const deviceId = this.selectedDevice;
    const ownerId = this.ownerId;
    const keys = items.map((item: ReadStatsRank): string => item.bookKey);
    try {
      const confirmation = await promptAction.showDialog({ title, message,
        buttons: [{ text: '取消', color: this.subTextColor() }, { text: '删除', color: ThemeRuntime.dangerColor(this.appDarkMode) }] });
      if (confirmation.index !== 1) return;
      // 等确认框退场后这些行消散，与删记录同时进行；播完补位，再原位重读排名和图表。
      const fade = ListDissolve.fadeOut(this.getUIContext(), keys, (key: string) => {
        this.dissolvingBookKeys = [...this.dissolvingBookKeys, key];
      }, ListDissolve.particles('reading_stats_root', [this.accentColor(), this.primaryTextColor(), this.subTextColor()],
        (key: string): string => this.statsRowElementId(key), (): DeleteParticleBurst[] => this.deleteParticleBursts,
        (bursts: DeleteParticleBurst[]): void => { this.deleteParticleBursts = bursts; }), ListDissolve.AFTER_DIALOG_MS);
      try {
        await readStatsTracker.flushAndWait();
        for (const item of items) {
          for (const recordBookKey of item.recordBookKeys) {
            await appDb.deleteReadStatsSelection(recordBookKey, range.startKey, range.endKey, deviceId, ownerId);
          }
        }
      } finally {
        await fade;
      }
      if (!this.alive) return;
      ListDissolve.commit(this.getUIContext(), () => {
        keys.forEach((key: string): void => this.source.remove(key));
      }, () => {
        this.dissolvingBookKeys = ListDissolve.without(this.dissolvingBookKeys, keys);
      });
      await new Promise<void>((resolve: () => void) => { setTimeout(resolve, ListDissolve.CLEAR_DELAY_MS); });
      if (!this.alive) return;
      // 补位动画播完再退出多选，退出会整表重建，提前做会打断消散。
      this.selecting = false;
      this.selectedKeys = [];
      await this.loadStats(true);
      HdsFeedback.showToast(toast);
    } catch (error) {
      console.warn('删除阅读记录失败:', error);
      this.dissolvingBookKeys = ListDissolve.without(this.dissolvingBookKeys, keys);
      HdsFeedback.showToast('删除失败，请重试');
      // 多条删到一半失败时，已删掉的那些要从排行里去掉。
      if (this.alive && items.length > 1) this.loadStats(true);
    }
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
  private statsCaption(): string {
    if (this.selectedDevice === ReadStatsDevice.LEGACY_ID) return '历史导入 · 原设备来源未留存';
    if (!this.statsRecording) return '本机暂停记录中 · 其他设备照常计时';
    return this.statsCountListening ? '阅读与听书合并计时' : '只计阅读，听书不计时';
  }
  private setStatsRecording(recording: boolean, listening: boolean): void {
    if (recording === this.statsRecording && listening === this.statsCountListening) return;
    const recordingChanged = recording !== this.statsRecording;
    ReadStatsSettingsStore.save(getContext(this), recording, listening).catch((error: Error): void => {
      console.warn('保存阅读统计开关失败:', error);
      HdsFeedback.showToast('保存失败，请重试');
    });
    if (recordingChanged) HdsFeedback.showToast(recording ? '已恢复记录' : '已暂停记录，已有记录保留');
    else HdsFeedback.showToast(listening ? '听书恢复计时' : '听书不再计时');
  }
  @Builder
  pausedBanner() {
    Row({ space: AppSpacing.MD }) {
      SymbolGlyph($r('sys.symbol.pause')).fontSize(18).fontColor([ThemeRuntime.warningColor(this.appDarkMode)])
      Column({ space: 2 }) {
        Text('本机已暂停记录').fontSize(AppFontSize.BODY).fontWeight(FontWeight.Medium)
          .fontColor(ThemeRuntime.warningColor(this.appDarkMode))
        Text('已有记录照常查看和同步').fontSize(AppFontSize.CAPTION).fontColor(this.subTextColor())
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      Button('恢复', { type: ButtonType.Capsule }).fontSize(AppFontSize.CAPTION).fontWeight(FontWeight.Medium)
        .fontColor(ThemeRuntime.warningColor(this.appDarkMode)).backgroundColor(this.cardColor()).height(30)
        .padding({ left: 14, right: 14 })
        .onClick((): void => { this.setStatsRecording(true, this.statsCountListening); })
    }.width('100%').padding({ left: AppSpacing.LG, right: AppSpacing.MD, top: AppSpacing.MD, bottom: AppSpacing.MD })
      .backgroundColor('#24E89725').borderRadius(ThemeRuntime.cardRadius()).margin({ bottom: AppSpacing.LG })
  }
  /** 第二行读状态而不靠传值，按值传入的 @Builder 不刷新。 */
  @Builder
  statsSwitchRow(listeningRow: boolean) {
    Row({ space: AppSpacing.MD }) {
      Column({ space: 2 }) {
        Text(listeningRow ? '听书计入时长' : '记录阅读时长').fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.primaryTextColor())
        Text(listeningRow ? '朗读和有声书播放时计时' : '关闭后本机不再计时，已有记录保留')
          .fontSize(AppFontSize.CAPTION).fontColor(this.subTextColor())
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      AdaptiveSwitch({
        isOn: listeningRow ? this.statsCountListening : this.statsRecording,
        switchEnabled: listeningRow ? this.statsRecording : true,
        accessibilityLabel: listeningRow ? '听书计入时长' : '记录阅读时长',
        onChange: (isOn: boolean): void => {
          if (listeningRow) this.setStatsRecording(this.statsRecording, isOn);
          else this.setStatsRecording(isOn, this.statsCountListening);
        }
      })
    }.width('100%').padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .opacity(listeningRow && !this.statsRecording ? 0.45 : 1)
  }
  @Builder
  moreMenu() {
    Column() {
      this.statsSwitchRow(false)
      this.statsSwitchRow(true)
    }.width(300).padding(ImmersiveMaterialRuntime.POPUP_MENU_PADDING)
  }
  @Builder
  pageActions() {
    if (this.selecting) {
      ImmersiveHeaderAction({
        label: this.allSelected() ? '取消全选' : '全选',
        tint: this.accentColor(),
        onTap: (): void => this.toggleAllSelected()
      }).margin({ right: AppSpacing.XL })
    } else {
      this.normalPageActions()
    }
  }
  @Builder
  normalPageActions() {
    Row({ space: AppSpacing.MD }) {
      ImmersiveHeaderAction({
        icon: $r('sys.symbol.share'),
        accessibilityLabel: '分享阅读统计',
        actionEnabled: !this.loading && !this.errorMessage && !this.openingShare,
        onTap: (): void => { this.shareStatistics(); }
      })
      ImmersiveHeaderAction({
        icon: $r('sys.symbol.more'),
        accessibilityLabel: '统计设置',
        onTap: (): void => { this.showMoreMenu = !this.showMoreMenu; }
      })
        .bindPopup(this.showMoreMenu, ImmersiveMaterialRuntime.popupMenuOptions(this.immersiveLightLevel,
          (): void => { this.moreMenu(); }, Placement.BottomRight, this.appDarkMode, this.accentColor(),
          (): void => { this.showMoreMenu = false; }))
    }.margin({ right: AppSpacing.XL })
  }
  /** 删除范围写全，免得以为删的是这本书的全部记录。 */
  private selectionScopeText(): string {
    return `删除范围：${this.periodTitle()} · ${this.deviceTitle()}`;
  }
  /**
   * 多选底部：一颗沉浸光感胶囊放“合并”“删除 N 条”，上方常驻删除范围。合并要两条以上。
   * 外层铺满整页、不拦触摸，只有胶囊本身接收点按。
   */
  @Builder
  selectionDock() {
    Column({ space: AppSpacing.SM }) {
      Text(this.selectionScopeText()).fontSize(AppFontSize.CAPTION).fontColor(this.subTextColor())
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).constraintSize({ maxWidth: '90%' })
        .padding({ left: AppSpacing.MD, right: AppSpacing.MD, top: 3, bottom: 3 })
        .backgroundColor(this.cardColor()).borderRadius(12)
      ImmersiveMaterialSurface({
        surfaceWidth: SELECTION_DOCK_WIDTH,
        surfaceHeight: SELECTION_DOCK_HEIGHT,
        darkMode: this.appDarkMode,
        fallbackColor: this.cardColor(),
        glowColor: `#40${this.accentColor().substring(1)}`
      }) {
        Row({ space: AppSpacing.XS }) {
          this.dockButton(false)
          this.dockButton(true)
        }.width('100%').height('100%').padding(5)
      }
    }.width('100%').height('100%').justifyContent(FlexAlign.End).alignItems(HorizontalAlign.Center)
      .padding({ bottom: this.navBarHeight + AppSpacing.XL })
      .hitTestBehavior(HitTestMode.Transparent)
  }
  /** 已选条数在这里读，不靠传值：按值传入的 @Builder 不刷新。 */
  @Builder
  dockButton(remove: boolean) {
    Row({ space: 6 }) {
      SymbolGlyph(remove ? $r('sys.symbol.trash') : $r('sys.symbol.rectangle_on_rectangle')).fontSize(18)
        .fontColor([remove ? ThemeRuntime.dangerColor(this.appDarkMode) : this.primaryTextColor()])
      Text(this.dockButtonLabel(remove)).fontSize(AppFontSize.BODY).fontWeight(FontWeight.Medium).maxLines(1)
        .fontColor(remove ? ThemeRuntime.dangerColor(this.appDarkMode) : this.primaryTextColor())
    }.layoutWeight(1).height('100%').justifyContent(FlexAlign.Center)
      .borderRadius((SELECTION_DOCK_HEIGHT - 10) / 2)
      .backgroundColor(remove ? `#1F${ThemeRuntime.dangerColor(this.appDarkMode).substring(1)}` : Color.Transparent)
      .opacity(this.dockButtonEnabled(remove) ? 1 : 0.38).enabled(this.dockButtonEnabled(remove))
      .accessibilityGroup(true).accessibilityText(this.dockButtonLabel(remove))
      .onClick((): void => {
        if (remove) this.confirmDeleteSelected(); else this.openMergeSelectionSheet();
      })
  }
  private dockButtonLabel(remove: boolean): string {
    if (!remove) return '合并';
    return this.selectedKeys.length > 0 ? `删除 ${this.selectedKeys.length} 条` : '删除';
  }
  private dockButtonEnabled(remove: boolean): boolean {
    return remove ? this.selectedKeys.length > 0 : this.selectedKeys.length >= 2;
  }
  cardColor(): string { return ThemeRuntime.cardColor(this.appDarkMode); }
  softColor(): string { return ThemeRuntime.inputColor(this.appDarkMode); }
  primaryTextColor(): string { return ThemeRuntime.primaryTextColor(this.appDarkMode); }
  subTextColor(): string { return ThemeRuntime.subTextColor(this.appDarkMode); }
  accentColor(): string { return ThemeRuntime.accentColor(this.appDarkMode); }
  statsRowElementId(bookKey: string): string { return `reading_stats_row_${encodeURIComponent(bookKey)}`; }
  isStatsRowDissolving(item: ReadStatsRank): boolean {
    return this.dissolvingBookKeys.length > 0 && !!item.bookKey && this.dissolvingBookKeys.indexOf(item.bookKey) >= 0;
  }
  syncBars(): void { syncSystemBars(getContext(this), this.appDarkMode, this.pageColor()); }
  @Builder
  pageContent() {
    List({ scroller: this.headerScroller, space: AppSpacing.SM }) {
      LazyForEach(this.source, (item: ReadStatsRank) => {
        if (!item.bookKey) {
          ListItem() { this.headerContent() }
            .padding({ left: AppSpacing.XL, right: AppSpacing.XL,
              top: PageScaffold.BAR_HEIGHT + this.statusBarHeight }).clip(false)
        } else if (deviceInfo.sdkApiVersion >= 26 && !this.selecting) {
          HdsListItem({ customItemBuilder: (): void => { this.bookRow(item) }, swipeActionOptions: this.itemSwipeActions(item) })
            .margin({ left: AppSpacing.XL, right: AppSpacing.XL })
        } else {
          // 多选时不挂左滑删除，免得和点按勾选抢手势。
          if (this.selecting) {
            ListItem() { this.bookRow(item) }
              .margin({ left: AppSpacing.XL, right: AppSpacing.XL })
          } else {
            ListItem() { this.bookRow(item) }
              .margin({ left: AppSpacing.XL, right: AppSpacing.XL })
              .swipeAction({ end: { builder: (): void => { this.deleteSwipeButton(item) } }, edgeEffect: SwipeEdgeEffect.Spring })
          }
        }
      }, (item: ReadStatsRank): string => item.bookKey ? `${item.bookKey}:${item.durationMs}:${item.percent}:${item.rank}:${item.name}:${item.onShelf}:${item.mergedWorks}:${this.shownSort()}:${this.selecting}` : `header:${this.selecting}`)
      ListItem() {
        // 多选时底部浮着“合并 / 删除”胶囊，多留出它的高度，最后一行才能滚到胶囊上方。
        Row().width('100%').height(this.navBarHeight + AppSpacing.XXL + (this.selecting ? SELECTION_DOCK_SPACE : 0))
          .hitTestBehavior(HitTestMode.None)
      }
    }.width('100%').height('100%').cachedCount(4).scrollBar(BarState.Off)
      // 留白随内容滚动，避免裁切顶栏下方的内容、下拉框阴影和底部列表。
      .constraintSize({ maxWidth: 760 }).align(Alignment.Top)
      .onDidScroll((yOffset: number) => {
        this.headerCollapse = CollapsingHeader.next(this.headerCollapse, yOffset,
          this.headerScroller.currentOffset().yOffset);
      })
      .onScrollStop(() => {
        const target = CollapsingHeader.settle(this.headerCollapse, this.headerScroller.currentOffset().yOffset);
        if (target !== this.headerCollapse) {
          this.getUIContext().animateTo({ duration: 200, curve: Curve.FastOutSlowIn }, () => {
            this.headerCollapse = target;
          });
        }
      })
  }
  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      PageScaffold({ title: this.pageTitle(), scrollable: false, edgeToEdge: true, externalCollapse: this.headerCollapse,
        onBack: (): void => this.handleBack(),
        actions: (): void => { this.pageActions() }, content: (): void => { this.pageContent() } })
      if (this.selecting) {
        this.selectionDock()
      }
      Column().width(1).height(1).position({ x: this.contextMenuX, y: this.contextMenuY }).hitTestBehavior(HitTestMode.None)
        .bindPopup(this.showItemActionMenu, ImmersiveMaterialRuntime.popupMenuOptions(this.immersiveLightLevel,
          (): void => { this.itemActionMenu() }, Placement.BottomLeft, this.appDarkMode, this.accentColor(),
          (): void => { this.showItemActionMenu = false; }))
      if (this.deleteParticleBursts.length > 0) {
        DeleteParticleLayer({ bursts: this.deleteParticleBursts })
      }
    }.id('reading_stats_root').width('100%').height('100%').backgroundColor(this.pageColor())
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .bindSheet($$this.showRecordSheet, this.recordSheet(), this.recordSheetOptions())
  }
}
