import { BookCover } from '../book/BookCover';
import { BookMarkStatus } from '../../model/book/BookMark';
import { ReadingTicket, ReadingTicketRules, TicketDay, TicketMedia } from '../../core/ticket/ReadingTicket';
import { ReadingTicketBack } from '../../core/ticket/ReadingTicketLoader';
import { TicketAlbumStore } from '../../utils/TicketAlbumStore';

/** 票面固定用纸张色，不跟主题和深浅色走；数值都按 300vp 宽设计，再按 cardWidth 等比缩放。 */
const DESIGN_WIDTH: number = 300;
const CARD_PAPER: string = '#F6EEDD';
const CARD_INK: string = '#1F2A3A';
const CARD_LABEL: string = '#3C4656';
const CARD_RULE: string = '#B9B0A0';
const CARD_FOOT: string = '#5F6774';
const MOVIE_PAPER: string = '#FBF6EC';
const MOVIE_LABEL: string = '#8A8170';
const MOVIE_PERF: string = '#D8CDB8';
const BACK_PAPER: string = '#FBF8F1';
const BACK_TEXT: string = '#2A2F38';
const STAMP_READ: string = '#B3352E';
const STAMP_READING: string = '#2E5F9A';
const STAMP_DROPPED: string = '#7D7D7D';
const COVER_PLACEHOLDER: string = '#8C7B65';
const HEAT_COLORS: string[] = ['#ECE5D6', '#E3C99A', '#D4A865', '#BB8236', '#8F5A1C'];
const BORROW_PAPER: string = '#EAD7A6';
const BORROW_RULE: string = '#8B6A35';
const BORROW_LINE: string = '#C4A56F';
const BORROW_CELL: string = '#B08D55';
const BORROW_LABEL: string = '#6D5229';
const BORROW_TEXT: string = '#2C2112';
const BORROW_BROWN: string = '#4A3518';
const BORROW_DATE: string = '#5A2D82';
const TRAIN_INK: string = '#13283A';
const TRAIN_SUB: string = '#46606F';
const TRAIN_RED: string = '#C0392B';
/** 借书卡每行日期戳的歪斜角度，按行轮换，看起来像手盖的。 */
const STAMP_TILTS: number[] = [-2.5, 1.5, -1, 2.5, -2, 1, -1.5];
const QR_SIZE: number = 9;

function stampColor(status: number): string {
  if (status === BookMarkStatus.READ) return STAMP_READ;
  if (status === BookMarkStatus.READING) return STAMP_READING;
  return STAMP_DROPPED;
}

/**
 * 一张票的正面。藏书卡照纸质藏书卡排：书名作者编号、三行数据、印章、日期；
 * 电影票是封面作海报，场次=开读、散场=读完、片长=时长、座号=第几本读完，下面是撕线和票根条码。
 */
@Component
export struct ReadingTicketCard {
  @Prop ticket: ReadingTicket = new ReadingTicket();
  @Prop ticketStyle: string = TicketAlbumStore.STYLE_CARD;
  @Prop cardWidth: number = DESIGN_WIDTH;
  /** 电影票两侧齿孔露出的底色，取票所在的背景。 */
  @Prop notchColor: ResourceColor = '#F5F5F5';
  /** 缩略图用小一点的封面解码尺寸。 */
  @Prop thumbnail: boolean = false;

  private u(value: number): number {
    return value * this.cardWidth / DESIGN_WIDTH;
  }

  build() {
    if (this.ticketStyle === TicketAlbumStore.STYLE_MOVIE) {
      this.movieTicket()
    } else if (this.ticketStyle === TicketAlbumStore.STYLE_BORROW) {
      this.borrowCard()
    } else if (this.ticketStyle === TicketAlbumStore.STYLE_TRAIN) {
      this.trainTicket()
    } else {
      this.libraryCard()
    }
  }

  @Builder
  cover(width: Length, height: Length, radius: number) {
    BookCover({
      bookUrl: this.ticket.bookUrl,
      origin: this.ticket.origin,
      coverUrl: this.ticket.coverUrl,
      name: this.ticket.bookName,
      author: this.ticket.author,
      useBookshelfCover: true,
      placeholderColor: COVER_PLACEHOLDER,
      cornerRadius: radius,
      decodeWidth: this.thumbnail ? 180 : 360,
      decodeHeight: this.thumbnail ? 240 : 480
    })
      .width(width)
      .height(height)
  }

  // ---------- 藏书卡 ----------

