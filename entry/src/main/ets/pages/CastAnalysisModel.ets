import { router } from '@kit.ArkUI';
import { PageScaffold } from '../components/common/PageScaffold';
import { PopupMenuAction } from '../components/common/PopupMenuAction';
import { CastAnalysisEndpoint, CastVoicePolicy } from '../core/mimo/CastVoicePolicy';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { CastVoiceStore } from '../utils/mimo/CastVoiceStore';
import { MimoStore } from '../utils/mimo/MimoStore';
import { HdsFeedback } from '../utils/HdsFeedback';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';
import { ThemedDialog } from '../utils/ThemedDialog';
import { syncSystemBars } from '../utils/SystemBars';

const ROW_HEIGHT: number = 64;
/** 长按菜单开在 MiMo 那一行时的标记；接口 id 里不会有“#”。 */
const MIMO_MENU: string = '#mimo';

/**
 * 多角色朗读用哪个文本模型识别“这句话是谁说的”：已配置的 MiMo，或保存下来的某个兼容 OpenAI chat/completions 的接口。
 * 接口可以存多个，同一时间只用一个；左滑或长按启用，添加和修改在 CastAnalysisEndpointEdit 页。
 */
@Entry
@Component
struct CastAnalysisModelPage {
  @StorageProp('appDarkMode') dark: boolean = false;
  @StorageProp('themeRevision') themeRevision: number = 0;
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  @StorageProp('castVoiceRevision') @Watch('refresh') revision: number = 0;
  @StorageProp('mimoConfigured') mimoConfigured: boolean = false;
  @StorageProp('mimoAnalysisAvailable') mimoAnalysis: boolean = false;
  @State endpoints: CastAnalysisEndpoint[] = [];
  /** 正在用的接口 id；空串是 MiMo。 */
  @State activeId: string = '';
  /** 长按菜单开在哪一行；空串表示没有菜单。 */
  @State menuId: string = '';

  aboutToAppear(): void {
    MimoStore.load();
    this.refresh();
  }
  onPageShow(): void {
    syncSystemBars(getContext(this), this.dark, ThemeRuntime.pageColor(this.dark));
    this.refresh();
  }

  refresh(): void {
    const analysis = CastVoiceStore.analysisModel();
    this.endpoints = analysis.endpoints.slice();
    this.activeId = analysis.activeId;
  }

  private mimoStatus(): string {
    if (!this.mimoConfigured) return '未配置';
    return this.mimoAnalysis ? '已配置 · 和 MiMo 朗读共用密钥' : '密钥不能识别人物';
  }

  private useMimo(): void {
    if (!this.activeId) return;
    // MiMo 还不能识别人物时不切过去，免得把正在用的接口换成一个用不了的。
    if (!this.mimoConfigured || !this.mimoAnalysis) {
      HdsFeedback.showToast(this.mimoConfigured ? 'MiMo 的密钥不能识别人物，请重新测试' : '请先配置 MiMo API Key');
      router.pushUrl({ url: 'pages/MimoSettings' });
      return;
    }
    try {
      CastVoiceStore.useMimoAnalysis();
      HdsFeedback.showToast('已改用 MiMo 识别人物');
    } catch (error) { HdsFeedback.showToast((error as Error).message); }
  }

  private use(endpoint: CastAnalysisEndpoint): void {
    if (this.activeId === endpoint.id) return;
    if (!endpoint.verified) {
      HdsFeedback.showToast('这个接口要重新填写密钥并测试');
      this.edit(endpoint.id);
      return;
    }
    try {
      CastVoiceStore.useEndpoint(endpoint.id);
      HdsFeedback.showToast(`已改用“${CastVoicePolicy.endpointTitle(endpoint)}”识别人物`);
    } catch (error) { HdsFeedback.showToast((error as Error).message); }
  }

  private edit(id: string): void {
    router.pushUrl({ url: 'pages/CastAnalysisEndpointEdit', params: { id: id } });
  }

  private add(): void {
    if (this.endpoints.length >= CastVoicePolicy.ENDPOINT_LIMIT) {
      HdsFeedback.showToast(`最多保存 ${CastVoicePolicy.ENDPOINT_LIMIT} 个接口`);
      return;
    }
    this.edit('');
  }

  private async remove(endpoint: CastAnalysisEndpoint): Promise<void> {
    const active = this.activeId === endpoint.id;
    try {
      const result = await ThemedDialog.showDialog(this.getUIContext(), {
        title: `删除“${CastVoicePolicy.endpointTitle(endpoint)}”？`,
        message: '接口地址、模型和已保存的密钥都会删除，不能恢复。' + (active ? '之后改用 MiMo 识别人物。' : ''),
        buttons: [{ text: '取消', color: ThemeRuntime.subTextColor(this.dark) },
          { text: '删除', color: ThemeRuntime.dangerColor(this.dark) }]
      }, this.dark);
      if (result.index !== 1) return;
    } catch (_) { return; }
    try {
      await CastVoiceStore.deleteEndpoint(endpoint.id);
    } catch (error) { HdsFeedback.showToast((error as Error).message); }
  }

