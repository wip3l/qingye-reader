import { router } from '@kit.ArkUI';
import { BookSource, NativeSourceService } from '@legado/sourceengine';
import { AppDatabase } from '../model/data/AppDatabase';
import { syncSystemBars } from '../utils/SystemBars';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { ImmersiveBackButton } from '../components/ImmersiveBackButton';
import { HdsFeedback } from '../utils/HdsFeedback';
import { ExploreResultCache } from '../utils/ExploreResultCache';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';

const NATIVE_SOURCE_TEMPLATE: string = `{
  "sourceFormat": "native",
  "version": 1,
  "name": "",
  "url": "https://",
  "group": "",
  "type": "text",
  "search": {
    "url": "{{source.url}}/search?q={{urlencode(key)}}&page={{page}}",
    "list": "$.data.list[*]",
    "fields": {
      "name": "$.name",
      "author": "$.author",
      "coverUrl": "$.cover",
      "intro": "$.intro",
      "bookUrl": "{{source.url}}/book/{{$.id}}"
    }
  },
  "detail": {
    "fields": {
      "name": "$.data.name",
      "intro": "$.data.intro",
      "tocUrl": "{{source.url}}/book/{{$.data.id}}/chapters"
    }
  },
  "toc": {
    "list": "$.data[*]",
    "fields": {
      "title": "$.title",
      "url": "{{source.url}}/chapter/{{$.id}}"
    }
  },
  "content": {
    "text": "$.data.content"
  }
}`;

interface NativeSourceEditParams {
  bookSourceUrl?: string;
}

/** 原生书源的编辑页：直接编辑定义 JSON，保存前做完整校验。 */
@Entry
@Component
struct NativeSourceEditPage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @State bookSourceUrl: string = '';
  @State definitionText: string = '';
  @State problem: string = '';
  @State isSaving: boolean = false;
  private existing: BookSource | null = null;

  aboutToAppear(): void {
    syncSystemBars(getContext(this), this.appDarkMode, ThemeRuntime.pageColor(this.appDarkMode));
    const params = router.getParams() as NativeSourceEditParams;
    this.bookSourceUrl = params && params.bookSourceUrl ? params.bookSourceUrl : '';
    if (this.bookSourceUrl) {
      this.loadSource();
    } else {
      this.definitionText = NATIVE_SOURCE_TEMPLATE;
    }
  }

  async loadSource(): Promise<void> {
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      const source = await db.getBookSource(this.bookSourceUrl);
      if (!source || !NativeSourceService.isNative(source)) {
        HdsFeedback.showToast('未找到该原生书源');
        router.back();
        return;
      }
      this.existing = source;
      this.definitionText = JSON.stringify(NativeSourceService.exportObject(source), null, 2);
    } catch (e) {
      console.error('加载原生书源失败:', e);
      HdsFeedback.showToast('加载书源失败');
    }
  }

  /** 解析并校验当前文本；通过时返回书源记录，否则返回 null 并给出原因。 */
  buildSource(): BookSource | null {
    let parsed: Object;
    try {
      parsed = JSON.parse(this.definitionText) as Object;
    } catch (e) {
      this.problem = `JSON 格式错误：${(e as Error).message}`;
      return null;
    }
    try {
      const source = NativeSourceService.importObject(parsed, this.existing);
      this.problem = '';
      return source;
    } catch (e) {
      this.problem = (e as Error).message || '书源定义不合法';
      return null;
    }
  }

  checkDefinition(): void {
    if (this.buildSource()) HdsFeedback.showToast('校验通过');
  }

  async saveSource(): Promise<void> {
    if (this.isSaving) return;
    if (this.existing && this.existing.isLocked) {
      HdsFeedback.showToast('锁定的书源不能修改，请先在书源管理中解锁');
      return;
    }
    const source = this.buildSource();
    if (!source) return;
    this.isSaving = true;
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      if (this.existing) {
        await db.updateBookSource(source, this.existing.bookSourceUrl);
      } else {
        if (await db.getBookSource(source.bookSourceUrl)) {
          this.problem = '已存在相同地址的书源，请修改 url 或先删除原书源';
          return;
        }
        await db.insertBookSource(source);
      }
      await ExploreResultCache.invalidateSources(getContext(this),
        [this.existing ? this.existing.bookSourceUrl : source.bookSourceUrl, source.bookSourceUrl]);
      HdsFeedback.showToast('已保存');
      router.back();
    } catch (e) {
      console.error('保存原生书源失败:', e);
      this.problem = `保存失败：${(e as Error).message || '未知错误'}`;
    } finally {
      this.isSaving = false;
    }
  }

  build() {
    Column() {
      Row() {
        ImmersiveBackButton({ iconColor: ThemeRuntime.primaryTextColor(this.appDarkMode), darkMode: this.appDarkMode,
          buttonSize: 40, containerWidth: 56, materialScale: 0.83, compactLayout: true,
          onBack: () => router.back() })

        Text(this.bookSourceUrl ? '编辑原生书源' : '新建原生书源')
          .fontSize(AppFontSize.TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
          .layoutWeight(1)

        Text('校验')
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(ThemeRuntime.accentColor(this.appDarkMode))
          .width(60)
          .height(56)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.checkDefinition();
          })

        Text('保存')
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(ThemeRuntime.accentColor(this.appDarkMode))
          .width(60)
          .height(56)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.saveSource();
          })
      }
      .width('100%')
      .height(56 + this.statusBarHeight)
      .padding({ top: this.statusBarHeight })
      .backgroundColor(ThemeRuntime.topBarColor(this.appDarkMode))
      .alignItems(VerticalAlign.Center)

      if (this.problem) {
        Text(this.problem)
          .fontSize(AppFontSize.BODY)
          .fontColor(ThemeRuntime.dangerColor(this.appDarkMode))
          .width('100%')
          .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.MD, bottom: AppSpacing.MD })
      }

      Text('原生书源不执行脚本：字段用选择器规则，以 = 开头写表达式，地址里用 {{ }} 插值。写法见书源开发文档的第一部分「原生书源」。')
        .fontSize(AppFontSize.CAPTION)
        .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
        .width('100%')
        .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.MD, bottom: AppSpacing.MD })

      TextArea({ text: this.definitionText, placeholder: '在此粘贴或编写原生书源定义（JSON）' })
        .layoutWeight(1)
        .width('100%')
        .fontSize(AppFontSize.BODY)
        .fontFamily('monospace')
        .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
        .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
        .borderRadius(ThemeRuntime.smallRadius())
        .margin({ left: AppSpacing.XL, right: AppSpacing.XL, bottom: this.navBarHeight + AppSpacing.XL })
        .onChange((value: string) => {
          this.definitionText = value;
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeRuntime.pageColor(this.appDarkMode))
  }
}
