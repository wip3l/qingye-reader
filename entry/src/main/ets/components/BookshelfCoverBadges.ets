import { BookshelfCoverBadgeSettings } from '../utils/BookshelfCoverBadgeSettings';

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
        if (this.combined(this.cornerItems(corner))) {
          Row({ space: 1 }) {
            ForEach(this.visibleItems(this.cornerItems(corner)), (item: string) => {
              this.badge(item, true)
            }, (item: string): string => `${item}:${this.badgeText(item)}`)
          }
          .constraintSize({ maxWidth: '100%' })
        } else {
          ForEach(this.visibleItems(this.cornerItems(corner)), (item: string) => {
            this.badge(item, false)
          }, (item: string): string => `${item}:${this.badgeText(item)}:${this.typeColor}`)
        }
      }
      .width('100%')
      .alignItems(corner === 1 || corner === 3 ? HorizontalAlign.End : HorizontalAlign.Start)
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
