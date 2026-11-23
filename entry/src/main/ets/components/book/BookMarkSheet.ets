import { window } from '@kit.ArkUI';
import { BookMark, BookMarkRules, BookMarkStatus } from '../../model/book/BookMark';
import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';
import { BookCover } from './BookCover';
import { BookMarkStars } from './BookMarkStars';

/**
 * 标记编辑面板的内容，材质交给宿主 bindSheet。打开时从 initial 复制一份草稿；
 * 点“完成”或下滑收起都会把草稿交给 onSave（没改动就不交），内容全清空由保存方当作删除。
 *
 * 写短评（短评框有焦点且键盘弹出）时进入专注状态：书名、评分、状态、标签收成一行摘要，
 * 短评框撑满键盘以上的空间，在框内滚动，长评的最后几行不会落到键盘下面；
 * 键盘收起或点摘要就恢复原样。宿主据 onFocusModeChange 把面板拉到最高档，
 * 并用 RESIZE_ONLY 让面板高度让出键盘；这里再按键盘顶边扣掉仍被遮住的部分兜底。
 */
@Component
export struct BookMarkSheet {
  static readonly REVIEW_INPUT_ID: string = 'bookMarkSheetReview';
  @StorageProp('appDarkMode') darkMode: boolean = false;
  @StorageProp('themeRevision') themeRevision: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  /** 已有标记或空草稿（workKey 与书籍信息已填好）；只在打开时读一次。 */
  initial: BookMark = new BookMark();
  /** 标记和书架上用过的标签，供点选。 */
  knownCategories: string[] = [];
  /** 这本书原来就有标记，显示“删除标记”。 */
  existing: boolean = false;
  coverBookUrl: string = '';
  coverOrigin: string = '';
  /** 打开后直接聚焦短评框（详情页点短评进来）。 */
  focusReview: boolean = false;
  onSave: (mark: BookMark) => void = (_mark: BookMark): void => {
  };
  onDelete: () => void = (): void => {
  };
  onClose: () => void = (): void => {
  };
  /** 专注写短评状态变化，宿主据此切换面板档位。 */
  onFocusModeChange: (focused: boolean) => void = (_focused: boolean): void => {
  };

  @State rating: number = 0;
  @State status: number = BookMarkStatus.NONE;
  @State categories: string[] = [];
  @State review: string = '';
  @State choices: string[] = [];
  @State addingCategory: boolean = false;
  @State categoryInput: string = '';
  @State reviewFocused: boolean = false;
  @State keyboardInset: number = 0;
  @State focusMode: boolean = false;
  /** 滚动区的可视高度（vp），面板让出键盘后会变小。 */
  @State viewportHeight: number = 0;
  /** 滚动区底边在窗口里的位置（vp），用来算仍被键盘盖住的部分。 */
  @State viewportBottom: number = 0;
  /** 短评框上方摘要行加短评标题的高度。 */
  @State reviewHeadHeight: number = 0;
  private finished: boolean = false;
  private scroller: Scroller = new Scroller();
  private windowHeight: number = 0;
  private keyboardWindow: window.Window | null = null;
  private keyboardCallback: (data: window.AvoidAreaOptions) => void = (data: window.AvoidAreaOptions): void => {
    if (data.type === window.AvoidAreaType.TYPE_KEYBOARD) {
      this.keyboardInset = this.getUIContext().px2vp(Math.max(0, data.area.bottomRect.height));
      this.syncFocusMode();
    }
  };

  aboutToAppear(): void {
    this.rating = this.initial.rating;
    this.status = this.initial.status;
    this.categories = this.initial.categories.slice();
    this.review = this.initial.review;
    const choices = this.knownCategories.slice();
    for (const name of this.categories) {
      if (!choices.includes(name)) choices.push(name);
    }
    this.choices = choices;
    this.watchKeyboard();
    if (this.focusReview) {
      // 等面板升起、短评框挂上树再要焦点；键盘弹出后照常进入专注写短评。
      setTimeout(() => {
        if (!this.finished) focusControl.requestFocus(BookMarkSheet.REVIEW_INPUT_ID);
      }, 360);
    }
  }

