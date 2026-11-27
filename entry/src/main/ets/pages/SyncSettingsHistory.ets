import { LengthMetrics } from '@kit.ArkUI';
import { AccountSessionStore } from '../account/AccountSessionStore';
import { AccountCommerceApi } from '../account/AccountCommerceApi';
import { CloudSyncCoordinator } from '../account/CloudSyncCoordinator';
import { CloudSyncSettingsStore } from '../account/CloudSyncSettingsStore';
import { CloudSyncStateStore } from '../account/CloudSyncStateStore';
import { CloudSyncDevice, CloudSyncHistoryGroup, CloudSyncHistoryItem } from '../account/CloudSyncModels';
import { SettingsHistoryItem, SettingsHistoryRecord, SettingsHistoryStore } from '../account/SettingsHistoryStore';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { syncSystemBars } from '../utils/SystemBars';
import { HdsFeedback } from '../utils/HdsFeedback';
import { PageScaffold } from '../components/common/PageScaffold';
import { CollapsingHeader } from '../utils/CollapsingHeader';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';

/** 一条记录里的一类设置。替换规则每条是一项，合成一类显示。 */
class HistoryCategory {
  entityType: string = '';
  label: string = '';
  description: string = '';
  /** 本机记录：要恢复的同步项 key（entityType:entityId）。 */
  keys: string[] = [];
  /** 云端记录：要恢复的历史 ID。 */
  historyIds: string[] = [];
}

/** 列表里的一条：本机设置历史一条记录，或云端同一次替换的一组。 */
class HistoryRow {
  key: string = '';
  cloud: boolean = false;
  recordId: string = '';
  at: number = 0;
  reason: string = '';
  deviceId: string = '';
  categories: HistoryCategory[] = [];
}

class HistoryDay {
  label: string = '';
  rows: HistoryRow[] = [];
}

const CATEGORY_ORDER: string[] = ['reader_settings', 'theme_settings', 'custom_theme_schemes', 'appearance_mode',
  'bookshelf_display', 'search_preferences', 'replace_rule'];

@Entry
@Component
struct SyncSettingsHistoryPage {
  @State headerCollapse: number = 0;
  private headerScroller: Scroller = new Scroller();
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  @State days: HistoryDay[] = [];
  @State loading: boolean = true;
  /** 云端记录读不到时的说明；本机记录照常显示。 */
  @State cloudNotice: string = '';
  @State showSheet: boolean = false;
  @State selected: HistoryRow = new HistoryRow();
  @State checkedTypes: string[] = [];
  @State restoring: boolean = false;
  /** 云同步已开启：本机恢复后会同步到其他设备。 */
  @State syncEnabled: boolean = false;
  private deviceNames: Map<string, string> = new Map<string, string>();
  private ownDeviceId: string = '';

  aboutToAppear(): void {
    this.load();
    this.syncBars();
  }

  onPageShow(): void {
    this.syncBars();
  }

  async load(): Promise<void> {
    this.loading = true;
    const context = getContext(this);
    const rows: HistoryRow[] = [];
    try {
      this.ownDeviceId = await CloudSyncStateStore.deviceId(context);
      for (const record of await SettingsHistoryStore.list(context)) {
        const row = this.localRow(record);
        if (row.categories.length > 0) rows.push(row);
      }
    } catch (e) {
      console.warn('读取本机设置历史失败:', e);
    }
    this.cloudNotice = '';
    try {
      await AccountSessionStore.load(context);
      if (AccountSessionStore.isLoggedIn()) {
        this.syncEnabled = (await CloudSyncSettingsStore.load(context,
          AccountSessionStore.account().userId)).enabled;
        const token = AccountSessionStore.token();
        const historyTask = CloudSyncCoordinator.fetchCloudSettingsHistory(context);
        const devices = await AccountCommerceApi.fetchSyncDevices(token);
        const history = await historyTask;
        this.deviceNames = new Map<string, string>();
        (devices.devices || []).forEach((device: CloudSyncDevice) => {
          this.deviceNames.set(device.deviceId, device.deviceName);
        });
        for (const group of history.groups) {
          const row = this.cloudRow(group);
          if (row.categories.length > 0) rows.push(row);
        }
      } else {
        this.cloudNotice = '登录账号后还能看到云端的设置历史。';
      }
    } catch (e) {
      console.warn('读取云端设置历史失败:', e);
      this.cloudNotice = '暂时读不到云端的设置历史，下面只有本机的记录。';
    }
    rows.sort((left: HistoryRow, right: HistoryRow) => right.at - left.at);
    this.days = this.groupByDay(rows);
    this.loading = false;
  }

