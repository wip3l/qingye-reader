import { ReaderMaterialPanel } from './ReaderFloatingMaterialBar';
import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { ImmersiveMaterialRuntime } from '../../utils/ImmersiveMaterialRuntime';
import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';
import { ReaderTtsCapsule } from './ReaderTtsControls';

/** 与朗读胶囊统一尺寸，提供调速、暂停/继续和直接结束滚动。 */
@Component
export struct ReaderAutoScrollCapsule {
  @Prop speed: number = 20;
  @Prop comic: boolean = false;
  /** 百叶窗方式：图标与标题换成百叶窗。 */
  @Prop blinds: boolean = false;
  @Prop paused: boolean = false;
  @Prop status: string = '';
  @Prop textColor: string;
  @Prop subTextColor: string;
  @Prop accentColor: string;
  @Prop panelColor: string;
  @Prop dark: boolean = false;
  onOpen: () => void = (): void => {};
  onToggle: () => void = (): void => {};
  onClose: () => void = (): void => {};
  onCapsuleDragStart: () => void = (): void => {};
  onCapsuleDragMove: (offsetX: number, offsetY: number) => void = (_offsetX: number, _offsetY: number): void => {};

  static readonly WIDTH: number = ReaderTtsCapsule.WIDTH;
  static readonly HEIGHT: number = ReaderTtsCapsule.HEIGHT;

  build() {
    Column() {
      ReaderMaterialPanel({
        panelWidth: ReaderAutoScrollCapsule.WIDTH, panelHeight: ReaderAutoScrollCapsule.HEIGHT,
        cornerRadius: ReaderAutoScrollCapsule.HEIGHT / 2, darkMode: this.dark, fallbackColor: this.panelColor
      }) {
        Row({ space: AppSpacing.SM }) {
          Button({ type: ButtonType.Normal }) {
            Row({ space: AppSpacing.SM }) {
              Stack({ alignContent: Alignment.Center }) {
                Circle().width(30).height(30).fill(this.accentColor)
                SymbolGlyph(this.blinds ? $r('sys.symbol.line_3_horizontal') : $r('sys.symbol.arrow_down'))
                  .fontSize(15).fontColor([ThemeRuntime.onAccentColor(this.accentColor)])
              }
              Column({ space: 1 }) {
                Text(this.status || (this.paused ? '已暂停' : (this.blinds ? '百叶窗' : '自动滚动')))
                  .fontSize(AppFontSize.CAPTION).fontWeight(FontWeight.Medium).fontColor(this.textColor)
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(this.comic ? `${this.speed / 20} 屏/分钟` : `${this.speed} 行/分钟`)
                  .fontSize(9).fontColor(this.subTextColor).maxLines(1)
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            }.width('100%')
          }
          .layoutWeight(1).height(34).padding(0)
          .borderRadius(17).backgroundColor(Color.Transparent)
          .accessibilityText(`${this.blinds ? '百叶窗自动翻页' : '自动滚动'}，${this.comic ? `${this.speed / 20} 屏` :
            `${this.speed} 行`}每分钟，点击调整速度`)
          .onClick(() => this.onOpen())
          Button({ type: ButtonType.Normal }) {
            SymbolGlyph(this.paused ? $r('sys.symbol.play') : $r('sys.symbol.pause'))
              .fontSize(17).fontColor([this.textColor])
          }
          .width(28).height(34).padding(0).borderRadius(17).backgroundColor(Color.Transparent)
          .accessibilityText(this.paused ? '继续自动滚动' : '暂停自动滚动')
          .onClick(() => this.onToggle())
          Button({ type: ButtonType.Normal }) {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(14).fontColor([this.subTextColor])
          }
          .width(24).height(34).padding(0).borderRadius(17).backgroundColor(Color.Transparent)
          .accessibilityText('结束自动滚动')
          .onClick(() => this.onClose())
        }.width('100%').height('100%').padding({ left: AppSpacing.MD, right: AppSpacing.XS })
      }
    }
    .parallelGesture(
      PanGesture({ direction: PanDirection.All, distance: 4 })
        .onActionStart(() => this.onCapsuleDragStart())
        .onActionUpdate((event: GestureEvent) => this.onCapsuleDragMove(event.offsetX, event.offsetY))
    )
  }
}

/** 半模态自身承接系统沉浸光感；内容不再铺第二层不透明底板。 */
@Component
export struct ReaderAutoScrollSpeedPanel {
  @Prop speed: number = 20;
  @Prop comic: boolean = false;
  @Prop paused: boolean = false;
  @Prop status: string = '';
  @Prop textColor: string;
  @Prop subTextColor: string;
  @Prop accentColor: string;
  @Prop accentSurfaceColor: string;
  @Prop controlColor: string;
  /** READER_AUTO_SCROLL_MODE_*；漫画不显示方式切换。 */
  @Prop mode: string = 'scroll';
  /** 本书当前能否用百叶窗（只有分页排版的正文能用）；不能时选项置灰并说明原因。 */
  @Prop blindsAvailable: boolean = true;
  /** 百叶窗叶片效果：flip / fade / wipe。 */
  @Prop blindsEffect: string = 'flip';
  onSpeed: (speed: number) => void = (_speed: number): void => {};
  onMode: (mode: string) => void = (_mode: string): void => {};
  onBlindsEffect: (effect: string) => void = (_effect: string): void => {};
  onToggle: () => void = (): void => {};
  onStop: () => void = (): void => {};
  onClose: () => void = (): void => {};

