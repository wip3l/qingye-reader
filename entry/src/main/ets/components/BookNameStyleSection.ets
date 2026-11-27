import { router } from '@kit.ArkUI';
import { SettingNavRow, SettingSwitchRow } from './common/SettingRow';
import { MimoRole } from '../core/mimo/MimoPolicy';
import { ReaderNamePatterns } from '../core/reader/ReaderNamePatterns';
import { ReaderNameStyle } from '../model/reader/ReaderNameStyle';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { HdsFeedback } from '../utils/HdsFeedback';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';
import { MimoBookCast, MimoStore } from '../utils/mimo/MimoStore';

/** 列表里的一个人。 */
class NameColorItem {
  id: string = '';
  name: string = '';
  aliases: string = '';
  /** 色板下标，-1 不上色。 */
  index: number = -1;
  color: string = '';
  own: boolean = false;
  signature: string = '';
}

/**
 * “本书人物”页里的正文人名上色：开关、人名样式（进阅读字体页的规则编辑改）、每个人的颜色。
 * 多角色朗读的两种人物页（离线/自定义音色、MiMo）共用；数据都在本书人物档案里（见 ReaderNameStyle）。
 */
@Component
export struct BookNameStyleSection {
  @Prop book: string = '';
  @StorageProp('appDarkMode') @Watch('reload') dark: boolean = false;
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  @StorageProp('mimoVoicesRevision') @Watch('reload') revision: number = 0;
  @State on: boolean = false;
  @State summary: string = '';
  @State items: NameColorItem[] = [];
  @State showSheet: boolean = false;
  @State sheetRoleId: string = '';

  aboutToAppear(): void {
    this.reload();
  }

  reload(): void {
    if (!this.book) return;
    try {
      const cast = MimoStore.cast(this.book);
      this.on = cast.nameStyleOn === true;
      this.summary = ReaderNameStyle.summary(cast);
      const roles = ReaderNameStyle.characters(cast);
      const colors = ReaderNameStyle.colors(cast);
      this.items = roles.map((role: MimoRole, index: number): NameColorItem => {
        const item = new NameColorItem();
        item.id = role.id;
        item.name = role.name;
        item.aliases = (role.aliases || []).join('、');
        item.index = colors[index];
        item.color = ReaderNameStyle.roleColor(cast, role, colors[index], this.dark);
        item.own = !!(role.nameRule && role.nameRule.trim());
        item.signature = [item.id, item.name, item.aliases, item.index, item.color, item.own ? 'o' : ''].join('|');
        return item;
      });
    } catch (error) {
      console.warn('读取本书人名样式失败:', error);
    }
  }

  private update(mutate: (cast: MimoBookCast) => void): void {
    try {
      const cast = MimoStore.cast(this.book);
      mutate(cast);
      MimoStore.saveCast(this.book, cast);
    } catch (error) {
      console.warn('保存本书人名样式失败:', error);
      HdsFeedback.showToast('保存失败');
    }
    this.reload();
  }

  private setColor(index: number): void {
    const roleId = this.sheetRoleId;
    this.showSheet = false;
    this.update((cast: MimoBookCast): void => {
      const role = cast.roles.find((item: MimoRole): boolean => item.id === roleId);
      if (role) role.nameColor = index;
    });
  }

  private openStyle(roleId: string): void {
    this.showSheet = false;
    const params: Record<string, string> = { 'nameStyleBook': this.book };
    if (roleId) params['nameStyleRole'] = roleId;
    router.pushUrl({ url: 'pages/ReaderFontSettings', params: params });
  }

  private sheetItem(): NameColorItem | undefined {
    return this.items.find((item: NameColorItem): boolean => item.id === this.sheetRoleId);
  }

  build() {
    Column({ space: AppSpacing.SM }) {
      Column() {
        SettingSwitchRow({
          title: '正文里人名上色',
          description: '人物和别名在正文里按人名样式显示，只对这本书',
          isOn: this.on,
          showDivider: this.on,
          onChange: (isOn: boolean) => this.update((cast: MimoBookCast): void => { cast.nameStyleOn = isOn; })
        })
        if (this.on) {
          SettingNavRow({ title: '人名样式', value: this.summary, showDivider: false,
            onTap: (): void => this.openStyle('') })
        }
      }
      .width('100%')
      .backgroundColor(ThemeRuntime.cardColor(this.dark))
      .borderRadius(ThemeRuntime.cardRadius())

      if (this.on) {
        if (this.items.length === 0) {
          Text('还没有识别出人物：开着多角色朗读读几章后会自动识别，也可以手动添加。')
            .fontSize(AppFontSize.CAPTION)
            .fontColor(ThemeRuntime.subTextColor(this.dark))
            .width('100%')
            .padding({ left: AppSpacing.XS, right: AppSpacing.XS })
        } else {
          Column() {
            ForEach(this.items, (item: NameColorItem, index: number) => {
              this.itemRow(item, index === this.items.length - 1)
            }, (item: NameColorItem, index: number): string =>
              `${item.signature}|${index === this.items.length - 1 ? 'e' : ''}`)
          }
          .width('100%')
          .backgroundColor(ThemeRuntime.cardColor(this.dark))
          .borderRadius(ThemeRuntime.cardRadius())
          Text('点色点换人名颜色或单独设置样式。一个字的名字和别名不上色，免得在别的词里撞上。')
            .fontSize(AppFontSize.CAPTION)
            .fontColor(ThemeRuntime.subTextColor(this.dark))
            .width('100%')
            .padding({ left: AppSpacing.XS, right: AppSpacing.XS })
        }
      }
    }
    .width('100%')
    .bindSheet($$this.showSheet, this.colorSheet(), ImmersiveMaterialRuntime.applySheetMaterial(this.immersiveLightLevel, {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      showClose: false,
      onDisappear: () => { this.showSheet = false; }
    }, this.dark, ThemeRuntime.accentColor(this.dark)))
  }

