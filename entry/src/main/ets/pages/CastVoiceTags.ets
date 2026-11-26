import { PageScaffold } from '../components/common/PageScaffold';
import { SettingSwitchRow } from '../components/common/SettingRow';
import { CastVoiceLine } from '../components/CastVoiceViews';
import {
  CAST_AGES, CAST_AGE_LABELS, CAST_GENDERS, CAST_GENDER_LABELS, CastVoicePolicy
} from '../core/mimo/CastVoicePolicy';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { CastVoiceItem, CastVoiceStore } from '../utils/mimo/CastVoiceStore';
import { CastVoicePreview } from '../utils/mimo/CastVoicePreview';
import { HdsFeedback } from '../utils/HdsFeedback';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';
import { syncSystemBars } from '../utils/SystemBars';

/**
 * 给离线音色和自定义音色标性别、年龄段、是否适合读旁白。
 * 标签决定选音色面板“合适的”里列哪些，以及第一次开启多角色朗读时默认方案怎么填。
 */
@Entry
@Component
struct CastVoiceTagsPage {
  @StorageProp('appDarkMode') dark: boolean = false;
  @StorageProp('themeRevision') themeRevision: number = 0;
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @State items: CastVoiceItem[] = [];
  @State previewing: string = '';
  @State showSheet: boolean = false;
  @State editKey: string = '';
  @State editGender: string = 'unknown';
  @State editAge: string = 'unknown';
  @State editNarrator: boolean = false;
  private preview: CastVoicePreview = new CastVoicePreview();

  onPageShow(): void {
    syncSystemBars(getContext(this), this.dark, ThemeRuntime.pageColor(this.dark));
    this.refresh();
  }
  onPageHide(): void { this.stopPreview(); }
  aboutToDisappear(): void { this.preview.release(); }

  private refresh(): void {
    try { this.items = CastVoiceStore.voices().slice(); } catch (error) { HdsFeedback.showToast((error as Error).message); }
  }
  private stopPreview(): void { this.preview.stop(); this.previewing = ''; }
  private async togglePreview(item: CastVoiceItem): Promise<void> {
    if (this.previewing === item.key) { this.stopPreview(); return; }
    this.previewing = item.key;
    try { await this.preview.play(item.ref); } catch (error) {
      if (!CastVoicePreview.interrupted(error as Error)) HdsFeedback.showToast((error as Error).message || '试听失败');
    }
    if (this.previewing === item.key) this.previewing = '';
  }
  private group(source: string): CastVoiceItem[] {
    return this.items.filter((item: CastVoiceItem): boolean => item.source === source);
  }
  private editing(): CastVoiceItem | undefined {
    return this.items.find((item: CastVoiceItem): boolean => item.key === this.editKey);
  }
  private open(item: CastVoiceItem): void {
    this.editKey = item.key;
    this.editGender = item.tag.gender;
    this.editAge = item.tag.age;
    this.editNarrator = item.tag.narrator;
    this.showSheet = true;
  }
  private store(): void {
    try { CastVoiceStore.setTag(this.editKey, this.editGender, this.editAge, this.editNarrator); this.refresh(); }
    catch (error) { HdsFeedback.showToast((error as Error).message); }
  }
  private clear(): void {
    try { CastVoiceStore.clearTag(this.editKey); CastVoiceStore.clearUnsupported(this.editKey); this.refresh(); }
    catch (error) { HdsFeedback.showToast((error as Error).message); }
    this.showSheet = false;
  }

  sheetOptions(): SheetOptions {
    return ImmersiveMaterialRuntime.applySheetMaterial(this.immersiveLightLevel, {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      showClose: false,
      onDisappear: () => { this.showSheet = false; this.stopPreview(); }
    }, this.dark, ThemeRuntime.accentColor(this.dark));
  }

  build() {
    Stack() {
      PageScaffold({ title: '音色标签', content: () => { this.content() } })
    }.width('100%').height('100%')
    .bindSheet($$this.showSheet, this.tagSheet(), this.sheetOptions())
  }

