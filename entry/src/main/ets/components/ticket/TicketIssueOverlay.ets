import { curves } from '@kit.ArkUI';
import { ReadingTicketCard, ticketAspect } from './ReadingTicketCard';
import { ReadingTicket } from '../../core/ticket/ReadingTicket';
import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';

/**
 * 标成“读过”后出票：压暗页面，票从屏幕下方升上来落定，再出一句“已收进票夹”和两个按钮。
 * 点遮罩或“好的”收起；“看看这张票”交给宿主打开单张票根页。宿主放在页面最外层 Stack 的最后。
 */
@Component
export struct TicketIssueOverlay {
  @StorageProp('appDarkMode') darkMode: boolean = false;
  @Prop ticket: ReadingTicket = new ReadingTicket();
  @Prop ticketStyle: string = 'card';
  onOpen: () => void = (): void => {
  };
  onClose: () => void = (): void => {
  };
  @State scrim: number = 0;
  @State rise: number = 1;
  @State tilt: number = 6;
  @State captionOpacity: number = 0;
  @State pageHeight: number = 800;
  private closing: boolean = false;

  aboutToAppear(): void {
    // 等标记面板收起的动画走完再出票。
    setTimeout(() => {
      this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
        this.scrim = 1;
      });
      this.getUIContext().animateTo({ duration: 900, curve: curves.springMotion(0.6, 0.78), delay: 120 }, () => {
        this.rise = 0;
        this.tilt = 0;
      });
      this.getUIContext().animateTo({ duration: 260, curve: Curve.EaseOut, delay: 820 }, () => {
        this.captionOpacity = 1;
      });
    }, 280);
  }

  private close(then?: () => void): void {
    if (this.closing) return;
    this.closing = true;
    this.getUIContext().animateTo({
      duration: 200, curve: Curve.EaseIn, onFinish: () => {
        this.onClose();
        if (then) then();
      }
    }, () => {
      this.scrim = 0;
      this.captionOpacity = 0;
      this.rise = 0.12;
    });
  }

  /** 票加下面的提示和按钮要放得下：高的票（影票、暗场）按高度反推宽度。 */
  private cardWidth(): number {
    const byHeight = (this.pageHeight - 220) / ticketAspect(this.ticketStyle);
    return Math.max(150, Math.min(300, byHeight));
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#73000000')
        .opacity(this.scrim)
        .onClick(() => {
          this.close();
        })

      Column({ space: AppSpacing.XL }) {
        Column() {
          ReadingTicketCard({
            ticket: this.ticket,
            ticketStyle: this.ticketStyle,
            cardWidth: this.cardWidth(),
            notchColor: '#5C5C5C'
          })
        }
        .translate({ y: this.rise * this.pageHeight })
        .rotate({ angle: this.tilt })
        .opacity(this.rise >= 1 ? 0 : 1 - this.rise * 0.6)
        .onClick(() => {
          this.close(this.onOpen);
        })

        Column({ space: AppSpacing.MD }) {
          Text(this.ticket.number > 0 ? `已收进票夹 · 第 ${this.ticket.number} 张` : '已收进票夹')
            .fontSize(AppFontSize.BODY)
            .fontColor(Color.White)
            .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: 7, bottom: 7 })
            .borderRadius(18)
            .backgroundColor('#DB14161A')
          Row({ space: AppSpacing.MD }) {
            Text('好的')
              .fontSize(AppFontSize.BODY_LARGE)
              .fontColor(ThemeRuntime.primaryTextColor(this.darkMode))
              .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: 9, bottom: 9 })
              .borderRadius(20)
              .backgroundColor(ThemeRuntime.cardColor(this.darkMode))
              .onClick(() => {
                this.close();
              })
            Text('看看这张票')
              .fontSize(AppFontSize.BODY_LARGE)
              .fontWeight(FontWeight.Medium)
              .fontColor(ThemeRuntime.onAccentColor(ThemeRuntime.accentColor(this.darkMode)))
              .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: 9, bottom: 9 })
              .borderRadius(20)
              .backgroundColor(ThemeRuntime.accentColor(this.darkMode))
              .onClick(() => {
                this.close(this.onOpen);
              })
          }
        }
        .opacity(this.captionOpacity)
        .hitTestBehavior(this.captionOpacity > 0.5 ? HitTestMode.Default : HitTestMode.None)
      }
      .alignItems(HorizontalAlign.Center)
      .hitTestBehavior(HitTestMode.Transparent)
    }
    .width('100%')
    .height('100%')
    .onSizeChange((_oldValue: SizeOptions, newValue: SizeOptions) => {
      this.pageHeight = Number(newValue.height) || this.pageHeight;
    })
  }
}
