import { router } from '@kit.ArkUI';
import { ReadingTicketCard } from './ReadingTicketCard';
import { BookMark, BookMarkStatus } from '../../model/book/BookMark';
import { ReadingTicket, ReadingTicketRules } from '../../core/ticket/ReadingTicket';
import { ReadingTicketLoader } from '../../core/ticket/ReadingTicketLoader';
import { TicketAlbumStore } from '../../utils/TicketAlbumStore';
import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';

/**
 * 详情页“标记”页签里的票根一行：小票面 + 编号，点开单张票根页。
 * 只在读过、在读、弃读时由宿主放进来；标记一变（markKey 变化）就重读。
 */
@Component
export struct TicketStubRow {
  @StorageProp('appDarkMode') darkMode: boolean = false;
  @Prop mark: BookMark = new BookMark();
  /** workKey|status|updateTime，变了就重算这张票。 */
  @Prop @Watch('reload') markKey: string = '';
  @State ticket: ReadingTicket | null = null;
  @State ticketStyle: string = TicketAlbumStore.STYLE_PAPER;
  private generation: number = 0;

  aboutToAppear(): void {
    this.reload();
  }

  async reload(): Promise<void> {
    const generation = ++this.generation;
    try {
      const context = getContext(this);
      await TicketAlbumStore.load(context);
      const ticket = await ReadingTicketLoader.loadOne(context, this.mark);
      if (generation !== this.generation) return;
      this.ticketStyle = TicketAlbumStore.currentStyle();
      this.ticket = ticket;
    } catch (error) {
      console.warn('读取票根失败:', error);
    }
  }

  private title(): string {
    if (!this.ticket) return '票根';
    const number = ReadingTicketRules.numberText(this.ticket);
    return number ? `票根 ${number}` : `${BookMarkStatus.label(this.ticket.status)}的票`;
  }

  build() {
    Row({ space: AppSpacing.MD }) {
      if (this.ticket) {
        // 只露出票的上半截，像从票夹里抽出一角；车票本来就矮，整张显示。
        Column() {
          ReadingTicketCard({
            ticket: this.ticket as ReadingTicket,
            ticketStyle: this.ticketStyle,
            cardWidth: 56,
            notchColor: ThemeRuntime.softFillColor(this.darkMode),
            thumbnail: true
          })
        }
        .width(56)
        .height(80)
        .alignItems(HorizontalAlign.Start)
        .clip(true)
      }
      Column({ space: 2 }) {
        Text(this.title())
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(ThemeRuntime.primaryTextColor(this.darkMode))
          .fontFeature('"tnum" 1')
        Text(`${TicketAlbumStore.styleName(this.ticketStyle)} · 点开看大图、翻背面、存图`)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(ThemeRuntime.subTextColor(this.darkMode))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(14)
        .fontColor([ThemeRuntime.subTextColor(this.darkMode)])
    }
    .width('100%')
    .padding(AppSpacing.MD)
    .borderRadius(14)
    .backgroundColor(ThemeRuntime.softFillColor(this.darkMode))
    .visibility(this.ticket ? Visibility.Visible : Visibility.None)
    .accessibilityGroup(true)
    .accessibilityText(this.title())
    .onClick(() => {
      if (!this.ticket) return;
      router.pushUrl({
        url: 'pages/TicketDetail',
        params: { workKey: (this.ticket as ReadingTicket).workKey, fromDetail: 'true' }
      }).catch((error: Error) => {
        console.warn('打开票根失败:', error.message);
      });
    })
  }
}
