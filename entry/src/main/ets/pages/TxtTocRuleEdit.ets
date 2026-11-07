import { promptAction, router } from '@kit.ArkUI';
import { Book } from '@legado/sourceengine';
import { PageScaffold } from '../components/common/PageScaffold';
import { SettingRow, SettingSwitchRow } from '../components/common/SettingRow';
import { ImmersiveHeaderAction } from '../components/ImmersiveHeaderAction';
import { ImmersiveBackButton } from '../components/ImmersiveBackButton';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { syncSystemBars } from '../utils/SystemBars';
import { HdsFeedback } from '../utils/HdsFeedback';
import { TxtTocRuleSettings, TxtTocRuleStore } from '../utils/TxtTocRuleStore';
import { TxtChapterMatcher, TxtTocResolvedRule, TxtTocRule, TxtTocRules } from '../core/book/TxtTocRules';
import { LocalBookService, TxtTocPreview, TxtTocPreviewItem } from '../core/book/LocalBookService';
import { appDb } from '../model/data/AppDatabase';

class TxtTocTestLine {
  text: string = '';
  isTitle: boolean = false;
}

const MIN_TITLE_LENGTH = 5;
const MAX_TITLE_LENGTH = 200;
const TITLE_LENGTH_STEP = 5;
const DEFAULT_TEST_TEXT ='第一卷 风起 第三章 灯塔\n\u3000\u3000雨是从傍晚开始下的。\n1、不要相信邮差。';