  localRow(record: SettingsHistoryRecord): HistoryRow {
    const row = new HistoryRow();
    row.key = `l:${record.id}`;
    row.recordId = record.id;
    row.at = record.createdAt;
    row.reason = record.reason;
    row.deviceId = record.sourceDeviceId;
    record.items.forEach((item: SettingsHistoryItem) => {
      this.category(row, item.entityType).keys.push(CloudSyncStateStore.entityKey(item.entityType, item.entityId));
    });
    this.finishCategories(row);
    return row;
  }

  cloudRow(group: CloudSyncHistoryGroup): HistoryRow {
    const row = new HistoryRow();
    row.key = `c:${group.groupId}`;
    row.cloud = true;
    row.at = group.replacedAt;
    row.reason = group.reason;
    row.deviceId = group.deviceId;
    if (group.deviceName && !this.deviceNames.has(group.deviceId)) {
      this.deviceNames.set(group.deviceId, group.deviceName);
    }
    (group.items || []).forEach((item: CloudSyncHistoryItem) => {
      this.category(row, item.entityType).historyIds.push(item.historyId);
    });
    this.finishCategories(row);
    return row;
  }

  category(row: HistoryRow, entityType: string): HistoryCategory {
    let found = row.categories.find((item: HistoryCategory) => item.entityType === entityType);
    if (!found) {
      found = new HistoryCategory();
      found.entityType = entityType;
      row.categories.push(found);
    }
    return found;
  }

  finishCategories(row: HistoryRow): void {
    row.categories = row.categories.filter((item: HistoryCategory) => CATEGORY_ORDER.indexOf(item.entityType) >= 0);
    row.categories.forEach((item: HistoryCategory) => {
      item.label = this.categoryLabel(item.entityType);
      const count = Math.max(item.keys.length, item.historyIds.length);
      item.description = item.entityType === 'replace_rule' ? `正文净化规则 · ${count} 条` :
        this.categoryDescription(item.entityType);
    });
    row.categories.sort((left: HistoryCategory, right: HistoryCategory) =>
      CATEGORY_ORDER.indexOf(left.entityType) - CATEGORY_ORDER.indexOf(right.entityType));
  }

  groupByDay(rows: HistoryRow[]): HistoryDay[] {
    const result: HistoryDay[] = [];
    for (const row of rows) {
      const label = this.dayLabel(row.at);
      let day = result.length > 0 ? result[result.length - 1] : undefined;
      if (!day || day.label !== label) {
        day = new HistoryDay();
        day.label = label;
        result.push(day);
      }
      day.rows.push(row);
    }
    return result;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      PageScaffold({ title: '设置历史', scrollable: false, externalCollapse: this.headerCollapse, edgeToEdge: true,
        content: () => {
          this.pageContent()
        } })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .bindSheet($$this.showSheet, this.restoreSheet(), this.sheetOptions())
  }

