class CoverRouteParams {
  shortcutAction: string = 'open_book';
  bookUrl: string = '';

  constructor(bookUrl: string) {
    this.bookUrl = bookUrl;
  }
}

class CoverRouteAction {
  action: string = 'router';
  abilityName: string = 'EntryAbility';
  params: CoverRouteParams;

  constructor(bookUrl: string) {
    this.params = new CoverRouteParams(bookUrl);
  }
}

class CoverOpenAppParams {
  source: string = 'coverReadCard';
}

/** 空状态点击：只拉起应用，不带 shortcutAction。 */
class CoverOpenAppAction {
  action: string = 'router';
  abilityName: string = 'EntryAbility';
  params: CoverOpenAppParams = new CoverOpenAppParams();
}

let coverStorage = new LocalStorage();

/**
 * 封面卡片（仅 2×2）：最近一本书的封面铺满整张卡，底部压暗渐变，上面叠章节和书名。
 * 与「最近阅读」卡片共用 RecentReadFormAbility 和同一份 RecentReadCardData，只读最近一本的字段。
 */
@Entry(coverStorage)
@Component
struct CoverReadCard {
  @LocalStorageProp('version') version: number = 0;
  @LocalStorageProp('orderSignature') orderSignature: string = '';
  @LocalStorageProp('count') count: number = 0;
  @LocalStorageProp('emptyTitle') emptyTitle: string = '暂无最近阅读';
  @LocalStorageProp('emptySubtitle') emptySubtitle: string = '打开书架阅读后会显示在这里';
  @LocalStorageProp('accentColor') accentColor: string = '#007DFF';

  @LocalStorageProp('book0Name') book0Name: string = '';
  @LocalStorageProp('book0Chapter') book0Chapter: string = '';
  @LocalStorageProp('book0Percent') book0Percent: number = -1;
  @LocalStorageProp('book0Time') book0Time: string = '';
  @LocalStorageProp('book0Url') book0Url: string = '';
  @LocalStorageProp('book0Cover') book0Cover: string = '';

  build() {
    Stack() {
      Text(`${this.version}|${this.orderSignature}`)
        .height(0)
        .opacity(0)
        .fontSize(1)

      // 按 version 重建内容树，保证每次 updateForm 后图片和文字都换成新数据。
      ForEach([this.version], (_version: number) => {
        if (this.count <= 0 || !this.book0Url) {
          this.emptyState()
        } else {
          this.coverLayout()
        }
      }, (version: number) => `${version}`)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.accentColor)
  }

  @Builder
  coverLayout() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 无封面时：主题色底 + 书名首字。
      Column() {
        Text(this.bookName().substring(0, 1))
          .fontSize(56)
          .fontWeight(FontWeight.Bold)
          .fontColor('#59FFFFFF')
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .linearGradient({
        angle: 160,
        colors: [[this.accentColor, 0], ['#33000000', 1]]
      })

      if (this.book0Cover) {
        Image(this.book0Cover)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
      }

      // 底部压暗，保证白字在浅色封面上也看得清。
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          direction: GradientDirection.Bottom,
          colors: [['#00000000', 0.35], ['#66000000', 0.62], ['#D9000000', 1]]
        })

      if (this.book0Percent >= 0) {
        Text(`${this.book0Percent}%`)
          .fontSize(10)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
          .backgroundColor('#59000000')
          .borderRadius(9)
          .padding({ left: 7, right: 7, top: 2, bottom: 2 })
          .position({ right: 10, top: 10 })
      }

      Column() {
        Row({ space: 5 }) {
          Stack() {
            SymbolGlyph($r('sys.symbol.book_pages'))
              .fontSize(9)
              .fontColor(['#FFFFFF'])
          }
          .width(15)
          .height(15)
          .borderRadius(8)
          .backgroundColor('#4DFFFFFF')

          Text(this.book0Chapter || (this.book0Time ? `上次阅读 ${this.book0Time}` : '继续阅读'))
            .fontSize(11)
            .fontColor('#D9FFFFFF')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .width('100%')

        Text(this.bookName())
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
          .lineHeight(21)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 5 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 12, right: 12, bottom: 12 })
    }
    .width('100%')
    .height('100%')
    .clip(true)
    .onClick(() => {
      postCardAction(this, new CoverRouteAction(this.book0Url));
    })
  }

  @Builder
  emptyState() {
    Column() {
      SymbolGlyph($r('sys.symbol.book_pages'))
        .fontSize(28)
        .fontColor(['#FFFFFF'])
      Text(this.emptyTitle || '暂无最近阅读')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor('#FFFFFF')
        .maxLines(1)
        .margin({ top: 10 })
      Text(this.emptySubtitle || '打开书架阅读后会显示在这里')
        .fontSize(10)
        .fontColor('#CCFFFFFF')
        .maxLines(2)
        .textAlign(TextAlign.Center)
        .margin({ top: 4 })
    }
    .width('100%')
    .height('100%')
    .padding(12)
    .justifyContent(FlexAlign.Center)
    .linearGradient({
      angle: 160,
      colors: [[this.accentColor, 0], ['#33000000', 1]]
    })
    .onClick(() => {
      postCardAction(this, new CoverOpenAppAction());
    })
  }

  private bookName(): string {
    return this.book0Name || '未命名书籍';
  }
}
