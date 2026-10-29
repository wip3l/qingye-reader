import { PageScaffold } from '../components/common/PageScaffold';
import { ImmersiveHeaderAction } from '../components/ImmersiveHeaderAction';
import { SettingNavRow } from '../components/common/SettingRow';
import { BookshelfCoverBadges } from '../components/BookshelfCoverBadges';
import { BookshelfCoverBadgeSettings } from '../utils/BookshelfCoverBadgeSettings';
import { BookshelfDisplaySettingsStore } from '../utils/BookshelfDisplaySettingsStore';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { syncSystemBars } from '../utils/SystemBars';
import { HdsFeedback } from '../utils/HdsFeedback';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';

@Entry
@Component
struct BookshelfCoverBadgeSettingsPage {
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  @StorageProp('appDarkMode') appDarkMode: boolean = false;
  @StorageProp('themeRevision') themeRevision: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @State draft: string = BookshelfCoverBadgeSettings.DEFAULT;
  @State original: string = BookshelfCoverBadgeSettings.DEFAULT;
  @State loaded: boolean = false;
  @State saving: boolean = false;
  @State showPicker: boolean = false;
  @State selectedCorner: number = 0;
  @State selectedItems: string[] = [];

  async aboutToAppear(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    syncSystemBars(context, this.appDarkMode, ThemeRuntime.pageColor(this.appDarkMode));
    try {
      const settings = await BookshelfDisplaySettingsStore.load(context);
      this.draft = settings.coverBadges;
      this.original = this.draft;
      this.loaded = true;
    } catch (e) {
      HdsFeedback.showToast('加载封面标识设置失败，请返回重试');
    }
  }

  onBackPress(): boolean {
    if (this.showPicker) {
      this.showPicker = false;
      return true;
    }
    if (this.saving) return true;
    if (this.draft === this.original) return false;
    this.leavePage();
    return true;
  }

  leavePage(): void {
    if (this.saving) return;
    if (this.draft === this.original) {
      this.getUIContext().getRouter().back();
      return;
    }
    this.getUIContext().showAlertDialog({
      title: '放弃修改？', message: '封面标识的修改尚未保存。',
      primaryButton: { value: '继续编辑', action: () => {} },
      secondaryButton: { value: '放弃修改', action: () => this.getUIContext().getRouter().back() }
    });
  }

  async saveSettings(): Promise<void> {
    if (!this.loaded || this.saving) return;
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    this.saving = true;
    try {
      // 从当前配置合并，只修改标识，保留书架布局等其他设置。
      const settings = await BookshelfDisplaySettingsStore.load(context);
      settings.coverBadges = this.draft;
      await BookshelfDisplaySettingsStore.save(context, settings);
      BookshelfDisplaySettingsStore.applyToStorage(settings);
      AppStorage.setOrCreate('shelfUpdateTime', Date.now());
      this.original = this.draft;
      this.getUIContext().getRouter().back();
    } catch (e) {
      HdsFeedback.showToast('保存失败，请重试');
    } finally {
      this.saving = false;
    }
  }

  previewConfiguration(): string {
    return this.showPicker ? BookshelfCoverBadgeSettings.move(this.draft, this.selectedCorner, this.selectedItems) : this.draft;
  }

  openCorner(corner: number): void {
    this.selectedCorner = corner;
    this.selectedItems = BookshelfCoverBadgeSettings.items(this.draft, corner);
    this.showPicker = true;
  }

  toggleItem(item: string): void {
    if (this.selectedItems.indexOf(item) >= 0) {
      this.selectedItems = this.selectedItems.filter((selected: string): boolean => selected !== item);
    } else if (this.selectedItems.length < 2) {
      this.selectedItems = this.selectedItems.concat([item]);
    } else {
      HdsFeedback.showToast('每个角最多选择两项，请先取消一项');
    }
  }

  itemDescription(item: string): string {
    const corner = BookshelfCoverBadgeSettings.location(this.draft, item);
    if (corner >= 0 && corner !== this.selectedCorner) return `当前在${BookshelfCoverBadgeSettings.cornerLabel(corner)}`;
    if (item === 'unread') return '0章或目录未知时隐藏，超过99显示99+';
    if (item === 'update') return '有更新时显示“新”';
    if (item === 'pin') return '仅已置顶的书籍显示';
    if (item === 'offline') return '下载过音频，或手动缓存过正文、漫画的在线书显示';
    if (item === 'type') return '书／漫／声／视';
    return '显示书源名称，本地书籍显示“本地”';
  }

  @Builder
  pageActions() {
    ImmersiveHeaderAction({
      label: this.saving ? '保存中' : '完成',
      tint: ThemeRuntime.buttonColor(this.appDarkMode),
      actionEnabled: this.loaded && !this.saving,
      onTap: () => this.saveSettings()
    })
      .margin({ right: AppSpacing.XL })
  }

