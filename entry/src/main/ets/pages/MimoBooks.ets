import { router } from '@kit.ArkUI';
import { PageScaffold } from '../components/common/PageScaffold';
import { SettingNavRow } from '../components/common/SettingRow';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { MimoCastSummary, MimoStore } from '../utils/mimo/MimoStore';
import { syncSystemBars } from '../utils/SystemBars';
import { appDb } from '../model/data/AppDatabase';

class MimoBookItem {
  book: string = '';
  name: string = '';
  description: string = '';
}

/** Books read with multi-role MiMo; each opens its character list. */
@Entry
@Component
struct MimoBooksPage {
  @StorageProp('appDarkMode') dark: boolean = false;
  @StorageProp('themeRevision') themeRevision: number = 0;
  @State items: MimoBookItem[] = [];
  @State loaded: boolean = false;
  private serial: number = 0;

  onPageShow(): void {
    syncSystemBars(getContext(this), this.dark, ThemeRuntime.pageColor(this.dark));
    // Reload on return: the roles page can delete a cast, and reading can add one.
    this.load();
  }
  private async load(): Promise<void> {
    const serial = ++this.serial;
    let summaries: MimoCastSummary[] = [];
    try { summaries = MimoStore.castSummaries(); } catch (_) {}
    const urls: string[] = [];
    const names: string[] = [];
    try {
      for (const book of await appDb.getAllBooks()) { urls.push(book.bookUrl); names.push(book.name); }
    } catch (_) {}
    if (serial !== this.serial) return;
    try { MimoStore.linkLegacyCasts(summaries, urls, names); } catch (_) {}
    this.items = summaries.filter((summary: MimoCastSummary): boolean => summary.book.length > 0)
      .map((summary: MimoCastSummary): MimoBookItem => {
        const item = new MimoBookItem();
        item.book = summary.book;
        const shelfIndex = urls.indexOf(summary.book);
        // Prefer the current shelf title; a removed book keeps the title saved with its cast.
        item.name = shelfIndex >= 0 ? names[shelfIndex] : (summary.bookName || '未知书籍');
        const date = new Date(summary.updatedAt);
        item.description = (summary.characters > 0 ? `${summary.characters} 个人物` : '仅旁白') +
          ` · ${date.getMonth() + 1}月${date.getDate()}日更新` + (shelfIndex >= 0 ? '' : ' · 已不在书架');
        return item;
      });
    this.loaded = true;
  }
  build() {
    Stack() {
      PageScaffold({ title: '人物档案', content: () => { this.content() } })
    }.width('100%').height('100%')
  }
  @Builder
  content() {
    Column({ space: AppSpacing.LG }) {
      if (this.loaded && this.items.length === 0) {
        Column({ space: AppSpacing.MD }) {
          SymbolGlyph($r('sys.symbol.person')).fontSize(40).fontColor([ThemeRuntime.subTextColor(this.dark)])
          Text('还没有人物档案').fontSize(AppFontSize.BODY_LARGE).fontColor(ThemeRuntime.primaryTextColor(this.dark))
          Text('开启“自动多角色”后朗读一本书，识别到的人物会出现在这里。单音色朗读不会建立人物档案。')
            .fontSize(AppFontSize.BODY).fontColor(ThemeRuntime.subTextColor(this.dark)).textAlign(TextAlign.Center)
        }.width('100%').padding({ top: 80, left: AppSpacing.XL, right: AppSpacing.XL })
      } else if (this.items.length > 0) {
        Text('每本书的人物音色单独保存，可在这里调整或纠正。')
          .fontSize(AppFontSize.CAPTION).fontColor(ThemeRuntime.subTextColor(this.dark)).width('100%')
          .padding({ top: AppSpacing.SM })
        Column() {
          ForEach(this.items, (item: MimoBookItem, index: number) => {
            SettingNavRow({ title: item.name, description: item.description,
              showDivider: index < this.items.length - 1,
              onTap: () => router.pushUrl({ url: 'pages/MimoBookRoles', params: { book: item.book } }) })
          }, (item: MimoBookItem): string => item.book + item.description)
        }.width('100%').backgroundColor(ThemeRuntime.cardColor(this.dark)).borderRadius(ThemeRuntime.cardRadius())
      }
    }.width('100%').constraintSize({ maxWidth: 760 })
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG })
  }
}
