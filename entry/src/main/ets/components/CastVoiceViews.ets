import { LengthMetrics } from '@kit.ArkUI';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { CastVoicePolicy } from '../core/mimo/CastVoicePolicy';
import { CastVoiceItem, CastVoiceStore } from '../utils/mimo/CastVoiceStore';
import { CastVoicePreview } from '../utils/mimo/CastVoicePreview';
import { HdsFeedback } from '../utils/HdsFeedback';

/** 多角色朗读各页面共用的小部件：人物头像、小标签、一行音色、选音色面板。 */

/** 按性别着色的圆形头像，里面是名字的第一个字。 */
@Component
export struct CastAvatar {
  @Prop label: string = '';
  @Prop gender: string = 'unknown';
  @Prop diameter: number = 38;
  @StorageProp('appDarkMode') dark: boolean = false;
  @StorageProp('themeRevision') themeRevision: number = 0;

  private hue(): ResourceColor {
    if (this.gender === 'male') return ThemeRuntime.accentColor(this.dark);
    if (this.gender === 'female') return this.dark ? '#E39AB8' : '#A8456B';
    return ThemeRuntime.subTextColor(this.dark);
  }

  build() {
    Stack() {
      Row().width(this.diameter).height(this.diameter).borderRadius(this.diameter / 2)
        .backgroundColor(this.hue()).opacity(this.dark ? 0.22 : 0.14)
      Text(this.label.substring(0, 1)).fontSize(this.diameter * 0.4).fontWeight(FontWeight.Medium).fontColor(this.hue())
    }.width(this.diameter).height(this.diameter)
  }
}

/** 音色名下方的小标签。tone：''=普通，'accent'=强调（谁在用），'danger'=不可用原因。 */
@Component
export struct CastPill {
  @Prop text: string = '';
  @Prop tone: string = '';
  @StorageProp('appDarkMode') dark: boolean = false;
  @StorageProp('themeRevision') themeRevision: number = 0;

  build() {
    Text(this.text)
      .fontSize(11)
      .fontColor(this.tone === 'accent' ? ThemeRuntime.accentColor(this.dark) :
        (this.tone === 'danger' ? ThemeRuntime.dangerColor(this.dark) : ThemeRuntime.subTextColor(this.dark)))
      .backgroundColor(this.tone === 'accent' ? ThemeRuntime.accentSurfaceColor(this.dark) :
        ThemeRuntime.softFillColor(this.dark))
      .padding({ left: 7, right: 7, top: 3, bottom: 3 })
      .borderRadius(7)
      .maxLines(1)
  }
}

/** 一行音色：名称、来源与标签、试听钮，可带勾选和右侧文字操作。 */
@Component
export struct CastVoiceLine {
  @Prop title: string = '';
  @Prop source: string = '';
  @Prop tagText: string = '';
  @Prop note: string = '';
  @Prop noteTone: string = 'accent';
  @Prop dimmed: boolean = false;
  @Prop checked: boolean = false;
  @Prop playing: boolean = false;
  @Prop showPlay: boolean = true;
  @Prop action: string = '';
  @Prop showDivider: boolean = false;
  @StorageProp('appDarkMode') dark: boolean = false;
  @StorageProp('themeRevision') themeRevision: number = 0;
  onTap: () => void = (): void => {};
  onPlay: () => void = (): void => {};
  onAction: () => void = (): void => {};

