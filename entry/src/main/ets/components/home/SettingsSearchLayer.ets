import { promptAction, router } from '@kit.ArkUI';
import preferences from '@ohos.data.preferences';
import { TextTranslator } from '@legado/aiengine';
import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';
import { ImmersiveBackButton } from '../ImmersiveBackButton';
import { ImmersiveMaterialSurface } from '../ImmersiveMaterialSurface';
import { HelpData, HelpManual, HelpSection } from '../../utils/HelpManual';
import { SettingsFocus } from '../../utils/SettingsFocus';
import {
  normalizeSettingsQuery,
  searchSettings,
  SETTINGS_SEARCH_HINTS,
  SettingsSearchEntry,
  settingsHighlightParts,
  settingsQueryTokens
} from '../../utils/SettingsSearchIndex';

class FaqHit {
  section: HelpSection;
  score: number;

  constructor(section: HelpSection, score: number) {
    this.section = section;
    this.score = score;
  }
}

/**
 * “我的”页的设置搜索层：盖在“我的”上，搜设置项和帮助里的常见问题。
 * 点设置结果打开所在页面并定位到那一行（SettingsFocus）；从设置页返回时搜索层和关键词都还在。
 * 开合由 AppStorage `mineSearchActive` 控制，首页的返回键先收起它。
 */
@Component
export struct SettingsSearchLayer {
  private static readonly INPUT_ID: string = 'mine_settings_search_input';
  private static readonly STORE_NAME: string = 'settings_search';
  private static readonly KEY_RECENT: string = 'recent';
  private static readonly MAX_RECENT: number = 8;
  private static readonly MAX_FAQ: number = 6;
  private static readonly CONTROL_SIZE: number = 40;