  @Builder
  pageContent() {
    List({ scroller: this.headerScroller }) {
      ListItem() {
        Row()
          .width('100%')
          .height(PageScaffold.BAR_HEIGHT + this.statusBarHeight)
          .hitTestBehavior(HitTestMode.None)
      }

      ListItem() {
        this.hintCard('同步或恢复要替换设置前，会把原来的设置留在这里。“云端”记录在你所有的设备上都能看到。')
      }

      if (this.cloudNotice) {
        ListItem() {
          Text(this.cloudNotice)
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.subTextColor())
            .lineHeight(18)
            .width('100%')
            .padding({ left: AppSpacing.XS, right: AppSpacing.XS, top: AppSpacing.MD })
        }
      }

      if (this.loading && this.days.length === 0) {
        ListItem() {
          Column({ space: AppSpacing.LG }) {
            LoadingProgress()
              .width(36)
              .height(36)
              .color(this.accentColor())
            Text('正在读取设置历史…')
              .fontSize(AppFontSize.BODY)
              .fontColor(this.subTextColor())
          }
          .width('100%')
          .padding({ top: 48 })
        }
      } else if (this.days.length === 0) {
        ListItem() {
          Text('还没有设置历史。同步或恢复要替换设置时，原来的设置会先存在这里，本机保留 30 天，云端保留 90 天。')
            .fontSize(AppFontSize.BODY)
            .fontColor(this.subTextColor())
            .lineHeight(20)
            .width('100%')
            .padding(AppSpacing.XL)
            .margin({ top: AppSpacing.LG })
            .borderRadius(ThemeRuntime.cardRadius())
            .backgroundColor(this.cardColor())
        }
      } else {
        ForEach(this.days, (day: HistoryDay) => {
          ListItem() {
            Column({ space: AppSpacing.MD }) {
              Text(day.label)
                .fontSize(AppFontSize.BODY)
                .fontColor(this.subTextColor())
                .width('100%')
                .padding({ left: AppSpacing.LG, top: AppSpacing.XL })
              ForEach(day.rows, (row: HistoryRow) => {
                this.recordCard(row)
              }, (row: HistoryRow) => row.key)
            }
            .width('100%')
          }
        }, (day: HistoryDay) => `${day.label}:${day.rows.map((row: HistoryRow) => row.key).join(',')}`)
      }

      ListItem() {
        Row()
          .width('100%')
          .height(32 + this.navBarHeight)
          .hitTestBehavior(HitTestMode.None)
      }
    }
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .scrollBar(BarState.Off)
    .width('100%')
    .height('100%')
    .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
    .onDidScroll((yOffset: number) => {
      this.headerCollapse = CollapsingHeader.next(this.headerCollapse, yOffset,
        this.headerScroller.currentOffset().yOffset);
    })
    .onScrollStop(() => {
      const target = CollapsingHeader.settle(this.headerCollapse, this.headerScroller.currentOffset().yOffset);
      if (target !== this.headerCollapse) {
        animateTo({ duration: 200, curve: Curve.FastOutSlowIn }, () => {
          this.headerCollapse = target;
        });
      }
    })
  }

  @Builder
  hintCard(text: string) {
    Row({ space: AppSpacing.MD }) {
      SymbolGlyph($r('sys.symbol.clock'))
        .fontSize(16)
        .fontColor([this.accentColor()])
        .margin({ top: 1 })
      Text(text)
        .fontSize(AppFontSize.CAPTION + 0.5)
        .lineHeight(19)
        .fontColor(this.subTextColor())
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.LG, bottom: AppSpacing.LG })
    .margin({ top: AppSpacing.SM })
    .borderRadius(ThemeRuntime.largeRadius())
    .backgroundColor(this.cardColor())
  }

  @Builder
  recordCard(row: HistoryRow) {
    Column({ space: AppSpacing.SM }) {
      Row({ space: AppSpacing.MD }) {
        Text(this.timeText(row.at))
          .fontSize(AppFontSize.BODY_LARGE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.primaryTextColor())
          .fontFeature('"tnum" on')
        this.sourceTag(row)
      }
      Text(this.reasonText(row))
        .fontSize(AppFontSize.BODY - 1)
        .fontColor(this.subTextColor())
        .width('100%')
      Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(6), cross: LengthMetrics.vp(6) } }) {
        ForEach(row.categories, (item: HistoryCategory) => {
          Text(item.label)
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.primaryTextColor())
            .padding({ left: 9, right: 9, top: 3, bottom: 3 })
            .borderRadius(999)
            .backgroundColor(ThemeRuntime.softFillColor(this.appDarkMode))
        }, (item: HistoryCategory) => item.entityType)
      }
      .width('100%')
      .margin({ top: AppSpacing.XS })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: AppSpacing.LG + 2, right: AppSpacing.LG + 2, top: AppSpacing.LG + 1, bottom: AppSpacing.LG + 1 })
    .borderRadius(ThemeRuntime.cardRadius())
    .backgroundColor(this.cardColor())
    .onClick(() => this.openSheet(row))
  }

  @Builder
  sourceTag(row: HistoryRow) {
    Text(row.cloud ? '云端' : '本机')
      .fontSize(AppFontSize.CAPTION - 0.5)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.tagColor(row))
      .padding({ left: 7, right: 7, top: 2, bottom: 2 })
      .borderRadius(6)
      .backgroundColor(this.tagFill(row))
  }

  @Builder
  restoreSheet() {
    Column() {
      Column({ space: AppSpacing.XS }) {
        Text(`${this.dayLabel(this.selected.at)} ${this.timeText(this.selected.at)} · ${this.selected.cloud ? '云端' : '本机'}`)
          .fontSize(AppFontSize.SUBTITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())
          .width('100%')
        Text(this.reasonText(this.selected))
          .fontSize(AppFontSize.BODY - 1)
          .fontColor(this.subTextColor())
          .width('100%')
      }
      .width('100%')
      .padding({ bottom: AppSpacing.MD })

      List() {
        ForEach(this.selected.categories, (item: HistoryCategory, index: number) => {
          ListItem() {
            this.categoryOption(item, index < this.selected.categories.length - 1)
          }
        }, (item: HistoryCategory) => `${this.selected.key}:${item.entityType}`)
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.None)

      Text(this.selected.cloud || this.syncHint() ?
        '恢复后会同步到你的其他设备。当前设置会先留一份在设置历史里，恢复错了可以再换回来。' :
        '当前设置会先留一份在设置历史里，恢复错了可以再换回来。')
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
        .lineHeight(18)
        .width('100%')
        .margin({ top: AppSpacing.MD, bottom: AppSpacing.LG })

      Button() {
        if (this.restoring) {
          LoadingProgress()
            .width(24)
            .height(24)
            .color(ThemeRuntime.onAccentColor(this.accentColor()))
        } else {
          Text(this.checkedTypes.length > 0 ? `恢复所选的 ${this.checkedTypes.length} 项` : '请选择要恢复的设置')
            .fontSize(AppFontSize.BODY_LARGE)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeRuntime.onAccentColor(this.accentColor()))
        }
      }
      .type(ButtonType.Capsule)
      .width('100%')
      .height(44)
      .backgroundColor(this.accentColor())
      .opacity(this.checkedTypes.length > 0 ? 1 : 0.45)
      .enabled(this.checkedTypes.length > 0 && !this.restoring)
      .onClick(() => {
        this.restoreSelected();
      })
    }
    .width('100%')
    .height('100%')
    .padding({ left: AppSpacing.XL + 2, right: AppSpacing.XL + 2, top: AppSpacing.LG,
      bottom: AppSpacing.XXL + this.navBarHeight })
  }

  @Builder
  categoryOption(item: HistoryCategory, divider: boolean) {
    Row({ space: AppSpacing.LG }) {
      Column({ space: 2 }) {
        Text(item.label)
          .fontSize(AppFontSize.BODY_LARGE - 1)
          .fontColor(this.primaryTextColor())
        Text(item.description)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      this.checkMark(this.checkedTypes.indexOf(item.entityType) >= 0)
    }
    .width('100%')
    .padding({ top: AppSpacing.LG - 1, bottom: AppSpacing.LG - 1, left: 2, right: 2 })
    .border({ width: { bottom: divider ? 0.5 : 0 }, color: this.dividerColor() })
    .onClick(() => {
      const index = this.checkedTypes.indexOf(item.entityType);
      this.checkedTypes = index >= 0 ? this.checkedTypes.filter((type: string) => type !== item.entityType) :
        this.checkedTypes.concat([item.entityType]);
    })
    .accessibilityRole(AccessibilityRoleType.CHECKBOX)
    .accessibilityChecked(this.checkedTypes.indexOf(item.entityType) >= 0)
  }

  @Builder
  checkMark(checked: boolean) {
    Stack() {
      Row()
        .width(22)
        .height(22)
        .borderRadius(11)
        .backgroundColor(checked ? this.accentColor() : Color.Transparent)
        .border({ width: 1.6, color: checked ? this.accentColor() : this.subTextColor() })
      if (checked) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor([ThemeRuntime.onAccentColor(this.accentColor())])
      }
    }
    .width(22)
    .height(22)
  }

  sheetOptions(): SheetOptions {
    return ImmersiveMaterialRuntime.applySheetMaterial(this.immersiveLightLevel, {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      showClose: false,
      onDisappear: () => {
        this.showSheet = false;
      }
    }, this.appDarkMode, this.accentColor());
  }

  openSheet(row: HistoryRow): void {
    this.selected = row;
    this.checkedTypes = row.categories.map((item: HistoryCategory) => item.entityType);
    this.showSheet = true;
  }

  syncHint(): boolean {
    return this.syncEnabled;
  }

  async restoreSelected(): Promise<void> {
    if (this.restoring || this.checkedTypes.length === 0) return;
    const row = this.selected;
    const chosen = row.categories.filter((item: HistoryCategory) => this.checkedTypes.indexOf(item.entityType) >= 0);
    const context = getContext(this);
    this.restoring = true;
    try {
      await AccountSessionStore.load(context);
      const userId = AccountSessionStore.isLoggedIn() ? AccountSessionStore.account().userId : '';
      const syncOn = !!userId && (await CloudSyncSettingsStore.load(context, userId)).enabled;
      if (row.cloud) {
        if (!syncOn) {
          HdsFeedback.showToast('请先开启云同步，再恢复云端的设置');
          return;
        }
        const ids: string[] = [];
        chosen.forEach((item: HistoryCategory) => item.historyIds.forEach((id: string) => ids.push(id)));
        await CloudSyncCoordinator.restoreCloudSettings(context, ids);
      } else {
        const keys: string[] = [];
        chosen.forEach((item: HistoryCategory) => item.keys.forEach((key: string) => keys.push(key)));
        await CloudSyncCoordinator.restoreLocalSettings(context, row.recordId, keys);
        if (syncOn) {
          try {
            // 用户明确要换回这份设置，同步时以本机为准，其他设备随后也会换回来。
            await CloudSyncCoordinator.syncNow(context, 'local');
          } catch (e) {
            HdsFeedback.showToast('已恢复，同步到其他设备失败，稍后会自动重试');
            this.showSheet = false;
            await this.load();
            return;
          }
        }
      }
      HdsFeedback.showToast(`已恢复 ${chosen.length} 项设置`);
      this.showSheet = false;
      await this.load();
    } catch (e) {
      HdsFeedback.showToast(e instanceof Error ? e.message : '恢复失败，请稍后重试');
    } finally {
      this.restoring = false;
    }
  }

  reasonText(row: HistoryRow): string {
    const device = this.deviceLabel(row.deviceId);
    if (row.cloud) {
      return row.reason === 'restore' ? `${device} 恢复设置历史前` : `被 ${device} 以“本地为主”替换前`;
    }
    if (row.reason === SettingsHistoryStore.REASON_RESTORE) {
      return row.deviceId && row.deviceId !== this.ownDeviceId ? `${device} 恢复设置历史前` : '恢复设置历史前';
    }
    return row.deviceId ? `来自 ${device} 的同步替换前` : '同步替换前';
  }

  deviceLabel(deviceId: string): string {
    if (deviceId && deviceId === this.ownDeviceId) return '本机';
    return this.deviceNames.get(deviceId) || '其他设备';
  }

  categoryLabel(entityType: string): string {
    switch (entityType) {
      case 'reader_settings': return '阅读设置';
      case 'theme_settings': return '主题设置';
      case 'custom_theme_schemes': return '自定义主题';
      case 'appearance_mode': return '显示模式';
      case 'bookshelf_display': return '书架布局';
      case 'search_preferences': return '搜索设置';
      case 'replace_rule': return '替换规则';
      default: return entityType;
    }
  }

  categoryDescription(entityType: string): string {
    switch (entityType) {
      case 'reader_settings': return '字体、排版、翻页方式';
      case 'theme_settings': return '应用主题、强调色';
      case 'custom_theme_schemes': return '我的方案';
      case 'appearance_mode': return '浅色、深色或跟随系统';
      case 'bookshelf_display': return '书架样式与显示项';
      case 'search_preferences': return '结果显示、精确搜索';
      default: return '';
    }
  }

  dayLabel(at: number): string {
    const date = new Date(at);
    const today = new Date();
    const startOfToday = new Date(today.getFullYear(), today.getMonth(), today.getDate()).getTime();
    if (at >= startOfToday) return '今天';
    if (at >= startOfToday - 24 * 60 * 60 * 1000) return '昨天';
    const sameYear = date.getFullYear() === today.getFullYear();
    return sameYear ? `${date.getMonth() + 1}月${date.getDate()}日` :
      `${date.getFullYear()}年${date.getMonth() + 1}月${date.getDate()}日`;
  }

  timeText(at: number): string {
    if (at <= 0) return '';
    const date = new Date(at);
    return `${date.getHours()}:${String(date.getMinutes()).padStart(2, '0')}`;
  }

  tagColor(row: HistoryRow): string {
    if (row.cloud) return this.appDarkMode ? '#A598FF' : '#6B5BD6';
    if (row.reason === SettingsHistoryStore.REASON_RESTORE) return this.subTextColor();
    return this.accentColor();
  }

  tagFill(row: HistoryRow): string {
    if (row.cloud) return this.appDarkMode ? 'rgba(165,152,255,0.16)' : 'rgba(107,91,214,0.12)';
    if (row.reason === SettingsHistoryStore.REASON_RESTORE) return ThemeRuntime.softFillColor(this.appDarkMode);
    return ThemeRuntime.accentSurfaceColor(this.appDarkMode);
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

  dividerColor(): string {
    return ThemeRuntime.hairlineColor(this.appDarkMode);
  }

  accentColor(): string {
    return ThemeRuntime.accentColor(this.appDarkMode);
  }

  syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, this.pageColor());
  }
}