  build() {
    Column() {
      Row({ space: AppSpacing.LG }) {
        Column({ space: AppSpacing.SM }) {
          Text(this.title).fontSize(AppFontSize.BODY_LARGE).fontWeight(FontWeight.Medium)
            .fontColor(ThemeRuntime.primaryTextColor(this.dark))
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
          Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(5), cross: LengthMetrics.vp(4) } }) {
            if (this.source) { CastPill({ text: this.source }) }
            if (this.tagText) { CastPill({ text: this.tagText }) }
            if (this.note) { CastPill({ text: this.note, tone: this.noteTone }) }
          }.width('100%')
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        if (this.showPlay && !this.dimmed) {
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph(this.playing ? $r('sys.symbol.stop_circle') : $r('sys.symbol.play_fill'))
              .fontSize(15).fontColor([ThemeRuntime.accentColor(this.dark)])
          }.width(32).height(32).backgroundColor(ThemeRuntime.accentSurfaceColor(this.dark))
          .accessibilityText(this.playing ? '停止试听' : '试听 ' + this.title)
          .onClick(() => this.onPlay())
        }
        if (this.action) {
          Text(this.action).fontSize(AppFontSize.BODY).fontColor(ThemeRuntime.accentColor(this.dark))
            .padding({ left: AppSpacing.SM, right: AppSpacing.SM, top: AppSpacing.MD, bottom: AppSpacing.MD })
            .onClick(() => this.onAction())
        }
        if (this.checked) {
          SymbolGlyph($r('sys.symbol.checkmark')).fontSize(18).fontColor([ThemeRuntime.accentColor(this.dark)])
        }
      }
      .width('100%')
      .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG, bottom: AppSpacing.LG })
      .constraintSize({ minHeight: 56 })
      .opacity(this.dimmed ? 0.46 : 1)
      .onClick(() => this.onTap())
      if (this.showDivider) {
        Divider().strokeWidth(0.5).color(ThemeRuntime.dividerColor(this.dark)).margin({ left: AppSpacing.XL })
      }
    }.width('100%')
  }
}

/**
 * 选音色面板（放在半模态里）。默认只列“合适的”：按 gender 筛（旁白位置只列标了“适合读旁白”的），
 * 切到“全部”列出所有离线与自定义音色。usedKeys/usedLabels 标出哪些音色已经被别处占用。
 */
@Component
export struct CastVoicePicker {
  @Prop heading: string = '';
  @Prop sub: string = '';
  @Prop avatar: string = '';
  @Prop gender: string = 'unknown';
  @Prop narratorOnly: boolean = false;
  @Prop selectedKeys: string[] = [];
  @Prop usedKeys: string[] = [];
  @Prop usedLabels: string[] = [];
  /** 面板底部的文字按钮，最多两个。 */
  @Prop actions: string[] = [];
  @StorageProp('appDarkMode') dark: boolean = false;
  @StorageProp('themeRevision') themeRevision: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @State all: boolean = false;
  @State items: CastVoiceItem[] = [];
  @State previewing: string = '';
  onPick: (item: CastVoiceItem) => void = (_item: CastVoiceItem): void => {};
  onAction: (index: number) => void = (_index: number): void => {};
  private preview: CastVoicePreview = new CastVoicePreview();

  aboutToAppear(): void {
    this.items = CastVoiceStore.voices();
    // 没有任何“合适的”音色时直接给全部，免得打开是空的。
    if (this.shown('离线').length + this.shown('自定义').length === 0) this.all = true;
  }
  aboutToDisappear(): void { this.preview.release(); }

  private fits(item: CastVoiceItem): boolean {
    if (this.all) return true;
    if (this.narratorOnly) return item.tag.narrator;
    if (this.gender === 'male' || this.gender === 'female') return item.tag.gender === this.gender;
    return CastVoicePolicy.tagged(item.tag);
  }
  private shown(source: string): CastVoiceItem[] {
    return this.items.filter((item: CastVoiceItem): boolean => item.source === source &&
      (this.fits(item) || this.selectedKeys.includes(item.key)));
  }
  private note(item: CastVoiceItem): string {
    if (item.unsupported) return item.reason;
    const index = this.usedKeys.indexOf(item.key);
    return index >= 0 ? (this.usedLabels[index] || '') : '';
  }
  private async togglePreview(item: CastVoiceItem): Promise<void> {
    if (this.previewing === item.key) { this.preview.stop(); this.previewing = ''; return; }
    this.previewing = item.key;
    try { await this.preview.play(item.ref); } catch (error) {
      if (!CastVoicePreview.interrupted(error as Error)) HdsFeedback.showToast((error as Error).message || '试听失败');
    }
    if (this.previewing === item.key) this.previewing = '';
  }

