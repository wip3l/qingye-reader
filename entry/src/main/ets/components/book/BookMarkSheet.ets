import { BookMark, BookMarkRules, BookMarkStatus } from '../../model/book/BookMark';
import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';
import { BookCover } from './BookCover';
import { BookMarkStars } from './BookMarkStars';

/**
 * 标记编辑面板的内容，材质交给宿主 bindSheet。打开时从 initial 复制一份草稿；
 * 点“完成”或下滑收起都会把草稿交给 onSave（没改动就不交），内容全清空由保存方当作删除。
 */
@Component
export struct BookMarkSheet {
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
  onSave: (mark: BookMark) => void = (_mark: BookMark): void => {
  };
  onDelete: () => void = (): void => {
  };
  onClose: () => void = (): void => {
  };

  @State rating: number = 0;
  @State status: number = BookMarkStatus.NONE;
  @State categories: string[] = [];
  @State review: string = '';
  @State choices: string[] = [];
  @State addingCategory: boolean = false;
  @State categoryInput: string = '';
  private finished: boolean = false;

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
  }

  aboutToDisappear(): void {
    // 下滑或点遮罩收起也保存，免得写了一半的短评丢掉。
    this.commit();
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

      Scroll() {
        Column() {
          this.bookRow()
          this.ratingSection()
          this.statusSection()
          this.categorySection()
          this.reviewSection()
          if (this.existing) {
            Text('删除标记')
              .fontSize(AppFontSize.BODY_LARGE)
              .fontColor(ThemeRuntime.dangerColor(this.darkMode))
              .padding(AppSpacing.LG)
              .margin({ top: AppSpacing.XL })
              .onClick(() => this.confirmDelete())
          }
        }
        .width('100%')
        .padding({ left: AppSpacing.XXL, right: AppSpacing.XXL, bottom: AppSpacing.XXXL + this.navBarHeight })
      }
      .layoutWeight(1)
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
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
      ForEach([BookMarkStatus.WANT, BookMarkStatus.READING, BookMarkStatus.READ], (value: number) => {
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
  reviewSection() {
    this.sectionLabel('短评', 'review')
    TextArea({ text: this.review, placeholder: '读完的感受、推荐给谁、记住的一个细节……' })
      .width('100%')
      .constraintSize({ minHeight: 110 })
      .maxLength(BookMarkRules.MAX_REVIEW_LENGTH)
      .fontSize(AppFontSize.BODY_LARGE)
      .fontColor(ThemeRuntime.primaryTextColor(this.darkMode))
      .placeholderColor(ThemeRuntime.subTextColor(this.darkMode))
      .caretColor(ThemeRuntime.accentColor(this.darkMode))
      .backgroundColor(ThemeRuntime.inputColor(this.darkMode))
      .borderRadius(ThemeRuntime.mediumRadius())
      .onChange((value: string) => {
        this.review = value;
      })
  }
}
