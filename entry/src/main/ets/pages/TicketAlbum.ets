import { router } from '@kit.ArkUI';
import { PageScaffold } from '../components/common/PageScaffold';
import { PopupMenuHeader } from '../components/common/PopupMenuAction';
import { ImmersiveHeaderAction } from '../components/ImmersiveHeaderAction';
import { ReadingTicketCard } from '../components/ticket/ReadingTicketCard';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { syncSystemBars } from '../utils/SystemBars';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';
import { TicketAlbumStore } from '../utils/TicketAlbumStore';
import { BookMarkStatus } from '../model/book/BookMark';
import { ReadingTicket, ReadingTicketRules } from '../core/ticket/ReadingTicket';
import { ReadingTicketLoader } from '../core/ticket/ReadingTicketLoader';

/** 列表的一行：月份标题，或一行一到两张票。 */
class AlbumRow {
  key: string = '';
  title: string = '';
  count: number = 0;
  tickets: ReadingTicket[] = [];
}

/**
 * 票夹：读过、在读、弃读的书各一张票，按读完（或最后读）的月份分组。
 * 顶部切换票面样式（所有票一起换，记在本机），下面是合计、状态与年份筛选。点一张进单张票根页。
 */
@Entry
@Component
struct TicketAlbumPage {
  @StorageProp('appDarkMode') darkMode: boolean = false;
  @StorageProp('themeRevision') themeRevision: number = 0;
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @StorageProp('bookMarkRevision') @Watch('onRevisionChanged') bookMarkRevision: number = 0;
  @State tickets: ReadingTicket[] = [];
  @State loaded: boolean = false;
  @State ticketStyle: string = TicketAlbumStore.STYLE_CARD;
  @State singleColumn: boolean = false;
  @State issueAnimation: boolean = true;
  @State statusFilter: number = 0;
  @State yearFilter: number = 0;
  @State listWidth: number = 0;
  @State showMoreMenu: boolean = false;
  @State showYearMenu: boolean = false;
  private visible: boolean = false;
  private loadGeneration: number = 0;

  onPageShow(): void {
    this.visible = true;
    syncSystemBars(getContext(this), this.darkMode, ThemeRuntime.pageColor(this.darkMode));
    // 从详情页回来时可能改过标记或读过几章，每次显示都重算。
    this.load();
  }

  onPageHide(): void {
    this.visible = false;
  }

  onRevisionChanged(): void {
    if (this.visible) this.load();
  }

  async load(): Promise<void> {
    const generation = ++this.loadGeneration;
    try {
      const context = getContext(this);
      await TicketAlbumStore.load(context);
      if (!this.loaded) {
        this.ticketStyle = TicketAlbumStore.currentStyle();
        this.singleColumn = TicketAlbumStore.singleColumn();
      }
      this.issueAnimation = TicketAlbumStore.issueAnimation();
      const tickets = await ReadingTicketLoader.loadAll(context);
      if (generation !== this.loadGeneration) return;
      this.tickets = tickets;
      if (this.yearFilter && !ReadingTicketRules.years(tickets).includes(this.yearFilter)) this.yearFilter = 0;
    } catch (error) {
      console.warn('读取票夹失败:', error);
    } finally {
      if (generation === this.loadGeneration) this.loaded = true;
    }
  }

  private visibleTickets(): ReadingTicket[] {
    return ReadingTicketRules.filter(this.tickets, this.statusFilter, this.yearFilter);
  }

  private columns(): number {
    return this.singleColumn ? 1 : 2;
  }

  private cellWidth(): number {
    const width = this.listWidth > 0 ? this.listWidth : 340;
    if (this.singleColumn) return Math.min(300, width - AppSpacing.XL * 2);
    return Math.floor((width - AppSpacing.MD) / 2);
  }

  private rows(): AlbumRow[] {
    const rows: AlbumRow[] = [];
    const columns = this.columns();
    let month = '';
    let pending: ReadingTicket[] = [];
    let header: AlbumRow | null = null;
    const flush = (): void => {
      if (pending.length === 0) return;
      const row = new AlbumRow();
      row.tickets = pending;
      row.key = pending.map((ticket: ReadingTicket): string => this.ticketKey(ticket)).join('#') + `#${columns}`;
      rows.push(row);
      pending = [];
    };
    this.visibleTickets().forEach((ticket: ReadingTicket): void => {
      if (ticket.monthKey !== month || header === null) {
        flush();
        month = ticket.monthKey;
        header = new AlbumRow();
        header.key = `m:${month}`;
        header.title = month ? `${month.substring(0, 4)} 年 ${Number(month.substring(5, 7))} 月` : '更早';
        rows.push(header);
      }
      (header as AlbumRow).count++;
      pending.push(ticket);
      if (pending.length >= columns) flush();
    });
    flush();
    return rows;
  }