  // 按值传进 @Builder 的参数不会随状态刷新，选中态在这里直接读 this.all。
  @Builder
  segment(label: string, value: boolean) {
    Text(label).fontSize(AppFontSize.BODY).textAlign(TextAlign.Center)
      .fontWeight(this.all === value ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.all === value ? ThemeRuntime.primaryTextColor(this.dark) : ThemeRuntime.subTextColor(this.dark))
      .backgroundColor(this.all === value ? ThemeRuntime.cardColor(this.dark) : Color.Transparent)
      .height(30).borderRadius(9).layoutWeight(1)
      .onClick(() => { this.all = value; })
  }

  @Builder
  group(source: string) {
    if (this.shown(source).length > 0) {
      Text(source).fontSize(AppFontSize.CAPTION).fontColor(ThemeRuntime.subTextColor(this.dark))
        .width('100%').padding({ left: AppSpacing.XS, top: AppSpacing.XS })
      Column() {
        ForEach(this.shown(source), (item: CastVoiceItem, index: number) => {
          CastVoiceLine({
            title: item.title, tagText: CastVoicePolicy.tagLabel(item.tag),
            note: this.note(item), noteTone: item.unsupported ? 'danger' : 'accent',
            dimmed: item.unsupported, checked: this.selectedKeys.includes(item.key),
            playing: this.previewing === item.key, showDivider: index < this.shown(source).length - 1,
            onTap: (): void => {
              if (item.unsupported) { HdsFeedback.showToast('这个音色' + item.reason); return; }
              this.preview.stop();
              this.onPick(item);
            },
            onPlay: (): void => { this.togglePreview(item); }
          })
          // 键里带上“是不是最后一行”：在“合适的 / 全部”之间切换后行数变了，分隔线要跟着重画。
        }, (item: CastVoiceItem, index: number): string => item.key + '|' + CastVoicePolicy.tagLabel(item.tag) + '|' +
          this.note(item) + (this.selectedKeys.includes(item.key) ? '1' : '0') +
          (this.previewing === item.key ? 'p' : '') + (index < this.shown(source).length - 1 ? 'd' : ''))
      }.width('100%').backgroundColor(ThemeRuntime.cardColor(this.dark)).borderRadius(ThemeRuntime.cardRadius())
    }
  }

  build() {
    Column({ space: AppSpacing.LG }) {
      Row({ space: AppSpacing.LG }) {
        if (this.avatar) { CastAvatar({ label: this.avatar, gender: this.gender }) }
        Column({ space: AppSpacing.XXS }) {
          Text(this.heading).fontSize(AppFontSize.SUBTITLE).fontWeight(FontWeight.Medium)
            .fontColor(ThemeRuntime.primaryTextColor(this.dark)).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
          if (this.sub) {
            Text(this.sub).fontSize(AppFontSize.CAPTION).fontColor(ThemeRuntime.subTextColor(this.dark)).width('100%')
          }
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }.width('100%')

      Row() {
        this.segment('合适的', false)
        this.segment('全部', true)
      }.width('100%').padding(3).borderRadius(12).backgroundColor(ThemeRuntime.softFillColor(this.dark))

      Scroll() {
        Column({ space: AppSpacing.MD }) {
          this.group('离线')
          this.group('自定义')
          if (this.shown('离线').length + this.shown('自定义').length === 0) {
            Text(this.items.length === 0 ? '还没有可用的离线音色或自定义音色，先到音色管理里下载或导入。' :
              '没有标成这一类的音色。切到“全部”可以选任何音色，或先去给音色标上性别。')
              .fontSize(AppFontSize.BODY).fontColor(ThemeRuntime.subTextColor(this.dark))
              .textAlign(TextAlign.Center).width('100%').padding({ top: 40, bottom: 40 })
          }
        }.width('100%')
      }.layoutWeight(1).scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring).align(Alignment.Top)

      if (this.actions.length > 0) {
        Row({ space: AppSpacing.LG }) {
          ForEach(this.actions, (label: string, index: number) => {
            Button(label).height(42).layoutWeight(1).fontSize(AppFontSize.BODY)
              .fontColor(ThemeRuntime.primaryTextColor(this.dark))
              .backgroundColor(ThemeRuntime.softFillColor(this.dark))
              .onClick(() => { this.preview.stop(); this.onAction(index); })
          }, (label: string): string => label)
        }.width('100%')
      }
    }
    .width('100%').height('100%')
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.XXL, bottom: AppSpacing.XL + this.navBarHeight })
  }
}
