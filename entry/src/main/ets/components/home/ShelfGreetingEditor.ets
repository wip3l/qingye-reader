import { ShelfGreetingTemplate, ShelfGreetingToken, ShelfGreetingValues } from '../../utils/ShelfGreetingTemplate';
import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';

/**
 * 陪伴布局问候语的编辑面板，书架长按问候语与书架设置共用。调用方在自己的对话框 builder 里创建它，
 * 保存、取消交回调用方写设置并关闭对话框；“恢复默认”只把内置文案填进输入框，仍要点保存。
 */
@Component
export struct ShelfGreetingEditor {
  @Prop appDarkMode: boolean = false;
  @Prop initialTitle: string = '';
  @Prop initialSubtitle: string = '';
  @Prop nickname: string = '';
  @Prop todayReadMs: number = 0;
  @Prop readingBookName: string = '';
  @State title: string = '';
  @State subtitle: string = '';
  // 点变量标签时插到最后获得焦点的那一行的光标处。
  @State focusedField: string = 'title';
  private titleCaret: number = 0;
  private subtitleCaret: number = 0;
  private titleController: TextInputController = new TextInputController();
  private subtitleController: TextInputController = new TextInputController();
  // 点过“恢复默认”时填进去的内置文案；保存时两行仍与它相同，就存回按时段模式，次行继续随时段变化。
  private restoredDraft: string[] = [];
  onSave: (title: string, subtitle: string) => void = () => {};
  /** 恢复默认后未改动就保存：调用方存回按时段模式。 */
  onSaveDefault: () => void = () => {};
  onCancel: () => void = () => {};

  aboutToAppear(): void {
    this.title = this.initialTitle;
    this.subtitle = this.initialSubtitle;
    this.titleCaret = this.title.length;
    this.subtitleCaret = this.subtitle.length;
  }

  previewValues(): ShelfGreetingValues {
    const values = new ShelfGreetingValues();
    const now = new Date();
    values.hour = now.getHours();
    values.date = now;
    values.nickname = this.nickname;
    values.todayReadMs = this.todayReadMs;
    values.readingBookName = this.readingBookName;
    return values;
  }

  restoreDefault(): void {
    this.restoredDraft = ShelfGreetingTemplate.defaultDraft(new Date().getHours());
    this.title = this.restoredDraft[0];
    this.subtitle = this.restoredDraft[1];
    this.titleCaret = this.title.length;
    this.subtitleCaret = this.subtitle.length;
  }

  save(): void {
    const title = this.title.trim();
    const subtitle = this.subtitle.trim();
    if (this.restoredDraft.length === 2 && title === this.restoredDraft[0] && subtitle === this.restoredDraft[1]) {
      this.onSaveDefault();
      return;
    }
    this.onSave(title, subtitle);
  }

  insertToken(token: string): void {
    if (this.focusedField === 'subtitle') {
      const at = Math.max(0, Math.min(this.subtitleCaret, this.subtitle.length));
      const next = this.subtitle.slice(0, at) + token + this.subtitle.slice(at);
      if (next.length > ShelfGreetingTemplate.MAX_LENGTH) return;
      this.subtitle = next;
      this.subtitleCaret = at + token.length;
      this.subtitleController.caretPosition(this.subtitleCaret);
      return;
    }
    const at = Math.max(0, Math.min(this.titleCaret, this.title.length));
    const next = this.title.slice(0, at) + token + this.title.slice(at);
    if (next.length > ShelfGreetingTemplate.MAX_LENGTH) return;
    this.title = next;
    this.titleCaret = at + token.length;
    this.titleController.caretPosition(this.titleCaret);
  }

  build() {
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
        Text(ShelfGreetingTemplate.customLines(this.title, this.subtitle, this.previewValues())[0])
          .fontSize(AppFontSize.TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeRuntime.accentColor(this.appDarkMode))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (ShelfGreetingTemplate.customLines(this.title, this.subtitle, this.previewValues())[1]) {
          Text(ShelfGreetingTemplate.customLines(this.title, this.subtitle, this.previewValues())[1])
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
          this.title = value;
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
          this.subtitle = value;
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
      .margin({ top: AppSpacing.LG })
    }
    .padding(AppSpacing.XXL)
  }

  @Builder
  fieldLabel(text: string) {
    Text(text)
      .fontSize(AppFontSize.BODY)
      .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
      .width('100%')
      .margin({ top: 14, bottom: AppSpacing.SM })
  }
}