  @Builder
  libraryCard() {
    Column() {
      Column() {
        Stack({ alignContent: Alignment.Bottom }) {
          Column() {
            Text('开源轻页')
              .fontSize(this.u(12))
              .fontWeight(FontWeight.Bold)
              .letterSpacing(this.u(4))
              .fontColor(CARD_INK)
            Text('藏书卡')
              .fontSize(this.u(34))
              .fontWeight(FontWeight.Bolder)
              .letterSpacing(this.u(2))
              .fontColor(CARD_INK)
              .margin({ top: this.u(2), bottom: this.u(18) })
            Row({ space: this.u(14) }) {
              Column() {
                this.cover('100%', '100%', this.u(3))
              }
              .width(this.u(84))
              .height(this.u(116))
              .shadow({ radius: this.u(6), color: '#2E000000', offsetY: this.u(2) })
              Column({ space: this.u(8) }) {
                this.cardField('书名', this.ticket.bookName, 3)
                this.cardField('作者', this.ticket.author || '佚名', 2)
                this.cardField('编号', ReadingTicketRules.numberText(this.ticket) || '—', 1)
              }
              .layoutWeight(1)
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
            Column() {
              this.cardRow(TicketMedia.durationLabel(this.ticket.bookType),
                ReadingTicketRules.durationValue(this.ticket.totalMs).join(' ').trim())
              this.cardRow('阅读天数', this.ticket.activeDays > 0 ? `${this.ticket.activeDays}` : '—')
              this.cardRow('评分', ReadingTicketRules.ratingText(this.ticket.rating))
            }
            .width('100%')
            .margin({ top: this.u(18) })
            Text(ReadingTicketRules.rangeText(this.ticket) ? `— ${ReadingTicketRules.rangeText(this.ticket)} —` : '')
              .fontSize(this.u(11))
              .letterSpacing(this.u(0.6))
              .fontColor(CARD_FOOT)
              .margin({ top: this.u(52) })
          }
          .width('100%')
          .padding({ top: this.u(22), left: this.u(20), right: this.u(20), bottom: this.u(16) })

          Column() {
            this.ovalStamp(this.u(84), this.u(46), this.u(18))
          }
          .margin({ bottom: this.u(38) })
          .hitTestBehavior(HitTestMode.None)
        }
        .width('100%')
        .border({ width: Math.max(0.5, this.u(1)), color: CARD_INK })
      }
      .width('100%')
      .padding(this.u(4))
      .border({ width: this.u(3), color: CARD_INK })
    }
    .width(this.cardWidth)
    .padding(this.u(9))
    .backgroundColor(CARD_PAPER)
    .shadow({ radius: this.u(18), color: '#29281E0F', offsetY: this.u(6) })
  }

  @Builder
  cardField(label: string, value: string, lines: number) {
    Row({ space: this.u(8) }) {
      Text(label)
        .fontSize(this.u(12.5))
        .fontColor(CARD_LABEL)
      Text(value)
        .fontSize(this.u(12.5))
        .fontWeight(FontWeight.Bold)
        .fontColor(CARD_INK)
        .textAlign(TextAlign.End)
        .lineHeight(this.u(17))
        .maxLines(lines)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .fontFeature('"tnum" 1')
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  cardRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(this.u(13.5))
        .fontColor(CARD_INK)
      Blank()
      Text(value)
        .fontSize(this.u(13.5))
        .fontWeight(FontWeight.Bold)
        .fontColor(CARD_INK)
        .fontFeature('"tnum" 1')
    }
    .width('100%')
    .padding({ top: this.u(9), bottom: this.u(9) })
    .border({ width: { bottom: this.u(1.5) }, color: CARD_RULE })
  }

  /** 读过是双圈椭圆红章，在读是蓝色虚线方章，弃读是灰色单圈。 */
  @Builder
  ovalStamp(width: number, height: number, size: number) {
    Stack() {
      if (this.ticket.status === BookMarkStatus.READING) {
        Column()
          .width(width)
          .height(height)
          .borderRadius(this.u(10))
          .border({ width: this.u(2), color: STAMP_READING, style: BorderStyle.Dashed })
      } else {
        Ellipse()
          .width(width)
          .height(height)
          .fillOpacity(0)
          .stroke(stampColor(this.ticket.status))
          .strokeWidth(this.u(this.ticket.status === BookMarkStatus.READ ? 2.5 : 2))
        if (this.ticket.status === BookMarkStatus.READ) {
          Ellipse()
            .width(width - this.u(8))
            .height(height - this.u(8))
            .fillOpacity(0)
            .stroke(STAMP_READ)
            .strokeWidth(Math.max(0.5, this.u(1)))
        }
      }
      Text(ReadingTicketRules.stampText(this.ticket.status))
        .fontSize(size)
        .fontWeight(FontWeight.Bolder)
        .letterSpacing(this.u(2))
        .fontColor(stampColor(this.ticket.status))
    }
    .width(width)
    .height(height)
    .rotate({ angle: -10 })
    .opacity(0.88)
    .hitTestBehavior(HitTestMode.None)
  }

  // ---------- 电影票 ----------

  @Builder
  movieTicket() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column() {
        Stack() {
          this.cover('100%', '100%', 0)
          Column()
            .width('100%')
            .height('100%')
            .linearGradient({ angle: 180, colors: [['#0D0F141E', 0], ['#C80F141E', 1]] })
          Column() {
            Row() {
              Text(TicketMedia.sessionLabel(this.ticket.bookType))
                .fontSize(this.u(10))
                .fontWeight(FontWeight.Medium)
                .letterSpacing(this.u(2))
                .fontColor(Color.White)
                .padding({ left: this.u(6), right: this.u(6), top: this.u(1), bottom: this.u(1) })
                .borderRadius(this.u(3))
                .border({ width: Math.max(0.5, this.u(1)), color: '#B3FFFFFF' })
              Blank()
              Text(this.ticket.originName ? `${this.ticket.originName} 厅` : '')
                .fontSize(this.u(11))
                .fontColor('#E6FFFFFF')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .constraintSize({ maxWidth: this.u(150) })
            }
            .width('100%')
            Blank()
            Text(this.ticket.bookName)
              .fontSize(this.u(22))
              .fontWeight(FontWeight.Bolder)
              .lineHeight(this.u(28))
              .fontColor(Color.White)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(`主创 ${this.ticket.author || '佚名'}`)
              .fontSize(this.u(11.5))
              .fontColor('#E0FFFFFF')
              .maxLines(1)
              .margin({ top: this.u(2) })
          }
          .width('100%')
          .height('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ left: this.u(16), right: this.u(16), top: this.u(12), bottom: this.u(14) })
        }
        .width('100%')
        .height(this.u(150))

        Column({ space: this.u(12) }) {
          Row() {
            this.movieField('场次', ReadingTicketRules.shortDate(this.ticket.startDayKey) || '—', '')
            this.movieField('散场', this.ticket.endDayKey ? ReadingTicketRules.shortDate(this.ticket.endDayKey) :
              (this.ticket.status === BookMarkStatus.READING ? '未散场' : '—'), '')
            this.movieField('片长', ReadingTicketRules.durationValue(this.ticket.totalMs)[0],
              ReadingTicketRules.durationValue(this.ticket.totalMs)[1])
          }
          .width('100%')
          Row() {
            this.movieField('场数', this.ticket.activeDays > 0 ? `${this.ticket.activeDays}` : '—',
              this.ticket.activeDays > 0 ? '场' : '')
            this.movieField('座号', this.ticket.number > 0 ? `${this.ticket.number}` : '—',
              this.ticket.number > 0 ? '号' : '')
            this.movieField('评分', ReadingTicketRules.ratingText(this.ticket.rating), '')
          }
          .width('100%')
        }
        .width('100%')
        .padding({ left: this.u(16), right: this.u(16), top: this.u(14), bottom: this.u(14) })

        // 撕线：虚线加两侧半圆缺口（圆心压在票边上，外半圆被裁掉）。
        Stack() {
          Column()
            .width('100%')
            .height(0)
            .border({ width: { top: this.u(2) }, color: MOVIE_PERF, style: BorderStyle.Dashed })
            .padding({ left: this.u(14), right: this.u(14) })
          Row() {
            Circle()
              .width(this.u(18))
              .height(this.u(18))
              .fill(this.notchColor)
              .offset({ x: -this.u(9) })
            Blank()
            Circle()
              .width(this.u(18))
              .height(this.u(18))
              .fill(this.notchColor)
              .offset({ x: this.u(9) })
          }
          .width('100%')
        }
        .width('100%')
        .height(this.u(18))

        Row({ space: this.u(12) }) {
          Column() {
            Text(ReadingTicketRules.numberText(this.ticket) || '—')
              .fontSize(this.u(12))
              .fontWeight(FontWeight.Medium)
              .fontColor(CARD_INK)
              .fontFeature('"tnum" 1')
            Text(ReadingTicketRules.checkText(this.ticket.status))
              .fontSize(this.u(10))
              .fontColor(MOVIE_LABEL)
          }
          .alignItems(HorizontalAlign.Start)
          Blank()
          Row() {
            ForEach(ReadingTicketRules.barcode(this.ticket.workKey || this.ticket.bookName),
              (width: number, index: number) => {
                Column()
                  .width(this.u(width))
                  .height(this.u(34))
                  .backgroundColor(CARD_INK)
                  .margin({ right: this.u(index % 3 === 0 ? 2 : 1) })
              }, (width: number, index: number) => `${index}:${width}`)
          }
        }
        .width('100%')
        .padding({ left: this.u(16), right: this.u(16), top: this.u(10), bottom: this.u(16) })
      }
      .width('100%')
      .backgroundColor(MOVIE_PAPER)
      .borderRadius(this.u(12))
      .clip(true)

      Column() {
        this.circleStamp(this.u(66), this.u(15))
      }
      .margin({ top: this.u(118), right: this.u(16) })
      .hitTestBehavior(HitTestMode.None)
    }
    .width(this.cardWidth)
    .borderRadius(this.u(12))
    .shadow({ radius: this.u(18), color: '#29281E0F', offsetY: this.u(6) })
  }

