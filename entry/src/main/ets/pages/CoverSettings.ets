import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import fs from '@ohos.file.fs';
import fileUri from '@ohos.file.fileuri';
import { Book } from '@legado/sourceengine';
import { syncSystemBars } from '../utils/SystemBars';
import { AppDatabase } from '../model/data/AppDatabase';
import { CoverAlbum, CoverGallerySettings } from '../utils/CoverGallerySettings';
import { CoverGalleryStore, CoverGallerySnapshot } from '../utils/CoverGalleryStore';
import { CoverDimSettings } from '../utils/CoverDimSettings';
import { ThemeBookCoverSettings } from '../utils/ThemeBookCoverSettings';
import { AppThemeSettingsStore } from '../utils/AppThemeSettingsStore';
import { ThemeTrialManager } from '../utils/ThemeTrialManager';
import { SearchExploreSettings, SearchExploreSettingsStore } from '../utils/SearchExploreSettingsStore';
import { SearchExplorePendingBook } from '../utils/SearchExplorePendingBook';
import { PrivateShelfStore } from '../utils/PrivateShelfStore';
import { RecentReadCardUpdater } from '../utils/RecentReadCardUpdater';
import { BookDisplayHelper } from '../utils/BookDisplayHelper';
import { HdsFeedback } from '../utils/HdsFeedback';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { AdaptiveSwitch } from '../components/AdaptiveSwitch';
import { BookCover } from '../components/book/BookCover';
import { PageScaffold } from '../components/common/PageScaffold';
import { SettingNavRow, SettingRow, SettingSwitchRow } from '../components/common/SettingRow';
import { SettingSegment } from '../components/common/SettingSegment';

/**
 * 封面设置：一本书显示哪张封面，按页面上“封面来源”从上到下的顺序取用——
 * 单独设置的封面 → 统一封面（主题封面或图集）→ 书籍自带封面 → 没有封面时的兜底。
 * 取图规则在 CoverGallerySettings.getDisplayCoverList 与 ThemeBookCoverSettings.enabledFor。
 */
@Entry
@Component
struct CoverSettingsPage {
  @StorageProp('applicationFontFamily') applicationFontFamily: string = '';
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  @StorageProp('webParseEnabled') webParseEnabled: boolean = false;
  @StorageLink('bookshelfCoverAlbums') @Watch('onCoverAlbumsChanged') bookshelfCoverAlbums: string = '';
  @StorageLink('bookshelfLightCoverAlbumId') bookshelfLightCoverAlbumId: string = '';
  @StorageLink('bookshelfDarkCoverAlbumId') bookshelfDarkCoverAlbumId: string = '';
  @StorageLink('bookshelfCoverApplyScope') bookshelfCoverApplyScope: string = 'all';
  @StorageLink('bookshelfCoverTargetBooks') bookshelfCoverTargetBooks: string = '';
  @StorageLink('bookshelfCoverReplaceAlbum') bookshelfCoverReplaceAlbum: boolean = false;
  @StorageLink('bookshelfCoverAlbumMix') bookshelfCoverAlbumMix: boolean = false;
  @StorageLink('bookshelfCoverFallback') bookshelfCoverFallback: string = 'text';
  @StorageLink('bookshelfCoverMode') bookshelfCoverMode: string = 'sequence';
  @StorageLink('bookshelfDarkCoverDim') bookshelfDarkCoverDim: boolean = false;
  @StorageLink('bookshelfDarkCoverDimLevel') bookshelfDarkCoverDimLevel: number = 20;
  @StorageLink('coverGalleryUpdateTime') @Watch('onCoverGalleryUpdateTimeChanged') coverGalleryUpdateTime: number = 0;
  /** 统一封面用主题封面。存在主题设置里，主题页的开关改的是同一项。 */
  @StorageLink('appThemeBookCoverEnabled') themeBookCoverEnabled: boolean = false;
  @StorageLink('searchExploreUseBookshelfCoverGallery') searchUseBookshelfCover: boolean = false;
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;

