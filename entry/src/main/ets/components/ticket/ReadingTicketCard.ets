import { BookCover } from '../book/BookCover';
import { BookMarkStatus } from '../../model/book/BookMark';
import { ReadingTicket, ReadingTicketRules, TicketMedia } from '../../core/ticket/ReadingTicket';
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
}

/** 票的背面：短评、一条摘录、截至读完那天的 28 天阅读日历。高度跟正面一致。 */
@Component
export struct ReadingTicketBackFace {
  @Prop ticket: ReadingTicket = new ReadingTicket();
  @Prop back: ReadingTicketBack = new ReadingTicketBack();
  @Prop cardWidth: number = DESIGN_WIDTH;
  @Prop cardHeight: number = 0;

  private u(value: number): number {
    return value * this.cardWidth / DESIGN_WIDTH;
  }

  private weeks(): number[][] {
    const cells = this.back.calendar.length > 0 ? this.back.calendar : new Array<number>(28).fill(0);
    const rows: number[][] = [];
    for (let i = 0; i < cells.length; i += 7) rows.push(cells.slice(i, i + 7));
    return rows;
  }

  build() {
    Column({ space: this.u(12) }) {
      this.heading('短评')
      Text(this.ticket.review.trim() || '还没写短评。在书籍详情的“标记”里写一句，背面就会出现。')
        .fontSize(this.u(14))
        .lineHeight(this.u(24))
        .fontColor(this.ticket.review.trim() ? BACK_TEXT : MOVIE_LABEL)
        .maxLines(6)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      if (this.back.quote) {
        this.heading('摘录')
        Text(this.back.quote)
          .fontSize(this.u(13))
          .lineHeight(this.u(22))
          .fontColor('#4A4436')
          .maxLines(5)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .padding({ left: this.u(10) })
          .border({ width: { left: this.u(3) }, color: '#C9B48A' })
      }
      this.heading(`阅读日历 · 截至 ${ReadingTicketRules.shortDate(this.back.calendarEndKey)}`)
      Column({ space: this.u(4) }) {
        ForEach(this.weeks(), (week: number[], row: number) => {
          Row({ space: this.u(4) }) {
            ForEach(week, (level: number, col: number) => {
              Column()
                .layoutWeight(1)
                .aspectRatio(1)
                .borderRadius(this.u(3))
                .backgroundColor(HEAT_COLORS[Math.max(0, Math.min(4, level))])
            }, (level: number, col: number) => `${row}:${col}:${level}`)
          }
          .width('100%')
        }, (week: number[], row: number) => `${row}:${week.join('')}`)
      }
      .width('100%')
      Blank()
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
    }
    .width(this.cardWidth)
    .constraintSize({ minHeight: this.cardHeight })
    .padding({ left: this.u(20), right: this.u(20), top: this.u(22), bottom: this.u(18) })
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(BACK_PAPER)
    .borderRadius(this.u(6))
    .shadow({ radius: this.u(18), color: '#29281E0F', offsetY: this.u(6) })
  }

  @Builder
  heading(text: string) {
    Text(text)
      .fontSize(this.u(11))
      .fontWeight(FontWeight.Bold)
      .letterSpacing(this.u(2.5))
      .fontColor(MOVIE_LABEL)
  }
}