  @Builder
  movieField(label: string, value: string, unit: string) {
    Column({ space: this.u(1) }) {
      Text(label)
        .fontSize(this.u(10))
        .letterSpacing(this.u(0.8))
        .fontColor(MOVIE_LABEL)
      Row({ space: this.u(1) }) {
        Text(value)
          .fontSize(this.u(14))
          .fontWeight(FontWeight.Medium)
          .fontColor(CARD_INK)
          .fontFeature('"tnum" 1')
          .maxLines(1)
        if (unit) {
          Text(unit)
            .fontSize(this.u(10))
            .fontColor(CARD_INK)
        }
      }
      .alignItems(VerticalAlign.Bottom)
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  circleStamp(size: number, fontSize: number) {
    Stack() {
      if (this.ticket.status === BookMarkStatus.READING) {
        Circle()
          .width(size)
          .height(size)
          .fillOpacity(0)
          .stroke(STAMP_READING)
          .strokeWidth(this.u(2))
          .strokeDashArray([this.u(5), this.u(4)])
      } else {
        Circle()
          .width(size)
          .height(size)
          .fillOpacity(0)
          .stroke(stampColor(this.ticket.status))
          .strokeWidth(this.u(this.ticket.status === BookMarkStatus.READ ? 2.5 : 2))
        if (this.ticket.status === BookMarkStatus.READ) {
          Circle()
            .width(size - this.u(8))
            .height(size - this.u(8))
            .fillOpacity(0)
            .stroke(STAMP_READ)
            .strokeWidth(Math.max(0.5, this.u(1)))
        }
      }
      Text(ReadingTicketRules.stampText(this.ticket.status))
        .fontSize(fontSize)
        .fontWeight(FontWeight.Bolder)
        .letterSpacing(this.u(1.5))
        .fontColor(stampColor(this.ticket.status))
    }
    .width(size)
    .height(size)
    .rotate({ angle: 12 })
    .opacity(0.88)
    .hitTestBehavior(HitTestMode.None)
  }

  // ---------- 借书卡 ----------

  /** 固定七行：有记录的日子旧的在前；读过的书读完那天红字“读完”（那天没记录就补一行），其余留空行。 */
  private borrowRows(): TicketDay[] {
    const rows = this.ticket.log.slice();
    const finishKey = this.ticket.status === BookMarkStatus.READ ? this.ticket.endDayKey : '';
    if (finishKey && !rows.some((day: TicketDay): boolean => day.dayKey === finishKey)) {
      if (rows.length >= ReadingTicketRules.LOG_DAYS) rows.shift();
      const finish = new TicketDay();
      finish.dayKey = finishKey;
      rows.push(finish);
    }
    while (rows.length < 7) rows.push(new TicketDay());
    return rows.slice(0, 7);
  }

  private isFinishRow(day: TicketDay): boolean {
    return !!day.dayKey && this.ticket.status === BookMarkStatus.READ && day.dayKey === this.ticket.endDayKey;
  }

  private hairline(): number {
    return Math.max(0.5, this.u(1));
  }

  @Builder
  borrowCard() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        Circle()
          .width(this.u(16))
          .height(this.u(16))
          .fill(this.notchColor)
        Text('借书卡')
          .fontSize(this.u(20))
          .fontWeight(FontWeight.Bolder)
          .letterSpacing(this.u(14))
          .fontColor(BORROW_BROWN)
          .margin({ top: this.u(4), bottom: this.u(10), left: this.u(14) })
        Column() {
          this.borrowMeta('书名', this.ticket.bookName, false)
          this.borrowMeta('著者', this.ticket.author || '佚名', false)
          this.borrowMeta('卡号', ReadingTicketRules.numberText(this.ticket) || '—', true)
        }
        .width('100%')
        .border({ width: this.u(1.5), color: BORROW_RULE })

        Column() {
          Row() {
            this.borrowHead('日期')
            this.borrowHead('时长')
            this.borrowHead('累计')
          }
          .width('100%')
          .border({ width: { bottom: this.u(1.5) }, color: BORROW_RULE })
          ForEach(this.borrowRows(), (day: TicketDay, index: number) => {
            this.borrowLine(day, index)
          }, (day: TicketDay, index: number) => `${index}:${day.dayKey}:${day.durationMs}`)
        }
        .width('100%')
        .margin({ top: this.u(10) })
        .border({ width: this.u(1.5), color: BORROW_RULE })

        Row() {
          Text(this.ticket.activeDays > 0 ?
            `共 ${this.ticket.activeDays} 日 · ${ReadingTicketRules.durationValue(this.ticket.totalMs).join(' ').trim()}` :
            '没有阅读记录')
            .fontSize(this.u(11.5))
            .fontColor(BORROW_BROWN)
            .fontFeature('"tnum" 1')
          Blank()
          Text(ReadingTicketRules.ratingText(this.ticket.rating))
            .fontSize(this.u(11.5))
            .fontColor(BORROW_BROWN)
        }
        .width('100%')
        .margin({ top: this.u(9) })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .padding({ left: this.u(16), right: this.u(16), top: this.u(12), bottom: this.u(18) })

      Column() {
        this.circleStamp(this.u(62), this.u(14))
      }
      .margin({ right: this.u(22), bottom: this.u(40) })
      .hitTestBehavior(HitTestMode.None)
    }
    .width(this.cardWidth)
    .backgroundColor(BORROW_PAPER)
    .borderRadius(this.u(2))
    .shadow({ radius: this.u(18), color: '#29281E0F', offsetY: this.u(6) })
  }

