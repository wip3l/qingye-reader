import { BookshelfCoverBadgeSettings } from '../utils/BookshelfCoverBadgeSettings';

const RIBBON_WIDTH = 20;
const RIBBON_NOTCH = 5;
const RIBBON_LINE_HEIGHT = 11;

/**
 * 书架与设置预览共用；不截获封面的点击、长按或滑动。单角最多两项；一般纵排，更新与未读数合为横向胶囊。
 * 四个角用 @Builder 画在同一个组件里：书架连缓存页一屏有七八十本书的封面，四角各拆成子组件时就多出三百多个
 * 自定义组件，进出分组整页重建时光销毁它们就要二三十毫秒，正卡在动画起步那一帧。
 */
@Component
export struct BookshelfCoverBadges {
  @Prop configuration: string = BookshelfCoverBadgeSettings.DEFAULT;
  @Prop typeLabel: string = '书';
  @Prop typeColor: string = '#3978C5';
  @Prop sourceText: string = '';
  @Prop unreadCount: number = 0;
  @Prop updated: boolean = false;
  @Prop pinned: boolean = false;
  @Prop offline: boolean = false;
  @Prop selecting: boolean = false;
  /**
   * 陪伴布局的精装书：大于等于 0 时为书脊加压槽的宽度，左侧两角让到压槽右边，四角离边 5vp；
   * 更新标识与未读数不再画成小胶囊，改为从所在角的书边垂下（上角）或升起（下角）的丝带书签。
   */
  @Prop spineInset: number = -1;

  hardcover(): boolean {
    return this.spineInset >= 0;
  }

  isRibbonItem(item: string): boolean {
    return this.hardcover() && (item === 'update' || item === 'unread');
  }

  ribbonItems(corner: number): string[] {
    return this.visibleItems(this.cornerItems(corner)).filter((item: string): boolean => this.isRibbonItem(item));
  }

  pillItems(corner: number): string[] {
    return this.visibleItems(this.cornerItems(corner)).filter((item: string): boolean => !this.isRibbonItem(item));
  }

  ribbonLines(corner: number): string[] {
    const items = this.ribbonItems(corner);
    const lines: string[] = [];
    if (items.indexOf('update') >= 0) lines.push('新');
    if (items.indexOf('unread') >= 0) lines.push(BookshelfCoverBadgeSettings.unreadText(this.unreadCount));
    return lines;
  }

  ribbonHeight(corner: number): number {
    return this.ribbonLines(corner).length * RIBBON_LINE_HEIGHT + RIBBON_NOTCH + 6;
  }

  /** 上角的丝带尾部朝下开叉，下角的朝上开叉。 */
  ribbonPoints(corner: number): number[][] {
    const width = RIBBON_WIDTH;
    const height = this.ribbonHeight(corner);
    return corner < 2 ?
      [[0, 0], [width, 0], [width, height], [width / 2, height - RIBBON_NOTCH], [0, height]] :
      [[0, 0], [width / 2, RIBBON_NOTCH], [width, 0], [width, height], [0, height]];
  }

  ribbonColor(corner: number): string {
    return this.ribbonItems(corner).indexOf('update') >= 0 ? '#E33E38' : '#B5452F';
  }

  ribbonPosition(corner: number): Edges {
    const left = this.spineInset + 5;
    if (corner === 0) return { left: left, top: 0 };
    if (corner === 1) return { right: 6, top: 0 };
    if (corner === 2) return { left: left, bottom: 0 };
    return { right: 6, bottom: 0 };
  }

  ribbonTextPadding(corner: number): Padding {
    return corner < 2 ? { top: 3 } : { bottom: 3 };
  }

  layerPadding(): Padding {
    return this.hardcover() ? { left: this.spineInset + 5, right: 5, top: 5, bottom: 5 } :
      { left: 4, right: 4, top: 4, bottom: 4 };
  }

  ribbonAccessibilityText(corner: number): string {
    const items = this.ribbonItems(corner);
    const parts: string[] = [];
    if (items.indexOf('update') >= 0) parts.push('有更新');
    if (items.indexOf('unread') >= 0) parts.push(`${this.unreadCount}章未读`);
    return parts.join('，');
  }

  cornerItems(corner: number): string[] {
    return BookshelfCoverBadgeSettings.items(this.configuration, corner);
  }

  visibleItems(itemList: string[]): string[] {
    return itemList.filter((item: string): boolean => {
      if (item === 'pin') return this.pinned;
      if (item === 'offline') return this.offline;
      if (item === 'update') return this.updated;
      if (item === 'source') return this.sourceText.length > 0;
      if (item === 'unread') return BookshelfCoverBadgeSettings.unreadText(this.unreadCount).length > 0;
      return item === 'type';
    });
  }