  @Prop statusBarHeight: number = 0;
  @Prop navBarHeight: number = 0;
  @StorageLink('mineSearchActive') mineSearchActive: boolean = false;
  @StorageProp('webParseEnabled') webParseEnabled: boolean = false;
  @StorageProp('appDarkMode') appDarkMode: boolean = false;
  @StorageProp('themeRevision') themeRevision: number = 0;
  @State keyword: string = '';
  @State results: SettingsSearchEntry[] = [];
  @State faqResults: HelpSection[] = [];
  @State recent: string[] = [];
  @State fieldWidth: number = 0;
  private helpData: HelpData | null = null;
  /** 繁体输入搜不到时才加载的繁→简字典（等长转换）。 */
  private toSimplified: ((text: string) => string) | null = null;
  private dictionaryLoading: boolean = false;
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    const context = getContext(this);
    this.loadRecent(context);
    HelpManual.load(context).then((data: HelpData) => {
      this.helpData = data;
      if (this.keyword.trim()) this.runSearch();
    }).catch((error: Error) => {
      console.warn('设置搜索读取常见问题失败:', error.message);
    });
    this.focusInputSoon();
  }

  focusInputSoon(): void {
    setTimeout(() => {
      try {
        this.getUIContext().getFocusController().requestFocus(SettingsSearchLayer.INPUT_ID);
      } catch (e) {
      }
    }, 120);
  }

  close(): void {
    try {
      this.getUIContext().getFocusController().clearFocus();
    } catch (e) {
    }
    this.mineSearchActive = false;
  }

  onKeywordChange(value: string): void {
    this.keyword = value;
    this.runSearch();
  }

  runSearch(): void {
    const query = this.keyword;
    if (!query.trim()) {
      this.results = [];
      this.faqResults = [];
      return;
    }
    let settings = searchSettings(query);
    let faq = this.searchFaq(query);
    if (settings.length === 0 && faq.length === 0) {
      // 可能是繁体输入：折成简体再搜一次；字典第一次用到时才加载。
      if (this.toSimplified) {
        const simplified = this.toSimplified(query);
        if (simplified !== query) {
          settings = searchSettings(simplified);
          faq = this.searchFaq(simplified);
        }
      } else {
        this.loadDictionary();
      }
    }
    this.results = settings;
    this.faqResults = faq;
  }

  loadDictionary(): void {
    if (this.dictionaryLoading) return;
    this.dictionaryLoading = true;
    TextTranslator.dictionary(getContext(this)).then((dictionary) => {
      this.toSimplified = (text: string): string => dictionary.convertSameLength(text);
      if (this.keyword.trim()) this.runSearch();
    }).catch((error: Error) => {
      console.warn('设置搜索加载繁简字典失败:', error.message);
    });
  }

  /** 常见问题：标题命中排前，正文命中排后；空格分开的词须全部命中。 */
  searchFaq(query: string): HelpSection[] {
    const faq = this.helpData?.faq;
    if (!faq) return [];
    const tokens = settingsQueryTokens(query);
    if (tokens.length === 0) return [];
    const hits: FaqHit[] = [];
    faq.parts.forEach((part) => {
      part.sections.forEach((section: HelpSection) => {
        const title = normalizeSettingsQuery(section.title);
        const text = normalizeSettingsQuery(section.text);
        let score = 0;
        for (const token of tokens) {
          if (title.includes(token)) score += 2;
          else if (text.includes(token)) score += 1;
          else return;
        }
        hits.push(new FaqHit(section, score));
      });
    });
    return hits.sort((a: FaqHit, b: FaqHit) => b.score - a.score)
      .slice(0, SettingsSearchLayer.MAX_FAQ)
      .map((hit: FaqHit) => hit.section);
  }

  isBlocked(entry: SettingsSearchEntry): boolean {
    return entry.requiresWebParse && !this.webParseEnabled;
  }

  openEntry(entry: SettingsSearchEntry): void {
    this.rememberKeyword();
    if (this.isBlocked(entry)) {
      try {
        promptAction.showToast({ message: `先开启网页解析，才能使用“${entry.title}”` });
      } catch (e) {
      }
      SettingsFocus.open('pages/WebParseSettings', undefined, '网页解析');
      return;
    }
    SettingsFocus.open(entry.page.url, entry.page.params, entry.focus);
  }

  openFaq(section: HelpSection): void {
    this.rememberKeyword();
    HelpManual.openTopic(HelpManual.FAQ_TOPIC_ID, section.id);
  }

  async loadRecent(context: Context): Promise<void> {
    try {
      const store = await preferences.getPreferences(context, SettingsSearchLayer.STORE_NAME);
      const raw = await store.get(SettingsSearchLayer.KEY_RECENT, '[]') as string;
      const parsed = JSON.parse(raw) as string[];
      this.recent = Array.isArray(parsed) ? parsed.filter((item: string) => typeof item === 'string').slice(0,
        SettingsSearchLayer.MAX_RECENT) : [];
    } catch (e) {
      this.recent = [];
    }
  }

  rememberKeyword(): void {
    const keyword = this.keyword.trim();
    if (!keyword) return;
    this.recent = [keyword, ...this.recent.filter((item: string) => item !== keyword)]
      .slice(0, SettingsSearchLayer.MAX_RECENT);
    this.saveRecent();
  }

  clearRecent(): void {
    this.recent = [];
    this.saveRecent();
  }

  async saveRecent(): Promise<void> {
    try {
      const store = await preferences.getPreferences(getContext(this), SettingsSearchLayer.STORE_NAME);
      await store.put(SettingsSearchLayer.KEY_RECENT, JSON.stringify(this.recent));
      await store.flush();
    } catch (e) {
      console.warn('保存设置搜索记录失败:', (e as Error).message);
    }
  }

  build() {
    Column() {
      Column()
        .width('100%')
        .height(this.statusBarHeight)

      this.header()

      Scroll(this.scroller) {
        Column({ space: AppSpacing.LG }) {
          if (!this.keyword.trim()) {
            this.idleContent()
          } else if (this.results.length === 0 && this.faqResults.length === 0) {
            this.emptyContent()
          } else {
            if (this.results.length > 0) {
              this.groupLabel(`设置 · ${this.results.length}`)
              Column() {
                ForEach(this.results, (entry: SettingsSearchEntry, index: number) => {
                  this.settingRow(entry, index < this.results.length - 1)
                }, (entry: SettingsSearchEntry) => `${entry.id}:${this.keyword}:${this.webParseEnabled}`)
              }
              .width('100%')
              .borderRadius(ThemeRuntime.largeRadius())
              .clip(true)
              .backgroundColor(this.cardColor())
            }
            if (this.faqResults.length > 0) {
              this.groupLabel(`常见问题 · ${this.faqResults.length}`)
              Column() {
                ForEach(this.faqResults, (section: HelpSection, index: number) => {
                  this.faqRow(section, index < this.faqResults.length - 1)
                }, (section: HelpSection) => `${section.id}:${this.keyword}`)
              }
              .width('100%')
              .borderRadius(ThemeRuntime.largeRadius())
              .clip(true)
              .backgroundColor(this.cardColor())
            }
          }
          Row()
            .width('100%')
            .height(Math.max(this.navBarHeight, 8) + 24)
        }
        .width('calc(100% - 32vp)')
        .margin({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.XS })
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.TopStart)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .onScrollStart(() => {
        // 滑动结果时收起键盘，留出更多空间。
        try {
          this.getUIContext().getFocusController().clearFocus();
        } catch (e) {
        }
      })
    }
    .width('100%')
    .height('100%')
    // 有主题背景图时“我的”页底色是透明的，搜索层要自己铺满底色，不能透出下面的列表。
    .backgroundColor(ThemeRuntime.pageColor(this.appDarkMode))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  header() {
    Row() {
      ImmersiveBackButton({ iconColor: this.primaryTextColor(), darkMode: this.appDarkMode,
        buttonSize: 40, containerWidth: 56, containerHeight: SettingsSearchLayer.CONTROL_SIZE,
        materialScale: 0.83, compactLayout: true, accessibilityLabel: '关闭设置搜索',
        onBack: () => this.close() })
      Row() {
        if (this.fieldWidth > 0) {
          ImmersiveMaterialSurface({
            surfaceWidth: this.fieldWidth,
            surfaceHeight: SettingsSearchLayer.CONTROL_SIZE,
            darkMode: this.appDarkMode,
            fallbackColor: this.cardColor(),
            glowColor: `#40${this.accentColor().substring(1)}`
          }) {
            Row() {
              this.fieldContent()
            }
            .width('100%')
            .height('100%')
            .alignItems(VerticalAlign.Center)
          }
        }
      }
      .layoutWeight(1)
      .height(SettingsSearchLayer.CONTROL_SIZE)
      .onAreaChange((_oldValue: Area, newValue: Area) => {
        const width = Math.floor(Number(newValue.width));
        if (Number.isFinite(width) && width > 0 && width !== this.fieldWidth) this.fieldWidth = width;
      })
    }
    .width('100%')
    .padding({ right: AppSpacing.XL, top: AppSpacing.SM, bottom: AppSpacing.MD })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  fieldContent() {
    SymbolGlyph($r('sys.symbol.magnifyingglass'))
      .fontSize(18)
      .fontColor([this.subTextColor()])
      .margin({ left: AppSpacing.LG })
    TextInput({ placeholder: '搜索设置', text: this.keyword })
      .id(SettingsSearchLayer.INPUT_ID)
      .layoutWeight(1)
      .height(SettingsSearchLayer.CONTROL_SIZE)
      .enterKeyType(EnterKeyType.Search)
      .backgroundColor(Color.Transparent)
      .fontColor(this.primaryTextColor())
      .placeholderColor(this.subTextColor())
      .padding({ left: AppSpacing.SM, right: AppSpacing.XS })
      .onChange((value: string) => this.onKeywordChange(value))
      .onSubmit(() => {
        this.rememberKeyword();
        this.getUIContext().getFocusController().clearFocus();
      })
    if (this.keyword.length > 0) {
      SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
        .fontSize(18)
        .fontColor([this.subTextColor()])
        .width(36)
        .height(36)
        .margin({ right: AppSpacing.XS })
        .accessibilityText('清除输入')
        .onClick(() => {
          this.onKeywordChange('');
          this.focusInputSoon();
        })
    }
  }

  @Builder
  idleContent() {
    if (this.recent.length > 0) {
      Row() {
        Text('最近搜索')
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
          .layoutWeight(1)
        Text('清除')
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
          .padding({ left: AppSpacing.MD, top: AppSpacing.XS, bottom: AppSpacing.XS })
          .accessibilityText('清除最近搜索')
          .onClick(() => this.clearRecent())
      }
      .width('100%')
      .padding({ left: AppSpacing.XS, right: AppSpacing.XS, top: AppSpacing.SM })
      this.chips(this.recent)
    }
    Text('试试搜')
      .fontSize(AppFontSize.CAPTION)
      .fontColor(this.subTextColor())
      .padding({ left: AppSpacing.XS, top: AppSpacing.SM })
    this.chips(SETTINGS_SEARCH_HINTS)
  }

  @Builder
  chips(items: string[]) {
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(items, (item: string) => {
        Text(item)
          .fontSize(AppFontSize.BODY)
          .fontColor(this.primaryTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: 220 })
          .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.SM, bottom: AppSpacing.SM })
          .borderRadius(16)
          .backgroundColor(this.cardColor())
          .margin({ right: AppSpacing.SM, bottom: AppSpacing.SM })
          .onClick(() => this.onKeywordChange(item))
      }, (item: string) => item)
    }
    .width('100%')
  }

  @Builder
  emptyContent() {
    Column({ space: AppSpacing.MD }) {
      Text(`没找到“${this.keyword.trim()}”`)
        .fontSize(AppFontSize.BODY_LARGE)
        .fontColor(this.primaryTextColor())
      Text('换个说法试试，比如“字体大小”也可以搜“字号”')
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
        .textAlign(TextAlign.Center)
      Text('去帮助里看看')
        .fontSize(AppFontSize.BODY)
        .fontColor(this.accentColor())
        .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.SM, bottom: AppSpacing.SM })
        .borderRadius(18)
        .backgroundColor(this.cardColor())
        .onClick(() => {
          router.pushUrl({ url: 'pages/Help' }).catch((error: Error) => {
            console.error('打开帮助失败:', error.message);
          });
        })
    }
    .width('100%')
    .padding({ top: 48 })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  groupLabel(text: string) {
    Text(text)
      .fontSize(AppFontSize.CAPTION)
      .fontColor(this.subTextColor())
      .padding({ left: AppSpacing.XS, top: AppSpacing.SM })
      .margin({ bottom: -AppSpacing.SM })
  }

  @Builder
  highlightedTitle(text: string) {
    Text() {
      Span(settingsHighlightParts(text, this.keyword)[0])
      Span(settingsHighlightParts(text, this.keyword)[1])
        .fontColor(this.accentColor())
        .fontWeight(FontWeight.Medium)
      Span(settingsHighlightParts(text, this.keyword)[2])
    }
    .fontSize(AppFontSize.BODY_LARGE)
    .fontColor(this.primaryTextColor())
  }

  @Builder
  settingRow(entry: SettingsSearchEntry, showDivider: boolean) {
    Row({ space: AppSpacing.MD }) {
      Column({ space: 2 }) {
        this.highlightedTitle(entry.title)
        Text(entry.section && entry.section !== entry.title ? `${entry.page.path} · ${entry.section}` : entry.page.path)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.accentColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (entry.description) {
          Text(entry.description)
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.subTextColor())
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (this.isBlocked(entry)) {
        Text('需开启在线阅读')
          .fontSize(AppFontSize.CAPTION)
          .fontColor(ThemeRuntime.warningColor(this.appDarkMode))
          .padding({ left: AppSpacing.SM, right: AppSpacing.SM, top: 2, bottom: 2 })
          .borderRadius(10)
          .border({ width: 1, color: ThemeRuntime.warningColor(this.appDarkMode) })
      }
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(18)
        .fontColor([this.subTextColor()])
    }
    .width('100%')
    .constraintSize({ minHeight: 60 })
    .padding({ left: AppSpacing.XL, right: AppSpacing.LG, top: AppSpacing.MD, bottom: AppSpacing.MD })
    .border({ width: { bottom: showDivider ? 0.5 : 0 }, color: ThemeRuntime.hairlineColor(this.appDarkMode) })
    .alignItems(VerticalAlign.Center)
    .accessibilityText(`${entry.title}，位于${entry.page.path}${this.isBlocked(entry) ? '，需开启在线阅读' : ''}`)
    .onClick(() => this.openEntry(entry))
  }

  @Builder
  faqRow(section: HelpSection, showDivider: boolean) {
    Row({ space: AppSpacing.MD }) {
      Column({ space: 2 }) {
        this.highlightedTitle(section.title)
        Text('帮助 · 常见问题')
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.accentColor())
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(18)
        .fontColor([this.subTextColor()])
    }
    .width('100%')
    .constraintSize({ minHeight: 56 })
    .padding({ left: AppSpacing.XL, right: AppSpacing.LG, top: AppSpacing.MD, bottom: AppSpacing.MD })
    .border({ width: { bottom: showDivider ? 0.5 : 0 }, color: ThemeRuntime.hairlineColor(this.appDarkMode) })
    .alignItems(VerticalAlign.Center)
    .onClick(() => this.openFaq(section))
  }

  primaryTextColor(): string {
    return ThemeRuntime.primaryTextColor(this.appDarkMode);
  }

  subTextColor(): string {
    return ThemeRuntime.subTextColor(this.appDarkMode);
  }

  accentColor(): string {
    return ThemeRuntime.accentColor(this.appDarkMode);
  }

  cardColor(): string {
    return ThemeRuntime.cardColor(this.appDarkMode);
  }
}