  @Builder
  speedStep(icon: Resource, label: string, step: number, available: boolean) {
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph(icon).fontSize(20).fontColor([this.accentColor])
    }
    .width(44).height(44).backgroundColor(this.controlColor).enabled(available)
    .accessibilityText(label).onClick(() => this.onSpeed(this.speed + step))
  }

  @Builder
  modeOption(mode: string, icon: Resource, label: string) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 6 }) {
        SymbolGlyph(icon).fontSize(15)
          .fontColor([this.mode === mode ? this.accentColor : this.textColor])
        Text(label).fontSize(14)
          .fontWeight(this.mode === mode ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.mode === mode ? this.accentColor : this.textColor)
      }.justifyContent(FlexAlign.Center)
    }
    .layoutWeight(1).height(40).borderRadius(13).padding(0)
    .backgroundColor(this.mode === mode ? this.accentSurfaceColor : Color.Transparent)
    // 可用状态在 builder 里读：按值传进来的参数不会随状态刷新。
    .enabled(mode !== 'blinds' || this.blindsAvailable).opacity(mode !== 'blinds' || this.blindsAvailable ? 1 : 0.4)
    .accessibilityText(`${label}${this.mode === mode ? '，已选中' : ''}`)
    .onClick(() => this.onMode(mode))
  }

  @Builder
  effectOption(effect: string, label: string) {
    Button({ type: ButtonType.Normal }) {
      Text(label).fontSize(13)
        .fontWeight(this.blindsEffect === effect ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.blindsEffect === effect ? this.accentColor : this.textColor)
    }
    .layoutWeight(1).height(34).borderRadius(11).padding(0)
    .backgroundColor(this.blindsEffect === effect ? this.accentSurfaceColor : Color.Transparent)
    .accessibilityText(`${label}${this.blindsEffect === effect ? '，已选中' : ''}`)
    .onClick(() => this.onBlindsEffect(effect))
  }

  modeHint(): string {
    if (this.mode === 'blinds') {
      if (!this.blindsAvailable) return '当前排版不支持百叶窗，正在使用平滑滚动';
      if (this.blindsEffect === 'wipe') return '画面不动，一条线连续往下擦出下一页';
      if (this.blindsEffect === 'fade') return '画面不动，读过的行逐行淡出、换成下一页';
      return '画面不动，读过的行逐行翻成下一页';
    }
    return '整屏文字匀速向上滚动';
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        Row({ space: 8 }) {
          Column({ space: 4 }) {
            Text('自动滚动').fontSize(20).fontWeight(FontWeight.Medium).fontColor(this.textColor)
            Text(this.status || (this.paused ? '已暂停 · 按自己的节奏阅读' :
              (this.mode === 'blinds' && !this.comic ? '正在翻页 · 调速即时生效' : '正在滚动 · 调速即时生效')))
              .fontSize(12).fontColor(this.subTextColor).maxLines(2)
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.chevron_down')).fontSize(20).fontColor([this.accentColor])
          }
          .width(44).height(44).backgroundColor(this.controlColor)
          .accessibilityText('收起调速面板').onClick(() => this.onClose())
        }.width('100%')

        if (!this.comic) {
          Column({ space: 6 }) {
            Row({ space: 4 }) {
              this.modeOption('scroll', $r('sys.symbol.arrow_down'), '平滑滚动')
              this.modeOption('blinds', $r('sys.symbol.line_3_horizontal'), '百叶窗')
            }
            .width('100%').padding(3).borderRadius(16).backgroundColor(this.controlColor)
            if (this.mode === 'blinds' && this.blindsAvailable) {
              Row({ space: 4 }) {
                this.effectOption('flip', '逐行翻转')
                this.effectOption('fade', '逐行淡入')
                this.effectOption('wipe', '平滑擦除')
              }
              .width('100%').padding(3).borderRadius(14).backgroundColor(this.controlColor)
            }
            Text(this.modeHint()).fontSize(12).fontColor(this.subTextColor).maxLines(2)
          }.width('100%').alignItems(HorizontalAlign.Start)
        }

        Row({ space: 16 }) {
          this.speedStep($r('sys.symbol.minus'), this.comic ? '每分钟减慢零点一屏' : '每分钟减慢两行', -2, this.speed > 6)
          Row({ space: 8 }) {
            Text(`${this.comic ? this.speed / 20 : this.speed}`).fontSize(38).fontColor(this.textColor)
            Text(this.comic ? '屏 / 分钟' : '行 / 分钟').fontSize(12).fontColor(this.subTextColor)
          }.layoutWeight(1).justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Bottom)
          this.speedStep($r('sys.symbol.plus'), this.comic ? '每分钟加快零点一屏' : '每分钟加快两行', 2, this.speed < 100)
        }.width('100%').margin({ top: 4 })

        Column() {
          Slider({ value: this.speed, min: 6, max: 100, step: 2 })
            .height(44).selectedColor(this.accentColor).blockColor(this.accentColor)
            .trackColor(this.controlColor)
            .sliderInteractionMode(SliderInteraction.SLIDE_ONLY)
            .accessibilityText(this.comic ? '自动滚动速度，每分钟零点三至五屏' : '自动滚动速度，每分钟六至一百行')
            .onChange((speed: number) => this.onSpeed(speed))
          Row() {
            Text(this.comic ? '0.3 屏/分钟' : '6 行/分钟').fontSize(11).fontColor(this.subTextColor)
            Blank()
            Text(this.comic ? '5 屏/分钟' : '100 行/分钟').fontSize(11).fontColor(this.subTextColor)
          }.width('100%')
        }.width('100%')

        Row({ space: 8 }) {
          ForEach([12, 20, 32], (speed: number) => {
            Button({ type: ButtonType.Normal }) {
              Text(`${speed === 12 ? '慢读' : speed === 20 ? '舒适' : '快速'} ${this.comic ? speed / 20 : speed}`)
                .fontSize(13).fontColor(this.speed === speed ? this.accentColor : this.textColor)
            }
            .layoutWeight(1).height(44).borderRadius(16).padding({ left: 4, right: 4 })
            .backgroundColor(this.speed === speed ? this.accentSurfaceColor : this.controlColor)
            .accessibilityText(`${this.comic ? `${speed / 20} 屏` : `${speed} 行`}每分钟${this.speed === speed ? '，已选中' : ''}`)
            .onClick(() => this.onSpeed(speed))
          }, (speed: number): string => `${speed}`)
        }.width('100%')

        Row({ space: 12 }) {
          Button({ type: ButtonType.Capsule }) {
            Text('结束').fontSize(14).fontColor(this.accentColor)
          }
          .height(44).padding({ left: 16, right: 16 }).backgroundColor(Color.Transparent)
          .accessibilityText('结束自动滚动').onClick(() => this.onStop())
          Button({ type: ButtonType.Capsule }) {
            Text(this.paused ? '继续滚动' : '暂停滚动').fontSize(16)
              .fontColor(ThemeRuntime.onAccentColor(this.accentColor))
          }
          .layoutWeight(1).height(44).backgroundColor(this.accentColor).onClick(() => this.onToggle())
        }.width('100%')
        Text(this.comic ? '双击正文暂停 / 继续 · 速度自动记住' : '双击正文暂停 / 继续 · 方式和速度自动记住')
          .fontSize(12).fontColor(this.subTextColor)
      }.width('100%').padding({ left: 24, right: 24, top: 8, bottom: 24 })
    }.width('100%').height('100%').scrollBar(BarState.Off)
  }
}
