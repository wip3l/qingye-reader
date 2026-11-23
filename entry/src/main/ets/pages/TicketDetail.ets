import { router } from '@kit.ArkUI';
import { ReaderComicSuperResolution, ReaderComicSuperResolutionAccess } from '@legado/aiengine';
import { AiAccessPolicy } from '../account/AiAccessPolicy';
import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { PageScaffold } from '../components/common/PageScaffold';
import { ImmersiveHeaderAction } from '../components/ImmersiveHeaderAction';
import { MaterialUnderlineTabs } from '../components/common/MaterialUnderlineTabs';
import { ReadingTicketBackFace, ReadingTicketCard } from '../components/ticket/ReadingTicketCard';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { syncSystemBars } from '../utils/SystemBars';
import { HdsFeedback } from '../utils/HdsFeedback';
import { ImageFileExport } from '../utils/ImageFileExport';
import { TicketAlbumStore } from '../utils/TicketAlbumStore';
import { appDb } from '../model/data/AppDatabase';
import { BookMarkStatus } from '../model/book/BookMark';
import { BookMarkService } from '../core/mark/BookMarkService';
import { ReadingTicket, ReadingTicketRules } from '../core/ticket/ReadingTicket';
import { ReadingTicketBack, ReadingTicketLoader } from '../core/ticket/ReadingTicketLoader';

/** 导出图就是票和它四周留给阴影的透明边，不带底板。 */
const EXPORT_ID: string = 'reading_ticket_export';

/**
 * 单张票根：大图、翻到背面（短评、摘录、阅读日历）、临时换样式、保存图片和分享。
 * 这里换样式只影响本页和导出，不改票夹的样式。参数 workKey；fromDetail=true 时不显示“书籍详情”。
 */