  aboutToDisappear(): void {
    this.unwatchKeyboard();
    // 下滑或点遮罩收起也保存，免得写了一半的短评丢掉。
    this.commit();
  }

  private watchKeyboard(): void {
    window.getLastWindow(this.getUIContext().getHostContext()).then((win: window.Window): void => {
      if (this.finished) return;
      this.keyboardWindow = win;
      try {
        this.windowHeight = this.getUIContext().px2vp(win.getWindowProperties().windowRect.height);
        win.on('avoidAreaChange', this.keyboardCallback);
        const area = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_KEYBOARD);
        this.keyboardInset = this.getUIContext().px2vp(Math.max(0, area.bottomRect.height));
        this.syncFocusMode();
      } catch (error) {
        console.warn('标记面板监听键盘失败:', JSON.stringify(error));
      }
    }).catch((error: Error): void => {
      console.warn('标记面板取窗口失败:', error.message);
    });
  }

  private unwatchKeyboard(): void {
    if (!this.keyboardWindow) return;
    try {
      this.keyboardWindow.off('avoidAreaChange', this.keyboardCallback);
    } catch (_) {
    }
    this.keyboardWindow = null;
  }

  private syncFocusMode(): void {
    const next = this.reviewFocused && this.keyboardInset > 0;
    if (next === this.focusMode) return;
    this.focusMode = next;
    if (next) {
      // 上方区块收起后内容从顶上开始，旧的滚动位置会把短评框推出视口。
      this.scroller.scrollTo({ xOffset: 0, yOffset: 0 });
    }
    this.onFocusModeChange(next);
  }

  /** 专注状态下短评框的高度：可视高度扣掉键盘仍盖住的部分、上方标题和底部留白。 */
  private focusedReviewHeight(): number {
    let overlap = 0;
    if (this.windowHeight > 0 && this.keyboardInset > 0 && this.viewportBottom > 0) {
      overlap = Math.max(0, this.viewportBottom - (this.windowHeight - this.keyboardInset));
    }
    const height = this.viewportHeight - overlap - this.reviewHeadHeight - AppSpacing.LG;
    return Math.max(110, height);
  }

  private leaveFocusMode(): void {
    this.getUIContext().getFocusController().clearFocus();
    this.reviewFocused = false;
    this.syncFocusMode();
  }

  private summaryText(): string {
    const parts: string[] = [];
    if (this.rating > 0) {
      parts.push(`${BookMarkRules.ratingText(this.rating)} ${BookMarkRules.ratingLabel(this.rating)}`);
    }
    if (this.status !== BookMarkStatus.NONE) parts.push(BookMarkStatus.label(this.status));
    if (this.categories.length > 0) parts.push(`${this.categories.length} 个标签`);
    return parts.length > 0 ? parts.join(' · ') : '评分、状态和标签';
  }

  private commit(): void {
    if (this.finished) return;
    this.finished = true;
    this.addPendingCategory();
    if (!this.changed()) return;
    const mark = this.initial.clone();
    mark.rating = this.rating;
    mark.status = this.status;
    mark.categories = this.categories.slice();
    mark.review = this.review;
    this.onSave(mark);
  }

  private changed(): boolean {
    return this.rating !== this.initial.rating || this.status !== this.initial.status ||
      this.review.trim() !== this.initial.review.trim() ||
      this.categories.join('\n') !== this.initial.categories.join('\n');
  }

  private finish(): void {
    this.commit();
    this.onClose();
  }

  private toggleCategory(name: string): void {
    if (this.categories.includes(name)) {
      this.categories = this.categories.filter((item: string): boolean => item !== name);
    } else if (this.categories.length < BookMarkRules.MAX_CATEGORIES) {
      this.categories = [...this.categories, name];
    }
  }

  private addPendingCategory(): void {
    const name = BookMarkRules.normalizeCategory(this.categoryInput);
    this.categoryInput = '';
    this.addingCategory = false;
    if (!name) return;
    if (!this.choices.includes(name)) this.choices = [...this.choices, name];
    if (!this.categories.includes(name) && this.categories.length < BookMarkRules.MAX_CATEGORIES) {
      this.categories = [...this.categories, name];
    }
  }

  private confirmDelete(): void {
    this.getUIContext().showAlertDialog({
      title: '删除标记',
      message: '这本书的评分、状态、标签和短评都会删除，书架上的标签保留。',
      primaryButton: { value: '取消', action: (): void => {} },
      secondaryButton: {
        value: '删除',
        fontColor: ThemeRuntime.dangerColor(this.darkMode),
        action: (): void => {
          this.finished = true;
          this.onDelete();
          this.onClose();
        }
      }
    });
  }

  build() {
    Column() {
      Row({ space: AppSpacing.MD }) {
        Text(this.existing ? '编辑标记' : '标记这本书')
          .fontSize(AppFontSize.TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeRuntime.primaryTextColor(this.darkMode))
          .layoutWeight(1)
        Button('完成')
          .height(34)
          .fontSize(AppFontSize.BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeRuntime.onAccentColor(ThemeRuntime.accentColor(this.darkMode)))
          .backgroundColor(ThemeRuntime.accentColor(this.darkMode))
          .padding({ left: AppSpacing.XL, right: AppSpacing.XL })
          .onClick(() => this.finish())
      }
      .width('100%')
      .padding({ left: AppSpacing.XXL, right: AppSpacing.XL, top: AppSpacing.XL, bottom: AppSpacing.MD })
      .alignItems(VerticalAlign.Center)

      Scroll(this.scroller) {
        Column() {
          // 专注写短评时用 Visibility.None 收起而不是拆掉，标签输入等状态和短评框的焦点都保留。
          Column() {
            this.bookRow()
            this.ratingSection()
            this.statusSection()
            this.categorySection()
          }
          .width('100%')
          .visibility(this.focusMode ? Visibility.None : Visibility.Visible)
          this.reviewSection()
          if (this.existing) {
            Text('删除标记')
              .fontSize(AppFontSize.BODY_LARGE)
              .fontColor(ThemeRuntime.dangerColor(this.darkMode))
              .padding(AppSpacing.LG)
              .margin({ top: AppSpacing.XL })
              .visibility(this.focusMode ? Visibility.None : Visibility.Visible)
              .onClick(() => this.confirmDelete())
          }
        }
        .width('100%')
        .padding({
          left: AppSpacing.XXL,
          right: AppSpacing.XXL,
          bottom: this.focusMode ? AppSpacing.LG : AppSpacing.XXXL + this.navBarHeight
        })
      }
      .layoutWeight(1)
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .edgeEffect(this.focusMode ? EdgeEffect.None : EdgeEffect.Spring)
      .onSizeChange((_old: SizeOptions, next: SizeOptions) => {
        this.viewportHeight = Number(next.height ?? 0);
      })
      // 只量滚动区自身的位置，跟着面板动画和键盘变化，不随内容滚动回调。
      .onAreaChange((_old: Area, next: Area) => {
        this.viewportBottom = Number(next.globalPosition.y ?? 0) + Number(next.height);
      })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  bookRow() {
    Row({ space: AppSpacing.LG }) {
      Stack() {
        BookCover({
          bookUrl: this.coverBookUrl,
          origin: this.coverOrigin,
          coverUrl: this.initial.coverUrl,
          name: this.initial.bookName,
          author: this.initial.author,
          placeholderColor: ThemeRuntime.accentColor(this.darkMode),
          cornerRadius: 4,
          decodeWidth: 96,
          decodeHeight: 128
        })
      }
      .width(36)
      .height(48)
      .borderRadius(4)
      .clip(true)
      Column({ space: 2 }) {
        Text(this.initial.bookName)
          .fontSize(AppFontSize.BODY_LARGE)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeRuntime.primaryTextColor(this.darkMode))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.initial.author) {
          Text(this.initial.author)
            .fontSize(AppFontSize.CAPTION)
            .fontColor(ThemeRuntime.subTextColor(this.darkMode))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ top: AppSpacing.XS, bottom: AppSpacing.SM })
  }

  /** 右侧文字在 builder 里按状态算：按值传进 @Builder 的参数不会随状态刷新。 */
  private trailingText(kind: string): string {
    if (kind === 'rating') return this.rating > 0 ? '清除评分' : '点左半边是半颗星';
    if (kind === 'status') return '可以不选';
    if (kind === 'category') return `${this.categories.length}/${BookMarkRules.MAX_CATEGORIES}`;
    if (kind === 'review') return `${this.review.length}/${BookMarkRules.MAX_REVIEW_LENGTH}`;
    return '';
  }

  @Builder
  sectionLabel(title: string, kind: string) {
    Row() {
      Text(title)
        .fontSize(AppFontSize.CAPTION)
        .fontColor(ThemeRuntime.subTextColor(this.darkMode))
        .layoutWeight(1)
      Text(this.trailingText(kind))
        .fontSize(AppFontSize.CAPTION)
        .fontColor(kind === 'rating' && this.rating > 0 ? ThemeRuntime.accentColor(this.darkMode) :
          ThemeRuntime.subTextColor(this.darkMode))
        .padding({ left: AppSpacing.MD, top: AppSpacing.XS, bottom: AppSpacing.XS })
        .onClick(() => {
          if (kind === 'rating') this.rating = 0;
        })
    }
    .width('100%')
    .margin({ top: AppSpacing.XL, bottom: AppSpacing.MD })
  }

  @Builder
  ratingSection() {
    this.sectionLabel('评分', 'rating')
    Row({ space: AppSpacing.LG }) {
      BookMarkStars({
        rating: this.rating,
        starSize: 34,
        darkMode: this.darkMode,
        emptyColor: ThemeRuntime.softFillColor(this.darkMode),
        interactive: true,
        onRate: (value: number): void => { this.rating = value; }
      })
      Text(this.rating > 0 ? `${BookMarkRules.ratingText(this.rating)} · ${BookMarkRules.ratingLabel(this.rating)}` :
        '未打分')
        .fontSize(AppFontSize.BODY_LARGE)
        .fontWeight(this.rating > 0 ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.rating > 0 ? ThemeRuntime.primaryTextColor(this.darkMode) :
          ThemeRuntime.subTextColor(this.darkMode))
    }
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  statusSection() {
    this.sectionLabel('阅读状态', 'status')
    Row({ space: 3 }) {
      ForEach(BookMarkStatus.ALL, (value: number) => {
        Text(BookMarkStatus.label(value))
          .fontSize(AppFontSize.BODY)
          .fontWeight(this.status === value ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.status === value ? ThemeRuntime.primaryTextColor(this.darkMode) :
            ThemeRuntime.subTextColor(this.darkMode))
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
          .height(34)
          .borderRadius(ThemeRuntime.mediumRadius() - 2)
          .backgroundColor(this.status === value ? ThemeRuntime.cardColor(this.darkMode) : Color.Transparent)
          .shadow(this.status === value ? { radius: 4, color: '#1A000000', offsetY: 1 } :
            { radius: 0, color: Color.Transparent })
          .accessibilityText(`${BookMarkStatus.label(value)}${this.status === value ? '，已选' : ''}`)
          .onClick(() => {
            this.status = this.status === value ? BookMarkStatus.NONE : value;
          })
      }, (value: number) => `${value}`)
    }
    .width('100%')
    .padding(3)
    .borderRadius(ThemeRuntime.mediumRadius())
    .backgroundColor(ThemeRuntime.inputColor(this.darkMode))
  }

  @Builder
  categorySection() {
    this.sectionLabel('标签', 'category')
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(this.choices, (name: string) => {
        Text(name)
          .fontSize(AppFontSize.BODY)
          .fontColor(this.categories.includes(name) ? ThemeRuntime.accentColor(this.darkMode) :
            ThemeRuntime.subTextColor(this.darkMode))
          .height(32)
          .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
          .borderRadius(16)
          .border({ width: 1, color: this.categories.includes(name) ? ThemeRuntime.accentColor(this.darkMode) :
            Color.Transparent })
          .backgroundColor(this.categories.includes(name) ? ThemeRuntime.accentSurfaceColor(this.darkMode) :
            ThemeRuntime.inputColor(this.darkMode))
          .margin({ right: AppSpacing.MD, bottom: AppSpacing.MD })
          .accessibilityText(`${name}${this.categories.includes(name) ? '，已选' : ''}`)
          .onClick(() => this.toggleCategory(name))
      }, (name: string) => name)
      if (!this.addingCategory) {
        Row({ space: 2 }) {
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(14)
            .fontColor([ThemeRuntime.accentColor(this.darkMode)])
          Text('新标签')
            .fontSize(AppFontSize.BODY)
            .fontColor(ThemeRuntime.accentColor(this.darkMode))
        }
        .height(32)
        .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
        .borderRadius(16)
        .backgroundColor(ThemeRuntime.inputColor(this.darkMode))
        .margin({ right: AppSpacing.MD, bottom: AppSpacing.MD })
        .onClick(() => {
          this.addingCategory = true;
        })
      }
    }
    .width('100%')

    if (this.addingCategory) {
      Row({ space: AppSpacing.MD }) {
        TextInput({ text: this.categoryInput, placeholder: '标签名，比如“通勤读”' })
          .layoutWeight(1)
          .height(40)
          .maxLength(BookMarkRules.MAX_CATEGORY_LENGTH)
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(ThemeRuntime.primaryTextColor(this.darkMode))
          .placeholderColor(ThemeRuntime.subTextColor(this.darkMode))
          .caretColor(ThemeRuntime.accentColor(this.darkMode))
          .backgroundColor(ThemeRuntime.inputColor(this.darkMode))
          .borderRadius(ThemeRuntime.mediumRadius())
          .defaultFocus(true)
          .enterKeyType(EnterKeyType.Done)
          .onChange((value: string) => {
            this.categoryInput = value;
          })
          .onSubmit(() => this.addPendingCategory())
        Text('添加')
          .fontSize(AppFontSize.BODY_LARGE)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeRuntime.accentColor(this.darkMode))
          .padding({ left: AppSpacing.SM, right: AppSpacing.SM, top: AppSpacing.MD, bottom: AppSpacing.MD })
          .onClick(() => this.addPendingCategory())
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
  }

  @Builder
  focusSummaryRow() {
    Row({ space: AppSpacing.SM }) {
      if (this.rating > 0) {
        SymbolGlyph($r('sys.symbol.star_fill'))
          .fontSize(14)
          .fontColor([ThemeRuntime.accentColor(this.darkMode)])
      }
      Text(this.summaryText())
        .fontSize(AppFontSize.BODY)
        .fontColor(ThemeRuntime.primaryTextColor(this.darkMode))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      SymbolGlyph($r('sys.symbol.chevron_down'))
        .fontSize(14)
        .fontColor([ThemeRuntime.subTextColor(this.darkMode)])
    }
    .width('100%')
    .height(40)
    .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
    .margin({ top: AppSpacing.XS })
    .borderRadius(ThemeRuntime.mediumRadius())
    .backgroundColor(ThemeRuntime.inputColor(this.darkMode))
    .accessibilityText(`${this.summaryText()}，展开评分、状态和标签`)
    .onClick(() => this.leaveFocusMode())
  }

  @Builder
  reviewSection() {
    Column() {
      if (this.focusMode) {
        this.focusSummaryRow()
      }
      this.sectionLabel('短评', 'review')
    }
    .width('100%')
    .onSizeChange((_old: SizeOptions, next: SizeOptions) => {
      this.reviewHeadHeight = Number(next.height ?? 0);
    })
    TextArea({ text: this.review, placeholder: '读完的感受、推荐给谁、记住的一个细节……' })
      .id(BookMarkSheet.REVIEW_INPUT_ID)
      .width('100%')
      .height(this.focusMode ? this.focusedReviewHeight() : undefined)
      .constraintSize({ minHeight: 110 })
      .maxLength(BookMarkRules.MAX_REVIEW_LENGTH)
      .fontSize(AppFontSize.BODY_LARGE)
      .fontColor(ThemeRuntime.primaryTextColor(this.darkMode))
      .placeholderColor(ThemeRuntime.subTextColor(this.darkMode))
      .caretColor(ThemeRuntime.accentColor(this.darkMode))
      .backgroundColor(ThemeRuntime.inputColor(this.darkMode))
      .borderRadius(ThemeRuntime.mediumRadius())
      .onFocus(() => {
        this.reviewFocused = true;
        this.syncFocusMode();
      })
      .onBlur(() => {
        this.reviewFocused = false;
        this.syncFocusMode();
      })
      .onChange((value: string) => {
        this.review = value;
      })
  }
}