  badgeText(item: string): string {
    if (item === 'type') return this.typeLabel;
    if (item === 'source') return this.sourceText;
    if (item === 'update') return '新';
    if (item === 'offline') return '离线';
    return BookshelfCoverBadgeSettings.unreadText(this.unreadCount);
  }

  combined(itemList: string[]): boolean {
    return itemList.indexOf('update') >= 0 && itemList.indexOf('unread') >= 0;
  }

  @Builder
  badge(item: string, combined: boolean) {
    if (item === 'pin') {
      SymbolGlyph($r('sys.symbol.pin'))
        .fontSize(10)
        .fontColor(['#FFFFFF'])
        .padding(3)
        .backgroundColor(this.typeColor)
        .borderRadius(4)
        .accessibilityText('已置顶')
    } else {
      Text(this.badgeText(item))
        .fontSize(combined ? '8vp' : '9vp')
        .fontWeight(FontWeight.Medium)
        .fontColor('#FFFFFF')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: '100%' })
        .padding({ left: combined ? 1 : 3, right: combined ? 1 : 3, top: 2, bottom: 2 })
        .backgroundColor(item === 'update' ? '#E33E38' : (item === 'type' ? this.typeColor :
          (item === 'offline' ? '#2E8B57' : '#CC25282E')))
        .borderRadius(3)
        .accessibilityText(item === 'unread' ? `${this.unreadCount}章未读` :
          (item === 'update' ? '有更新' : (item === 'offline' ? '有离线内容' :
            `${BookshelfCoverBadgeSettings.label(item)}：${this.badgeText(item)}`)))
    }
  }

  @Builder
  corner(corner: number) {
    Column() {
      Column({ space: 2 }) {
        if (!this.hardcover() && this.combined(this.cornerItems(corner))) {
          Row({ space: 1 }) {
            ForEach(this.visibleItems(this.cornerItems(corner)), (item: string) => {
              this.badge(item, true)
            }, (item: string): string => `${item}:${this.badgeText(item)}`)
          }
          .constraintSize({ maxWidth: '100%' })
        } else {
          ForEach(this.pillItems(corner), (item: string) => {
            this.badge(item, false)
          }, (item: string): string => `${item}:${this.badgeText(item)}:${this.typeColor}`)
        }
      }
      .width('100%')
      .alignItems(corner === 1 || corner === 3 ? HorizontalAlign.End : HorizontalAlign.Start)
      // 同一角有丝带时，其余胶囊排在丝带内侧。
      .padding({
        left: (corner === 0 || corner === 2) && this.ribbonItems(corner).length > 0 ? RIBBON_WIDTH + 3 : 0,
        right: (corner === 1 || corner === 3) && this.ribbonItems(corner).length > 0 ? RIBBON_WIDTH + 3 : 0
      })
    }
    .layoutWeight(1)
    .visibility(this.selecting && corner === 0 ? Visibility.Hidden : Visibility.Visible)
  }

  @Builder
  ribbon(corner: number) {
    Stack({ alignContent: corner < 2 ? Alignment.Top : Alignment.Bottom }) {
      Polygon({ width: RIBBON_WIDTH, height: this.ribbonHeight(corner) })
        .points(this.ribbonPoints(corner))
        .fill(this.ribbonColor(corner))
      Column() {
        ForEach(this.ribbonLines(corner), (line: string) => {
          Text(line)
            .fontSize('9vp')
            .lineHeight(RIBBON_LINE_HEIGHT)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FFFFFF')
            .maxLines(1)
        }, (line: string, index: number): string => `${index}:${line}`)
      }
      .padding(this.ribbonTextPadding(corner))
    }
    .width(RIBBON_WIDTH)
    .height(this.ribbonHeight(corner))
    .position(this.ribbonPosition(corner))
    .visibility(this.selecting && corner === 0 ? Visibility.Hidden : Visibility.Visible)
    .accessibilityText(this.ribbonAccessibilityText(corner))
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        Row({ space: 4 }) {
          this.corner(0)
          this.corner(1)
        }.width('100%').alignItems(VerticalAlign.Top)
        Blank().layoutWeight(1)
        Row({ space: 4 }) {
          this.corner(2)
          this.corner(3)
        }.width('100%').alignItems(VerticalAlign.Bottom)
      }
      .padding(this.layerPadding())
      .width('100%')
      .height('100%')

      if (this.hardcover()) {
        ForEach(BookshelfCoverBadgeSettings.CORNERS, (corner: number) => {
          if (this.ribbonItems(corner).length > 0) {
            this.ribbon(corner)
          }
        }, (corner: number): string => `${corner}:${this.ribbonLines(corner).join(',')}`)
      }
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None)
  }
}