  @Builder
  borrowLine(day: TicketDay, index: number) {
    Row() {
      Text(day.dayKey ? ReadingTicketRules.shortDate(day.dayKey) : '')
        .fontSize(this.u(11.5))
        .fontWeight(FontWeight.Medium)
        .fontColor(this.isFinishRow(day) ? STAMP_READ : BORROW_DATE)
        .fontFeature('"tnum" 1')
        .rotate({ angle: STAMP_TILTS[index % STAMP_TILTS.length] })
        .textAlign(TextAlign.Center)
        .layoutWeight(1)
      Text(day.durationMs > 0 ? ReadingTicketRules.durationValue(day.durationMs).join(' ').trim() : '')
        .fontSize(this.u(11.5))
        .fontColor(BORROW_TEXT)
        .fontFeature('"tnum" 1')
        .textAlign(TextAlign.Center)
        .layoutWeight(1)
        .height('100%')
        .border({ width: { left: this.hairline(), right: this.hairline() }, color: BORROW_LINE })
      Text(this.isFinishRow(day) ? '读完' :
        (day.cumulativeMs > 0 ? ReadingTicketRules.durationValue(day.cumulativeMs).join(' ').trim() : ''))
        .fontSize(this.u(11))
        .fontWeight(this.isFinishRow(day) ? FontWeight.Bold : FontWeight.Regular)
        .fontColor(this.isFinishRow(day) ? STAMP_READ : BORROW_BROWN)
        .fontFeature('"tnum" 1')
        .textAlign(TextAlign.Center)
        .layoutWeight(1)
    }
    .width('100%')
    .height(this.u(25))
    .border({ width: { top: index === 0 ? 0 : this.hairline() }, color: BORROW_LINE })
  }

