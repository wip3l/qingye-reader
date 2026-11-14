import { Book } from '@legado/sourceengine';
import { ImmersiveBackButton } from '../ImmersiveBackButton';
import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';
import { LocalBookService, TxtTocPreview, TxtTocPreviewItem } from '../../core/book/LocalBookService';
import { TxtTocRule, TxtTocRules } from '../../core/book/TxtTocRules';
import { TxtTocRuleStore } from '../../utils/TxtTocRuleStore';

class TxtTocRuleRowItem {
  rule: TxtTocRule;
  header: string;

  constructor(rule: TxtTocRule, header: string) {
    this.rule = rule;
    this.header = header;
  }
}

/**
 * "目录规则"对话框的内容（配合系统自定义对话框使用）：选一条规则即时试分章，看章数和开头几章，
 * 确认后由页面重新解析。重新解析期间锁住操作，和字符编码对话框一致。
 */
@Component
export struct ReaderTxtTocRuleDialogContent {
  book: Book | null = null;
  listHeight: number = 260;
  onApply: (ref: string) => Promise<void> = (_ref: string): Promise<void> => Promise.resolve();
  onClose: () => void = (): void => {
  };
  onManageRules: () => void = (): void => {
  };
  onApplyingChanged: (applying: boolean) => void = (_applying: boolean): void => {
  };

  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @State private rows: TxtTocRuleRowItem[] = [];
  @State private currentRef: string = '';
  @State private draftId: string = TxtTocRules.AUTO_ID;
  @State private draftWords: number = TxtTocRules.DEFAULT_WORDS_PER_CHAPTER;
  @State private preview: TxtTocPreview | null = null;
  @State private previewLoading: boolean = false;
  @State private previewError: string = '';
  @State private applying: boolean = false;
  /** 当前规则在分章之后被改过或删掉：选中它也能再应用一次。 */
  @State private currentOutdated: boolean = false;
  private previewToken: number = 0;

  aboutToAppear(): void {
    this.currentRef = LocalBookService.getTxtTocRuleRef(this.book);
    this.draftId = TxtTocRules.ruleIdOf(this.currentRef);
    this.draftWords = TxtTocRules.wordsOf(this.currentRef);
    this.loadRules();
  }

  private async loadRules(): Promise<void> {
    const settings = await TxtTocRuleStore.load(getContext(this));
    try {
      this.currentOutdated = await LocalBookService.txtTocRuleOutdated(getContext(this), this.book);
    } catch (e) {
      this.currentOutdated = false;
    }
    const rows: TxtTocRuleRowItem[] = [];
    let customHeaderShown = false;
    for (const rule of TxtTocRuleStore.allRules(settings)) {
      // 关掉的规则不在列表里出现，但这本书正在用的照样显示。
      if (!rule.enabled && rule.id !== this.draftId) continue;
      let header = '';
      if (!rule.builtin && !customHeaderShown) {
        header = '我的规则';
        customHeaderShown = true;
      }
      rows.push(new TxtTocRuleRowItem(rule, header));
    }
    if (!rows.some((row: TxtTocRuleRowItem): boolean => row.rule.id === this.draftId)) {
      this.draftId = TxtTocRules.AUTO_ID;
    }
    this.rows = rows;
    this.refreshPreview();
  }

  private draftRef(): string {
    return TxtTocRules.ref(this.draftId, this.draftWords);
  }

  private isDraftCurrent(): boolean {
    return this.draftRef() === this.currentRef && !this.currentOutdated;
  }

  private applyLabel(): string {
    if (this.applying) return '正在重新解析…';
    if (this.isDraftCurrent()) return '正在使用';
    return this.draftRef() === this.currentRef ? '重新分章' : '应用';
  }

  private draftRule(): TxtTocRule | null {
    const row = this.rows.find((item: TxtTocRuleRowItem): boolean => item.rule.id === this.draftId);
    return row ? row.rule : null;
  }

  private currentRuleName(): string {
    const id = TxtTocRules.ruleIdOf(this.currentRef);
    const row = this.rows.find((item: TxtTocRuleRowItem): boolean => item.rule.id === id);
    if (!row) return '智能识别';
    return TxtTocRules.displayName(row.rule, TxtTocRules.wordsOf(this.currentRef));
  }