  private ticketKey(ticket: ReadingTicket): string {
    return `${ticket.workKey}|${ticket.status}|${ticket.number}|${ticket.rating}|${ticket.totalMs}|${ticket.coverUrl}|` +
      `${ticket.review.length}`;
  }

  private statusCount(status: number): number {
    return ReadingTicketRules.filter(this.tickets, status, this.yearFilter).length;
  }

  private openTicket(ticket: ReadingTicket): void {
    router.pushUrl({ url: 'pages/TicketDetail', params: { workKey: ticket.workKey } }).catch((error: Error) => {
      console.warn('打开票根失败:', error.message);
    });
  }

  private selectStyle(style: string): void {
    if (this.ticketStyle === style) return;
    this.ticketStyle = style;
    TicketAlbumStore.saveStyle(getContext(this), style);
  }

  build() {
    Stack() {
      PageScaffold({
        title: '票夹',
        scrollable: false,
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
    Row({ space: AppSpacing.MD }) {
      if (this.tickets.length > 0) {
        ImmersiveHeaderAction({
          icon: this.singleColumn ? $r('sys.symbol.square_grid_2x2') : $r('sys.symbol.rectangle_portrait'),
          accessibilityLabel: this.singleColumn ? '两列显示' : '单列显示',
          onTap: (): void => {
            this.singleColumn = !this.singleColumn;
            TicketAlbumStore.saveSingleColumn(getContext(this), this.singleColumn);
          }
        })
      }
      ImmersiveHeaderAction({
        icon: $r('sys.symbol.more'),
        accessibilityLabel: '票夹设置',
        onTap: (): void => {
          this.showMoreMenu = !this.showMoreMenu;
        }
      })
        .bindPopup(this.showMoreMenu, ImmersiveMaterialRuntime.popupMenuOptions(this.immersiveLightLevel,
          (): void => {
            this.moreMenu();
          }, Placement.BottomRight, this.darkMode, ThemeRuntime.accentColor(this.darkMode), (): void => {
            this.showMoreMenu = false;
          }))
    }
    .margin({ right: AppSpacing.XL })
  }

  @Builder
  moreMenu() {
    Column() {
      PopupMenuHeader('设置', ThemeRuntime.subTextColor(this.darkMode))
      Row({ space: 10 }) {
        Column({ space: 2 }) {
          Text('读完时出票动画')
            .fontSize(AppFontSize.BODY_LARGE)
            .fontColor(ThemeRuntime.primaryTextColor(this.darkMode))
          Text('在详情页标成“读过”时出一张票')
            .fontSize(AppFontSize.CAPTION)
            .fontColor(ThemeRuntime.subTextColor(this.darkMode))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.issueAnimation })
          .selectedColor(ThemeRuntime.accentColor(this.darkMode))
          .onChange((isOn: boolean) => {
            if (isOn === this.issueAnimation) return;
            this.issueAnimation = isOn;
            TicketAlbumStore.saveIssueAnimation(getContext(this), isOn);
          })
      }
      .width('100%')
      .padding({ left: 12, right: 8, top: 8, bottom: 8 })
    }
    .width(260)
    .padding(ImmersiveMaterialRuntime.POPUP_MENU_PADDING)
  }

  @Builder
  yearMenu() {
    Column() {
      PopupMenuHeader('年份', ThemeRuntime.subTextColor(this.darkMode))
      this.yearChoice(0, '全部年份')
      ForEach(ReadingTicketRules.years(this.tickets), (year: number) => {
        this.yearChoice(year, `${year} 年`)
      }, (year: number) => `${year}`)
    }
    .width(160)
    .padding(ImmersiveMaterialRuntime.POPUP_MENU_PADDING)
  }

  @Builder
  yearChoice(year: number, label: string) {
    Row({ space: 10 }) {
      Text(label)
        .fontSize(AppFontSize.BODY_LARGE)
        .fontColor(this.yearFilter === year ? ThemeRuntime.accentColor(this.darkMode) :
          ThemeRuntime.primaryTextColor(this.darkMode))
        .layoutWeight(1)
      if (this.yearFilter === year) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(16)
          .fontColor([ThemeRuntime.accentColor(this.darkMode)])
      }
    }
    .width('100%')
    .height(44)
    .padding({ left: 12, right: 12 })
    .onClick(() => {
      this.yearFilter = year;
      this.showYearMenu = false;
    })
  }

  @Builder
  pageContent() {
    Column({ space: AppSpacing.SM }) {
      if (this.loaded && this.tickets.length === 0) {
        this.emptyState('票夹还是空的', '在书籍详情页把书标成“读过”“在读”或“弃读”，就会在这里出一张票。')
      } else if (this.loaded) {
        this.styleTabs()
        List({ space: AppSpacing.MD }) {
          ListItem() {
            this.summaryCard()
          }
          ListItem() {
            this.filterRow()
          }
          if (this.visibleTickets().length === 0) {
            ListItem() {
              this.emptyState('没有符合条件的票', '换个状态或年份试试。')
            }
          } else {
            ForEach(this.rows(), (row: AlbumRow) => {
              ListItem() {
                if (row.tickets.length > 0) {
                  this.ticketRow(row)
                } else {
                  this.monthHeader(row)
                }
              }
            }, (row: AlbumRow) => row.tickets.length > 0 ? `${row.key}#${this.ticketStyle}` :
              `${row.key}:${row.count}`)
          }
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .contentEndOffset(this.navBarHeight + AppSpacing.XXXL)
        .onSizeChange((_oldValue: SizeOptions, newValue: SizeOptions) => {
          this.listWidth = Number(newValue.width) || 0;
        })
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.SM })
  }

  /** 票面样式：强调色文字加短下划线，与书源管理页的格式切换条一致。 */
  @Builder
  styleTabs() {
    Row() {
      ForEach(TicketAlbumStore.STYLES, (style: string) => {
        Column({ space: 4 }) {
          Text(TicketAlbumStore.styleName(style))
            .fontSize(AppFontSize.BODY_LARGE)
            .fontWeight(this.ticketStyle === style ? FontWeight.Bold : FontWeight.Regular)
            .fontColor(this.ticketStyle === style ? ThemeRuntime.accentColor(this.darkMode) :
              ThemeRuntime.subTextColor(this.darkMode))
          Column()
            .width(18)
            .height(3)
            .borderRadius(2)
            .backgroundColor(this.ticketStyle === style ? ThemeRuntime.accentColor(this.darkMode) : Color.Transparent)
        }
        .layoutWeight(1)
        .padding({ top: AppSpacing.SM, bottom: AppSpacing.XS })
        .accessibilityGroup(true)
        .accessibilityText(`${TicketAlbumStore.styleName(style)}样式`)
        .accessibilitySelected(this.ticketStyle === style)
        .onClick(() => {
          this.selectStyle(style);
        })
      }, (style: string) => style)
    }
    .width('100%')
    .borderRadius(14)
    .backgroundColor(ThemeRuntime.cardColor(this.darkMode))
  }

  @Builder
  summaryCard() {
    Row() {
      this.summaryCell(`${ReadingTicketRules.summary(this.tickets)[0]}`, '张票')
      this.summaryDivider()
      this.summaryCell(`${ReadingTicketRules.summary(this.tickets)[1]}`, '读过')
      this.summaryDivider()
      this.summaryCell(`${ReadingTicketRules.summary(this.tickets)[2]}`, '小时')
      this.summaryDivider()
      this.summaryCell(ReadingTicketRules.summary(this.tickets)[3] > 0 ?
        `★${ReadingTicketRules.summary(this.tickets)[3].toFixed(1)}` : '—', '均分')
    }
    .width('100%')
    .padding({ top: AppSpacing.MD, bottom: AppSpacing.MD })
    .borderRadius(16)
    .backgroundColor(ThemeRuntime.cardColor(this.darkMode))
  }

  @Builder
  summaryCell(value: string, label: string) {
    Column({ space: 2 }) {
      Text(value)
        .fontSize(19)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeRuntime.primaryTextColor(this.darkMode))
        .fontFeature('"tnum" 1')
      Text(label)
        .fontSize(AppFontSize.MICRO + 1)
        .fontColor(ThemeRuntime.subTextColor(this.darkMode))
    }
    .layoutWeight(1)
    .accessibilityGroup(true)
    .accessibilityText(`${label} ${value}`)
  }

  @Builder
  summaryDivider() {
    Column()
      .width(0.5)
      .height(28)
      .backgroundColor(ThemeRuntime.hairlineColor(this.darkMode))
  }

  @Builder
  filterRow() {
    Row({ space: AppSpacing.SM }) {
      ForEach([0, ...ReadingTicketRules.STATUSES], (status: number) => {
        Text(`${status === 0 ? '全部' : BookMarkStatus.label(status)} ${this.statusCount(status)}`)
          .fontSize(AppFontSize.CAPTION)
          .fontWeight(this.statusFilter === status ? FontWeight.Bold : FontWeight.Regular)
          .fontColor(this.statusFilter === status ? ThemeRuntime.accentColor(this.darkMode) :
            ThemeRuntime.subTextColor(this.darkMode))
          .fontFeature('"tnum" 1')
          .padding({ left: 11, right: 11, top: 5, bottom: 5 })
          .borderRadius(14)
          .backgroundColor(this.statusFilter === status ? ThemeRuntime.accentSurfaceColor(this.darkMode) :
            ThemeRuntime.cardColor(this.darkMode))
          .accessibilitySelected(this.statusFilter === status)
          .onClick(() => {
            this.statusFilter = status;
          })
      }, (status: number) => `${status}`)
      Blank()
      if (ReadingTicketRules.years(this.tickets).length > 1) {
        Row({ space: 2 }) {
          Text(this.yearFilter ? `${this.yearFilter}` : '全部年份')
            .fontSize(AppFontSize.CAPTION)
            .fontColor(ThemeRuntime.subTextColor(this.darkMode))
          SymbolGlyph($r('sys.symbol.chevron_down'))
            .fontSize(12)
            .fontColor([ThemeRuntime.subTextColor(this.darkMode)])
        }
        .padding({ left: 11, right: 9, top: 5, bottom: 5 })
        .borderRadius(14)
        .backgroundColor(ThemeRuntime.cardColor(this.darkMode))
        .onClick(() => {
          this.showYearMenu = !this.showYearMenu;
        })
        .bindPopup(this.showYearMenu, ImmersiveMaterialRuntime.popupMenuOptions(this.immersiveLightLevel,
          (): void => {
            this.yearMenu();
          }, Placement.BottomRight, this.darkMode, ThemeRuntime.accentColor(this.darkMode), (): void => {
            this.showYearMenu = false;
          }))
      }
    }
    .width('100%')
  }

  @Builder
  monthHeader(row: AlbumRow) {
    Row() {
      Text(row.title)
        .fontSize(AppFontSize.BODY)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeRuntime.subTextColor(this.darkMode))
      Blank()
      Text(`${row.count} 张`)
        .fontSize(AppFontSize.CAPTION)
        .fontColor(ThemeRuntime.subTextColor(this.darkMode))
    }
    .width('100%')
    .padding({ left: AppSpacing.XS, right: AppSpacing.XS, top: AppSpacing.SM })
  }