  @Builder
  borrowMeta(label: string, value: string, last: boolean) {
    Row() {
      Text(label)
        .fontSize(this.u(12))
        .letterSpacing(this.u(2.5))
        .fontColor(BORROW_LABEL)
        .padding({ left: this.u(8), right: this.u(8) })
        .height('100%')
        .border({ width: { right: this.hairline() }, color: BORROW_CELL })
      Text(value)
        .fontSize(this.u(13))
        .fontWeight(FontWeight.Bold)
        .fontColor(BORROW_TEXT)
        .fontFeature('"tnum" 1')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .padding({ left: this.u(8), right: this.u(8) })
        .layoutWeight(1)
    }
    .width('100%')
    .height(this.u(28))
    .border({ width: { bottom: last ? 0 : this.hairline() }, color: BORROW_CELL })
  }

  @Builder
  borrowHead(label: string) {
    Text(label)
      .fontSize(this.u(11))
      .letterSpacing(this.u(2))
      .fontColor(BORROW_LABEL)
      .textAlign(TextAlign.Center)
      .padding({ top: this.u(4), bottom: this.u(4) })
      .layoutWeight(1)
  }

  // ---------- 车票 ----------

  /** 车票：开读站到读完站，车次 = 第几本读完，票价位写时长，右下角装饰二维码。 */
  @Builder
  trainTicket() {
    // 不能用 100% 高的子组件铺底纹：Stack 没有定高，放进列表会被撑到可视区那么高。斜纹画在内容层自己的背景上。
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        Row() {
          Text(ReadingTicketRules.trainNumberText(this.ticket))
            .fontSize(this.u(12))
            .fontWeight(FontWeight.Medium)
            .fontColor(TRAIN_RED)
            .fontFeature('"tnum" 1')
          Blank()
          Text(this.ticket.originName ? `${this.ticket.originName} 检票口` : '')
            .fontSize(this.u(11))
            .fontColor(TRAIN_SUB)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: this.u(170) })
        }
        .width('100%')

        Row() {
          this.trainStation('开读', '出发')
          Column({ space: this.u(2) }) {
            Text(this.ticket.number > 0 ? `第${this.ticket.number}次` :
              (this.ticket.status === BookMarkStatus.READING ? '进行中' : '未到站'))
              .fontSize(this.u(12))
              .fontWeight(FontWeight.Medium)
              .fontColor(TRAIN_INK)
              .fontFeature('"tnum" 1')
            Stack({ alignContent: Alignment.End }) {
              Column()
                .width(this.u(60))
                .height(Math.max(0.5, this.u(1.5)))
                .backgroundColor(TRAIN_INK)
              Column()
                .width(this.u(7))
                .height(this.u(7))
                .border({ width: { top: Math.max(0.5, this.u(1.5)), right: Math.max(0.5, this.u(1.5)) },
                  color: TRAIN_INK })
                .rotate({ angle: 45 })
                .margin({ right: this.u(1) })
            }
            .width(this.u(62))
            .height(this.u(10))
          }
          .padding({ left: this.u(6), right: this.u(6) })
          this.trainStation(ReadingTicketRules.arrivalText(this.ticket.status, this.ticket.bookType)[0],
            ReadingTicketRules.arrivalText(this.ticket.status, this.ticket.bookType)[1])
        }
        .width('100%')
        .margin({ top: this.u(8) })

        Row() {
          this.trainDate(this.ticket.startDayKey)
          this.trainDate(this.ticket.endDayKey)
        }
        .width('100%')
        .margin({ top: this.u(2) })

        Row({ space: this.u(10) }) {
          Column() {
            this.cover('100%', '100%', this.u(2))
          }
          .width(this.u(40))
          .height(this.u(54))
          Column({ space: this.u(2) }) {
            Text(this.ticket.bookName)
              .fontSize(this.u(15))
              .fontWeight(FontWeight.Bold)
              .fontColor(TRAIN_INK)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(`${this.ticket.author || '佚名'} · ${this.ticket.activeDays > 0 ? this.ticket.activeDays : '—'} 天 · ` +
              ReadingTicketRules.ratingText(this.ticket.rating))
              .fontSize(this.u(11))
              .fontColor('#3B5566')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .margin({ top: this.u(12) })

        Row() {
          Column({ space: this.u(1) }) {
            Row({ space: this.u(2) }) {
              Text(ReadingTicketRules.durationValue(this.ticket.totalMs)[0])
                .fontSize(this.u(18))
                .fontWeight(FontWeight.Medium)
                .fontColor(TRAIN_INK)
                .fontFeature('"tnum" 1')
              Text(ReadingTicketRules.durationValue(this.ticket.totalMs)[1])
                .fontSize(this.u(11))
                .fontColor(TRAIN_INK)
            }
            .alignItems(VerticalAlign.Bottom)
            Text('仅供纪念 · 开源轻页')
              .fontSize(this.u(9.5))
              .fontColor(TRAIN_SUB)
          }
          .alignItems(HorizontalAlign.Start)
          Blank()
          this.qrCode()
        }
        .width('100%')
        .alignItems(VerticalAlign.Bottom)
        .margin({ top: this.u(10) })
        .padding({ top: this.u(8) })
        .border({ width: { top: this.hairline() }, color: '#5913283A', style: BorderStyle.Dashed })
      }
      .width('100%')
      .padding({ left: this.u(16), right: this.u(16), top: this.u(12), bottom: this.u(12) })
      .linearGradient({
        angle: 45,
        repeating: true,
        colors: [['#2EFFFFFF', 0], ['#2EFFFFFF', 0.008], ['#00FFFFFF', 0.008], ['#00FFFFFF', 0.026]]
      })

      Column() {
        this.circleStamp(this.u(56), this.u(13))
      }
      .margin({ right: this.u(74), bottom: this.u(14) })
      .hitTestBehavior(HitTestMode.None)
    }
    .width(this.cardWidth)
    .borderRadius(this.u(10))
    .clip(true)
    .linearGradient({ angle: 135, colors: [['#CFE6EA', 0], ['#B9D8E6', 0.55], ['#C9DFF0', 1]] })
    .shadow({ radius: this.u(18), color: '#29281E0F', offsetY: this.u(6) })
  }

  @Builder
  trainStation(name: string, caption: string) {
    Column() {
      Text(name)
        .fontSize(this.u(22))
        .fontWeight(FontWeight.Bolder)
        .letterSpacing(this.u(3))
        .fontColor(TRAIN_INK)
      Text(caption)
        .fontSize(this.u(10))
        .letterSpacing(this.u(2))
        .fontColor(TRAIN_SUB)
    }
    .layoutWeight(1)
  }

  @Builder
  trainDate(dayKey: string) {
    Text(ReadingTicketRules.monthDayText(dayKey) || '—')
      .fontSize(this.u(13))
      .fontWeight(FontWeight.Medium)
      .fontColor(TRAIN_INK)
      .fontFeature('"tnum" 1')
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
  }

  private qrRows(): boolean[][] {
    const cells = ReadingTicketRules.qrCells(this.ticket.workKey || this.ticket.bookName, QR_SIZE);
    const rows: boolean[][] = [];
    for (let i = 0; i < cells.length; i += QR_SIZE) rows.push(cells.slice(i, i + QR_SIZE));
    return rows;
  }

  @Builder
  qrCode() {
    Column() {
      ForEach(this.qrRows(), (cells: boolean[], row: number) => {
        Row() {
          ForEach(cells, (dark: boolean, col: number) => {
            Column()
              .width(this.u(4))
              .height(this.u(4))
              .backgroundColor(dark ? TRAIN_INK : Color.Transparent)
          }, (dark: boolean, col: number) => `${row}:${col}:${dark}`)
        }
      }, (cells: boolean[], row: number) => `${row}:${cells.join(',')}`)
    }
    .padding(this.u(3))
    .backgroundColor(Color.White)
  }
}