  @Builder
  chip(label: string, on: boolean, onTap: () => void) {
    Text(label).fontSize(AppFontSize.BODY).height(34).textAlign(TextAlign.Center)
      .padding({ left: 15, right: 15 }).borderRadius(17)
      .fontWeight(on ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(on ? ThemeRuntime.onAccentColor(ThemeRuntime.buttonColor(this.dark)) : ThemeRuntime.primaryTextColor(this.dark))
      .backgroundColor(on ? ThemeRuntime.buttonColor(this.dark) : ThemeRuntime.softFillColor(this.dark))
      .onClick(() => onTap())
  }

  @Builder
  tagSheet() {
    Column({ space: AppSpacing.XL }) {
      Row({ space: AppSpacing.LG }) {
        Column({ space: AppSpacing.XXS }) {
          Text(this.editing()?.title || '').fontSize(AppFontSize.SUBTITLE).fontWeight(FontWeight.Medium)
            .fontColor(ThemeRuntime.primaryTextColor(this.dark)).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
          Text((this.editing()?.source || '') + '音色' + (this.editing()?.unsupported ? ' · ' + (this.editing()?.reason || '') : ''))
            .fontSize(AppFontSize.CAPTION).fontColor(ThemeRuntime.subTextColor(this.dark)).width('100%')
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph(this.previewing === this.editKey ? $r('sys.symbol.stop_circle') : $r('sys.symbol.play_fill'))
            .fontSize(15).fontColor([ThemeRuntime.accentColor(this.dark)])
        }.width(36).height(36).backgroundColor(ThemeRuntime.accentSurfaceColor(this.dark))
        .accessibilityText('试听')
        .onClick(() => { const item = this.editing(); if (item) this.togglePreview(item); })
      }.width('100%')

      Column({ space: AppSpacing.MD }) {
        Text('性别').fontSize(AppFontSize.BODY).fontColor(ThemeRuntime.subTextColor(this.dark)).width('100%')
        Row({ space: AppSpacing.MD }) {
          ForEach(['male', 'female', 'unknown'], (value: string) => {
            this.chip(CAST_GENDER_LABELS[CAST_GENDERS.indexOf(value)], this.editGender === value,
              (): void => { this.editGender = value; this.store(); })
          }, (value: string): string => value + (this.editGender === value ? '1' : '0'))
        }.width('100%')
      }.width('100%')

      Column({ space: AppSpacing.MD }) {
        Text('年龄段').fontSize(AppFontSize.BODY).fontColor(ThemeRuntime.subTextColor(this.dark)).width('100%')
        Row({ space: AppSpacing.MD }) {
          ForEach(['teen', 'young', 'middle', 'elder'], (value: string) => {
            this.chip(CAST_AGE_LABELS[CAST_AGES.indexOf(value)], this.editAge === value,
              (): void => { this.editAge = this.editAge === value ? 'unknown' : value; this.store(); })
          }, (value: string): string => value + (this.editAge === value ? '1' : '0'))
        }.width('100%')
      }.width('100%')

      Column() {
        SettingSwitchRow({ title: '适合读旁白', description: '打开后会出现在方案旁白位置的“合适的”里',
          isOn: this.editNarrator, showDivider: false,
          onChange: (on: boolean): void => { this.editNarrator = on; this.store(); } })
      }.width('100%').backgroundColor(ThemeRuntime.cardColor(this.dark)).borderRadius(ThemeRuntime.cardRadius())

      Row({ space: AppSpacing.LG }) {
        Button(this.editing()?.unsupported ? '清除标签并重新检测' : '清除标签').height(42).layoutWeight(1).fontSize(AppFontSize.BODY)
          .fontColor(ThemeRuntime.primaryTextColor(this.dark)).backgroundColor(ThemeRuntime.softFillColor(this.dark))
          .onClick(() => this.clear())
        Button('完成').height(42).layoutWeight(1).fontSize(AppFontSize.BODY)
          .backgroundColor(ThemeRuntime.buttonColor(this.dark))
          .fontColor(ThemeRuntime.onAccentColor(ThemeRuntime.buttonColor(this.dark)))
          .onClick(() => { this.showSheet = false; })
      }.width('100%')
    }
    .width('100%')
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.XXL, bottom: AppSpacing.XL + this.navBarHeight })
  }

  @Builder
  section(source: string) {
    if (this.group(source).length > 0) {
      Row({ space: AppSpacing.MD }) {
        Text(source + '音色').fontSize(AppFontSize.BODY_LARGE).fontWeight(FontWeight.Medium)
          .fontColor(ThemeRuntime.primaryTextColor(this.dark))
        Text(`${this.group(source).length}`).fontSize(AppFontSize.CAPTION).fontColor(ThemeRuntime.subTextColor(this.dark))
      }.width('100%').padding({ left: AppSpacing.XXS, top: AppSpacing.SM })
      Column() {
        ForEach(this.group(source), (item: CastVoiceItem, index: number) => {
          CastVoiceLine({
            title: item.title,
            tagText: CastVoicePolicy.tagged(item.tag) ? CastVoicePolicy.tagLabel(item.tag) : '',
            note: item.unsupported ? item.reason : (CastVoicePolicy.tagged(item.tag) ? '' : '未标'),
            noteTone: 'danger',
            playing: this.previewing === item.key,
            showDivider: index < this.group(source).length - 1,
            onTap: (): void => this.open(item),
            onPlay: (): void => { this.togglePreview(item); }
          })
        }, (item: CastVoiceItem): string => item.key + '|' + CastVoicePolicy.tagLabel(item.tag) +
          (item.unsupported ? 'u' : '') + (this.previewing === item.key ? 'p' : ''))
      }.width('100%').backgroundColor(ThemeRuntime.cardColor(this.dark)).borderRadius(ThemeRuntime.cardRadius())
    }
  }

  @Builder
  content() {
    Column({ space: AppSpacing.LG }) {
      if (this.items.length === 0) {
        Text('还没有可用的离线音色或自定义音色。先到“音色管理”里下载离线音色或导入自定义音色。')
          .fontSize(AppFontSize.BODY).fontColor(ThemeRuntime.subTextColor(this.dark))
          .textAlign(TextAlign.Center).width('100%').padding({ top: 80 })
      } else {
        Text('点一个音色给它标性别、年龄段。内置离线音色自带标签；没标的音色不会自动进方案，但可以手动选给任何人物。')
          .fontSize(AppFontSize.CAPTION).fontColor(ThemeRuntime.subTextColor(this.dark)).width('100%')
          .padding({ top: AppSpacing.SM })
        this.section('离线')
        this.section('自定义')
      }
    }.width('100%').constraintSize({ maxWidth: 760 })
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG })
  }
}
