import { BookshelfCoverBadgeSettings } from '../utils/BookshelfCoverBadgeSettings';

/** 单角最多两项；一般纵排，更新与未读数合为横向胶囊。 */
@Component
struct BookshelfCoverBadgeCorner {
  @Prop itemList: string[] = [];
  @Prop rightAligned: boolean = false;
  @Prop typeLabel: string = '书';
  @Prop typeColor: string = '#3978C5';
  @Prop sourceText: string = '';
  @Prop unreadCount: number = 0;
  @Prop updated: boolean = false;
  @Prop pinned: boolean = false;
  @Prop offline: boolean = false;

  visibleItems(): string[] {
    return this.itemList.filter((item: string): boolean => {
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

  combined(): boolean {
    return this.itemList.indexOf('update') >= 0 && this.itemList.indexOf('unread') >= 0;
  }

  @Builder
  badge(item: string) {
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
        .fontSize(this.combined() ? '8vp' : '9vp')
        .fontWeight(FontWeight.Medium)
        .fontColor('#FFFFFF')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: '100%' })
        .padding({ left: this.combined() ? 1 : 3, right: this.combined() ? 1 : 3, top: 2, bottom: 2 })
        .backgroundColor(item === 'update' ? '#E33E38' : (item === 'type' ? this.typeColor :
          (item === 'offline' ? '#2E8B57' : '#CC25282E')))
        .borderRadius(3)
        .accessibilityText(item === 'unread' ? `${this.unreadCount}章未读` :
          (item === 'update' ? '有更新' : (item === 'offline' ? '有离线内容' :
            `${BookshelfCoverBadgeSettings.label(item)}：${this.badgeText(item)}`)))
    }
  }

  build() {
    Column({ space: 2 }) {
      if (this.combined()) {
        Row({ space: 1 }) {
          ForEach(this.visibleItems(), (item: string) => {
            this.badge(item)
          }, (item: string): string => `${item}:${this.badgeText(item)}`)
        }
        .constraintSize({ maxWidth: '100%' })
      } else {
        ForEach(this.visibleItems(), (item: string) => {
          this.badge(item)
        }, (item: string): string => `${item}:${this.badgeText(item)}:${this.typeColor}`)
      }
    }
    .width('100%')
    .alignItems(this.rightAligned ? HorizontalAlign.End : HorizontalAlign.Start)
  }
}

/** 书架与设置预览共用；不截获封面的点击、长按或滑动。 */
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

  @Builder
  corner(corner: number) {
    Column() {
      BookshelfCoverBadgeCorner({
        itemList: BookshelfCoverBadgeSettings.items(this.configuration, corner),
        rightAligned: corner === 1 || corner === 3,
        typeLabel: this.typeLabel, typeColor: this.typeColor, sourceText: this.sourceText,
        unreadCount: this.unreadCount, updated: this.updated, pinned: this.pinned, offline: this.offline
      })
    }
    .layoutWeight(1)
    .visibility(this.selecting && corner === 0 ? Visibility.Hidden : Visibility.Visible)
  }

  build() {
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
    .padding(4)
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None)
  }
}