/** 背面各块的尺寸：先扣掉日历、页脚和留白，剩下的高度再分给短评和摘录。 */
class TicketBackLayout {
  height: number = 0;
  padTop: number = 0;
  padBottom: number = 0;
  space: number = 0;
  columns: number = 7;
  textAreaHeight: number = 0;
  reviewLines: number = 1;
  quoteLines: number = 0;
}

/**
 * 票的背面：短评、一条摘录、截至读完那天的 28 天阅读日历。高度始终跟正面一样，
 * 短评、摘录长了按剩下的行数截断，不会把卡片撑长；横向的票（车票）日历排成两行 14 格。
 */
@Component
export struct ReadingTicketBackFace {
  @Prop ticket: ReadingTicket = new ReadingTicket();
  @Prop back: ReadingTicketBack = new ReadingTicketBack();
  @Prop cardWidth: number = DESIGN_WIDTH;
  /** 正面量到的高度；0 时按竖向票的常见比例。 */
  @Prop cardHeight: number = 0;

  private u(value: number): number {
    return value * this.cardWidth / DESIGN_WIDTH;
  }

  private reviewText(): string {
    return this.ticket.review.trim() || '还没写短评。在书籍详情的“标记”里写一句，背面就会出现。';
  }

  /** 按每行能放几个字粗估要几行；英文和数字按半个字算，换行符另起一行。 */
  private estimateLines(text: string, fontSize: number, width: number): number {
    const perLine = Math.max(1, Math.floor(width / fontSize));
    let lines = 0;
    text.split('\n').forEach((part: string): void => {
      let units = 0;
      for (let i = 0; i < part.length; i++) units += part.charCodeAt(i) < 128 ? 0.55 : 1;
      lines += Math.max(1, Math.ceil(units / perLine));
    });
    return lines;
  }