  private async refreshPreview(): Promise<void> {
    if (!this.book) return;
    const token = ++this.previewToken;
    this.previewLoading = true;
    this.previewError = '';
    try {
      const preview = await LocalBookService.previewTxtToc(getContext(this), this.book, this.draftRef(), 5);
      if (token !== this.previewToken) return;
      this.preview = preview;
    } catch (e) {
      if (token !== this.previewToken) return;
      this.preview = null;
      this.previewError = (e as Error)?.message || '预览失败';
    } finally {
      if (token === this.previewToken) this.previewLoading = false;
    }
  }

  private select(rule: TxtTocRule): void {
    if (this.applying || this.draftId === rule.id) return;
    this.draftId = rule.id;
    this.refreshPreview();
  }

  private selectWords(words: number): void {
    if (this.applying || this.draftWords === words) return;
    this.draftWords = words;
    this.refreshPreview();
  }

  private async apply(): Promise<void> {
    if (this.applying || this.isDraftCurrent()) return;
    this.applying = true;
    this.onApplyingChanged(true);
    try {
      await this.onApply(this.draftRef());
    } finally {
      this.applying = false;
      this.onApplyingChanged(false);
    }
  }

  private textColor(): string {
    return ThemeRuntime.primaryTextColor(this.appDarkMode);
  }

  private subTextColor(): string {
    return ThemeRuntime.subTextColor(this.appDarkMode);
  }

  private warningTextColor(): string {
    return this.appDarkMode ? '#F2B766' : '#8A4500';
  }

  private warningSurfaceColor(): string {
    return this.appDarkMode ? '#3A2C1A' : '#FFF3E6';
  }

  private previewSummary(): string {
    const preview = this.preview;
    if (!preview) return '';
    if (preview.chapterCount <= 0) return '0 章';
    return `${preview.chapterCount.toLocaleString()} 章`;
  }

  private previewAverage(): string {
    const preview = this.preview;
    if (!preview || preview.chapterCount <= 0) return '';
    return `平均 ${Math.round(preview.totalChars / preview.chapterCount).toLocaleString()} 字`;
  }

  /** 预览结果的提示：空串表示看起来没问题。 */
  private previewWarning(): string {
    const preview = this.preview;
    if (!preview) return '';
    if (preview.noTitleMatched) return '没有匹配到任何标题。应用后整本书会按长度自动分段。';
    if (this.draftRule()?.kind === TxtTocRules.KIND_WORDS) return '';
    if (LocalBookService.looksOverSplit(preview.shortCount, preview.chapterCount)) {
      return `有 ${preview.shortCount} 章不到 ${TxtTocRules.SHORT_CHAPTER_CHARS} 字，可能把正文里的列表或对话认成了标题。`;
    }
    return '';
  }