/** 新建 / 编辑一条自定义 TXT 目录规则，可逐行试匹配，也能用当前书全文试分章。 */
@Entry
@Component
struct TxtTocRuleEditPage {
  @StorageProp('appDarkMode') darkMode: boolean = false;
  @StorageProp('themeRevision') themeRevision: number = 0;
  @State name: string = '';
  @State pattern: string = '';
  @State example: string = '';
  @State maxTitleLength: number = TxtTocRules.DEFAULT_MAX_TITLE_LENGTH;
  @State ignoreCase: boolean = true;
  @State ruleEnabled: boolean = true;
  @State maxTitleLengthInputVisible: boolean = false;
  @State maxTitleLengthDraft: string = '';
  @State testText: string = DEFAULT_TEST_TEXT;
  @State isNew: boolean = true;
  @State loaded: boolean = false;
  @State testBookName: string = '';
  @State bookPreview: TxtTocPreview | null = null;
  @State bookPreviewLoading: boolean = false;
  @State bookPreviewError: string = '';
  private ruleId: string = '';
  private testBook: Book | null = null;
  private previewToken: number = 0;

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, string>;
    const ruleId = params && typeof params['ruleId'] === 'string' ? params['ruleId'] : '';
    const copyFrom = params && typeof params['copyFrom'] === 'string' ? params['copyFrom'] : '';
    const bookUrl = params && typeof params['bookUrl'] === 'string' ? params['bookUrl'] : '';
    this.load(ruleId, copyFrom, bookUrl);
  }

  onPageShow(): void {
    const context = this.getUIContext().getHostContext();
    if (context) syncSystemBars(context, this.darkMode);
  }

  private async load(ruleId: string, copyFrom: string, bookUrl: string): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    const settings = await TxtTocRuleStore.load(context, true);
    const rules = TxtTocRuleStore.allRules(settings);
    const existing = ruleId ? settings.customRules.find((rule: TxtTocRule): boolean => rule.id === ruleId) : undefined;
    const source = copyFrom ? rules.find((rule: TxtTocRule): boolean => rule.id === copyFrom) : undefined;
    if (existing) {
      this.ruleId = existing.id;
      this.isNew = false;
      this.fill(existing);
      this.ruleEnabled = existing.enabled;
    } else {
      this.ruleId = TxtTocRules.newCustomRule().id;
      this.isNew = true;
      if (source && source.kind === TxtTocRules.KIND_REGEX) {
        this.fill(source);
        this.name = `${source.name}（副本）`;
      }
    }
    if (this.example) this.testText = `${this.example}\n${DEFAULT_TEST_TEXT}`;
    this.loaded = true;
    if (bookUrl) {
      try {
        await appDb.initWithContext(context);
        const book = await appDb.getBook(bookUrl);
        if (book && LocalBookService.isLocalTxtBook(book)) {
          this.testBook = book;
          this.testBookName = book.name;
        }
      } catch (e) {
        console.warn('[TxtTocRuleEdit] 读取测试书籍失败:', e);
      }
    }
  }

  private fill(rule: TxtTocRule): void {
    this.name = rule.name;
    this.pattern = rule.pattern;
    this.example = rule.example;
    this.maxTitleLength = rule.maxTitleLength;
    this.ignoreCase = rule.ignoreCase;
  }

  private setMaxTitleLength(value: number): void {
    if (!Number.isFinite(value)) return;
    this.maxTitleLength = Math.min(MAX_TITLE_LENGTH, Math.max(MIN_TITLE_LENGTH, Math.round(value)));
  }

  private applyMaxTitleLengthInput(): void {
    if (!this.maxTitleLengthInputVisible) return;
    if (this.maxTitleLengthDraft.trim()) this.setMaxTitleLength(Number(this.maxTitleLengthDraft));
    this.maxTitleLengthInputVisible = false;
  }

  private stepMaxTitleLength(delta: number): void {
    this.applyMaxTitleLengthInput();
    this.setMaxTitleLength(this.maxTitleLength + delta);
  }

  private draftRule(): TxtTocRule {
    const rule = TxtTocRules.newCustomRule();
    rule.id = this.ruleId;
    rule.name = this.name.trim() || '未命名规则';
    rule.pattern = this.pattern.trim();
    rule.example = this.example.trim();
    rule.maxTitleLength = this.maxTitleLength;
    rule.ignoreCase = this.ignoreCase;
    rule.enabled = this.ruleEnabled;
    return rule;
  }

  private draftResolved(): TxtTocResolvedRule {
    const resolved = new TxtTocResolvedRule();
    resolved.rule = this.draftRule();
    return resolved;
  }

  private patternError(): string {
    return this.pattern.trim() ? TxtTocRules.patternError(this.pattern) : '';
  }

  private testLines(): TxtTocTestLine[] {
    const lines = this.testText.split('\n').filter((line: string): boolean => line.trim().length > 0).slice(0, 20);
    let matcher: TxtChapterMatcher | null = null;
    if (this.pattern.trim() && !this.patternError()) {
      try {
        matcher = new TxtChapterMatcher(this.draftResolved());
      } catch (e) {
        matcher = null;
      }
    }
    return lines.map((line: string): TxtTocTestLine => {
      const item = new TxtTocTestLine();
      item.text = line;
      const candidate = line.replace(/[\u200B-\u200D\u2060\uFEFF]/g, '').trim();
      item.isTitle = matcher !== null && matcher.isTitle(line, candidate);
      return item;
    });
  }

  private async runBookPreview(): Promise<void> {
    const book = this.testBook;
    if (!book) return;
    const error = TxtTocRules.patternError(this.pattern);
    if (error) {
      HdsFeedback.showToast(error);
      return;
    }
    const token = ++this.previewToken;
    this.bookPreviewLoading = true;
    this.bookPreviewError = '';
    try {
      const preview = await LocalBookService.previewTxtTocWithRule(book, this.draftResolved(), 5);
      if (token !== this.previewToken) return;
      this.bookPreview = preview;
    } catch (e) {
      if (token !== this.previewToken) return;
      this.bookPreview = null;
      this.bookPreviewError = (e as Error)?.message || '测试失败';
    } finally {
      if (token === this.previewToken) this.bookPreviewLoading = false;
    }
  }

  private async save(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    this.applyMaxTitleLengthInput();
    const error = TxtTocRules.patternError(this.pattern);
    if (error) {
      HdsFeedback.showToast(error);
      return;
    }
    try {
      const settings = await TxtTocRuleStore.load(context, true);
      const next = this.copySettings(settings);
      const rule = this.draftRule();
      const index = next.customRules.findIndex((item: TxtTocRule): boolean => item.id === rule.id);
      if (index >= 0) next.customRules[index] = rule;
      else next.customRules.push(rule);
      await TxtTocRuleStore.save(context, next);
      HdsFeedback.showToast(this.isNew ? '已新建目录规则' : '已保存');
      router.back();
    } catch (e) {
      console.warn('[TxtTocRuleEdit] 保存失败:', e);
      HdsFeedback.showToast('保存失败，请重试');
    }
  }

  private async confirmDelete(): Promise<void> {
    const result = await promptAction.showDialog({
      title: '删除这条规则？',
      message: '正在用它的书会改回智能识别，下次重新解析时生效。',
      buttons: [
        { text: '取消', color: ThemeRuntime.subTextColor(this.darkMode) },
        { text: '删除', color: ThemeRuntime.dangerColor(this.darkMode) }
      ]
    });
    if (result.index !== 1) return;
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    try {
      const settings = await TxtTocRuleStore.load(context, true);
      const next = this.copySettings(settings);
      next.customRules = next.customRules.filter((item: TxtTocRule): boolean => item.id !== this.ruleId);
      if (TxtTocRules.ruleIdOf(next.defaultRuleRef) === this.ruleId) next.defaultRuleRef = '';
      await TxtTocRuleStore.save(context, next);
      HdsFeedback.showToast('已删除');
      router.back();
    } catch (e) {
      console.warn('[TxtTocRuleEdit] 删除失败:', e);
      HdsFeedback.showToast('删除失败，请重试');
    }
  }

  private copySettings(source: TxtTocRuleSettings): TxtTocRuleSettings {
    const next = new TxtTocRuleSettings();
    next.customRules = source.customRules.map((rule: TxtTocRule): TxtTocRule => TxtTocRules.clone(rule));
    next.disabledBuiltins = source.disabledBuiltins.slice();
    next.defaultRuleRef = source.defaultRuleRef;
    return next;
  }

  private textColor(): string {
    return ThemeRuntime.primaryTextColor(this.darkMode);
  }

  private subTextColor(): string {
    return ThemeRuntime.subTextColor(this.darkMode);
  }

  @Builder
  sectionTitle(label: string) {
    Text(label)
      .fontSize(AppFontSize.BODY)
      .fontColor(this.subTextColor())
      .width('100%')
      .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.XXL, bottom: AppSpacing.MD })
  }

  @Builder
  fieldLabel(label: string) {
    Text(label)
      .fontSize(AppFontSize.BODY)
      .fontColor(this.textColor())
      .width('100%')
  }

  @Builder
  pageActions() {
    ImmersiveHeaderAction({
      label: '保存',
      accessibilityLabel: '保存目录规则',
      onTap: () => {
        this.save();
      }
    })
      .margin({ right: AppSpacing.XL })
  }

  @Builder
  ruleFields() {
    this.fieldLabel('名称')
    TextInput({ text: this.name, placeholder: '例如：卷章同行' })
      .fontSize(AppFontSize.BODY)
      .fontColor(this.textColor())
      .backgroundColor(ThemeRuntime.inputColor(this.darkMode))
      .height(42)
      .maxLength(30)
      .onChange((value: string) => {
        this.name = value;
      })
    this.fieldLabel('标题正则')
    TextArea({ text: this.pattern, placeholder: '^第.{1,8}章.{0,30}$' })
      .fontSize(AppFontSize.BODY)
      .fontFamily('monospace')
      .fontColor(this.textColor())
      .backgroundColor(ThemeRuntime.inputColor(this.darkMode))
      .constraintSize({ minHeight: 72 })
      .onChange((value: string) => {
        this.pattern = value;
        this.bookPreview = null;
      })
    if (this.patternError()) {
      Text(this.patternError())
        .fontSize(AppFontSize.CAPTION)
        .fontColor(ThemeRuntime.dangerColor(this.darkMode))
    }
    Text('逐行匹配，每行去掉首尾空白后再判断，匹配到的行就是章节标题。支持安卓阅读的 Java 正则写法。')
      .fontSize(AppFontSize.CAPTION)
      .fontColor(this.subTextColor())
    this.fieldLabel('示例标题（选填）')
    TextInput({ text: this.example, placeholder: '第一卷 风起 第三章 灯塔' })
      .fontSize(AppFontSize.BODY)
      .fontColor(this.textColor())
      .backgroundColor(ThemeRuntime.inputColor(this.darkMode))
      .height(42)
      .onChange((value: string) => {
        this.example = value;
      })
  }

  @Builder
  optionRows() {
    SettingRow({ title: '标题最长字数', description: '超过这个长度的行一律当正文' }) {
      // 和亮屏时间、排版数值一样的步进器：图标按钮加减，点中间的数值直接输入。
      Row({ space: 4 }) {
        ImmersiveBackButton({
          icon: $r('sys.symbol.minus'),
          accessibilityLabel: '减少标题最长字数',
          iconColor: this.textColor(),
          disabledIconColor: this.subTextColor(),
          darkMode: this.darkMode,
          buttonEnabled: this.maxTitleLength > MIN_TITLE_LENGTH,
          buttonSize: 34,
          containerWidth: 34,
          containerHeight: 34,
          startInset: 0,
          compactLayout: true,
          onBack: (): void => this.stepMaxTitleLength(-TITLE_LENGTH_STEP)
        })
        if (this.maxTitleLengthInputVisible) {
          TextInput({ text: this.maxTitleLengthDraft, placeholder: `${this.maxTitleLength}` })
            .type(InputType.Number)
            .enterKeyType(EnterKeyType.Done)
            .defaultFocus(true)
            .fontSize(AppFontSize.BODY)
            .fontColor(this.textColor())
            .width(52)
            .height(34)
            .padding(0)
            .textAlign(TextAlign.Center)
            .backgroundColor(ThemeRuntime.inputColor(this.darkMode))
            .borderRadius(ThemeRuntime.mediumRadius())
            .onChange((value: string) => {
              this.maxTitleLengthDraft = value.replace(/[^0-9]/g, '').substring(0, 3);
            })
            .onSubmit(() => this.applyMaxTitleLengthInput())
            .onBlur(() => this.applyMaxTitleLengthInput())
        } else {
          Text(`${this.maxTitleLength}`)
            .fontSize(AppFontSize.BODY)
            .fontColor(this.textColor())
            .width(52)
            .height(34)
            .textAlign(TextAlign.Center)
            .accessibilityText(`标题最长 ${this.maxTitleLength} 字，点按输入`)
            .onClick(() => {
              this.maxTitleLengthDraft = '';
              this.maxTitleLengthInputVisible = true;
            })
        }
        ImmersiveBackButton({
          icon: $r('sys.symbol.plus'),
          accessibilityLabel: '增加标题最长字数',
          iconColor: this.textColor(),
          disabledIconColor: this.subTextColor(),
          darkMode: this.darkMode,
          buttonEnabled: this.maxTitleLength < MAX_TITLE_LENGTH,
          buttonSize: 34,
          containerWidth: 34,
          containerHeight: 34,
          startInset: 0,
          compactLayout: true,
          onBack: (): void => this.stepMaxTitleLength(TITLE_LENGTH_STEP)
        })
      }
      .alignItems(VerticalAlign.Center)
    }
    SettingSwitchRow({
      title: '忽略英文大小写',
      isOn: this.ignoreCase,
      onChange: (checked: boolean): void => {
        this.ignoreCase = checked;
      }
    })
    SettingSwitchRow({
      title: '启用',
      description: '关掉后不在书内的规则列表里出现',
      isOn: this.ruleEnabled,
      showDivider: false,
      onChange: (checked: boolean): void => {
        this.ruleEnabled = checked;
      }
    })
  }

  @Builder
  testSection() {
    TextArea({ text: this.testText, placeholder: '每行一句，看看哪些会被当成标题' })
      .fontSize(AppFontSize.BODY)
      .fontColor(this.textColor())
      .backgroundColor(ThemeRuntime.inputColor(this.darkMode))
      .constraintSize({ minHeight: 72 })
      .onChange((value: string) => {
        this.testText = value;
      })
    ForEach(this.testLines(), (line: TxtTocTestLine, index: number) => {
      Row({ space: AppSpacing.MD }) {
        Text(line.isTitle ? '标题' : '正文')
          .fontSize(AppFontSize.CAPTION)
          .fontColor(line.isTitle ? ThemeRuntime.accentColor(this.darkMode) : this.subTextColor())
          .fontWeight(line.isTitle ? FontWeight.Medium : FontWeight.Normal)
          .width(44)
          .height(22)
          .textAlign(TextAlign.Center)
          .borderRadius(11)
          .backgroundColor(line.isTitle ? ThemeRuntime.accentSurfaceColor(this.darkMode) :
            ThemeRuntime.softFillColor(this.darkMode))
        Text(line.text)
          .fontSize(AppFontSize.BODY)
          .fontColor(this.textColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .width('100%')
    }, (line: TxtTocTestLine, index: number) => `${index}|${line.isTitle}|${line.text}`)
    if (this.testBook) {
      Button(this.bookPreviewLoading ? '正在试分章…' : `用「${this.testBookName}」全文测试`)
        .width('100%')
        .height(42)
        .fontColor(ThemeRuntime.accentColor(this.darkMode))
        .backgroundColor(ThemeRuntime.accentSurfaceColor(this.darkMode))
        .enabled(!this.bookPreviewLoading)
        .onClick(() => {
          this.runBookPreview();
        })
      if (this.bookPreviewError) {
        Text(this.bookPreviewError)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(ThemeRuntime.dangerColor(this.darkMode))
      } else if (this.bookPreview) {
        this.bookPreviewResult(this.bookPreview)
      }
    }
  }

  @Builder
  bookPreviewResult(preview: TxtTocPreview) {
    Text(preview.noTitleMatched ? '没有匹配到任何标题' :
      `分成 ${preview.chapterCount.toLocaleString()} 章，平均 ${Math.round(preview.totalChars /
        Math.max(1, preview.chapterCount)).toLocaleString()} 字` +
        (LocalBookService.looksOverSplit(preview.shortCount, preview.chapterCount) ?
          `；有 ${preview.shortCount} 章不到 ${TxtTocRules.SHORT_CHAPTER_CHARS} 字` : ''))
      .fontSize(AppFontSize.BODY)
      .fontColor(this.textColor())
    ForEach(preview.items, (item: TxtTocPreviewItem, index: number) => {
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
    }, (item: TxtTocPreviewItem, index: number) => `${index}|${item.title}`)
  }

  @Builder
  pageContent() {
    if (this.loaded) {
      Column({ space: AppSpacing.MD }) {
        this.ruleFields()
      }
      .width('calc(100% - 24vp)')
      .margin({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.MD })
      .padding(AppSpacing.LG)
      .borderRadius(ThemeRuntime.cardRadius())
      .backgroundColor(ThemeRuntime.cardColor(this.darkMode))
      .alignItems(HorizontalAlign.Start)

      Column() {
        this.optionRows()
      }
      .width('calc(100% - 24vp)')
      .margin({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.MD })
      .borderRadius(ThemeRuntime.cardRadius())
      .clip(true)
      .backgroundColor(ThemeRuntime.cardColor(this.darkMode))

      this.sectionTitle('测试 · 每行会标出是否被当成标题')
      Column({ space: AppSpacing.SM }) {
        this.testSection()
      }
      .width('calc(100% - 24vp)')
      .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
      .padding(AppSpacing.LG)
      .borderRadius(ThemeRuntime.cardRadius())
      .backgroundColor(ThemeRuntime.cardColor(this.darkMode))
      .alignItems(HorizontalAlign.Start)

      if (!this.isNew) {
        Button('删除规则')
          .width('calc(100% - 24vp)')
          .height(44)
          .margin({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.XXL, bottom: AppSpacing.XXL })
          .fontColor(ThemeRuntime.dangerColor(this.darkMode))
          .backgroundColor(ThemeRuntime.cardColor(this.darkMode))
          .onClick(() => {
            this.confirmDelete();
          })
      } else {
        Blank().height(AppSpacing.XXL)
      }
    }
  }

  build() {
    Stack() {
      PageScaffold({
        title: this.isNew ? '新建目录规则' : '编辑目录规则',
        content: (): void => {
          this.pageContent();
        },
        actions: (): void => {
          this.pageActions();
        }
      })
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