  private layout(): TicketBackLayout {
    const layout = new TicketBackLayout();
    const height = this.cardHeight > 0 ? this.cardHeight : this.cardWidth * 1.45;
    const landscape = height < this.cardWidth;
    layout.height = height;
    layout.columns = landscape ? 14 : 7;
    layout.padTop = this.u(landscape ? 14 : 22);
    layout.padBottom = this.u(landscape ? 12 : 18);
    layout.space = this.u(landscape ? 8 : 12);
    const innerWidth = this.cardWidth - this.u(40);
    const gap = this.u(landscape ? 3 : 4);
    const cell = (innerWidth - gap * (layout.columns - 1)) / layout.columns;
    const rows = Math.ceil(28 / layout.columns);
    const gridHeight = rows * cell + (rows - 1) * gap;
    const headingHeight = this.u(16);
    const footerHeight = this.u(16);
    layout.textAreaHeight = Math.max(0, height - layout.padTop - layout.padBottom - headingHeight - gridHeight -
      footerHeight - layout.space * 3);

    const reviewLine = this.u(24);
    const quoteLine = this.u(22);
    const head = headingHeight + this.u(6);
    const reviewNeed = this.estimateLines(this.reviewText(), this.u(14), innerWidth);
    const reviewMax = Math.max(1, Math.floor((layout.textAreaHeight - head) / reviewLine));
    layout.reviewLines = Math.min(reviewNeed, reviewMax);
    if (this.back.quote) {
      const quoteNeed = this.estimateLines(this.back.quote, this.u(13), innerWidth - this.u(13));
      const quoteHead = this.u(10) + head;
      // 摘录至少留两行；放不下就只显示短评。
      const reviewRoom = Math.floor((layout.textAreaHeight - head - quoteHead - 2 * quoteLine) / reviewLine);
      if (reviewRoom >= 1) {
        layout.reviewLines = Math.min(reviewNeed, reviewRoom);
        const quoteRoom = Math.floor((layout.textAreaHeight - head - layout.reviewLines * reviewLine - quoteHead) /
          quoteLine);
        layout.quoteLines = Math.max(0, Math.min(quoteNeed, quoteRoom));
        if (layout.quoteLines < Math.min(2, quoteNeed)) layout.quoteLines = 0;
      }
    }
    return layout;
  }

