import { ThemePack, ThemeVariant } from '../../theme/ThemeModels';
import { ThemeImageSlots } from '../../theme/ThemePackRegistry';
import { ThemeImageCrop } from '../../theme/share/ThemePackageFormat';
import { ThemeCroppedImage } from './ThemeCroppedImage';
import { ThemeAssetRegistry } from '../../theme/ThemeAssetRegistry';
import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { HexColor } from '../../utils/HexColor';
import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';
import { TtsPanelThemeBackground } from '../TtsPanelThemeBackground';
import { BookCover } from '../book/BookCover';
import { HomeTabBarSettingsStore } from '../../utils/HomeTabBarSettingsStore';
import { BookTileLayout } from '../../utils/BookTileLayout';

/** 实景预览里的示例书：固定内容，不读用户书架，没拥有的主题也能看。 */
class SceneBook {
  name: string;
  author: string;
  chapter: string;
  latest: string;
  updated: string;
  percent: number;
  isNew: boolean;

  constructor(name: string, author: string, chapter: string, latest: string, updated: string, percent: number,
    isNew: boolean) {
    this.name = name;
    this.author = author;
    this.chapter = chapter;
    this.latest = latest;
    this.updated = updated;
    this.percent = percent;
    this.isNew = isNew;
  }
}

const SCENE_BOOKS: SceneBook[] = [
  new SceneBook('山野来信', '林溪', '第十二章 灯下', '第八十六章 归途', '2小时前', 38, true),
  new SceneBook('长夜微光', '顾北', '第三章 旧码头', '第四十章 潮声', '昨天', 9, false),
  new SceneBook('人间草木', '沈见青', '第二十一章 槐花', '第二十四章 秋分', '3天前', 72, false),
  new SceneBook('海上来客', '陆行舟', '第七章 灯塔', '第一百零二章 靠岸', '5小时前', 15, true),
  new SceneBook('雪国列车', '白榆', '第一章 站台', '第十八章 隧道', '上周', 0, false),
  new SceneBook('松风阁笔谈', '闻一舟', '第五章 听雨', '第三十章 煮茶', '上周', 54, false),
  new SceneBook('远客', '程砚', '第九章 渡口', '第六十章 故人', '11-02', 100, false),
  new SceneBook('雾里行舟', '苏叶', '第二章 晨雾', '第十二章 拢岸', '10-28', 21, false),
  new SceneBook('半窗明月', '季闲', '第四章 更鼓', '第二十章 残棋', '10-20', 63, false)
];

const SCENE_CONTROL_SIZE: number = 40;
const SCENE_TILE_RATIO: number = 0.735;

/**
 * 主题详情里的实景预览：书架（四种布局）和听书面板，按真实页面的结构、字号与间距画，内容是固定示例。
 * 真实页面改了版式，这里要跟着改：书架见 components/home/BookshelfPage，听书面板见 components/ReaderTtsPlayerPanel。
 */
