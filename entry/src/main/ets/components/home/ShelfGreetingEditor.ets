import {
  ShelfGreetingSlot,
  ShelfGreetingTemplate,
  ShelfGreetingToken,
  ShelfGreetingValues
} from '../../utils/ShelfGreetingTemplate';
import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';

/**
 * 陪伴布局问候语的编辑面板，书架长按问候语与书架设置共用。调用方在自己的对话框 builder 里创建它，
 * 保存、取消交回调用方写设置并关闭对话框；“恢复默认”只把内置文案填进输入框，仍要点保存。
 *
 * 文案按时段写：顶上一排时段，点哪个改哪个，每个时段有自己的开始时间和两行文字。只有一个时段时全天都显示它，
 * 不出现开始时间。
 */
@Component
export struct ShelfGreetingEditor {
  @Prop appDarkMode: boolean = false;
  /** ShelfGreetingTemplate.serializeSlots 的结果。 */
  @Prop initialSlots: string = '';
  @Prop nickname: string = '';
  @Prop todayReadMs: number = 0;
  @Prop readingBookName: string = '';
  // 元素的字段改动不触发刷新：增删、改开始时间都换一个新数组；正在编辑的两行文字另放在 title / subtitle。
  @State slots: ShelfGreetingSlot[] = [];
  @State selected: number = 0;
  @State title: string = '';
  @State subtitle: string = '';
  // 点变量标签时插到最后获得焦点的那一行的光标处。
  @State focusedField: string = 'title';
  private titleCaret: number = 0;
  private subtitleCaret: number = 0;
  private titleController: TextInputController = new TextInputController();
  private subtitleController: TextInputController = new TextInputController();
  private slotScroller: Scroller = new Scroller();
  private initialSlotIndex: number = 0;
  // 点过“恢复默认”时填进去的内置文案；保存时仍只有这一条且两行与它相同，就存回按时段模式，次行继续随时段变化。
  private restoredDraft: string[] = [];
  /** slots 是序列化后的时段列表，title、subtitle 是其中最早一条的两行。 */
  onSave: (slots: string, title: string, subtitle: string) => void = () => {};
  /** 恢复默认后未改动就保存：调用方存回按时段模式。 */
  onSaveDefault: () => void = () => {};
  onCancel: () => void = () => {};

  aboutToAppear(): void {
    this.slots = ShelfGreetingTemplate.parseSlots(this.initialSlots, '', '');
    this.initialSlotIndex = ShelfGreetingTemplate.activeSlotIndex(this.slots, this.nowMinutes());
    this.selectSlot(this.initialSlotIndex);
  }

  nowMinutes(): number {
    const now = new Date();
    return now.getHours() * 60 + now.getMinutes();
  }

  selectSlot(index: number): void {
    const slot = this.slots[index];
    this.selected = index;
    this.title = slot.title;
    this.subtitle = slot.subtitle;
    this.titleCaret = this.title.length;
    this.subtitleCaret = this.subtitle.length;
  }

  /** 预览按正在编辑的时段开始那一刻来算；只有一个时段时全天都是它，按此刻算。 */
  previewValues(): ShelfGreetingValues {
    const values = new ShelfGreetingValues();
    const now = new Date();
    values.hour = now.getHours();
    values.minute = now.getMinutes();
    if (this.slots.length > 1 && this.selected < this.slots.length) {
      values.hour = Math.floor(this.slots[this.selected].start / 60);
      values.minute = this.slots[this.selected].start % 60;
    }
    values.date = now;
    values.nickname = this.nickname;
    values.todayReadMs = this.todayReadMs;
    values.readingBookName = this.readingBookName;
    return values;
  }

  previewLines(): string[] {
    return ShelfGreetingTemplate.customLines(this.title, this.subtitle, this.previewValues());
  }

  /** 从 start 起找一个还没被别的时段占用的开始时间。 */
  freeStart(start: number, ignoreIndex: number): number {
    let next = ShelfGreetingTemplate.normalizeSlotStart(start % 1440);
    for (let i = 0; i < 1440 / ShelfGreetingTemplate.SLOT_STEP; i++) {
      const taken = this.slots.some((slot: ShelfGreetingSlot, index: number) =>
        index !== ignoreIndex && slot.start === next);
      if (!taken) break;
      next = (next + ShelfGreetingTemplate.SLOT_STEP) % 1440;
    }
    return next;
  }

