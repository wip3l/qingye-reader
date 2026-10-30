import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';
import { HelpBlock, HelpListItem, HelpRow, HelpRun, HelpZoneCell } from '../../utils/HelpManual';

/** 说明书正文的一串块，按网页版的段落、列表、表格等样式换成应用内的排版。 */
@Component
export struct HelpBlockView {
  @StorageProp('appDarkMode') appDarkMode: boolean = false;
  @StorageProp('themeRevision') themeRevision: number = 0;
  blocks: HelpBlock[] = [];
  /** 段落用次要文字色，用于专题开头的导语。 */
  muted: boolean = false;
  onLink: (url: string) => void = () => {
  };

  build() {
    Column({ space: AppSpacing.MD }) {
      ForEach(this.blocks, (block: HelpBlock) => {
        this.blockView(block)
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  blockView(block: HelpBlock) {
    if (block.k === 'h') {
      this.richText(block.r || [], AppFontSize.BODY_LARGE, this.primaryTextColor(), FontWeight.Medium)
    } else if (block.k === 'tip' || block.k === 'note') {
      Row({ space: AppSpacing.MD }) {
        SymbolGlyph(block.k === 'note' ? $r('sys.symbol.exclamationmark_circle') : $r('sys.symbol.info_circle'))
          .fontSize(16)
          .fontColor([this.accentColor()])
          .margin({ top: 2 })
        Column() {
          this.richText(block.r || [], AppFontSize.BODY, this.subTextColor(), FontWeight.Normal)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.MD + 2, bottom: AppSpacing.MD + 2 })
      .borderRadius(ThemeRuntime.mediumRadius())
      .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
    } else if (block.k === 'ul' || block.k === 'ol') {
      Column({ space: AppSpacing.SM }) {
        ForEach(block.items || [], (item: HelpListItem, index: number) => {
          Row() {
            Text(block.k === 'ol' && item.lv === 0 ? `${index + 1}.` : '•')
              .fontSize(AppFontSize.BODY)
              .fontColor(this.accentColor())
              .lineHeight(22)
              .width(block.k === 'ol' && item.lv === 0 ? 20 : 14)
            Column() {
              this.richText(item.r, AppFontSize.BODY, this.primaryTextColor(), FontWeight.Normal)
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
          .padding({ left: item.lv * AppSpacing.XL })
        })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    } else if (block.k === 'rows') {
      Column() {
        ForEach(block.rows || [], (row: HelpRow, index: number) => {
          this.rowView(block.head || [], row, index)
        })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    } else if (block.k === 'zone') {
      this.zoneView(block)
    } else {
      this.richText(block.r || [], AppFontSize.BODY, this.muted ? this.subTextColor() : this.primaryTextColor(),
        FontWeight.Normal)
    }
  }

  @Builder
  richText(runs: HelpRun[], size: number, color: string, weight: FontWeight) {
    Text() {
      ForEach(runs, (run: HelpRun) => {
        if (run.k === 2) {
          // 菜单路径做成浅色小块，与网页版的高亮路径对应。
          Span(` ${run.t} `)
            .fontColor(this.accentColor())
            .fontWeight(FontWeight.Medium)
            .textBackgroundStyle({ color: ThemeRuntime.accentSurfaceColor(this.appDarkMode), radius: 6 })
        } else if (run.k === 3) {
          Span(` ${run.t} `)
            .fontColor(this.primaryTextColor())
            .textBackgroundStyle({ color: ThemeRuntime.softFillColor(this.appDarkMode), radius: 4 })
        } else if (run.k === 4) {
          Span(run.t)
            .fontColor(this.accentColor())
            .decoration({ type: TextDecorationType.Underline, color: this.accentColor() })
            .onClick(() => this.onLink(run.u || ''))
        } else {
          Span(run.t)
            .fontColor(color)
            .fontWeight(run.k === 1 ? FontWeight.Medium : weight)
        }
      })
    }
    .fontSize(size)
    .fontColor(color)
    .lineHeight(size + 8)
    .width('100%')
  }

  @Builder
  rowView(head: string[], row: HelpRow, index: number) {
    Column({ space: AppSpacing.XXS }) {
      Text(row.title)
        .fontSize(AppFontSize.BODY)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.primaryTextColor())
      if (row.cells.length === 1) {
        this.richText(row.cells[0], AppFontSize.CAPTION + 1, this.subTextColor(), FontWeight.Normal)
      } else {
        // 多列对照表（如原生与兼容书源）每格前加上列名。
        ForEach(row.cells, (cell: HelpRun[], cellIndex: number) => {
          Row({ space: AppSpacing.SM }) {
            Text(head[cellIndex + 1] || '')
              .fontSize(AppFontSize.CAPTION)
              .fontColor(this.accentColor())
              .lineHeight(20)
            Column() {
              this.richText(cell, AppFontSize.CAPTION + 1, this.subTextColor(), FontWeight.Normal)
            }
            .layoutWeight(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
        })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: AppSpacing.MD, bottom: AppSpacing.MD })
    .border({ width: { top: index === 0 ? 0 : 0.5 }, color: this.dividerColor() })
  }

  @Builder
  zoneView(block: HelpBlock) {
    Row({ space: AppSpacing.LG }) {
      Grid() {
        ForEach(block.cells || [], (cell: HelpZoneCell) => {
          GridItem() {
            Text(cell.t)
              .fontSize(AppFontSize.MICRO)
              .fontColor(cell.m === 1 ? ThemeRuntime.onAccentColor(this.accentColor())
                : cell.m === 2 ? this.accentColor() : this.subTextColor())
              .textAlign(TextAlign.Center)
              .width('100%')
              .height('100%')
              .backgroundColor(cell.m === 1 ? this.accentColor()
                : cell.m === 2 ? ThemeRuntime.accentSurfaceColor(this.appDarkMode) : Color.Transparent)
          }
        })
      }
      .columnsTemplate('1fr 1fr 1fr')
      .rowsTemplate('1fr 1fr 1fr')
      .width(84)
      .height(150)
      .borderRadius(12)
      .border({ width: 1.5, color: this.primaryTextColor() })
      .clip(true)

      Column() {
        this.richText(block.r || [], AppFontSize.BODY, this.primaryTextColor(), FontWeight.Normal)
      }
      .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
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

  dividerColor(): string {
    return ThemeRuntime.dividerColor(this.appDarkMode);
  }
}