@Component
export struct ThemeDetailScene {
  @Prop themePack: ThemePack = new ThemePack();
  @Prop previewDark: boolean = false;
  /** shelf 或 listen。 */
  @Prop scene: string = 'shelf';
  @Prop shelfLayout: string = 'companion';
  @Prop ttsThemeId: string = '';
  /** 空串表示不铺首页背景。 */
  @Prop homeBackdropThemeId: string = '';
  /** 全屏预览时让出状态栏和底部小白条。 */
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  // 底栏按“外观 › 底栏”里选的第四个页签画，和首页一致。
  @StorageProp('homeExtraTab') homeExtraTab: string = 'none';
  // 画面自己的宽度：平铺网格和书架一样按宽度定列数，宽屏多排几列而不是把封面放大。
  @State sceneWidth: number = 360;

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.scene === 'listen') {
        this.listenScene()
      } else {
        this.shelfScene()
      }
    }
    .width('100%')
    .height('100%')
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      const width = Number(newArea.width);
      if (width > 0 && Math.abs(width - this.sceneWidth) >= 1) this.sceneWidth = width;
    })
    .backgroundColor(this.variant().colors.pageColor)
    .clip(true)
    .accessibilityGroup(true)
    .accessibilityText(`${this.scene === 'listen' ? '听书面板' : '书架'}${this.previewDark ? '深色' : '浅色'}效果预览`)
  }

  variant(): ThemeVariant {
    return this.previewDark ? this.themePack.dark : this.themePack.light;
  }

  font(): string {
    return this.themePack.typography.appFontFamily;
  }

  trackColor(): string {
    return this.previewDark ? '#2D3138' : '#E8EAED';
  }

  // ---------- 书架 ----------

  homeBackdrop(): ResourceStr | null {
    return this.homeBackdropThemeId ?
      ThemeAssetRegistry.homeBackdrop(this.homeBackdropThemeId, this.previewDark, this.shelfLayout) : null;
  }

  @Builder
  shelfScene() {
    Stack({ alignContent: Alignment.Bottom }) {
      if (this.homeBackdrop()) {
        this.backdropLayer()
      }
      Column() {
        this.shelfHeader()
        Column({ space: AppSpacing.MD }) {
          if (this.shelfLayout === 'compact') {
            ForEach(SCENE_BOOKS.slice(0, 6), (book: SceneBook, index: number) => {
              this.compactCard(book, index)
            }, (book: SceneBook) => `compact_${book.name}`)
          } else if (this.shelfLayout === 'loose') {
            ForEach(SCENE_BOOKS.slice(0, 5), (book: SceneBook, index: number) => {
              this.looseCard(book, index)
            }, (book: SceneBook) => `loose_${book.name}`)
          } else if (this.shelfLayout === 'tile') {
            this.tileGrid(0, 3)
          } else {
            this.companionGreeting()
            this.companionHero(SCENE_BOOKS[0])
            this.companionDots()
            this.companionNote()
            this.companionSectionHeader()
            this.tileGrid(1, 2)
          }
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: AppSpacing.XL, right: AppSpacing.XL })
        .justifyContent(FlexAlign.Start)
        .alignItems(HorizontalAlign.Start)
        .clip(true)
      }
      .width('100%')
      .height('100%')
      this.tabBar()
    }
    .width('100%')
    .height('100%')
  }

  /** 首页背景：贴顶铺满宽度，和首页一样向下淡成页面底色。 */
  @Builder
  backdropLayer() {
    Stack({ alignContent: Alignment.Top }) {
      if (ThemeAssetRegistry.imageCrop(ThemeImageSlots.BACKDROP, this.homeBackdrop(), this.previewDark,
        this.shelfLayout)) {
        ThemeCroppedImage({ src: this.homeBackdrop() as ResourceStr,
          crop: ThemeAssetRegistry.imageCrop(ThemeImageSlots.BACKDROP, this.homeBackdrop(), this.previewDark,
            this.shelfLayout) as ThemeImageCrop })
          .width('100%')
          .aspectRatio(ThemeAssetRegistry.HOME_BACKDROP_ASPECT)
      } else {
        Image(this.homeBackdrop() as ResourceStr)
          .width('100%')
          .aspectRatio(ThemeAssetRegistry.HOME_BACKDROP_ASPECT)
          .objectFit(ImageFit.Cover)
          .draggable(false)
      }
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          direction: GradientDirection.Bottom,
          colors: [[HexColor.withOpacity(this.variant().colors.pageColor, this.previewDark ? 0.4 : 0.2), 0],
            [this.variant().colors.pageColor, 1]]
        })
    }
    .width('100%')
    .height('100%')
    .position({ x: 0, y: 0 })
    .clip(true)
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  shelfHeader() {
    Row({ space: 10 }) {
      // 陪伴布局的顶栏左侧不显示标题，问候语就是标题。
      if (this.shelfLayout !== 'companion') {
        Text('书架')
          .fontFamily(this.font())
          .fontSize(AppFontSize.TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.variant().colors.primaryTextColor)
      }
      Blank()
      if (this.shelfLayout === 'companion') {
        this.headerButton($r('sys.symbol.folder'))
      }
      this.headerButton($r('sys.symbol.square_stack_3d'))
      this.headerButton($r('sys.symbol.funnel'))
      this.headerButton($r('sys.symbol.more'))
    }
    .width('100%')
    .height(56 + this.topInset)
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: this.topInset })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  headerButton(icon: Resource) {
    Stack() {
      SymbolGlyph(icon)
        .fontSize(20)
        .fontColor([this.variant().colors.primaryTextColor])
    }
    .width(SCENE_CONTROL_SIZE)
    .height(SCENE_CONTROL_SIZE)
    .borderRadius(SCENE_CONTROL_SIZE / 2)
    .backgroundColor(HexColor.withOpacity(this.variant().colors.cardColor, 0.72))
    .border({ width: 0.5, color: HexColor.withOpacity(this.variant().colors.dividerColor, 0.8) })
  }

  coverResource(index: number): ResourceStr {
    const covers = ThemeAssetRegistry.themeBookCovers(this.themePack.book.coverAssetId, this.previewDark);
    return covers.length > 0 ? covers[index % covers.length] : '';
  }

  /** 一本书的封面：主题封面（按书轮换）或普通封面，叠主题书架边框。 */
  @Builder
  cover(book: SceneBook, index: number, radius: number) {
    Stack() {
      if (ThemeAssetRegistry.imageCrop(ThemeImageSlots.COVER, this.coverResource(index), this.previewDark)) {
        ThemeCroppedImage({ src: this.coverResource(index),
          crop: ThemeAssetRegistry.imageCrop(ThemeImageSlots.COVER, this.coverResource(index),
            this.previewDark) as ThemeImageCrop })
          .width('100%')
          .height('100%')
      } else if (this.coverResource(index)) {
        Image(this.coverResource(index))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Fill)
          .draggable(false)
      } else {
        BookCover({ name: book.name, useBookshelfCover: false,
          placeholderColor: this.variant().colors.accentColor, cornerRadius: radius })
          .width('100%')
          .height('100%')
      }
      if (this.themePack.book.shelfFrameAssetId) {
        Image(ThemeAssetRegistry.themeShelfFrame(this.themePack.book.shelfFrameAssetId, this.previewDark))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Fill)
          .draggable(false)
      }
    }
    .width('100%')
    .height('100%')
    .borderRadius(radius)
    .clip(true)
  }

  @Builder
  progressLine(percent: number) {
    Progress({ value: percent, total: 100, type: ProgressType.Linear })
      .width('100%')
      .height(3)
      .color(this.variant().colors.accentColor)
      .backgroundColor(this.trackColor())
  }

  progressText(book: SceneBook): string {
    if (book.percent <= 0) return '未读';
    return book.percent >= 100 ? '已读完' : `${book.percent}% · ${book.chapter}`;
  }

  /** 列表卡片右上角的“新”：贴住卡片角。 */
  @Builder
  newCorner() {
    Text('新')
      .fontSize(AppFontSize.MICRO)
      .fontWeight(FontWeight.Medium)
      .fontColor('#FFFFFF')
      .height(18)
      .padding({ left: 8, right: 8 })
      .borderRadius({ topRight: this.themePack.radius.medium, bottomLeft: 10 })
      .backgroundColor(this.variant().colors.dangerColor)
  }

  /** 紧凑：封面与信息块等高，信息块底部是进度文字加细进度条。 */
  @Builder
  compactCard(book: SceneBook, index: number) {
    Stack({ alignContent: Alignment.TopEnd }) {
      Row() {
        Column() {
          this.cover(book, index, 8)
        }
        .width(54)
        .height(74)
        Column({ space: AppSpacing.XXS }) {
          Text(book.name)
            .fontFamily(this.font())
            .fontSize(AppFontSize.BODY_LARGE)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.variant().colors.primaryTextColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Text(book.author)
            .fontFamily(this.font())
            .fontSize(AppFontSize.BODY)
            .fontColor(this.variant().colors.subTextColor)
            .maxLines(1)
            .width('100%')
          Blank()
          Text(this.progressText(book))
            .fontFamily(this.font())
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.variant().colors.subTextColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .margin({ bottom: AppSpacing.XXS })
          this.progressLine(book.percent)
        }
        .layoutWeight(1)
        .height(74)
        .margin({ left: AppSpacing.LG })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding(AppSpacing.LG)
      .alignItems(VerticalAlign.Top)
      if (book.isNew) {
        this.newCorner()
      }
    }
    .width('100%')
    .borderRadius(this.themePack.radius.medium)
    .backgroundColor(this.variant().colors.cardColor)
    .clip(true)
  }

  /** 宽松：书名和作者贴顶，最新章节标签贴封面底边，卡片底部是进度条和居中的进度文字。 */
  @Builder
  looseCard(book: SceneBook, index: number) {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column({ space: AppSpacing.MD }) {
        Row() {
          Column() {
            this.cover(book, index, 8)
          }
          .width(66)
          .height(93)
          Column() {
            Text(book.name)
              .fontFamily(this.font())
              .fontSize(AppFontSize.BODY_LARGE)
              .lineHeight(20)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.variant().colors.primaryTextColor)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
            Text(`${book.author} · 连载中`)
              .fontFamily(this.font())
              .fontSize(AppFontSize.CAPTION)
              .fontColor(this.variant().colors.subTextColor)
              .maxLines(1)
              .width('100%')
              .margin({ top: 6 })
            Blank()
            Row({ space: 6 }) {
              Text(book.updated)
                .fontFamily(this.font())
                .fontSize(AppFontSize.CAPTION)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.variant().colors.accentColor)
                .maxLines(1)
                .flexShrink(0)
              Text(book.latest)
                .fontFamily(this.font())
                .fontSize(AppFontSize.CAPTION)
                .fontColor(this.variant().colors.subTextColor)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .flexShrink(1)
            }
            .height(24)
            .padding({ left: 9, right: 9 })
            .borderRadius(12)
            .backgroundColor(HexColor.withOpacity(this.variant().colors.accentColor, 0.1))
          }
          .layoutWeight(1)
          .height(93)
          .margin({ left: AppSpacing.LG })
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
        Column({ space: AppSpacing.XS }) {
          this.progressLine(book.percent)
          Text(this.progressText(book))
            .fontFamily(this.font())
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.variant().colors.subTextColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
      }
      .width('100%')
      .padding(AppSpacing.LG)
      if (book.isNew) {
        this.newCorner()
      }
    }
    .width('100%')
    .borderRadius(this.themePack.radius.medium)
    .backgroundColor(this.variant().colors.cardColor)
    .clip(true)
  }

  /** 平铺的一格：封面、两行书名、进度文字和细进度条。 */
  @Builder
  tileBook(book: SceneBook, index: number) {
    Column({ space: AppSpacing.XS }) {
      Column() {
        this.cover(book, index, 8)
      }
      .width('100%')
      .aspectRatio(SCENE_TILE_RATIO)
      .borderRadius(8)
      .shadow({ radius: 8, color: this.previewDark ? '#52000000' : '#24000000', offsetX: 0, offsetY: 3 })
      Text(book.name)
        .fontFamily(this.font())
        .fontSize(AppFontSize.CAPTION)
        .lineHeight(18)
        .height(36)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.variant().colors.primaryTextColor)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Row({ space: 5 }) {
        SymbolGlyph($r('sys.symbol.checkmark_circle'))
          .fontSize(13)
          .fontColor([this.variant().colors.subTextColor])
        Text(book.percent <= 0 ? '未读' : `${book.percent}%`)
          .fontFamily(this.font())
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.variant().colors.subTextColor)
          .maxLines(1)
      }
      .width('100%')
      .height(18)
      this.progressLine(book.percent)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  tileColumns(): number {
    return BookTileLayout.columnCount(this.sceneWidth);
  }

  tileColumnsTemplate(): string {
    return new Array<string>(this.tileColumns()).fill('1fr').join(' ');
  }

  /** 从第 from 本起排满 rows 行；示例书不够时从头接着排。 */
  tileIndexes(from: number, rows: number): number[] {
    const indexes: number[] = [];
    for (let offset = 0; offset < rows * this.tileColumns(); offset++) indexes.push(from + offset);
    return indexes;
  }

  /** from、rows 只传固定值：列数在里面读状态，宽度变了格子数才会跟着变。 */
  @Builder
  tileGrid(from: number, rows: number) {
    Grid() {
      ForEach(this.tileIndexes(from, rows), (index: number) => {
        GridItem() {
          this.tileBook(SCENE_BOOKS[index % SCENE_BOOKS.length], index)
        }
      }, (index: number) => `tile_${index}`)
    }
    .width('100%')
    .columnsTemplate(this.tileColumnsTemplate())
    .columnsGap(BookTileLayout.columnGap(this.sceneWidth))
    .rowsGap(AppSpacing.XL)
    .scrollBar(BarState.Off)
    .enableScrollInteraction(false)
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  companionGreeting() {
    Column({ space: AppSpacing.XS }) {
      Text('下午好')
        .fontFamily(this.font())
        .fontSize(AppFontSize.HEADLINE)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.variant().colors.accentColor)
      Text('今天读了 24 分钟，接着读《山野来信》吧')
        .fontFamily(this.font())
        .fontSize(AppFontSize.BODY)
        .fontColor(this.variant().colors.subTextColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: AppSpacing.XS, bottom: AppSpacing.SM })
  }

  /** 陪伴布局顶上那本正在读的书：大封面在左，右边是书名、上次读到的章节和继续阅读。 */
  @Builder
  companionHero(book: SceneBook) {
    Row({ space: AppSpacing.XXL }) {
      Column() {
        this.cover(book, 0, 6)
      }
      .width(104)
      .height(146)
      .borderRadius(6)
      .shadow({ radius: 18, color: this.previewDark ? '#73000000' : '#38000000', offsetX: 6, offsetY: 10 })
      Column() {
        Text(book.name)
          .fontFamily(this.font())
          .fontSize(AppFontSize.HEADLINE)
          .lineHeight(32)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.variant().colors.accentColor)
          .maxLines(2)
          .width('100%')
        Text(`${book.author} 著`)
          .fontFamily(this.font())
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.variant().colors.subTextColor)
          .width('100%')
          .margin({ top: AppSpacing.XS })
        Blank()
        Text('上次读到 · 昨天')
          .fontFamily(this.font())
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.variant().colors.subTextColor)
          .width('100%')
        Text(book.chapter)
          .fontFamily(this.font())
          .fontSize(AppFontSize.BODY_LARGE)
          .lineHeight(22)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.variant().colors.primaryTextColor)
          .maxLines(1)
          .width('100%')
          .margin({ top: AppSpacing.XS })
        Row({ space: AppSpacing.XS }) {
          Text('继续阅读')
            .fontFamily(this.font())
            .fontSize(AppFontSize.BODY)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.variant().colors.accentColor)
          SymbolGlyph($r('sys.symbol.arrow_right'))
            .fontSize(14)
            .fontColor([this.variant().colors.accentColor])
        }
        .height(34)
        .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
        .borderRadius(17)
        .backgroundColor(HexColor.withOpacity(this.variant().colors.accentColor, 0.12))
        .margin({ top: AppSpacing.MD })
      }
      .layoutWeight(1)
      .height(146)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ left: AppSpacing.XS, right: AppSpacing.XS, top: AppSpacing.XS, bottom: AppSpacing.XL })
  }

  /** 继续阅读轮播下面的圆点。 */
  @Builder
  companionDots() {
    Row({ space: 5 }) {
      Row()
        .width(16)
        .height(5)
        .borderRadius(3)
        .backgroundColor(this.variant().colors.accentColor)
      Row()
        .width(5)
        .height(5)
        .borderRadius(3)
        .backgroundColor(HexColor.withOpacity(this.variant().colors.subTextColor, 0.4))
      Row()
        .width(5)
        .height(5)
        .borderRadius(3)
        .backgroundColor(HexColor.withOpacity(this.variant().colors.subTextColor, 0.4))
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }

  noteBarHeights(): number[] {
    return [22, 15, 6, 32, 16, 26, 25];
  }

  /** 阅读小记卡片：今日阅读时长和近七天的柱子。 */
  @Builder
  companionNote() {
    Column({ space: AppSpacing.MD }) {
      Row({ space: AppSpacing.SM }) {
        SymbolGlyph($r('sys.symbol.book_pages'))
          .fontSize(18)
          .fontColor([this.variant().colors.accentColor])
        Text('阅读小记')
          .fontFamily(this.font())
          .fontSize(AppFontSize.BODY_LARGE)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.variant().colors.accentColor)
        Blank()
        Text('阅读统计')
          .fontFamily(this.font())
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.variant().colors.subTextColor)
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(12)
          .fontColor([this.variant().colors.subTextColor])
      }
      .width('100%')
      Row({ space: AppSpacing.LG }) {
        Column({ space: AppSpacing.XS }) {
          Text('今日阅读')
            .fontFamily(this.font())
            .fontSize(AppFontSize.MICRO)
            .fontColor(this.variant().colors.subTextColor)
          Row({ space: AppSpacing.XS }) {
            Text('24')
              .fontFamily(this.font())
              .fontSize(AppFontSize.HEADLINE)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.variant().colors.accentColor)
            Text('分钟')
              .fontFamily(this.font())
              .fontSize(AppFontSize.CAPTION)
              .fontColor(this.variant().colors.subTextColor)
          }
          .alignItems(VerticalAlign.Bottom)
        }
        .alignItems(HorizontalAlign.Start)
        Row()
          .width(0.5)
          .height(48)
          .backgroundColor(this.variant().colors.dividerColor)
        Column({ space: AppSpacing.SM }) {
          Row({ space: 4 }) {
            ForEach(this.noteBarHeights(), (barHeight: number, index: number) => {
              Row()
                .width(16)
                .height(barHeight)
                .borderRadius(4)
                .backgroundColor(index === 6 ? this.variant().colors.accentColor :
                  HexColor.withOpacity(this.variant().colors.accentColor, 0.28))
            }, (barHeight: number, index: number) => `note_bar_${index}`)
          }
          .height(32)
          .alignItems(VerticalAlign.Bottom)
          Text('近 7 天 3小时48分 · 已连续读了 22 天')
            .fontFamily(this.font())
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.variant().colors.subTextColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)
    }
    .width('100%')
    .padding(AppSpacing.XL)
    .borderRadius(this.themePack.radius.card)
    .backgroundColor(this.variant().colors.cardColor)
    .margin({ bottom: AppSpacing.SM })
  }

  @Builder
  companionSectionHeader() {
    Row() {
      Text('书架里，还有故事')
        .fontFamily(this.font())
        .fontSize(AppFontSize.SUBTITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.variant().colors.primaryTextColor)
      Blank()
      Text(`共 ${SCENE_BOOKS.length} 本`)
        .fontFamily(this.font())
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.variant().colors.subTextColor)
    }
    .width('100%')
    .padding({ left: AppSpacing.XS, right: AppSpacing.XS, bottom: AppSpacing.XS })
  }

  hidesLabels(): boolean {
    return ThemeAssetRegistry.navigationHidesLabels(this.themePack.navigation.iconPackId);
  }

  tabLabel(tabId: string): string {
    if (tabId === 'explore') return '发现';
    if (tabId === 'mine') return '我的';
    if (tabId === 'listen') return '听';
    if (tabId === 'footprint') return '足迹';
    return '书架';
  }

  navigationTabs(): string[] {
    const extra = HomeTabBarSettingsStore.normalizeExtraTab(this.homeExtraTab);
    return extra === HomeTabBarSettingsStore.EXTRA_NONE ? ['bookshelf', 'explore', 'mine'] :
      ['bookshelf', 'explore', extra, 'mine'];
  }

  /** 悬浮底栏：整套导航图标，书架选中。 */
  @Builder
  tabBar() {
    Row() {
      ForEach(this.navigationTabs(), (tabId: string) => {
        Column({ space: 2 }) {
          Image(ThemeAssetRegistry.navigationIcon(this.themePack.navigation.iconPackId, tabId,
            tabId === 'bookshelf', this.previewDark))
            .width(this.hidesLabels() ? 32 : 24)
            .height(this.hidesLabels() ? 32 : 24)
            .fillColor(tabId === 'bookshelf' ? this.variant().colors.accentColor :
              this.variant().colors.subTextColor)
            .draggable(false)
          if (!this.hidesLabels()) {
            Text(this.tabLabel(tabId))
              .fontFamily(this.font())
              .fontSize(AppFontSize.MICRO)
              .fontColor(tabId === 'bookshelf' ? this.variant().colors.accentColor :
                this.variant().colors.subTextColor)
          }
        }
        .layoutWeight(1)
      }, (tabId: string) => tabId)
    }
    .width('calc(100% - 48vp)')
    .height(58)
    .margin({ bottom: AppSpacing.LG + this.bottomInset })
    .alignItems(VerticalAlign.Center)
    .borderRadius(29)
    .backgroundColor(HexColor.withOpacity(this.variant().colors.cardColor, 0.9))
    .border({ width: 0.5, color: HexColor.withOpacity(this.variant().colors.dividerColor, 0.8) })
    .shadow({ radius: 20, color: this.previewDark ? '#66000000' : '#24000000', offsetX: 0, offsetY: 6 })
  }

  // ---------- 听书面板（朗读模式） ----------

  @Builder
  listenScene() {
    Stack({ alignContent: Alignment.TopStart }) {
      TtsPanelThemeBackground({ themeId: this.ttsThemeId, darkMode: this.previewDark })
      Column({ space: AppSpacing.LG }) {
        this.listenHeader()
        this.listenReadingCard()
        this.progressLine(42)
        this.listenMainControls()
        Row() {
          this.listenSecondary($r('sys.symbol.timer'), '定时')
          this.listenSecondary($r('sys.symbol.hourglass'), '1.0x')
          this.listenSecondary($r('sys.symbol.list_bullet'), '目录')
          this.listenSecondary($r('sys.symbol.stop_circle'), '停止')
        }
        .width('100%')
        .padding({ top: AppSpacing.XS })
      }
      .width('100%')
      .height('100%')
      .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: this.topInset + 8, bottom: this.bottomInset + 12 })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  listenHeader() {
    Row() {
      Stack() {
        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(20)
          .fontColor([this.variant().colors.primaryTextColor])
      }
      .width(SCENE_CONTROL_SIZE)
      .height(SCENE_CONTROL_SIZE)
      .borderRadius(SCENE_CONTROL_SIZE / 2)
      .backgroundColor(HexColor.withOpacity(this.variant().colors.cardColor, 0.72))
      .border({ width: 0.5, color: HexColor.withOpacity(this.variant().colors.dividerColor, 0.8) })
      Column({ space: AppSpacing.XXS }) {
        Text(SCENE_BOOKS[0].name)
          .fontFamily(this.font())
          .fontSize(AppFontSize.BODY_LARGE)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.variant().colors.primaryTextColor)
          .maxLines(1)
        Text('正在朗读')
          .fontFamily(this.font())
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.variant().colors.subTextColor)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)
      Column()
        .width(SCENE_CONTROL_SIZE)
        .height(SCENE_CONTROL_SIZE)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  /** 朗读卡片：小封面和章节名，下面是正文，当前句高亮；底部是音色下拉。 */
  @Builder
  listenReadingCard() {
    Column({ space: AppSpacing.MD }) {
      Row({ space: AppSpacing.MD }) {
        Column() {
          this.cover(SCENE_BOOKS[0], 0, 6)
        }
        .width(42)
        .height(56)
        Column({ space: AppSpacing.XXS }) {
          Text(SCENE_BOOKS[0].chapter)
            .fontFamily(this.font())
            .fontSize(AppFontSize.BODY)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.variant().colors.primaryTextColor)
            .maxLines(1)
          Text('第 12 / 86 章')
            .fontFamily(this.font())
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.variant().colors.subTextColor)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      Column() {
        Text() {
          Span('雨停的时候，檐下还挂着水珠。她把灯芯拨亮了些，翻开那本旧书。')
            .fontColor(this.variant().colors.subTextColor)
          Span('纸页泛黄，墨迹却还清楚。')
            .fontColor(this.variant().colors.primaryTextColor)
            .fontWeight(FontWeight.Medium)
            .textBackgroundStyle({ color: HexColor.withOpacity(this.variant().colors.accentColor, 0.16), radius: 4 })
          Span('窗外起了风，吹得帘子轻轻晃动，她没有抬头。远处传来更鼓，一声，又一声。灯花落了下来，书页翻过去，' +
            '故事才刚刚开始。门外有人收了伞，在阶前跺了跺脚上的泥。来人不再劝，只把一盏新茶搁在案角。')
            .fontColor(this.variant().colors.subTextColor)
        }
        .fontFamily(this.font())
        .fontSize(AppFontSize.BODY_LARGE)
        .lineHeight(28)
        .width('100%')
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Start)
      .clip(true)
      Row() {
        Text('晓晓 · 温柔女声')
          .fontFamily(this.font())
          .fontSize(AppFontSize.BODY)
          .fontColor(this.variant().colors.primaryTextColor)
          .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(14)
          .fontColor([this.variant().colors.subTextColor])
      }
      .width('100%')
      .height(44)
      .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
      .borderRadius(this.themePack.radius.medium)
      .backgroundColor(this.previewDark ? '#1FFFFFFF' : '#0F000000')
    }
    .width('100%')
    .layoutWeight(1)
    .padding(AppSpacing.LG)
    .borderRadius(this.themePack.radius.large)
    .backgroundColor(this.previewDark ? '#991C1C1E' : '#B3FFFFFF')
    .border({ width: 0.5, color: this.previewDark ? '#26FFFFFF' : '#E6FFFFFF' })
  }

  /** 主控制区：上一章、大号播放键、下一章。 */
  @Builder
  listenMainControls() {
    Row() {
      Stack() {
        SymbolGlyph($r('sys.symbol.backward_end_fill'))
          .fontSize(30)
          .fontColor([this.variant().colors.primaryTextColor])
      }
      .width(56)
      .height(56)
      Stack() {
        SymbolGlyph($r('sys.symbol.pause_fill'))
          .fontSize(30)
          .fontColor([ThemeRuntime.onAccentColor(this.variant().colors.buttonColor)])
      }
      .width(68)
      .height(68)
      .borderRadius(34)
      .backgroundColor(this.variant().colors.buttonColor)
      .shadow({ radius: 16, color: this.previewDark ? '#66000000' : '#33000000', offsetX: 0, offsetY: 6 })
      Stack() {
        SymbolGlyph($r('sys.symbol.forward_end_fill'))
          .fontSize(30)
          .fontColor([this.variant().colors.primaryTextColor])
      }
      .width(56)
      .height(56)
    }
    .width('100%')
    .justifyContent(FlexAlign.SpaceEvenly)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  listenSecondary(icon: Resource, label: string) {
    Column({ space: AppSpacing.XS }) {
      SymbolGlyph(icon)
        .fontSize(22)
        .fontColor([this.variant().colors.primaryTextColor])
      Text(label)
        .fontFamily(this.font())
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.variant().colors.subTextColor)
        .maxLines(1)
    }
    .layoutWeight(1)
    .height(56)
    .justifyContent(FlexAlign.Center)
  }
}