@Entry
@Component
struct TicketDetailPage {
  @StorageProp('appDarkMode') darkMode: boolean = false;
  @StorageProp('themeRevision') themeRevision: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @StorageProp('ticketCoverSuperResolution') coverSrEnabled: boolean = true;
  @StorageProp('ticketOriginalCover') originalCover: boolean = false;
  @State ticket: ReadingTicket | null = null;
  @State back: ReadingTicketBack = new ReadingTicketBack();
  @State loaded: boolean = false;
  @State ticketStyle: string = TicketAlbumStore.STYLE_PAPER;
  @State showBack: boolean = false;
  @State flipAngle: number = 0;
  @State frontHeight: number = 0;
  @State busy: boolean = false;
  @State pageWidth: number = 0;
  private workKey: string = '';
  private fromDetail: boolean = false;
  private flipping: boolean = false;

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, string> | undefined;
    this.workKey = params && typeof params['workKey'] === 'string' ? params['workKey'] : '';
    this.fromDetail = !!params && params['fromDetail'] === 'true';
    this.load();
  }

  onPageShow(): void {
    syncSystemBars(this.context(), this.darkMode, ThemeRuntime.pageColor(this.darkMode));
  }

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private async load(): Promise<void> {
    try {
      const context = this.context();
      await TicketAlbumStore.load(context);
      this.ticketStyle = TicketAlbumStore.currentStyle();
      const tickets = await ReadingTicketLoader.loadAll(context);
      const ticket = tickets.find((item: ReadingTicket): boolean => item.workKey === this.workKey) || null;
      if (ticket && !ticket.accent) ticket.accent = await ReadingTicketLoader.accentOf(context, ticket.coverUrl);
      this.ticket = ticket;
      if (ticket) this.back = await ReadingTicketLoader.loadBack(context, ticket);
    } catch (error) {
      console.warn('读取票根失败:', error);
    } finally {
      this.loaded = true;
    }
  }

  private cardWidth(): number {
    const width = this.pageWidth > 0 ? this.pageWidth : 360;
    return Math.min(320, width - AppSpacing.LG * 2 - 40);
  }

  /** 先转到侧面，换面后从另一侧转回来；两段各自动画，避免中途判断正反面。 */
  private flip(): void {
    if (this.flipping || !this.ticket) return;
    this.flipping = true;
    this.getUIContext().animateTo({
      duration: 180, curve: Curve.EaseIn, onFinish: () => {
        this.showBack = !this.showBack;
        this.flipAngle = -90;
        this.getUIContext().animateTo({
          duration: 240, curve: Curve.EaseOut, onFinish: () => {
            this.flipping = false;
          }
        }, () => {
          this.flipAngle = 0;
        });
      }
    }, () => {
      this.flipAngle = 90;
    });
  }

  private async exportImage(share: boolean): Promise<void> {
    if (this.busy || !this.ticket) return;
    this.busy = true;
    let pixelMap: image.PixelMap | null = null;
    try {
      pixelMap = await this.getUIContext().getComponentSnapshot().get(EXPORT_ID,
        { scale: 1, waitUntilRenderFinished: true });
      const path = `${this.context().cacheDir}/reading_ticket_${Date.now()}.png`;
      const file = fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      const packer = image.createImagePacker();
      try {
        await packer.packToFile(pixelMap, file.fd, { format: 'image/png', quality: 100 });
      } finally {
        fileIo.closeSync(file);
        await packer.release();
      }
      if (share) {
        await ImageFileExport.share(this.context(), [path]);
      } else if (await ImageFileExport.save(this.context(), [path])) {
        HdsFeedback.showToast('已保存到图库');
      }
    } catch (error) {
      console.error('导出票根图片失败:', error);
      HdsFeedback.showToast(share ? '分享失败，请重试' : '保存失败，请重试');
    } finally {
      if (pixelMap) pixelMap.release();
      this.busy = false;
    }
  }

  private async openBook(): Promise<void> {
    try {
      const mark = await appDb.getBookMark(this.workKey);
      if (mark) await BookMarkService.openDetail(mark);
    } catch (error) {
      console.warn('从票根打开详情失败:', error);
    }
  }

  private titleText(): string {
    if (!this.ticket) return '票根';
    return ReadingTicketRules.numberText(this.ticket) || `${BookMarkStatus.label(this.ticket.status)}的票`;
  }

  build() {
    Stack() {
      PageScaffold({
        title: this.titleText(),
        collapsible: false,
        actions: () => {
          this.pageActions()
        },
        content: () => {
          this.pageContent()
        }
      })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  pageActions() {
    if (this.ticket) {
      Row({ space: AppSpacing.MD }) {
        // 封面超分：系统不支持（API 26 以下等）时不显示；会员不可用时点了提示。
        if (ReaderComicSuperResolution.supported()) {
          ImmersiveHeaderAction({
            label: '超分',
            tint: this.coverSrEnabled ? ThemeRuntime.accentColor(this.darkMode) : ThemeRuntime.subTextColor(this.darkMode),
            accessibilityLabel: this.coverSrEnabled ? '封面超分，已开启' : '封面超分，已关闭',
            onTap: (): void => {
              this.toggleCoverSr();
            }
          })
        }
        ImmersiveHeaderAction({
          label: '原封面',
          tint: this.originalCover ? ThemeRuntime.accentColor(this.darkMode) : ThemeRuntime.subTextColor(this.darkMode),
          accessibilityLabel: this.originalCover ? '使用书籍原始封面，已开启' : '使用书籍原始封面，已关闭',
          onTap: (): void => {
            this.toggleOriginalCover();
          }
        })
        ImmersiveHeaderAction({
          icon: $r('sys.symbol.arrow_left_arrow_right'),
          accessibilityLabel: this.showBack ? '翻到正面' : '翻到背面',
          onTap: (): void => {
            this.flip();
          }
        })
      }
      .margin({ right: AppSpacing.XL })
    }
  }

  private toggleCoverSr(): void {
    const next = !this.coverSrEnabled;
    // 开关照存；会员不可用时先不超分，开通后自动生效。
    TicketAlbumStore.saveCoverSuperResolution(this.context(), next);
    if (next && ReaderComicSuperResolution.access() === ReaderComicSuperResolutionAccess.MEMBER_REQUIRED) {
      HdsFeedback.showToast(`封面超分是会员功能，${AiAccessPolicy.blockedMessage()}`);
      return;
    }
    HdsFeedback.showToast(next ? '封面超分已开启，所有票的封面会自动变清晰' : '封面超分已关闭');
  }

  private toggleOriginalCover(): void {
    const next = !this.originalCover;
    TicketAlbumStore.saveOriginalCover(this.context(), next);
    HdsFeedback.showToast(next ? '票上改用书籍原始封面' : '票上改用书架上的封面');
  }

  @Builder
  pageContent() {
    Column({ space: AppSpacing.LG }) {
      if (this.loaded && !this.ticket) {
        Column({ space: AppSpacing.MD }) {
          SymbolGlyph($r('sys.symbol.coupon'))
            .fontSize(40)
            .fontColor([ThemeRuntime.subTextColor(this.darkMode)])
          Text('这张票已经不在票夹里了')
            .fontSize(AppFontSize.BODY_LARGE)
            .fontColor(ThemeRuntime.primaryTextColor(this.darkMode))
          Text('标记被删掉，或者状态改成了“想读”。')
            .fontSize(AppFontSize.BODY)
            .fontColor(ThemeRuntime.subTextColor(this.darkMode))
        }
        .width('100%')
        .padding({ top: 80 })
      } else if (this.ticket) {
        // 票直接放在页面上；导出图就是这一块（透明底）。
        Column() {
          Stack() {
            if (this.showBack) {
              ReadingTicketBackFace({
                ticket: this.ticket as ReadingTicket,
                back: this.back,
                cardWidth: this.cardWidth(),
                cardHeight: this.frontHeight,
                ticketStyle: this.ticketStyle
              })
            } else {
              Column() {
                ReadingTicketCard({
                  ticket: this.ticket as ReadingTicket,
                  ticketStyle: this.ticketStyle,
                  cardWidth: this.cardWidth(),
                  notchColor: ThemeRuntime.pageColor(this.darkMode)
                })
              }
              .onSizeChange((_oldValue: SizeOptions, newValue: SizeOptions) => {
                this.frontHeight = Number(newValue.height) || 0;
              })
            }
          }
          .rotate({ y: 1, angle: this.flipAngle, perspective: 900 })
          .onClick(() => {
            this.flip();
          })
        }
        .id(EXPORT_ID)
        .width('100%')
        .padding({ top: 28, bottom: 28 })
        .alignItems(HorizontalAlign.Center)

        Text(this.showBack ? '点票面翻回正面' : '点票面翻到背面：短评、摘录和阅读日历')
          .fontSize(AppFontSize.CAPTION)
          .fontColor(ThemeRuntime.subTextColor(this.darkMode))

        MaterialUnderlineTabs({
          labels: TicketAlbumStore.STYLE_NAMES,
          selectedIndex: Math.max(0, TicketAlbumStore.STYLES.indexOf(this.ticketStyle)),
          onSelect: (index: number): void => {
            this.ticketStyle = TicketAlbumStore.STYLES[index];
            if (this.showBack) this.flip();
          }
        })

        Row({ space: AppSpacing.MD }) {
          this.actionButton($r('sys.symbol.save'), '保存图片', () => {
            this.exportImage(false);
          })
          this.actionButton($r('sys.symbol.share'), '分享', () => {
            this.exportImage(true);
          })
          if (!this.fromDetail) {
            this.actionButton($r('sys.symbol.doc_text'), '书籍详情', () => {
              this.openBook();
            })
          }
        }
        .width('100%')
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.SM, bottom: this.navBarHeight + AppSpacing.XXL })
    .onSizeChange((_oldValue: SizeOptions, newValue: SizeOptions) => {
      this.pageWidth = Number(newValue.width) || 0;
    })
  }

  @Builder
  actionButton(icon: Resource, label: string, action: () => void) {
    Column({ space: 4 }) {
      SymbolGlyph(icon)
        .fontSize(20)
        .fontColor([ThemeRuntime.primaryTextColor(this.darkMode)])
      Text(label)
        .fontSize(AppFontSize.CAPTION)
        .fontColor(ThemeRuntime.primaryTextColor(this.darkMode))
    }
    .layoutWeight(1)
    .padding({ top: AppSpacing.MD, bottom: AppSpacing.MD })
    .borderRadius(16)
    .backgroundColor(ThemeRuntime.cardColor(this.darkMode))
    .opacity(this.busy ? 0.5 : 1)
    .onClick(action)
  }
}