  @State albums: CoverAlbum[] = [];
  @State albumSelectOptions: SelectOption[] = [{ value: '不使用图集' }];
  /** 书架上的全部公开书籍：预览、指定书籍、单独设置过封面的书都从这里取。 */
  @State books: Book[] = [];
  @State booksLoading: boolean = true;
  @State targetBookUrls: string[] = [];
  @State customListExpanded: boolean = false;
  @State themeSaving: boolean = false;
  private skipNextCoverGalleryReload: boolean = false;

  aboutToAppear(): void {
    this.reloadCoverSettings();
    this.loadBooks();
    this.syncBars();
  }

  onPageShow(): void {
    this.reloadCoverSettings();
    this.loadBooks();
    this.syncBars();
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      PageScaffold({ title: '封面设置', content: () => {
        this.pageContent()
      } })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  pageContent() {
    if (this.previewBooks().length > 0) {
      this.previewCard()
    }

    this.sectionTitle('封面来源 · 从上到下依次取用')
    Column() {
      SettingNavRow({
        badge: '1',
        title: '单独设置的封面',
        description: '长按书籍设置，始终最优先，不受下面影响',
        value: this.booksLoading ? '' : `${this.customCoverBooks().length} 本`,
        showDivider: false,
        onTap: () => {
          if (this.customCoverBooks().length === 0) {
            HdsFeedback.showToast('还没有单独设置过封面的书');
            return;
          }
          this.customListExpanded = !this.customListExpanded;
        }
      })
      if (this.customListExpanded && this.customCoverBooks().length > 0) {
        this.customCoverPanel()
      }
      this.itemDivider()

      SettingRow({
        badge: '2',
        title: '统一封面',
        description: '替换书籍自带的封面，让书架风格一致',
        showDivider: false
      })
      SettingSegment({
        labels: ['不使用', '主题封面', '图集'],
        selected: this.replaceIndex(),
        onSelect: (index: number) => {
          this.setReplace(index);
        }
      })
      if (this.themeBookCoverEnabled) {
        this.hintText(this.themeCoverAvailable() ? '主题边框在主题页单独开关' :
          '当前主题没有封面套装，这一项暂时不起作用')
      } else if (this.bookshelfCoverReplaceAlbum) {
        Column() {
          if (!this.albumChosen()) {
            this.hintText('还没有选图集，在下面的“图集”里选一个')
          }
          SettingRow({ title: '应用到', description: '图集用在全部书籍还是指定的几本', showDivider: false })
          SettingSegment({
            labels: ['全部书籍', '指定书籍'],
            selected: this.bookshelfCoverApplyScope === 'books' ? 1 : 0,
            onSelect: (index: number) => {
              this.bookshelfCoverApplyScope = index === 1 ? 'books' : 'all';
              this.onCoverSettingChanged();
            }
          })
          if (this.bookshelfCoverApplyScope === 'books') {
            this.targetBooksPanel()
          }
          SettingSwitchRow({
            title: '和自带封面一起轮播',
            description: '关闭后只显示图集里的图',
            isOn: this.bookshelfCoverAlbumMix,
            showDivider: false,
            onChange: (value: boolean) => {
              this.bookshelfCoverAlbumMix = value;
              this.onCoverSettingChanged();
            }
          })
        }
        .width('calc(100% - 32vp)')
        .margin({ left: AppSpacing.XL, right: AppSpacing.XL, bottom: AppSpacing.LG })
        .borderRadius(ThemeRuntime.mediumRadius())
        .backgroundColor(this.inputColor())
        .clip(true)
      }
      this.itemDivider()

      SettingRow({
        badge: '3',
        title: '书籍自带封面',
        description: '书源或文件里的封面',
        showDivider: false
      })
      this.itemDivider()

      SettingRow({
        badge: '4',
        title: '没有封面时',
        description: '只给没有封面的书兜底，不动其他书',
        showDivider: false
      })
      SettingSegment({
        labels: ['书名占位', '主题封面', '图集'],
        selected: this.fallbackIndex(),
        onSelect: (index: number) => {
          this.bookshelfCoverFallback = index === 1 ? 'theme' : index === 2 ? 'album' : 'text';
          this.onCoverSettingChanged();
        }
      })
      if (this.bookshelfCoverFallback === 'theme' && !this.themeCoverAvailable()) {
        this.hintText('当前主题没有封面套装，没有封面的书仍显示书名')
      } else if (this.bookshelfCoverFallback === 'album' && !this.albumChosen()) {
        this.hintText('还没有选图集，在下面的“图集”里选一个')
      }
    }
    .cardStyle(this.cardColor())

    this.sectionTitle('图集')
    Column() {
      SettingNavRow({
        title: '图集管理',
        description: '新建、导入图片、重命名、预览',
        showDivider: false,
        onTap: () => {
          router.pushUrl({ url: 'pages/CoverGalleryManager' });
        }
      })
      this.itemDivider()
      SettingRow({ title: '浅色模式图集', description: '浅色模式下使用的封面图集', showDivider: false }) {
        this.albumSelect(false)
      }
      this.itemDivider()
      SettingRow({ title: '深色模式图集', description: '深色模式下使用的封面图集', showDivider: false }) {
        this.albumSelect(true)
      }
    }
    .cardStyle(this.cardColor())

    this.sectionTitle('显示')
    Column() {
      SettingRow({
        title: '有多张封面时',
        description: '主题封面和图集都适用',
        showDivider: false
      })
      SettingSegment({
        labels: ['轮流显示', '每小时换', '每本固定'],
        selected: this.bookshelfCoverMode === 'fixed' ? 2 : this.bookshelfCoverMode === 'random' ? 1 : 0,
        onSelect: (index: number) => {
          this.bookshelfCoverMode = index === 2 ? 'fixed' : index === 1 ? 'random' : 'sequence';
          this.onCoverSettingChanged();
        }
      })
      this.itemDivider()
      SettingSwitchRow({
        title: '深色模式调暗封面',
        description: '深色模式下降低封面亮度；主题封面不调暗',
        isOn: this.bookshelfDarkCoverDim,
        showDivider: false,
        onChange: (value: boolean) => {
          this.bookshelfDarkCoverDim = value;
          this.onCoverSettingChanged();
        }
      })
      if (this.bookshelfDarkCoverDim) {
        this.itemDivider()
        SettingRow({ title: '调暗程度', description: '封面亮的书多可以选强一些', showDivider: false }) {
          this.dimLevelSelect()
        }
      }
      this.itemDivider()
      SettingNavRow({
        title: '封面标识',
        description: '配置四个角的类型、来源、更新、置顶和未读数',
        showDivider: false,
        onTap: () => {
          router.pushUrl({ url: 'pages/BookshelfCoverBadgeSettings' });
        }
      })
    }
    .cardStyle(this.cardColor())

    if (this.webParseEnabled) {
      this.sectionTitle('应用范围')
      Column() {
        SettingSwitchRow({
          title: '搜索与发现也用这套封面',
          description: '关闭后搜索、发现和书籍详情只显示书源封面',
          isOn: this.searchUseBookshelfCover,
          showDivider: false,
          onChange: (value: boolean) => {
            this.setSearchUseBookshelfCover(value);
          }
        })
      }
      .cardStyle(this.cardColor())
    }
  }

  /** 顶部预览：从书架上挑几本不同情况的书，按当前设置显示，并标出每本的封面来自哪一档。 */
  @Builder
  previewCard() {
    Column() {
      Text('按当前设置，书架上是这样')
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
        .width('100%')
        .margin({ bottom: AppSpacing.MD })
      Row({ space: AppSpacing.MD }) {
        ForEach(this.previewBooks(), (book: Book) => {
          Column() {
            Column() {
              BookCover({
                bookUrl: book.bookUrl,
                origin: book.origin,
                coverUrl: book.coverUrl,
                customCoverUrl: book.customCoverUrl,
                name: book.name,
                author: book.author,
                useBookshelfCover: true,
                placeholderColor: ThemeRuntime.buttonColor(this.appDarkMode),
                decodeWidth: 240,
                decodeHeight: 320
              })
            }
            .width('100%')
            .aspectRatio(0.75)
            Text(book.name || '未命名书籍')
              .fontSize(AppFontSize.CAPTION)
              .fontColor(this.primaryTextColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: AppSpacing.XS })
            Text(this.sourceLabel(book))
              .fontSize(10)
              .fontColor(ThemeRuntime.accentColor(this.appDarkMode))
              .padding({ left: 6, right: 6, top: 1, bottom: 1 })
              .borderRadius(999)
              .backgroundColor(ThemeRuntime.accentSurfaceColor(this.appDarkMode))
              .margin({ top: 2 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center)
        }, (book: Book) => `${book.bookUrl}_${this.sourceLabel(book)}_${book.customCoverUrl}`)
        // 不足四本时占住剩下的格子，封面大小不随书的多少变。
        ForEach(this.previewPadding(), (index: number) => {
          Column()
            .layoutWeight(1)
        }, (index: number) => `pad_${index}`)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
    }
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.MD })
    .padding(AppSpacing.LG)
    .borderRadius(ThemeRuntime.cardRadius())
    .backgroundColor(this.cardColor())
  }

  @Builder
  customCoverPanel() {
    Column() {
      ForEach(this.customCoverBooks(), (book: Book) => {
        Row({ space: AppSpacing.MD }) {
          Column() {
            BookCover({
              bookUrl: book.bookUrl,
              origin: book.origin,
              coverUrl: book.coverUrl,
              customCoverUrl: book.customCoverUrl,
              name: book.name,
              author: book.author,
              useBookshelfCover: true,
              cornerRadius: 4,
              decodeWidth: 120,
              decodeHeight: 160
            })
          }
          .width(33)
          .height(44)
          Text(book.name || '未命名书籍')
            .fontSize(AppFontSize.BODY)
            .fontColor(this.primaryTextColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Text('恢复默认')
            .fontSize(AppFontSize.BODY)
            .fontColor(ThemeRuntime.accentColor(this.appDarkMode))
            .padding({ left: AppSpacing.MD, right: AppSpacing.MD, top: AppSpacing.SM, bottom: AppSpacing.SM })
            .onClick(() => {
              this.restoreDefaultCover(book);
            })
        }
        .width('100%')
        .height(56)
        .padding({ left: AppSpacing.LG, right: AppSpacing.XS })
      }, (book: Book) => `${book.bookUrl}_${book.customCoverUrl}`)
    }
    .width('calc(100% - 32vp)')
    .margin({ left: AppSpacing.XL, right: AppSpacing.XL, bottom: AppSpacing.LG })
    .borderRadius(ThemeRuntime.mediumRadius())
    .backgroundColor(this.inputColor())
  }

  @Builder
  targetBooksPanel() {
    Column() {
      if (this.booksLoading) {
        this.panelNote('正在加载书籍...')
      } else if (this.books.length === 0) {
        this.panelNote('暂无可选择书籍')
      } else {
        ForEach(this.books, (book: Book) => {
          Row() {
            Text(book.name || '未命名书籍')
              .fontSize(AppFontSize.BODY)
              .fontColor(this.primaryTextColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            AdaptiveSwitch({
              isOn: this.targetBookUrls.includes(book.bookUrl),
              onChange: (checked: boolean) => {
                this.toggleTargetBook(book.bookUrl, checked);
              }
            })
          }
          .width('100%')
          .height(48)
          .padding({ left: AppSpacing.XL, right: AppSpacing.XL })
        }, (book: Book) => `${book.bookUrl}_${this.targetBookUrls.includes(book.bookUrl) ? 'on' : 'off'}`)
      }
    }
    .width('100%')
  }

  @Builder
  panelNote(text: string) {
    Text(text)
      .fontSize(AppFontSize.BODY)
      .fontColor(this.subTextColor())
      .width('100%')
      .height(48)
      .padding({ left: AppSpacing.XL, right: AppSpacing.XL })
      .textAlign(TextAlign.Start)
  }

  @Builder
  hintText(text: string) {
    Text(text)
      .fontSize(AppFontSize.CAPTION)
      .fontColor(this.subTextColor())
      .width('100%')
      .padding({ left: AppSpacing.XL, right: AppSpacing.XL, bottom: AppSpacing.LG })
  }

  /** dark 是固定值；选中项和选项都在里面直接读页面状态，图集变化后会跟着刷新。 */
  @Builder
  albumSelect(dark: boolean) {
    Select(this.albumSelectOptions)
      .selected(this.albumSelectedIndex(dark))
      .value(this.optionValue(this.albumSelectOptions, this.albumSelectedIndex(dark)))
      .font({ size: AppFontSize.BODY, family: this.applicationFontFamily })
      .optionFont({ family: this.applicationFontFamily })
      .selectedOptionFont({ family: this.applicationFontFamily })
      .fontColor(this.subTextColor())
      .backgroundColor(Color.Transparent)
      .arrowPosition(ArrowPosition.END)
      .padding({ left: 0, right: 0 })
      .borderRadius(16)
      .border({ width: 0 })
      .optionBgColor(Color.Transparent)
      .divider(null)
      .optionFontColor(this.primaryTextColor())
      .selectedOptionFontColor(ThemeRuntime.accentColor(this.appDarkMode))
      .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.appDarkMode))
      .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode))
      .menuBackgroundBlurStyle(BlurStyle.NONE)
      .attributeModifier(ImmersiveMaterialRuntime.selectMenuModifier(this.immersiveLightLevel))
      .onSelect((index: number) => {
        const albumId = index <= 0 || index - 1 >= this.albums.length ? '' : this.albums[index - 1].id;
        if (dark) {
          this.bookshelfDarkCoverAlbumId = albumId;
        } else {
          this.bookshelfLightCoverAlbumId = albumId;
        }
        this.onCoverSettingChanged();
      })
  }

  @Builder
  dimLevelSelect() {
    Select(this.dimLevelOptions())
      .selected(this.dimLevelSelectedIndex())
      .value(this.optionValue(this.dimLevelOptions(), this.dimLevelSelectedIndex()))
      .font({ size: AppFontSize.BODY, family: this.applicationFontFamily })
      .optionFont({ family: this.applicationFontFamily })
      .selectedOptionFont({ family: this.applicationFontFamily })
      .fontColor(this.subTextColor())
      .backgroundColor(Color.Transparent)
      .arrowPosition(ArrowPosition.END)
      .padding({ left: 0, right: 0 })
      .borderRadius(16)
      .border({ width: 0 })
      .optionBgColor(Color.Transparent)
      .divider(null)
      .optionFontColor(this.primaryTextColor())
      .selectedOptionFontColor(ThemeRuntime.accentColor(this.appDarkMode))
      .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.appDarkMode))
      .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode))
      .menuBackgroundBlurStyle(BlurStyle.NONE)
      .attributeModifier(ImmersiveMaterialRuntime.selectMenuModifier(this.immersiveLightLevel))
      .onSelect((index: number) => {
        this.bookshelfDarkCoverDimLevel = CoverDimSettings.LEVELS[index] ?? CoverDimSettings.DEFAULT_LEVEL;
        this.onCoverSettingChanged();
      })
  }

  @Builder
  sectionTitle(title: string) {
    Text(title)
      .fontSize(AppFontSize.BODY)
      .fontColor(this.subTextColor())
      .width('100%')
      .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.XXL, bottom: AppSpacing.MD })
  }

  @Builder
  itemDivider() {
    Divider()
      .strokeWidth(0.5)
      .color(ThemeRuntime.hairlineColor(this.appDarkMode))
      .width('calc(100% - 32vp)')
      .margin({ left: AppSpacing.XL, right: AppSpacing.XL })
  }

  // ---- 封面来源 ----

  replaceIndex(): number {
    if (this.themeBookCoverEnabled) return 1;
    return this.bookshelfCoverReplaceAlbum ? 2 : 0;
  }

  fallbackIndex(): number {
    if (this.bookshelfCoverFallback === 'theme') return 1;
    return this.bookshelfCoverFallback === 'album' ? 2 : 0;
  }

  themeCoverAvailable(): boolean {
    return this.themeRevision >= 0 && ThemeBookCoverSettings.enabled(this.appDarkMode, true);
  }

  albumChosen(): boolean {
    return !!(this.bookshelfLightCoverAlbumId || this.bookshelfDarkCoverAlbumId);
  }

  /** 统一封面三选一。主题封面的开关存在主题设置里，先存它，存不上就不改图集那一项。 */
  async setReplace(index: number): Promise<void> {
    if (index === this.replaceIndex() || this.themeSaving) return;
    const wantTheme = index === 1;
    if (wantTheme !== this.themeBookCoverEnabled && !(await this.saveThemeCoverEnabled(wantTheme))) return;
    this.bookshelfCoverReplaceAlbum = index === 2;
    this.onCoverSettingChanged();
  }

  async saveThemeCoverEnabled(enabled: boolean): Promise<boolean> {
    // 试用主题期间主题设置是临时的，存了会把试用的主题留下来。
    if (ThemeTrialManager.isActive()) {
      HdsFeedback.showToast('试用主题期间不能更改主题封面');
      return false;
    }
    this.themeSaving = true;
    try {
      const context = getContext(this);
      const settings = await AppThemeSettingsStore.load(context);
      settings.themeBookCoverEnabled = enabled;
      AppThemeSettingsStore.applyToStorage(settings);
      await AppThemeSettingsStore.save(context, settings);
      this.themeBookCoverEnabled = enabled;
      return true;
    } catch (e) {
      console.error('保存主题封面设置失败:', e);
      HdsFeedback.showToast('保存主题封面设置失败');
      return false;
    } finally {
      this.themeSaving = false;
    }
  }

  setSearchUseBookshelfCover(value: boolean): void {
    this.searchUseBookshelfCover = value;
    const context = getContext(this);
    SearchExploreSettingsStore.load(context).then((settings: SearchExploreSettings) => {
      settings.useBookshelfCoverGallery = value;
      SearchExploreSettingsStore.applyToStorage(settings);
      return SearchExploreSettingsStore.save(context, settings);
    }).catch((e: Error) => {
      console.warn('保存搜索/发现封面设置失败:', e);
    });
  }

  // ---- 预览与书籍 ----

  async loadBooks(): Promise<void> {
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      this.books = PrivateShelfStore.publicBooks(
        SearchExplorePendingBook.filterShelfBooks(await db.getAllBooks())).slice();
    } catch (e) {
      console.warn('加载书籍列表失败:', e);
      this.books = [];
    } finally {
      this.booksLoading = false;
      if (this.customCoverBooks().length === 0) this.customListExpanded = false;
    }
  }

  customCoverBooks(): Book[] {
    // 列的是设置过单独封面的书，图取不到的也在内，方便在这里改掉。
    return this.books.filter((book: Book) => BookDisplayHelper.decodeCoverList(book.customCoverUrl).length > 0);
  }

  /** 预览最多四本：一本单独设置过封面的、两本有封面的、一本没封面的，不够再用其余的书补。 */
  previewBooks(): Book[] {
    const picked: Book[] = [];
    const take = (candidates: Book[], count: number): void => {
      for (const book of candidates) {
        if (count <= 0 || picked.length >= 4) return;
        if (picked.includes(book)) continue;
        picked.push(book);
        count--;
      }
    };
    const plain = this.books.filter((book: Book) => !BookDisplayHelper.hasCustomCover(book));
    take(this.customCoverBooks(), 1);
    take(plain.filter((book: Book) => !!book.coverUrl), 2);
    take(plain.filter((book: Book) => !book.coverUrl), 1);
    take(this.books, 4);
    return picked;
  }

  previewPadding(): number[] {
    const padding: number[] = [];
    for (let index = this.previewBooks().length; index < 4; index++) padding.push(index);
    return padding;
  }

  sourceLabel(book: Book): string {
    const snapshot = this.currentSnapshot();
    if (this.themeRevision >= 0 &&
      ThemeBookCoverSettings.enabledFor(book, this.appDarkMode, this.themeBookCoverEnabled, snapshot)) {
      return '主题封面';
    }
    const kind = CoverGallerySettings.sourceKind(book, this.appDarkMode, snapshot);
    if (kind === 'custom') return '单独设置';
    if (kind === 'album') return '图集';
    if (kind === 'mixed') return '自带 + 图集';
    return kind === 'own' ? '自带封面' : '书名占位';
  }

  async restoreDefaultCover(book: Book): Promise<void> {
    try {
      const db = AppDatabase.getInstance();
      const current = await db.getBook(book.bookUrl);
      if (!current) {
        HdsFeedback.showToast('书籍已不在书架中');
        await this.loadBooks();
        return;
      }
      const previousCover = current.customCoverUrl;
      current.customCoverUrl = '';
      await db.updateBook(current);
      this.removeLocalCoverFiles(previousCover);
      AppStorage.setOrCreate('shelfUpdateTime', Date.now());
      await this.loadBooks();
      RecentReadCardUpdater.reload(getContext(this) as common.UIAbilityContext);
      HdsFeedback.showToast('已恢复默认封面');
    } catch (e) {
      console.error('恢复默认封面失败:', e);
      HdsFeedback.showToast('恢复默认封面失败');
    }
  }

  /** 单独设置的封面若是复制进应用目录的图片（上传的、从图集选的），恢复默认后把副本删掉。 */
  removeLocalCoverFiles(customCoverUrl: string): void {
    const prefix = `${fileUri.getUriFromPath(`${getContext(this).filesDir}/book_covers`)}/`;
    for (const cover of BookDisplayHelper.decodeCoverList(customCoverUrl)) {
      if (!cover.startsWith(prefix)) continue;
      try {
        fs.unlinkSync(new fileUri.FileUri(cover).path);
      } catch (e) {
        console.warn('删除本地封面失败:', e);
      }
    }
  }

  // ---- 图集与保存 ----

  onCoverAlbumsChanged(): void {
    this.syncAlbums(this.bookshelfCoverAlbums);
  }

  onCoverGalleryUpdateTimeChanged(): void {
    if (this.skipNextCoverGalleryReload) {
      this.skipNextCoverGalleryReload = false;
      return;
    }
    this.reloadCoverSettings();
  }

  async reloadCoverSettings(): Promise<void> {
    try {
      this.applySnapshot(await CoverGalleryStore.load(getContext(this)));
    } catch (e) {
      console.warn('重新加载封面设置失败:', e);
      this.syncAlbums(this.bookshelfCoverAlbums);
    }
  }

  applySnapshot(snapshot: CoverGallerySnapshot): void {
    const localAlbumsRaw = this.bookshelfCoverAlbums;
    const albumsRaw = (snapshot.albumsRaw || '').trim().length > 0 || (localAlbumsRaw || '').trim().length === 0 ?
      snapshot.albumsRaw : localAlbumsRaw;
    this.bookshelfCoverAlbums = albumsRaw;
    this.bookshelfLightCoverAlbumId = snapshot.lightAlbumId;
    this.bookshelfDarkCoverAlbumId = snapshot.darkAlbumId;
    this.bookshelfCoverApplyScope = snapshot.applyScope === 'books' ? 'books' : 'all';
    this.bookshelfCoverTargetBooks = snapshot.targetBooksRaw;
    this.targetBookUrls = CoverGallerySettings.parseTargetBooks(snapshot.targetBooksRaw);
    this.bookshelfCoverReplaceAlbum = snapshot.replaceAlbum;
    this.bookshelfCoverAlbumMix = snapshot.albumMix;
    this.bookshelfCoverFallback = CoverGalleryStore.normalizeFallback(snapshot.fallback);
    this.bookshelfCoverMode = snapshot.coverMode;
    this.bookshelfDarkCoverDim = snapshot.darkDim;
    this.bookshelfDarkCoverDimLevel = snapshot.darkDimLevel;
    this.syncAlbums(albumsRaw);
  }

  toggleTargetBook(bookUrl: string, selected: boolean): void {
    if (!bookUrl) return;
    const targets = this.targetBookUrls.filter((url: string) => url !== bookUrl);
    if (selected) targets.push(bookUrl);
    this.targetBookUrls = targets;
    this.bookshelfCoverTargetBooks = CoverGallerySettings.encodeTargetBooks(targets);
    this.onCoverSettingChanged();
  }

  onCoverSettingChanged(): void {
    const snapshot = this.currentSnapshot();
    CoverGalleryStore.applyToStorage(snapshot);
    AppStorage.setOrCreate('shelfUpdateTime', Date.now());
    this.skipNextCoverGalleryReload = true;
    AppStorage.setOrCreate('coverGalleryUpdateTime', Date.now());
    CoverGalleryStore.save(getContext(this), snapshot).then(() => {
      RecentReadCardUpdater.reload(getContext(this) as common.UIAbilityContext);
    }).catch((e: Error) => {
      console.warn('保存封面设置失败:', e);
    });
  }

  currentSnapshot(): CoverGallerySnapshot {
    const snapshot = new CoverGallerySnapshot();
    snapshot.albumsRaw = this.bookshelfCoverAlbums;
    snapshot.lightAlbumId = this.bookshelfLightCoverAlbumId;
    snapshot.darkAlbumId = this.bookshelfDarkCoverAlbumId;
    snapshot.applyScope = this.bookshelfCoverApplyScope === 'books' ? 'books' : 'all';
    snapshot.targetBooksRaw = this.bookshelfCoverTargetBooks;
    snapshot.replaceAlbum = this.bookshelfCoverReplaceAlbum;
    snapshot.albumMix = this.bookshelfCoverAlbumMix;
    snapshot.fallback = CoverGalleryStore.normalizeFallback(this.bookshelfCoverFallback);
    snapshot.coverMode = this.bookshelfCoverMode;
    snapshot.darkDim = this.bookshelfDarkCoverDim;
    snapshot.darkDimLevel = CoverDimSettings.normalizeLevel(this.bookshelfDarkCoverDimLevel);
    return snapshot;
  }

  syncAlbums(raw: string): void {
    this.albums = CoverGallerySettings.parseAlbums(raw);
    const options: SelectOption[] = [{ value: '不使用图集' }];
    for (const album of this.albums) {
      options.push({ value: `${album.name}(${album.covers.length})` });
    }
    this.albumSelectOptions = options;
  }

  albumSelectedIndex(dark: boolean): number {
    const selectedId = dark ? this.bookshelfDarkCoverAlbumId : this.bookshelfLightCoverAlbumId;
    for (let i = 0; i < this.albums.length; i++) {
      if (this.albums[i].id === selectedId) return i + 1;
    }
    return 0;
  }

  dimLevelOptions(): SelectOption[] {
    return CoverDimSettings.LEVELS.map((level: number, index: number): SelectOption => {
      const option: SelectOption = { value: `${CoverDimSettings.LEVEL_NAMES[index]}（${level}%）` };
      return option;
    });
  }

  dimLevelSelectedIndex(): number {
    return Math.max(0, CoverDimSettings.LEVELS.indexOf(CoverDimSettings.normalizeLevel(this.bookshelfDarkCoverDimLevel)));
  }

  optionValue(options: SelectOption[], index: number): ResourceStr {
    return index >= 0 && index < options.length ? options[index].value : '';
  }

  // ---- 外观 ----

  pageColor(): string {
    return ThemeRuntime.pageColor(this.appDarkMode);
  }

  cardColor(): string {
    return ThemeRuntime.cardColor(this.appDarkMode);
  }

  inputColor(): string {
    return ThemeRuntime.inputColor(this.appDarkMode);
  }

  primaryTextColor(): string {
    return ThemeRuntime.primaryTextColor(this.appDarkMode);
  }

  subTextColor(): string {
    return ThemeRuntime.subTextColor(this.appDarkMode);
  }

  syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, this.pageColor());
  }
}

@Extend(Column)
function cardStyle(color: string) {
  .width('calc(100% - 24vp)')
  .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
  .borderRadius(ThemeRuntime.cardRadius())
  .clip(true)
  .backgroundColor(color)
}