  @Builder
  pageContent() {
    Column({ space: 16 }) {
      Column({ space: 12 }) {
        Stack() {
          Image($r('app.media.theme_cover_ink_wash_01'))
            .width('100%').height('100%').objectFit(ImageFit.Cover)
          Text('山海之间')
            .fontSize(24).fontWeight(FontWeight.Bold)
            .fontColor('#25282E').margin({ bottom: 64 })
          BookshelfCoverBadges({
            configuration: this.previewConfiguration(),
            typeLabel: '书', sourceText: '起点', unreadCount: 12, updated: true, pinned: true, offline: true
          })
        }
        .width(160).height(218).borderRadius(8).clip(true)
        Text('示例：已置顶 · 有更新 · 12章未读 · 有离线内容')
          .fontSize(AppFontSize.CAPTION).fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
      }
      .width('100%').padding(20)
      .backgroundColor(ThemeRuntime.cardColor(this.appDarkMode)).borderRadius(ThemeRuntime.cardRadius())

      Column() {
        ForEach(BookshelfCoverBadgeSettings.CORNERS, (corner: number) => {
          SettingNavRow({
            title: BookshelfCoverBadgeSettings.cornerLabel(corner),
            value: BookshelfCoverBadgeSettings.summary(this.draft, corner),
            showDivider: corner !== 3,
            onTap: () => this.openCorner(corner)
          })
        }, (corner: number): string => BookshelfCoverBadgeSettings.cornerLabel(corner))
      }
      .width('100%').backgroundColor(ThemeRuntime.cardColor(this.appDarkMode))
      .borderRadius(ThemeRuntime.cardRadius()).clip(true)
      Text('每个角最多两项，同一内容仅显示一次。\n更新标识与未读数放在同一角时合并展示。')
        .fontSize(AppFontSize.CAPTION).fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
        .textAlign(TextAlign.Center)
      Button() {
        Text('恢复默认').fontSize(AppFontSize.BODY).fontColor(ThemeRuntime.buttonColor(this.appDarkMode))
      }
      .backgroundColor(Color.Transparent)
      .onClick(() => { this.draft = BookshelfCoverBadgeSettings.DEFAULT; })
    }
    .width('100%').padding(12).enabled(this.loaded && !this.saving)
  }

  @Builder
  pickerContent() {
    Scroll() {
      Column({ space: 12 }) {
        Text(`${BookshelfCoverBadgeSettings.cornerLabel(this.selectedCorner)}显示内容`)
          .fontSize(AppFontSize.TITLE).fontWeight(FontWeight.Bold)
          .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
        Text('最多选择两项').fontSize(AppFontSize.CAPTION).fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
        Column() {
          ForEach(BookshelfCoverBadgeSettings.ITEMS, (item: string) => {
            Row({ space: 12 }) {
              Column({ space: 4 }) {
                Text(BookshelfCoverBadgeSettings.label(item)).fontSize(AppFontSize.BODY)
                  .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
                Text(this.itemDescription(item)).fontSize(AppFontSize.CAPTION)
                  .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)
              Checkbox({ name: item })
                .select(this.selectedItems.indexOf(item) >= 0)
                .selectedColor(ThemeRuntime.buttonColor(this.appDarkMode))
                .width(22).height(22).hitTestBehavior(HitTestMode.None)
            }
            .width('100%').constraintSize({ minHeight: 60 }).padding({ top: 8, bottom: 8 })
            .onClick(() => this.toggleItem(item))
            .accessibilityText(`${BookshelfCoverBadgeSettings.label(item)}，${this.selectedItems.indexOf(item) >= 0 ? '已选' : '未选'}，${this.itemDescription(item)}`)
          }, (item: string): string => item)
        }.width('100%')
        Text('选择已有内容，会移动到此角')
          .fontSize(AppFontSize.CAPTION).fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
        Button() {
          Text('确定').fontSize(AppFontSize.BODY)
            .fontColor(ThemeRuntime.onAccentColor(ThemeRuntime.buttonColor(this.appDarkMode)))
        }
        .width('100%').height(44).backgroundColor(ThemeRuntime.buttonColor(this.appDarkMode))
        .onClick(() => {
          this.draft = BookshelfCoverBadgeSettings.move(this.draft, this.selectedCorner, this.selectedItems);
          this.showPicker = false;
        })
        Button() {
          Text('清空此角').fontSize(AppFontSize.BODY).fontColor(ThemeRuntime.buttonColor(this.appDarkMode))
        }
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.draft = BookshelfCoverBadgeSettings.move(this.draft, this.selectedCorner, []);
          this.showPicker = false;
        })
      }
      .width('100%').padding({ left: 24, right: 24, top: 16, bottom: 16 + this.navBarHeight })
    }.width('100%').height('100%')
  }

  pickerSheetOptions(): SheetOptions {
    // 与书架分组、发现分类面板共用材质参数，随光感档位和明暗主题切换。
    return ImmersiveMaterialRuntime.applySheetMaterial(this.immersiveLightLevel, {
      height: '75%',
      dragBar: true,
      showClose: true,
      onDisappear: () => {
        this.showPicker = false;
      }
    }, this.appDarkMode, ThemeRuntime.accentColor(this.appDarkMode));
  }

  build() {
    Stack() {
      PageScaffold({
        title: '封面标识', collapsible: false,
        onBack: () => this.leavePage(),
        actions: () => { this.pageActions(); },
        content: () => { this.pageContent(); }
      })
    }
      .width('100%').height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .bindSheet($$this.showPicker, this.pickerContent(), this.pickerSheetOptions())
  }
}
