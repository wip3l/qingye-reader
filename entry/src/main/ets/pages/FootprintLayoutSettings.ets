import { PageScaffold } from '../components/common/PageScaffold';
import { ImmersiveHeaderAction } from '../components/ImmersiveHeaderAction';
import { PopupMenuAction } from '../components/common/PopupMenuAction';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { syncSystemBars } from '../utils/SystemBars';
import { HdsFeedback } from '../utils/HdsFeedback';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';
import { FootprintLayout, FootprintSection } from '../utils/FootprintLayout';

/** 其他设置 › 足迹页内容：每块的开关、拖动排序、显示数量。改了立即生效。 */
@Entry
@Component
struct FootprintLayoutSettingsPage {
  @StorageProp('appDarkMode') darkMode: boolean = false;
  @StorageProp('themeRevision') themeRevision: number = 0;
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  @StorageProp('footprintLayout') layoutRaw: string = '';
  @State layout: FootprintLayout = new FootprintLayout();
  @State order: string[] = [];
  /** 打开数量菜单的那一块，空串是都没开。 */
  @State limitMenuId: string = '';

  aboutToAppear(): void {
    this.layout = FootprintLayout.parse(this.layoutRaw);
    this.order = this.layout.order.slice();
  }

  onPageShow(): void {
    syncSystemBars(getContext(this), this.darkMode, ThemeRuntime.pageColor(this.darkMode));
  }

  private commit(next: FootprintLayout): void {
    this.layout = next;
    this.order = next.order.slice();
    FootprintLayout.save(getContext(this), next);
  }

  private setVisible(id: string, visible: boolean): void {
    const next = this.layout.clone();
    next.hidden = next.hidden.filter((item: string): boolean => item !== id);
    if (!visible) next.hidden.push(id);
    this.commit(next);
  }

  private setLimit(id: string, limit: number): void {
    const next = this.layout.clone();
    next.limits[id] = limit;
    this.commit(next);
  }

  private move(from: number, to: number): void {
    const order = this.order.slice();
    const moved = order.splice(from, 1);
    order.splice(to, 0, ...moved);
    const next = this.layout.clone();
    next.order = order;
    this.commit(next);
  }

  private reset(): void {
    this.commit(new FootprintLayout());
    HdsFeedback.showToast('已恢复默认');
  }

  build() {
    Stack() {
      PageScaffold({
        title: '足迹页内容',
        scrollable: true,
        content: () => {
          this.pageContent()
        },
        actions: () => {
          this.pageActions()
        }
      })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  pageActions() {
    ImmersiveHeaderAction({
      label: '恢复默认',
      onTap: () => this.reset()
    })
      .margin({ right: AppSpacing.XL })
  }

  @Builder
  pageContent() {
    Column({ space: AppSpacing.MD }) {
      Text('开关决定显示哪些内容，按住左边的把手拖动调整顺序。设置只存本机。')
        .fontSize(AppFontSize.CAPTION)
        .fontColor(ThemeRuntime.subTextColor(this.darkMode))
        .width('100%')
        .padding({ left: AppSpacing.XS, right: AppSpacing.XS })
      List() {
        ForEach(this.order, (id: string, index: number) => {
          ListItem() {
            this.sectionRow(FootprintLayout.section(id), index < this.order.length - 1)
          }
        }, (id: string) => id)
          .onMove((from: number, to: number) => this.move(from, to))
      }
      .width('100%')
      // 外层是页面的滚动容器，列表按行数给定高度，不自己滚。
      .height(64 * this.order.length)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.None)
      .borderRadius(ThemeRuntime.cardRadius())
      .clip(true)
      .backgroundColor(ThemeRuntime.cardColor(this.darkMode))
      if (this.layout.visibleOrder().length === 0) {
        Text('全部关闭时，足迹页只显示一张去设置内容的卡片。')
          .fontSize(AppFontSize.CAPTION)
          .fontColor(ThemeRuntime.warningColor(this.darkMode))
          .width('100%')
          .padding({ left: AppSpacing.XS, right: AppSpacing.XS })
      }
    }
    .width('100%')
    .constraintSize({ maxWidth: 760 })
    .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.MD })
  }

  @Builder
  sectionRow(section: FootprintSection, showDivider: boolean) {
    Row({ space: AppSpacing.MD }) {
      SymbolGlyph($r('sys.symbol.line_3_horizontal'))
        .fontSize(18)
        .fontColor([ThemeRuntime.subTextColor(this.darkMode)])
        .accessibilityText('拖动调整顺序')
      Column({ space: 2 }) {
        Text(section.title)
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.layout.isVisible(section.id) ? ThemeRuntime.primaryTextColor(this.darkMode) :
            ThemeRuntime.subTextColor(this.darkMode))
        Text(section.description)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(ThemeRuntime.subTextColor(this.darkMode))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      if (section.limits.length > 0) {
        Text(`${this.layout.limit(section.id)} ${section.unit}`)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.layout.isVisible(section.id) ? ThemeRuntime.primaryTextColor(this.darkMode) :
            ThemeRuntime.subTextColor(this.darkMode))
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .borderRadius(12)
          .border({ width: 0.5, color: ThemeRuntime.hairlineColor(this.darkMode) })
          .accessibilityText(`${section.title}显示数量，${this.layout.limit(section.id)}${section.unit}`)
          .onClick(() => {
            this.limitMenuId = this.limitMenuId === section.id ? '' : section.id;
          })
          .bindPopup(this.limitMenuId === section.id, ImmersiveMaterialRuntime.popupMenuOptions(this.immersiveLightLevel,
            (): void => {
              this.limitMenu(section);
            }, Placement.Bottom, this.darkMode, ThemeRuntime.accentColor(this.darkMode), () => {
              if (this.limitMenuId === section.id) this.limitMenuId = '';
            }))
      }
      Toggle({ type: ToggleType.Switch, isOn: this.layout.isVisible(section.id) })
        .selectedColor(ThemeRuntime.accentColor(this.darkMode))
        .accessibilityText(`显示${section.title}`)
        .onChange((isOn: boolean) => this.setVisible(section.id, isOn))
    }
    .width('100%')
    .height(64)
    .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
    .border({ width: { bottom: showDivider ? 0.5 : 0 }, color: ThemeRuntime.hairlineColor(this.darkMode) })
    .backgroundColor(ThemeRuntime.cardColor(this.darkMode))
  }

  @Builder
  limitMenu(section: FootprintSection) {
    Column() {
      ForEach(section.limits, (limit: number) => {
        PopupMenuAction(undefined, `${limit} ${section.unit}`,
          limit === this.layout.limit(section.id) ? ThemeRuntime.accentColor(this.darkMode) :
            ThemeRuntime.primaryTextColor(this.darkMode), () => {
            this.limitMenuId = '';
            this.setLimit(section.id, limit);
          })
      }, (limit: number) => `${limit}`)
    }
    .width(140)
    .padding(ImmersiveMaterialRuntime.POPUP_MENU_PADDING)
  }
}
