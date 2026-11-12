import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';
import { ThemeRuntime } from '../../theme/ThemeRuntime';

/** 手柄负责排序，卡片其余部分仍可正常滚动、编辑和删除。 */
@Component
export struct SourceGroupSortList {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @Prop @Watch('syncGroups') groups: string[] = [];
  groupCount: (group: string) => number = () => 0;
  onRename: (group: string) => void = () => {};
  onDelete: (group: string) => void = () => {};
  onReorder: (groups: string[]) => Promise<boolean> = async () => false;
  @State orderedGroups: string[] = [];
  @State draggingGroup: string = '';
  @State dragTranslation: number = 0;
  @State savingOrder: boolean = false;
  private scroller: Scroller = new Scroller();
  private dragStartIndex: number = -1;
  private dragStartScroll: number = 0;
  private dragOffset: number = 0;
  private pointerY: number = 0;
  private viewportTop: number = 0;
  private viewportHeight: number = 0;
  private scrollTimer: number = -1;

  aboutToAppear(): void {
    this.syncGroups();
  }

  aboutToDisappear(): void {
    this.cancelDrag();
  }

  syncGroups(): void {
    if (!this.draggingGroup) this.orderedGroups = this.groups.slice();
  }

  beginDrag(group: string, event: GestureEvent): void {
    if (this.savingOrder) return;
    this.draggingGroup = group;
    this.dragStartIndex = this.orderedGroups.indexOf(group);
    this.dragStartScroll = this.scroller.currentOffset().yOffset;
    this.updateDrag(event);
    this.scrollTimer = setInterval(() => this.autoScroll(), 30);
  }

  updateDrag(event: GestureEvent): void {
    if (!this.draggingGroup) return;
    this.dragOffset = event.offsetY;
    const finger = event.fingerList[0];
    if (finger) this.pointerY = finger.globalY;
    this.moveDraggedGroup();
  }

  moveDraggedGroup(): void {
    const rowStride = 56 + AppSpacing.SM;
    const distance = this.dragOffset + this.scroller.currentOffset().yOffset - this.dragStartScroll;
    const target = Math.max(0, Math.min(this.orderedGroups.length - 1,
      this.dragStartIndex + Math.round(distance / rowStride)));
    const current = this.orderedGroups.indexOf(this.draggingGroup);
    if (current < 0) return;
    if (target !== current) {
      const next = this.orderedGroups.slice();
      next.splice(current, 1);
      next.splice(target, 0, this.draggingGroup);
      this.orderedGroups = next;
    }
    // 用剩余位移保持卡片跟手，不让换位后的布局再次叠加完整手势位移。
    this.dragTranslation = Math.max(-rowStride, Math.min(rowStride,
      distance - (target - this.dragStartIndex) * rowStride));
  }

  autoScroll(): void {
    if (!this.draggingGroup || this.viewportHeight <= 0) return;
    const localY = this.pointerY - this.viewportTop;
    const step = localY < 32 ? -8 : (localY > this.viewportHeight - 32 ? 8 : 0);
    if (step === 0) return;
    this.scroller.scrollBy(0, step);
    this.moveDraggedGroup();
  }

  stopAutoScroll(): void {
    if (this.scrollTimer >= 0) clearInterval(this.scrollTimer);
    this.scrollTimer = -1;
  }

  cancelDrag(): void {
    this.stopAutoScroll();
    this.draggingGroup = '';
    this.dragTranslation = 0;
    this.orderedGroups = this.groups.slice();
  }

  async finishDrag(): Promise<void> {
    if (!this.draggingGroup) return;
    this.stopAutoScroll();
    this.draggingGroup = '';
    this.dragTranslation = 0;
    if (this.orderedGroups.join('\n') === this.groups.join('\n')) return;
    this.savingOrder = true;
    try {
      if (!await this.onReorder(this.orderedGroups.slice())) this.cancelDrag();
    } finally {
      this.savingOrder = false;
    }
  }

  build() {
    Scroll(this.scroller) {
      Column({ space: AppSpacing.SM }) {
        ForEach(this.orderedGroups, (group: string) => {
          Row() {
            Stack({ alignContent: Alignment.Center }) {
              Text('☰')
                .fontSize(AppFontSize.SUBTITLE)
                .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
            }
            .width(40)
            .height(56)
            .enabled(!this.savingOrder)
            .accessibilityText(`上下拖动排序：${group}`)
            .gesture(
              PanGesture({ direction: PanDirection.Vertical, distance: 2 })
                .onActionStart((event: GestureEvent) => this.beginDrag(group, event))
                .onActionUpdate((event: GestureEvent) => this.updateDrag(event))
                .onActionEnd(() => this.finishDrag())
                .onActionCancel(() => this.cancelDrag())
            )
            Column() {
              Text(group)
                .fontSize(AppFontSize.BODY_LARGE)
                .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(`${this.groupCount(group)} 个规则`)
                .fontSize(AppFontSize.CAPTION)
                .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
                .margin({ top: AppSpacing.XXS })
            }
            .layoutWeight(1)
            .margin({ left: AppSpacing.XS })
            .alignItems(HorizontalAlign.Start)
            Text('编辑')
              .fontSize(AppFontSize.BODY)
              .fontColor(ThemeRuntime.accentColor(this.appDarkMode))
              .height(36)
              .padding({ left: AppSpacing.MD, right: AppSpacing.MD })
              .textAlign(TextAlign.Center)
              .enabled(!this.draggingGroup && !this.savingOrder)
              .onClick(() => this.onRename(group))
            Text('删除')
              .fontSize(AppFontSize.BODY)
              .fontColor(ThemeRuntime.dangerColor(this.appDarkMode))
              .height(36)
              .padding({ left: AppSpacing.MD, right: AppSpacing.XS })
              .textAlign(TextAlign.Center)
              .enabled(!this.draggingGroup && !this.savingOrder)
              .onClick(() => this.onDelete(group))
          }
          .width('100%')
          .height(56)
          .padding({ left: AppSpacing.XS, right: AppSpacing.MD })
          .borderRadius(ThemeRuntime.mediumRadius())
          .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
          .border({ width: this.draggingGroup === group ? 1 : 0,
            color: ThemeRuntime.accentColor(this.appDarkMode) })
          .translate({ y: this.draggingGroup === group ? this.dragTranslation : 0 })
          .zIndex(this.draggingGroup === group ? 1 : 0)
        }, (group: string): string => group)
      }
      .width('100%')
    }
    .width('100%')
    .constraintSize({ maxHeight: 360 })
    .scrollBar(BarState.Auto)
    .enableScrollInteraction(!this.draggingGroup)
    .edgeEffect(EdgeEffect.None)
    .onAreaChange((_oldArea: Area, area: Area) => {
      this.viewportTop = Number(area.globalPosition.y);
      this.viewportHeight = Number(area.height);
    })
  }
}