  replaceSlots(next: ShelfGreetingSlot[], selectedStart: number): void {
    next.sort((a: ShelfGreetingSlot, b: ShelfGreetingSlot) => a.start - b.start);
    this.slots = next;
    const index = next.findIndex((slot: ShelfGreetingSlot) => slot.start === selectedStart);
    this.selectSlot(index >= 0 ? index : 0);
    this.slotScroller.scrollToIndex(this.selected);
  }

  copySlots(): ShelfGreetingSlot[] {
    return this.slots.map((slot: ShelfGreetingSlot) => new ShelfGreetingSlot(slot.start, slot.title, slot.subtitle));
  }

  /** 改开始时间；撞上别的时段就顺延到下一个空着的时间。 */
  setStart(minutes: number): void {
    const start = this.freeStart(minutes, this.selected);
    const next = this.copySlots();
    next[this.selected].start = start;
    this.restoredDraft = [];
    this.replaceSlots(next, start);
  }

  /** 新时段默认排在正在编辑的那条两小时之后，文字留空。 */
  addSlot(): void {
    if (this.slots.length >= ShelfGreetingTemplate.MAX_SLOTS) return;
    const start = this.freeStart(this.slots[this.selected].start + 120, -1);
    const next = this.copySlots();
    next.push(new ShelfGreetingSlot(start, '', ''));
    this.restoredDraft = [];
    this.replaceSlots(next, start);
  }

  removeSlot(): void {
    if (this.slots.length <= 1) return;
    const next = this.copySlots();
    next.splice(this.selected, 1);
    this.replaceSlots(next, next[Math.max(0, this.selected - 1)].start);
  }

  applyPreset(preset: ShelfGreetingSlot[]): void {
    this.restoredDraft = [];
    preset.sort((a: ShelfGreetingSlot, b: ShelfGreetingSlot) => a.start - b.start);
    this.replaceSlots(preset, preset[ShelfGreetingTemplate.activeSlotIndex(preset, this.nowMinutes())].start);
  }

  restoreDefault(): void {
    const draft = ShelfGreetingTemplate.defaultDraft(new Date().getHours());
    this.replaceSlots([new ShelfGreetingSlot(0, draft[0], draft[1])], 0);
    this.restoredDraft = draft;
  }

  save(): void {
    if (this.restoredDraft.length === 2 && this.slots.length === 1 &&
      this.title.trim() === this.restoredDraft[0] && this.subtitle.trim() === this.restoredDraft[1]) {
      this.onSaveDefault();
      return;
    }
    const slots = this.copySlots();
    this.onSave(ShelfGreetingTemplate.serializeSlots(slots), slots[0].title.trim(), slots[0].subtitle.trim());
  }

  setTitle(value: string): void {
    this.title = value;
    this.slots[this.selected].title = value;
  }

  setSubtitle(value: string): void {
    this.subtitle = value;
    this.slots[this.selected].subtitle = value;
  }

  insertToken(token: string): void {
    if (this.focusedField === 'subtitle') {
      const at = Math.max(0, Math.min(this.subtitleCaret, this.subtitle.length));
      const next = this.subtitle.slice(0, at) + token + this.subtitle.slice(at);
      if (next.length > ShelfGreetingTemplate.MAX_LENGTH) return;
      this.setSubtitle(next);
      this.subtitleCaret = at + token.length;
      this.subtitleController.caretPosition(this.subtitleCaret);
      return;
    }
    const at = Math.max(0, Math.min(this.titleCaret, this.title.length));
    const next = this.title.slice(0, at) + token + this.title.slice(at);
    if (next.length > ShelfGreetingTemplate.MAX_LENGTH) return;
    this.setTitle(next);
    this.titleCaret = at + token.length;
    this.titleController.caretPosition(this.titleCaret);
  }

  twoDigits(value: number): string {
    return value < 10 ? `0${value}` : `${value}`;
  }

  hourOptions(): SelectOption[] {
    const options: SelectOption[] = [];
    for (let hour = 0; hour < 24; hour++) options.push({ value: `${this.twoDigits(hour)} 点` });
    return options;
  }