  private closeMenu(): CastAnalysisEndpoint | undefined {
    const id = this.menuId;
    this.menuId = '';
    return this.endpoints.find((item: CastAnalysisEndpoint): boolean => item.id === id);
  }

  build() {
    Stack() {
      PageScaffold({ title: '分析模型', content: () => { this.content() } })
    }.width('100%').height('100%')
  }

  @Builder
  inUseMark() {
    Row({ space: 2 }) {
      SymbolGlyph($r('sys.symbol.checkmark')).fontSize(14).fontColor([ThemeRuntime.accentColor(this.dark)])
      Text('使用中').fontSize(AppFontSize.CAPTION).fontColor(ThemeRuntime.accentColor(this.dark))
        .fontWeight(FontWeight.Medium)
    }
  }

  @Builder
  swipeButton(onTap: () => void) {
    Row() {
      Text('启用').fontSize(AppFontSize.BODY).fontWeight(FontWeight.Medium)
        .fontColor(ThemeRuntime.onAccentColor(ThemeRuntime.buttonColor(this.dark)))
        .textAlign(TextAlign.Center).width(64).height(40).borderRadius(20)
        .backgroundColor(ThemeRuntime.buttonColor(this.dark))
        .onClick(() => onTap())
    }.height('100%').padding({ left: AppSpacing.SM, right: AppSpacing.LG })
  }

  @Builder
  mimoMenu() {
    Column() {
      if (this.activeId) {
        PopupMenuAction($r('sys.symbol.checkmark_circle'), '启用', ThemeRuntime.primaryTextColor(this.dark), () => {
          this.menuId = '';
          this.useMimo();
        })
      }
      PopupMenuAction($r('sys.symbol.square_and_pencil'), '设置密钥', ThemeRuntime.primaryTextColor(this.dark), () => {
        this.menuId = '';
        router.pushUrl({ url: 'pages/MimoSettings' });
      })
    }.width(168).padding(ImmersiveMaterialRuntime.POPUP_MENU_PADDING)
  }

  @Builder
  endpointMenu() {
    Column() {
      if (this.menuId !== this.activeId) {
        PopupMenuAction($r('sys.symbol.checkmark_circle'), '启用', ThemeRuntime.primaryTextColor(this.dark), () => {
          const endpoint = this.closeMenu();
          if (endpoint) this.use(endpoint);
        })
      }
      PopupMenuAction($r('sys.symbol.square_and_pencil'), '编辑', ThemeRuntime.primaryTextColor(this.dark), () => {
        const endpoint = this.closeMenu();
        if (endpoint) this.edit(endpoint.id);
      })
      PopupMenuAction($r('sys.symbol.trash'), '删除', ThemeRuntime.dangerColor(this.dark), () => {
        const endpoint = this.closeMenu();
        if (endpoint) this.remove(endpoint);
      })
    }.width(168).padding(ImmersiveMaterialRuntime.POPUP_MENU_PADDING)
  }

  @Builder
  mimoRow() {
    Row({ space: AppSpacing.MD }) {
      Column({ space: 2 }) {
        Text('MiMo').fontSize(AppFontSize.BODY_LARGE).fontWeight(FontWeight.Medium)
          .fontColor(ThemeRuntime.primaryTextColor(this.dark)).width('100%')
        Text(this.mimoStatus()).fontSize(AppFontSize.CAPTION).width('100%')
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontColor(this.mimoConfigured && !this.mimoAnalysis ? ThemeRuntime.warningColor(this.dark) :
            ThemeRuntime.subTextColor(this.dark))
      }.layoutWeight(1)
      if (!this.activeId) {
        this.inUseMark()
      } else {
        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(16).fontColor([ThemeRuntime.subTextColor(this.dark)])
      }
    }
    .width('100%').height(ROW_HEIGHT).padding({ left: AppSpacing.XL, right: AppSpacing.XL })
    .backgroundColor(ThemeRuntime.cardColor(this.dark))
    .accessibilityGroup(true)
    .accessibilityText(`MiMo，${this.mimoStatus()}${this.activeId ? '' : '，使用中'}，点按设置密钥，长按出菜单`)
    .onClick(() => { router.pushUrl({ url: 'pages/MimoSettings' }); })
    .gesture(LongPressGesture({ repeat: false }).onAction(() => { this.menuId = MIMO_MENU; }))
    .bindPopup(this.menuId === MIMO_MENU, ImmersiveMaterialRuntime.popupMenuOptions(this.immersiveLightLevel,
      (): void => { this.mimoMenu() }, Placement.Bottom, this.dark, ThemeRuntime.accentColor(this.dark),
      () => { if (this.menuId === MIMO_MENU) this.menuId = ''; }))
  }