  private weeks(columns: number): number[][] {
    const cells = this.back.calendar.length > 0 ? this.back.calendar : new Array<number>(28).fill(0);
    const rows: number[][] = [];
    for (let i = 0; i < cells.length; i += columns) rows.push(cells.slice(i, i + columns));
    return rows;
  }

  build() {
    Column({ space: this.layout().space }) {
      Column({ space: this.u(6) }) {
        this.heading('短评')
        Text(this.reviewText())
          .fontSize(this.u(14))
          .lineHeight(this.u(24))
          .fontColor(this.ticket.review.trim() ? BACK_TEXT : MOVIE_LABEL)
          .maxLines(this.layout().reviewLines)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        if (this.layout().quoteLines > 0) {
          Column() {
            this.heading('摘录')
          }
          .margin({ top: this.u(10) })
          Text(this.back.quote)
            .fontSize(this.u(13))
            .lineHeight(this.u(22))
            .fontColor('#4A4436')
            .maxLines(this.layout().quoteLines)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .padding({ left: this.u(10) })
            .border({ width: { left: this.u(3) }, color: '#C9B48A' })
        }
      }
      .width('100%')
      .height(this.layout().textAreaHeight)
      .alignItems(HorizontalAlign.Start)
      .clip(true)

      this.heading(`阅读日历 · 截至 ${ReadingTicketRules.shortDate(this.back.calendarEndKey)}`)
      Column({ space: this.u(this.layout().columns > 7 ? 3 : 4) }) {
        ForEach(this.weeks(this.layout().columns), (week: number[], row: number) => {
          Row({ space: this.u(this.layout().columns > 7 ? 3 : 4) }) {
            ForEach(week, (level: number, col: number) => {
              Column()
                .layoutWeight(1)
                .aspectRatio(1)
                .borderRadius(this.u(this.layout().columns > 7 ? 2 : 3))
                .backgroundColor(HEAT_COLORS[Math.max(0, Math.min(4, level))])
            }, (level: number, col: number) => `${row}:${col}:${level}`)
          }
          .width('100%')
        }, (week: number[], row: number) => `${week.length}:${row}:${week.join('')}`)
      }
      .width('100%')
      Row() {
        Text(`划线 ${this.back.annotationCount} 条`)
          .fontSize(this.u(11))
          .fontColor(MOVIE_LABEL)
        Blank()
        Text(ReadingTicketRules.numberText(this.ticket) || ReadingTicketRules.stampText(this.ticket.status))
          .fontSize(this.u(11))
          .fontColor(MOVIE_LABEL)
          .fontFeature('"tnum" 1')
      }
      .width('100%')
      .height(this.u(16))
    }
    .width(this.cardWidth)
    .height(this.layout().height)
    .padding({ left: this.u(20), right: this.u(20), top: this.layout().padTop, bottom: this.layout().padBottom })
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(BACK_PAPER)
    .borderRadius(this.u(6))
    .clip(true)
    .shadow({ radius: this.u(18), color: '#29281E0F', offsetY: this.u(6) })
  }

  @Builder
  heading(text: string) {
    Text(text)
      .fontSize(this.u(11))
      .fontWeight(FontWeight.Bold)
      .letterSpacing(this.u(2.5))
      .fontColor(MOVIE_LABEL)
      .height(this.u(16))
  }
}
