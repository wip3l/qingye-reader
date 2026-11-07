import { AdaptiveSwitch } from '../AdaptiveSwitch';
import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';
import { SearchExploreSettings, SearchExploreSettingsStore } from '../../utils/SearchExploreSettingsStore';

/**
 * 搜索设置：开关即时生效并写回偏好。放在发现页“更多”菜单的二级页里（inMenu 时不画标题，左右留白与菜单行对齐）；
 * 聚合开关由搜索层监听同一个 AppStorage 键重排结果。
 */
@Component
export struct SearchSettingsPanel {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageLink('searchExploreExactSearch') exactSearch: boolean = false;
  @StorageLink('searchExploreExactSearchMatchAuthor') exactSearchMatchAuthor: boolean = true;
  @StorageLink('searchExploreShowSearchProgress') showSearchProgress: boolean = true;
  @StorageLink('searchExploreAggregateResults') searchExploreAggregateResults: boolean = true;
  @StorageLink('searchExploreSearchConcurrency') searchConcurrency: number = 6;
  @Prop panelWidth: number = 272;
  @Prop inMenu: boolean = false;

  build() {
    Column() {
      if (!this.inMenu) {
        Text('搜索设置')
          .fontSize(AppFontSize.BODY_LARGE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.primaryTextColor())
          .width('100%')
          .margin({ bottom: AppSpacing.SM })
      }

      this.switchSettingRow('精准搜索', this.exactSearch, (checked: boolean) => {
        this.exactSearch = checked;
        this.save();
      })

      this.switchSettingRow('匹配作者', this.exactSearchMatchAuthor, (checked: boolean) => {
        this.exactSearchMatchAuthor = checked;
        this.save();
      })

      this.switchSettingRow('显示搜索进度', this.showSearchProgress, (checked: boolean) => {
        this.showSearchProgress = checked;
        this.save();
      })

      this.switchSettingRow('聚合同名结果', this.searchExploreAggregateResults, (checked: boolean) => {
        this.searchExploreAggregateResults = checked;
        this.save();
      })

      this.numberSettingRow('搜索并发数', 1, 12, (value: number) => {
        this.searchConcurrency = SearchExploreSettingsStore.normalizeSearchConcurrency(value);
        this.save();
      })
    }
    .width(this.panelWidth)
    .padding(this.inMenu ? { left: AppSpacing.LG, right: AppSpacing.LG, top: 0, bottom: AppSpacing.XS } :
      { left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.LG, bottom: AppSpacing.SM })
  }

  save(): void {
    SearchExploreSettingsStore.load(getContext(this)).then((settings: SearchExploreSettings) => {
      settings.exactSearch = this.exactSearch;
      settings.exactSearchMatchAuthor = this.exactSearchMatchAuthor;
      settings.showSearchProgress = this.showSearchProgress;
      settings.aggregateSearchResults = this.searchExploreAggregateResults;
      settings.searchConcurrency = SearchExploreSettingsStore.normalizeSearchConcurrency(this.searchConcurrency);
      SearchExploreSettingsStore.applyToStorage(settings);
      return SearchExploreSettingsStore.save(getContext(this), settings);
    }).catch((e: Error) => {
      console.warn('保存搜索设置失败:', e);
    });
  }

  primaryTextColor(): string {
    return ThemeRuntime.primaryTextColor(this.appDarkMode);
  }

  @Builder
  switchSettingRow(title: string, checked: boolean, onChange: (checked: boolean) => void) {
    Row() {
      Text(title)
        .fontSize(AppFontSize.BODY_LARGE)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)

      AdaptiveSwitch({
        isOn: checked,
        onChange: onChange
      })
    }
    .width('100%')
    .height(42)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  numberSettingRow(title: string, minValue: number, maxValue: number, onChange: (value: number) => void) {
    Row() {
      Text(title)
        .fontSize(AppFontSize.BODY_LARGE)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)

      Row() {
        Text('−')
          .fontSize(AppFontSize.SUBTITLE)
          .fontColor(this.primaryTextColor())
          .width(30)
          .height(30)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            onChange(Math.max(minValue, this.searchConcurrency - 1));
          })
        Text(`${this.searchConcurrency}`)
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.primaryTextColor())
          .width(42)
          .textAlign(TextAlign.Center)
        Text('+')
          .fontSize(AppFontSize.SUBTITLE)
          .fontColor(this.primaryTextColor())
          .width(30)
          .height(30)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            onChange(Math.min(maxValue, this.searchConcurrency + 1));
          })
      }
      .height(30)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(42)
    .alignItems(VerticalAlign.Center)
  }
}