  @Builder
  ticketRow(row: AlbumRow) {
    Row({ space: AppSpacing.MD }) {
      ForEach(row.tickets, (ticket: ReadingTicket) => {
        Column() {
          ReadingTicketCard({
            ticket: ticket,
            ticketStyle: this.ticketStyle,
            cardWidth: this.cellWidth(),
            notchColor: ThemeRuntime.pageColor(this.darkMode),
            thumbnail: !this.singleColumn
          })
        }
        .accessibilityGroup(true)
        .accessibilityText(`${ticket.bookName}，${BookMarkStatus.label(ticket.status)}` +
          (ticket.number > 0 ? `，第 ${ticket.number} 本读完` : ''))
        .onClick(() => {
          this.openTicket(ticket);
        })
      }, (ticket: ReadingTicket) => this.ticketKey(ticket))
    }
    .width('100%')
    .justifyContent(this.singleColumn ? FlexAlign.Center : FlexAlign.Start)
    .alignItems(VerticalAlign.Top)
    .padding({ bottom: AppSpacing.SM })
  }

  @Builder
  emptyState(title: string, description: string) {
    Column({ space: AppSpacing.MD }) {
      SymbolGlyph($r('sys.symbol.coupon'))
        .fontSize(40)
        .fontColor([ThemeRuntime.subTextColor(this.darkMode)])
      Text(title)
        .fontSize(AppFontSize.BODY_LARGE)
        .fontColor(ThemeRuntime.primaryTextColor(this.darkMode))
      Text(description)
        .fontSize(AppFontSize.BODY)
        .fontColor(ThemeRuntime.subTextColor(this.darkMode))
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding({ top: 80, left: AppSpacing.XL, right: AppSpacing.XL })
  }
}