  @Builder
  itemRow(item: NameColorItem, last: boolean) {
    Row({ space: AppSpacing.MD }) {
      Column({ space: 2 }) {
        Row({ space: AppSpacing.SM }) {
          Text(item.name)
            .fontSize(AppFontSize.BODY_LARGE)
            .fontColor(ThemeRuntime.primaryTextColor(this.dark))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (item.own) {
            Text('单独样式')
              .fontSize(10)
              .fontWeight(FontWeight.Medium)
              .fontColor(ThemeRuntime.accentColor(this.dark))
              .padding({ left: 6, right: 6, top: 1, bottom: 1 })
              .borderRadius(6)
              .backgroundColor(ThemeRuntime.accentSurfaceColor(this.dark))
          }
        }
        Text(item.aliases ? `也叫 ${item.aliases}` : '没有别名')
          .fontSize(AppFontSize.CAPTION)
          .fontColor(ThemeRuntime.subTextColor(this.dark))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      this.colorDot(item.color, item.own, 26)
    }
    .width('100%')
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.MD, bottom: AppSpacing.MD })
    .border({ width: { bottom: last ? 0 : 0.5 }, color: ThemeRuntime.hairlineColor(this.dark) })
    .accessibilityText(`${item.name}的人名颜色${item.index < 0 ? '，不上色' : ''}`)
    .onClick(() => {
      this.sheetRoleId = item.id;
      this.showSheet = true;
    })
  }

  /** 色点：不上色画成斜纹空心圈；单独设过样式外面多一圈强调色描边。 */
  @Builder
  colorDot(color: string, own: boolean, size: number) {
    Stack() {
      if (color) {
        Circle().width(size).height(size).fill(color)
      } else {
        Circle().width(size).height(size).fill(Color.Transparent)
          .stroke(ThemeRuntime.subTextColor(this.dark)).strokeWidth(1).strokeDashArray([3, 3])
      }
    }
    .width(size + 6)
    .height(size + 6)
    .borderRadius((size + 6) / 2)
    .border({ width: own ? 1.5 : 0, color: ThemeRuntime.accentColor(this.dark) })
  }

  @Builder
  colorSheet() {
    Column({ space: AppSpacing.LG }) {
      Text(`${this.sheetItem()?.name ?? ''}的人名颜色`)
        .fontSize(AppFontSize.SUBTITLE)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeRuntime.primaryTextColor(this.dark))
        .width('100%')
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
        ForEach(ReaderNamePatterns.PALETTE, (pair: string[], index: number) => {
          Stack() {
            Circle().width(30).height(30).fill(pair[this.dark ? 1 : 0])
          }
          .width(38)
          .height(38)
          .borderRadius(19)
          .border({ width: this.sheetItem()?.index === index ? 2 : 0, color: ThemeRuntime.accentColor(this.dark) })
          .margin({ bottom: AppSpacing.SM })
          .accessibilityText(`颜色 ${index + 1}`)
          .onClick(() => this.setColor(index))
        }, (pair: string[], index: number): string => `${index}|${pair[0]}|${this.sheetRoleId}`)
      }
      .width('100%')
      Row({ space: AppSpacing.SM }) {
        Button('不上色')
          .layoutWeight(1)
          .height(40)
          .fontSize(AppFontSize.BODY)
          .fontColor(ThemeRuntime.primaryTextColor(this.dark))
          .backgroundColor(ThemeRuntime.softFillColor(this.dark))
          .onClick(() => this.setColor(ReaderNamePatterns.NONE))
        Button('单独设置样式…')
          .layoutWeight(1)
          .height(40)
          .fontSize(AppFontSize.BODY)
          .fontColor(ThemeRuntime.accentColor(this.dark))
          .backgroundColor(ThemeRuntime.accentSurfaceColor(this.dark))
          .onClick(() => this.openStyle(this.sheetRoleId))
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.XXL, bottom: AppSpacing.XXXL })
  }
}