  minuteOptions(): SelectOption[] {
    const options: SelectOption[] = [];
    for (let minute = 0; minute < 60; minute += ShelfGreetingTemplate.SLOT_STEP) {
      options.push({ value: `${this.twoDigits(minute)} 分` });
    }
    return options;
  }

  selectedStart(): number {
    return this.selected < this.slots.length ? this.slots[this.selected].start : 0;
  }

  build() {
    Scroll() {
      Column() {
        Text('编辑问候语')
          .fontSize(AppFontSize.SUBTITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ bottom: AppSpacing.XL })

        // 预览与书架上的样式一致：首行强调色大字，次行小字。
        Column({ space: AppSpacing.XS }) {
          Text(this.previewLines()[0])
            .fontSize(AppFontSize.TITLE)
            .fontWeight(FontWeight.Bold)
            .fontColor(ThemeRuntime.accentColor(this.appDarkMode))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.previewLines()[1]) {
            Text(this.previewLines()[1])
              .fontSize(AppFontSize.BODY)
              .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(AppSpacing.LG)
        .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
        .borderRadius(ThemeRuntime.mediumRadius())

        this.fieldLabel(this.slots.length > 1 ? `时段（${this.slots.length} 个，点选后在下面修改）` : '时段（全天显示同一条）')
        List({ space: AppSpacing.MD, scroller: this.slotScroller, initialIndex: this.initialSlotIndex }) {
          ForEach(this.slots, (slot: ShelfGreetingSlot, index: number) => {
            ListItem() {
              // 选中态直接读 this.selected：按值传进 @Builder 的参数不会跟着刷新。
              Text(this.slots.length > 1 ? ShelfGreetingTemplate.formatSlotStart(slot.start) : '全天')
                .fontSize(AppFontSize.CAPTION)
                .fontColor(index === this.selected ? ThemeRuntime.onAccentColor() :
                  ThemeRuntime.primaryTextColor(this.appDarkMode))
                .height(32)
                .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
                .backgroundColor(index === this.selected ? ThemeRuntime.buttonColor(this.appDarkMode) :
                  ThemeRuntime.inputColor(this.appDarkMode))
                .borderRadius(16)
                .onClick(() => this.selectSlot(index))
            }
          }, (slot: ShelfGreetingSlot, index: number) => `${index}_${slot.start}_${this.slots.length}`)
          if (this.slots.length < ShelfGreetingTemplate.MAX_SLOTS) {
            ListItem() {
              this.slotChip('＋ 添加时段', () => this.addSlot())
            }
          }
        }
        .listDirection(Axis.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
        .height(32)

        if (this.slots.length > 1) {
          Row({ space: AppSpacing.MD }) {
            Text('开始时间')
              .fontSize(AppFontSize.BODY)
              .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
            Select(this.hourOptions())
              .selected(Math.floor(this.selectedStart() / 60))
              .value(`${this.twoDigits(Math.floor(this.selectedStart() / 60))} 点`)
              .font({ size: AppFontSize.BODY })
              .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
              .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
              .optionFontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
              .selectedOptionFontColor(ThemeRuntime.accentColor(this.appDarkMode))
              .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.appDarkMode))
              .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode))
              .onSelect((index: number) => this.setStart(index * 60 + this.selectedStart() % 60))
            Select(this.minuteOptions())
              .selected(Math.floor((this.selectedStart() % 60) / ShelfGreetingTemplate.SLOT_STEP))
              .value(`${this.twoDigits(this.selectedStart() % 60)} 分`)
              .font({ size: AppFontSize.BODY })
              .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
              .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
              .optionFontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
              .selectedOptionFontColor(ThemeRuntime.accentColor(this.appDarkMode))
              .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.appDarkMode))
              .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode))
              .onSelect((index: number) =>
                this.setStart(Math.floor(this.selectedStart() / 60) * 60 + index * ShelfGreetingTemplate.SLOT_STEP))
            Blank()
            Text('删除')
              .fontSize(AppFontSize.BODY)
              .fontColor(ThemeRuntime.accentColor(this.appDarkMode))
              .padding({ left: AppSpacing.LG, top: AppSpacing.SM, bottom: AppSpacing.SM })
              .onClick(() => this.removeSlot())
              .accessibilityText('删除这个时段')
          }
          .width('100%')
          .margin({ top: AppSpacing.LG })
        }

        this.fieldLabel('第一行')
        TextInput({ placeholder: '留空则用默认问候', text: this.title, controller: this.titleController })
          .width('100%')
          .height(44)
          .maxLength(ShelfGreetingTemplate.MAX_LENGTH)
          .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
          .placeholderColor(ThemeRuntime.subTextColor(this.appDarkMode))
          .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
          .borderRadius(ThemeRuntime.mediumRadius())
          .onFocus(() => {
            this.focusedField = 'title';
          })
          .onChange((value: string) => {
            this.setTitle(value);
          })
          .onTextSelectionChange((start: number, end: number) => {
            this.titleCaret = Math.max(start, end);
          })

        this.fieldLabel('第二行')
        TextInput({ placeholder: '可留空', text: this.subtitle, controller: this.subtitleController })
          .width('100%')
          .height(44)
          .maxLength(ShelfGreetingTemplate.MAX_LENGTH)
          .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
          .placeholderColor(ThemeRuntime.subTextColor(this.appDarkMode))
          .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
          .borderRadius(ThemeRuntime.mediumRadius())
          .onFocus(() => {
            this.focusedField = 'subtitle';
          })
          .onChange((value: string) => {
            this.setSubtitle(value);
          })
          .onTextSelectionChange((start: number, end: number) => {
            this.subtitleCaret = Math.max(start, end);
          })

        Text(`点下面的标签插入到${this.focusedField === 'subtitle' ? '第二行' : '第一行'}，显示时换成实时内容`)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
          .width('100%')
          .margin({ top: AppSpacing.LG, bottom: AppSpacing.SM })
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(ShelfGreetingTemplate.TOKENS, (item: ShelfGreetingToken) => {
            Text(item.label)
              .fontSize(AppFontSize.CAPTION)
              .fontColor(ThemeRuntime.accentColor(this.appDarkMode))
              .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.SM, bottom: AppSpacing.SM })
              .border({ width: 1, color: ThemeRuntime.accentColor(this.appDarkMode) })
              .borderRadius(14)
              .margin({ right: AppSpacing.MD, bottom: AppSpacing.MD })
              .onClick(() => this.insertToken(item.token))
              .accessibilityText(`插入${item.label}`)
          }, (item: ShelfGreetingToken) => item.token)
        }
        .width('100%')

        Row({ space: AppSpacing.MD }) {
          Text('整套换成')
            .fontSize(AppFontSize.CAPTION)
            .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
          this.slotChip('十二时辰', () => this.applyPreset(ShelfGreetingTemplate.shichenPreset()))
          this.slotChip('早中晚五段', () => this.applyPreset(ShelfGreetingTemplate.periodPreset()))
        }
        .width('100%')
        .margin({ top: AppSpacing.SM })

        Row({ space: 10 }) {
          Button('恢复默认')
            .layoutWeight(1)
            .height(44)
            .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
            .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
            .onClick(() => this.restoreDefault())
          Button('取消')
            .layoutWeight(1)
            .height(44)
            .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
            .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
            .onClick(() => this.onCancel())
          Button('保存')
            .layoutWeight(1)
            .height(44)
            .backgroundColor(ThemeRuntime.buttonColor(this.appDarkMode))
            .fontColor(ThemeRuntime.onAccentColor())
            .onClick(() => this.save())
        }
        .width('100%')
        .margin({ top: AppSpacing.XL })
      }
      .padding(AppSpacing.XXL)
    }
    .scrollBar(BarState.Off)
  }

  @Builder
  fieldLabel(text: string) {
    Text(text)
      .fontSize(AppFontSize.BODY)
      .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
      .width('100%')
      .margin({ top: 14, bottom: AppSpacing.SM })
  }

  @Builder
  slotChip(label: string, onTap: () => void) {
    Text(label)
      .fontSize(AppFontSize.CAPTION)
      .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
      .height(32)
      .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
      .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
      .borderRadius(16)
      .onClick(() => onTap())
  }
}