  @Builder
  endpointRow(endpoint: CastAnalysisEndpoint) {
    Row({ space: AppSpacing.MD }) {
      Column({ space: 2 }) {
        Text(CastVoicePolicy.endpointTitle(endpoint)).fontSize(AppFontSize.BODY_LARGE).fontWeight(FontWeight.Medium)
          .fontColor(ThemeRuntime.primaryTextColor(this.dark)).width('100%')
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(endpoint.verified ? `${endpoint.model} · ${CastVoicePolicy.endpointHost(endpoint.url)}` : '需要重新填写密钥并测试')
          .fontSize(AppFontSize.CAPTION).width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontColor(endpoint.verified ? ThemeRuntime.subTextColor(this.dark) : ThemeRuntime.warningColor(this.dark))
      }.layoutWeight(1)
      if (this.activeId === endpoint.id) {
        this.inUseMark()
      }
    }
    .width('100%').height(ROW_HEIGHT).padding({ left: AppSpacing.XL, right: AppSpacing.XL })
    .backgroundColor(ThemeRuntime.cardColor(this.dark))
    .border({ width: { top: this.endpoints.length > 0 && this.endpoints[0].id === endpoint.id ? 0 : 0.5 },
      color: ThemeRuntime.dividerColor(this.dark) })
    .accessibilityGroup(true)
    .accessibilityText(`${CastVoicePolicy.endpointTitle(endpoint)}，` +
      (endpoint.verified ? endpoint.model : '需要重新填写密钥并测试') +
      (this.activeId === endpoint.id ? '，使用中，点按编辑，长按出菜单' : '，点按编辑，左滑启用，长按出菜单'))
    .onClick(() => { this.edit(endpoint.id); })
    .gesture(LongPressGesture({ repeat: false }).onAction(() => { this.menuId = endpoint.id; }))
    .bindPopup(this.menuId === endpoint.id, ImmersiveMaterialRuntime.popupMenuOptions(this.immersiveLightLevel,
      (): void => { this.endpointMenu() }, Placement.Bottom, this.dark, ThemeRuntime.accentColor(this.dark),
      () => { if (this.menuId === endpoint.id) this.menuId = ''; }))
  }

  @Builder
  content() {
    Column({ space: AppSpacing.LG }) {
      Text('多角色朗读靠一个文本模型识别每句话是谁说的。朗读时会把正文片段发给它，用量计入对应的账号。')
        .fontSize(AppFontSize.CAPTION).fontColor(ThemeRuntime.subTextColor(this.dark)).width('100%')
        .padding({ top: AppSpacing.SM })

      // 行放在不自己滚动的 List 里，只为了能左滑；高度按行数定死。
      List() {
        ListItem() { this.mimoRow() }
          .swipeAction(this.activeId ? {
            end: { builder: (): void => { this.swipeButton((): void => this.useMimo()) } },
            edgeEffect: SwipeEdgeEffect.Spring
          } : {})
      }
      .width('100%').height(ROW_HEIGHT).scrollBar(BarState.Off).edgeEffect(EdgeEffect.None)
      .borderRadius(ThemeRuntime.cardRadius()).clip(true).backgroundColor(ThemeRuntime.cardColor(this.dark))

      Text('其他接口').fontSize(AppFontSize.CAPTION).fontColor(ThemeRuntime.subTextColor(this.dark)).width('100%')
        .padding({ left: AppSpacing.XS, top: AppSpacing.XS })

      Column() {
        if (this.endpoints.length > 0) {
          List() {
            // 键里带上是否在用：启用后条目重建，左滑出来的按钮随之收回。
            ForEach(this.endpoints, (endpoint: CastAnalysisEndpoint) => {
              ListItem() { this.endpointRow(endpoint) }
                .swipeAction(this.activeId === endpoint.id ? {} : {
                  end: { builder: (): void => { this.swipeButton((): void => this.use(endpoint)) } },
                  edgeEffect: SwipeEdgeEffect.Spring
                })
            }, (endpoint: CastAnalysisEndpoint): string => `${endpoint.id}|${endpoint.name}|${endpoint.model}|` +
              `${endpoint.url}|${endpoint.verified}|${this.activeId === endpoint.id}`)
          }
          .width('100%').height(ROW_HEIGHT * this.endpoints.length).scrollBar(BarState.Off).edgeEffect(EdgeEffect.None)
        }
        Row({ space: AppSpacing.SM }) {
          SymbolGlyph($r('sys.symbol.plus')).fontSize(16).fontColor([ThemeRuntime.accentColor(this.dark)])
          Text('添加接口').fontSize(AppFontSize.BODY_LARGE).fontWeight(FontWeight.Medium)
            .fontColor(ThemeRuntime.accentColor(this.dark))
        }
        .width('100%').height(52).justifyContent(FlexAlign.Center)
        .border({ width: { top: this.endpoints.length > 0 ? 0.5 : 0 }, color: ThemeRuntime.dividerColor(this.dark) })
        .onClick(() => { this.add(); })
      }
      .width('100%').borderRadius(ThemeRuntime.cardRadius()).clip(true)
      .backgroundColor(ThemeRuntime.cardColor(this.dark))

      Text('左滑启用；长按可启用、编辑或删除。接口要兼容 OpenAI 的 chat/completions。密钥只保存在这台设备上，不进备份。')
        .fontSize(AppFontSize.CAPTION).fontColor(ThemeRuntime.subTextColor(this.dark)).width('100%')
        .padding({ left: AppSpacing.XS, right: AppSpacing.XS })
    }.width('100%').constraintSize({ maxWidth: 760 })
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG })
  }
}