  build() {
    Column({ space: AppSpacing.MD }) {
      Row() {
        Column({ space: AppSpacing.XXS }) {
          Text('目录规则')
            .fontSize(AppFontSize.TITLE)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.textColor())
          Text(`当前：${this.currentRuleName()}${this.currentOutdated ? '（规则已修改，可重新分章）' : ''}`)
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.subTextColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        ImmersiveBackButton({
          icon: $r('sys.symbol.xmark'),
          iconOffsetX: 0,
          iconColor: this.textColor(),
          darkMode: this.appDarkMode,
          buttonSize: 38,
          containerWidth: 38,
          containerHeight: 38,
          startInset: 0,
          compactLayout: true,
          accessibilityLabel: '关闭目录规则',
          onBack: () => {
            if (!this.applying) this.onClose();
          }
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Scroll() {
        Column({ space: AppSpacing.XS }) {
          ForEach(this.rows, (row: TxtTocRuleRowItem) => {
            this.ruleRow(row)
          }, (row: TxtTocRuleRowItem) => `${row.rule.id}|${row.header}`)
        }
        .width('100%')
      }
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .width('100%')
      .height(this.listHeight)
      .scrollBar(BarState.Auto)

      if (this.draftRule()?.kind === TxtTocRules.KIND_WORDS) {
        Row({ space: AppSpacing.SM }) {
          Text('每章字数')
            .fontSize(AppFontSize.BODY)
            .fontColor(this.subTextColor())
            .layoutWeight(1)
          ForEach(TxtTocRules.WORD_OPTIONS, (words: number) => {
            Text(TxtTocRules.wordsLabel(words))
              .fontSize(AppFontSize.CAPTION)
              .fontColor(this.draftWords === words ? ThemeRuntime.onAccentColor() : this.textColor())
              .height(32)
              .padding({ left: AppSpacing.MD, right: AppSpacing.MD })
              .borderRadius(16)
              .backgroundColor(this.draftWords === words ? ThemeRuntime.buttonColor(this.appDarkMode) :
                ThemeRuntime.softFillColor(this.appDarkMode))
              .enabled(!this.applying)
              .accessibilityText(`每章 ${TxtTocRules.wordsLabel(words)}`)
              .onClick(() => this.selectWords(words))
          }, (words: number) => `${words}`)
        }
        .width('100%')
      }

      this.previewCard()

      Row({ space: AppSpacing.LG }) {
        Button('管理规则')
          .layoutWeight(1)
          .height(42)
          .fontColor(this.textColor())
          .backgroundColor(ThemeRuntime.hairlineColor(this.appDarkMode))
          .enabled(!this.applying)
          .onClick(() => this.onManageRules())
        Button(this.applyLabel())
          .layoutWeight(1)
          .height(42)
          .fontColor(ThemeRuntime.onAccentColor())
          .backgroundColor(ThemeRuntime.buttonColor(this.appDarkMode))
          .enabled(!this.applying && !this.isDraftCurrent())
          .opacity(this.isDraftCurrent() && !this.applying ? 0.5 : 1)
          .onClick(() => this.apply())
      }
      .width('100%')
    }
    .width('100%')
    .constraintSize({ maxWidth: 440 })
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.XL, bottom: AppSpacing.XL })
  }

  @Builder
  ruleRow(row: TxtTocRuleRowItem) {
    Column({ space: AppSpacing.XS }) {
      if (row.header) {
        Text(row.header)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
          .padding({ left: AppSpacing.LG, top: AppSpacing.SM })
      }
      Row({ space: AppSpacing.LG }) {
        Column({ space: AppSpacing.XXS }) {
          Text(row.rule.name)
            .fontSize(AppFontSize.BODY_LARGE)
            .fontColor(this.textColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(row.rule.desc || row.rule.example || row.rule.pattern)
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.subTextColor())
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        if (this.draftId === row.rule.id) {
          SymbolGlyph($r('sys.symbol.checkmark_circle'))
            .fontSize(22)
            .fontColor([ThemeRuntime.accentColor(this.appDarkMode)])
        }
      }
      .width('100%')
      .constraintSize({ minHeight: 56 })
      .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.SM, bottom: AppSpacing.SM })
      .borderRadius(ThemeRuntime.largeRadius())
      .backgroundColor(this.draftId === row.rule.id ?
        ThemeRuntime.accentSurfaceColor(this.appDarkMode) : Color.Transparent)
      .enabled(!this.applying)
      .onClick(() => this.select(row.rule))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  previewCard() {
    Column({ space: AppSpacing.SM }) {
      Row({ space: AppSpacing.SM }) {
        Text('预览')
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
        if (this.previewLoading) {
          LoadingProgress()
            .width(18)
            .height(18)
            .color(this.subTextColor())
          Text('正在试分章…')
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.subTextColor())
        } else if (this.preview) {
          Text(this.previewSummary())
            .fontSize(AppFontSize.SUBTITLE)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.textColor())
          Text(this.previewAverage())
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.subTextColor())
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.previewError) {
        Text(this.previewError)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(ThemeRuntime.dangerColor(this.appDarkMode))
      } else if (this.preview && !this.previewLoading) {
        if (this.previewWarning()) {
          Text(this.previewWarning())
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.warningTextColor())
            .width('100%')
            .padding({ left: AppSpacing.MD, right: AppSpacing.MD, top: AppSpacing.SM, bottom: AppSpacing.SM })
            .borderRadius(10)
            .backgroundColor(this.warningSurfaceColor())
        }
        ForEach(this.preview.items, (item: TxtTocPreviewItem, index: number) => {
          Row({ space: AppSpacing.MD }) {
            Text(`${index + 1}`)
              .fontSize(AppFontSize.CAPTION)
              .fontColor(this.subTextColor())
              .width(22)
            Text(item.title)
              .fontSize(AppFontSize.BODY)
              .fontColor(this.textColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            Text(`${item.length.toLocaleString()} 字`)
              .fontSize(AppFontSize.CAPTION)
              .fontColor(this.subTextColor())
          }
          .width('100%')
          .height(28)
        }, (item: TxtTocPreviewItem, index: number) => `${index}|${item.title}|${item.length}`)
      }
    }
    .width('100%')
    .constraintSize({ minHeight: 120 })
    .padding(AppSpacing.LG)
    .borderRadius(ThemeRuntime.largeRadius())
    .backgroundColor(ThemeRuntime.softFillColor(this.appDarkMode))
    .alignItems(HorizontalAlign.Start)
  }
}
