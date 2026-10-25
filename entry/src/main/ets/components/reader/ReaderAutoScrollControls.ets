import { ReaderMaterialPanel } from './ReaderFloatingMaterialBar';
import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { ImmersiveMaterialRuntime } from '../../utils/ImmersiveMaterialRuntime';

/** 轻盈光感：阅读时只保留调速与暂停，结束操作留在展开面板内。 */
@Component
export struct ReaderAutoScrollCapsule {
  @Prop speed: number = 20;
  @Prop paused: boolean = false;
  @Prop status: string = '';
  @Prop textColor: string;
  @Prop subTextColor: string;
  @Prop accentColor: string;
  @Prop accentSurfaceColor: string;
  @Prop panelColor: string;
  @Prop dark: boolean = false;
  onOpen: () => void = (): void => {};
  onToggle: () => void = (): void => {};

  static readonly WIDTH: number = 248;
  static readonly HEIGHT: number = 56;

  build() {
    ReaderMaterialPanel({
      panelWidth: ReaderAutoScrollCapsule.WIDTH, panelHeight: ReaderAutoScrollCapsule.HEIGHT,
      cornerRadius: 28, darkMode: this.dark, fallbackColor: this.panelColor
    }) {
      Row({ space: 4 }) {
        Button({ type: ButtonType.Normal }) {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.arrow_down'))
              .fontSize(20).fontColor([this.accentColor])
            Column({ space: 2 }) {
              Text(this.status || (this.paused ? '已暂停' : '自动滚动'))
                .fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.textColor)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(`${this.speed} 行/分钟 · 调速`)
                .fontSize(11).fontColor(this.subTextColor).maxLines(1)
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          }.width('100%')
        }
        .layoutWeight(1).height(48).padding({ left: 8, right: 4 })
        .borderRadius(24).backgroundColor(Color.Transparent)
        .accessibilityText(`自动滚动，${this.speed} 行每分钟，点击调整速度`)
        .onClick(() => this.onOpen())
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph(this.paused ? $r('sys.symbol.play') : $r('sys.symbol.pause'))
            .fontSize(20).fontColor([this.accentColor])
        }
        .width(44).height(44).backgroundColor(this.accentSurfaceColor)
        .accessibilityText(this.paused ? '继续自动滚动' : '暂停自动滚动')
        .onClick(() => this.onToggle())
      }.width('100%').height('100%').padding({ left: 8, right: 8 })
    }
  }
}

/** 半模态自身承接系统沉浸光感；内容不再铺第二层不透明底板。 */
@Component
export struct ReaderAutoScrollSpeedPanel {
  @Prop speed: number = 20;
  @Prop paused: boolean = false;
  @Prop status: string = '';
  @Prop textColor: string;
  @Prop subTextColor: string;
  @Prop accentColor: string;
  @Prop accentSurfaceColor: string;
  @Prop controlColor: string;
  onSpeed: (speed: number) => void = (_speed: number): void => {};
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

  build() {
    Scroll() {
      Column({ space: 12 }) {
        Row({ space: 8 }) {
          Column({ space: 4 }) {
            Text('自动滚动').fontSize(20).fontWeight(FontWeight.Medium).fontColor(this.textColor)
            Text(this.status || (this.paused ? '已暂停 · 按自己的节奏阅读' : '正在滚动 · 调速即时生效'))
              .fontSize(12).fontColor(this.subTextColor).maxLines(2)
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.chevron_down')).fontSize(20).fontColor([this.accentColor])
          }
          .width(44).height(44).backgroundColor(this.controlColor)
          .accessibilityText('收起调速面板').onClick(() => this.onClose())
        }.width('100%')

        Row({ space: 16 }) {
          this.speedStep($r('sys.symbol.minus'), '每分钟减慢两行', -2, this.speed > 6)
          Row({ space: 8 }) {
            Text(`${this.speed}`).fontSize(38).fontColor(this.textColor)
            Text('行 / 分钟').fontSize(12).fontColor(this.subTextColor)
          }.layoutWeight(1).justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Bottom)
          this.speedStep($r('sys.symbol.plus'), '每分钟加快两行', 2, this.speed < 60)
        }.width('100%').margin({ top: 4 })

        Column() {
          Slider({ value: this.speed, min: 6, max: 60, step: 2 })
            .height(44).selectedColor(this.accentColor).blockColor(this.accentColor)
            .trackColor(this.controlColor)
            .sliderInteractionMode(ImmersiveMaterialRuntime.supportsHds() ?
              SliderInteraction.SLIDE_AND_CLICK_UP : SliderInteraction.SLIDE_ONLY)
            .accessibilityText('自动滚动速度，每分钟六至六十行')
            .onChange((speed: number) => this.onSpeed(speed))
          Row() {
            Text('6 行/分钟').fontSize(11).fontColor(this.subTextColor)
            Blank()
            Text('60 行/分钟').fontSize(11).fontColor(this.subTextColor)
          }.width('100%')
        }.width('100%')

        Row({ space: 8 }) {
          ForEach([12, 20, 32], (speed: number) => {
            Button({ type: ButtonType.Normal }) {
              Text(`${speed === 12 ? '慢读' : speed === 20 ? '舒适' : '快速'} ${speed}`)
                .fontSize(13).fontColor(this.speed === speed ? this.accentColor : this.textColor)
            }
            .layoutWeight(1).height(44).borderRadius(16).padding({ left: 4, right: 4 })
            .backgroundColor(this.speed === speed ? this.accentSurfaceColor : this.controlColor)
            .accessibilityText(`${speed} 行每分钟${this.speed === speed ? '，已选中' : ''}`)
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
        Text('触碰正文即暂停 · 速度自动记住').fontSize(12).fontColor(this.subTextColor)
      }.width('100%').padding({ left: 24, right: 24, top: 8, bottom: 24 })
    }.width('100%').height('100%').scrollBar(BarState.Off)
  }
}
