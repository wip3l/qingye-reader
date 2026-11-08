import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';
import { CloudSyncChangeTracker } from '../account/CloudSyncChangeTracker';
import { ExploreRankStyle } from './ExploreRankStyle';

export class SearchExploreSettings {
  showResultCover: boolean = true;
  showResultCoverBackground: boolean = true;
  useBookshelfCoverGallery: boolean = false;
  showResultTags: boolean = true;
  aggregateSearchResults: boolean = true;
  promptAddToShelfOnBack: boolean = true;
  exactSearch: boolean = false;
  exactSearchMatchAuthor: boolean = true;
  showSearchProgress: boolean = true;
  searchConcurrency: number = 6;
  selectedSourceGroupsRaw: string = '';
  selectedSourceUrlsRaw: string = '__LEGACY_SOURCE_GROUP_SELECTION__';
  // 搜索范围“自选”记住的书源；选“全部书源”时 selectedSourceUrlsRaw 清空，这份留着下次直接切回。
  customSourceUrlsRaw: string = '';
  // 搜索框前缀选的范围：all / current（跟着发现页当前书源）/ custom，重启后照旧；空为旧版本，按上面的选择推断。
  scopeMode: string = '';
  sourceSortRaw: string = '';
  exploreSourceUrl: string = '';
  explorePlatform: string = '';
  // 搜索、发现结果的布局：'list' 卡片列表，'grid' 封面平铺。
  searchResultLayout: string = 'list';
  exploreResultLayout: string = 'list';
}

/** 换源面板记住的搜索范围：mode 为 all（全部启用书源）或 group（只搜 groups 里的分组）。 */
export class ChangeSourceScope {
  mode: string = 'all';
  groups: string[] = [];
}

export class SearchExploreSettingsStore {
  static readonly KEY_SHOW_RESULT_COVER: string = 'searchExploreShowResultCover';
  static readonly KEY_SHOW_RESULT_COVER_BACKGROUND: string = 'searchExploreShowResultCoverBackground';
  static readonly KEY_USE_BOOKSHELF_COVER_GALLERY: string = 'searchExploreUseBookshelfCoverGallery';
  static readonly KEY_SHOW_RESULT_TAGS: string = 'searchExploreShowResultTags';
  static readonly KEY_AGGREGATE_SEARCH_RESULTS: string = 'searchExploreAggregateResults';
  static readonly KEY_PROMPT_ADD_TO_SHELF_ON_BACK: string = 'searchExplorePromptAddToShelfOnBack';
  static readonly KEY_EXACT_SEARCH: string = 'searchExploreExactSearch';
  static readonly KEY_EXACT_SEARCH_MATCH_AUTHOR: string = 'searchExploreExactSearchMatchAuthor';
  static readonly KEY_SHOW_SEARCH_PROGRESS: string = 'searchExploreShowSearchProgress';
  static readonly KEY_SEARCH_CONCURRENCY: string = 'searchExploreSearchConcurrency';
  static readonly KEY_SELECTED_SOURCE_GROUPS: string = 'searchExploreSelectedSourceGroups';
  static readonly KEY_SELECTED_SOURCE_URLS: string = 'searchExploreSelectedSourceUrls';
  static readonly KEY_CUSTOM_SOURCE_URLS: string = 'searchExploreCustomSourceUrls';
  static readonly KEY_SCOPE_MODE: string = 'searchExploreScopeMode';
  static readonly LEGACY_SOURCE_SELECTION: string = '__LEGACY_SOURCE_GROUP_SELECTION__';
  static readonly KEY_SOURCE_SORT: string = 'searchExploreSourceSort';
  static readonly KEY_EXPLORE_SOURCE_URL: string = 'exploreSourceUrl';
  static readonly KEY_EXPLORE_PLATFORM: string = 'explorePlatform';
  static readonly KEY_SEARCH_RESULT_LAYOUT: string = 'searchResultLayout';
  static readonly KEY_EXPLORE_RESULT_LAYOUT: string = 'exploreResultLayout';
  // 换源范围单独读写，不进 SearchExploreSettings：设置页整份保存时不会把面板里刚改的范围盖回旧值。
  static readonly KEY_CHANGE_SOURCE_SCOPE_MODE: string = 'changeSourceScopeMode';
  static readonly KEY_CHANGE_SOURCE_SCOPE_GROUPS: string = 'changeSourceScopeGroups';
  static readonly CHANGE_SOURCE_SCOPE_ALL: string = 'all';
  static readonly CHANGE_SOURCE_SCOPE_GROUP: string = 'group';
  private static readonly STORE_NAME: string = 'search_explore_settings';
  private static changeSourceScope: ChangeSourceScope | null = null;
  private static readonly DEFAULT_SEARCH_CONCURRENCY: number = 6;
  private static readonly MIN_SEARCH_CONCURRENCY: number = 1;
  private static readonly MAX_SEARCH_CONCURRENCY: number = 12;
  private static cachedSettings: SearchExploreSettings | null = null;

  static async load(context: Context): Promise<SearchExploreSettings> {
    if (SearchExploreSettingsStore.cachedSettings) {
      return SearchExploreSettingsStore.clone(SearchExploreSettingsStore.cachedSettings);
    }
    const store = await preferences.getPreferences(context, SearchExploreSettingsStore.STORE_NAME);
    const settings = new SearchExploreSettings();
    settings.showResultCover = await SearchExploreSettingsStore.getBoolean(
      store, SearchExploreSettingsStore.KEY_SHOW_RESULT_COVER, true);
    settings.showResultCoverBackground = await SearchExploreSettingsStore.getBoolean(
      store, SearchExploreSettingsStore.KEY_SHOW_RESULT_COVER_BACKGROUND, true);
    settings.useBookshelfCoverGallery = await SearchExploreSettingsStore.getBoolean(
      store, SearchExploreSettingsStore.KEY_USE_BOOKSHELF_COVER_GALLERY, false);
    settings.showResultTags = await SearchExploreSettingsStore.getBoolean(
      store, SearchExploreSettingsStore.KEY_SHOW_RESULT_TAGS, true);
    settings.aggregateSearchResults = await SearchExploreSettingsStore.getBoolean(
      store, SearchExploreSettingsStore.KEY_AGGREGATE_SEARCH_RESULTS, true);
    settings.promptAddToShelfOnBack = await SearchExploreSettingsStore.getBoolean(
      store, SearchExploreSettingsStore.KEY_PROMPT_ADD_TO_SHELF_ON_BACK, true);
    settings.exactSearch = await SearchExploreSettingsStore.getBoolean(
      store, SearchExploreSettingsStore.KEY_EXACT_SEARCH, false);
    settings.exactSearchMatchAuthor = await SearchExploreSettingsStore.getBoolean(
      store, SearchExploreSettingsStore.KEY_EXACT_SEARCH_MATCH_AUTHOR, true);
    settings.showSearchProgress = await SearchExploreSettingsStore.getBoolean(
      store, SearchExploreSettingsStore.KEY_SHOW_SEARCH_PROGRESS, true);
    const storageConcurrency = AppStorage.get<number>(SearchExploreSettingsStore.KEY_SEARCH_CONCURRENCY);
    settings.searchConcurrency = await SearchExploreSettingsStore.getNumber(
      store,
      SearchExploreSettingsStore.KEY_SEARCH_CONCURRENCY,
      typeof storageConcurrency === 'number' ?
        SearchExploreSettingsStore.normalizeSearchConcurrency(storageConcurrency) :
        SearchExploreSettingsStore.DEFAULT_SEARCH_CONCURRENCY);
    settings.selectedSourceGroupsRaw = await SearchExploreSettingsStore.getString(
      store, SearchExploreSettingsStore.KEY_SELECTED_SOURCE_GROUPS, '');
    settings.selectedSourceUrlsRaw = await SearchExploreSettingsStore.getString(
      store, SearchExploreSettingsStore.KEY_SELECTED_SOURCE_URLS,
      SearchExploreSettingsStore.LEGACY_SOURCE_SELECTION);
    settings.customSourceUrlsRaw = await SearchExploreSettingsStore.getString(
      store, SearchExploreSettingsStore.KEY_CUSTOM_SOURCE_URLS, '');
    settings.scopeMode = await SearchExploreSettingsStore.getString(
      store, SearchExploreSettingsStore.KEY_SCOPE_MODE, '');
    settings.sourceSortRaw = await SearchExploreSettingsStore.getString(
      store, SearchExploreSettingsStore.KEY_SOURCE_SORT, '');
    settings.exploreSourceUrl = await SearchExploreSettingsStore.getString(
      store, SearchExploreSettingsStore.KEY_EXPLORE_SOURCE_URL, '');
    settings.explorePlatform = await SearchExploreSettingsStore.getString(
      store, SearchExploreSettingsStore.KEY_EXPLORE_PLATFORM, '');
    // 旧版本只存在 PersistentStorage 里，偏好里还没有时沿用 AppStorage 中的值。
    settings.searchResultLayout = SearchExploreSettingsStore.normalizeResultLayout(
      await SearchExploreSettingsStore.getString(store, SearchExploreSettingsStore.KEY_SEARCH_RESULT_LAYOUT,
        AppStorage.get<string>(SearchExploreSettingsStore.KEY_SEARCH_RESULT_LAYOUT) ?? 'list'));
    settings.exploreResultLayout = SearchExploreSettingsStore.normalizeResultLayout(
      await SearchExploreSettingsStore.getString(store, SearchExploreSettingsStore.KEY_EXPLORE_RESULT_LAYOUT,
        AppStorage.get<string>(SearchExploreSettingsStore.KEY_EXPLORE_RESULT_LAYOUT) ?? 'list'));
    SearchExploreSettingsStore.cachedSettings = SearchExploreSettingsStore.clone(settings);
    return settings;
  }

  static async save(context: Context, settings: SearchExploreSettings): Promise<void> {
    const previous = SearchExploreSettingsStore.cachedSettings ?
      SearchExploreSettingsStore.clone(SearchExploreSettingsStore.cachedSettings) : null;
    SearchExploreSettingsStore.cachedSettings = SearchExploreSettingsStore.clone(settings);
    const store = await preferences.getPreferences(context, SearchExploreSettingsStore.STORE_NAME);
    await store.put(SearchExploreSettingsStore.KEY_SHOW_RESULT_COVER, settings.showResultCover);
    await store.put(SearchExploreSettingsStore.KEY_SHOW_RESULT_COVER_BACKGROUND, settings.showResultCoverBackground);
    await store.put(SearchExploreSettingsStore.KEY_USE_BOOKSHELF_COVER_GALLERY, settings.useBookshelfCoverGallery);
    await store.put(SearchExploreSettingsStore.KEY_SHOW_RESULT_TAGS, settings.showResultTags);
    await store.put(SearchExploreSettingsStore.KEY_AGGREGATE_SEARCH_RESULTS, settings.aggregateSearchResults);
    await store.put(SearchExploreSettingsStore.KEY_PROMPT_ADD_TO_SHELF_ON_BACK, settings.promptAddToShelfOnBack);
    await store.put(SearchExploreSettingsStore.KEY_EXACT_SEARCH, settings.exactSearch);
    await store.put(SearchExploreSettingsStore.KEY_EXACT_SEARCH_MATCH_AUTHOR, settings.exactSearchMatchAuthor);
    await store.put(SearchExploreSettingsStore.KEY_SHOW_SEARCH_PROGRESS, settings.showSearchProgress);
    await store.put(SearchExploreSettingsStore.KEY_SEARCH_CONCURRENCY,
      SearchExploreSettingsStore.normalizeSearchConcurrency(settings.searchConcurrency));
    await store.put(SearchExploreSettingsStore.KEY_SELECTED_SOURCE_GROUPS, settings.selectedSourceGroupsRaw);
    await store.put(SearchExploreSettingsStore.KEY_SELECTED_SOURCE_URLS, settings.selectedSourceUrlsRaw);
    await store.put(SearchExploreSettingsStore.KEY_CUSTOM_SOURCE_URLS, settings.customSourceUrlsRaw);
    await store.put(SearchExploreSettingsStore.KEY_SCOPE_MODE, settings.scopeMode);
    await store.put(SearchExploreSettingsStore.KEY_SOURCE_SORT, settings.sourceSortRaw);
    await store.put(SearchExploreSettingsStore.KEY_EXPLORE_SOURCE_URL, settings.exploreSourceUrl);
    await store.put(SearchExploreSettingsStore.KEY_EXPLORE_PLATFORM, settings.explorePlatform);
    await store.put(SearchExploreSettingsStore.KEY_SEARCH_RESULT_LAYOUT,
      SearchExploreSettingsStore.normalizeResultLayout(settings.searchResultLayout));
    await store.put(SearchExploreSettingsStore.KEY_EXPLORE_RESULT_LAYOUT,
      SearchExploreSettingsStore.normalizeResultLayout(settings.exploreResultLayout));
    await store.flush();
    if (!previous || SearchExploreSettingsStore.syncFieldsChanged(previous, settings)) {
      CloudSyncChangeTracker.markApplicationPreferenceChanged();
    }
  }

  static async saveExploreSelection(
    context: Context,
    exploreSourceUrl: string,
    explorePlatform: string
  ): Promise<void> {
    if (SearchExploreSettingsStore.cachedSettings) {
      SearchExploreSettingsStore.cachedSettings.exploreSourceUrl = exploreSourceUrl;
      SearchExploreSettingsStore.cachedSettings.explorePlatform = explorePlatform;
    }
    AppStorage.setOrCreate(SearchExploreSettingsStore.KEY_EXPLORE_SOURCE_URL, exploreSourceUrl);
    AppStorage.setOrCreate(SearchExploreSettingsStore.KEY_EXPLORE_PLATFORM, explorePlatform);
    const store = await preferences.getPreferences(context, SearchExploreSettingsStore.STORE_NAME);
    await store.put(SearchExploreSettingsStore.KEY_EXPLORE_SOURCE_URL, exploreSourceUrl);
    await store.put(SearchExploreSettingsStore.KEY_EXPLORE_PLATFORM, explorePlatform);
    await store.flush();
  }

  /** 搜索或发现页切换列表/平铺后立即写入偏好，key 为 KEY_SEARCH_RESULT_LAYOUT 或 KEY_EXPLORE_RESULT_LAYOUT。 */
  static async saveResultLayout(context: Context, key: string, layout: string): Promise<void> {
    const normalized = SearchExploreSettingsStore.normalizeResultLayout(layout);
    if (SearchExploreSettingsStore.cachedSettings) {
      if (key === SearchExploreSettingsStore.KEY_SEARCH_RESULT_LAYOUT) {
        SearchExploreSettingsStore.cachedSettings.searchResultLayout = normalized;
      } else {
        SearchExploreSettingsStore.cachedSettings.exploreResultLayout = normalized;
      }
    }
    AppStorage.setOrCreate(key, normalized);
    const store = await preferences.getPreferences(context, SearchExploreSettingsStore.STORE_NAME);
    await store.put(key, normalized);
    await store.flush();
  }

  static async loadChangeSourceScope(context: Context): Promise<ChangeSourceScope> {
    if (SearchExploreSettingsStore.changeSourceScope) {
      return SearchExploreSettingsStore.cloneChangeSourceScope(SearchExploreSettingsStore.changeSourceScope);
    }
    const store = await preferences.getPreferences(context, SearchExploreSettingsStore.STORE_NAME);
    const scope = new ChangeSourceScope();
    const mode = await SearchExploreSettingsStore.getString(
      store, SearchExploreSettingsStore.KEY_CHANGE_SOURCE_SCOPE_MODE, SearchExploreSettingsStore.CHANGE_SOURCE_SCOPE_ALL);
    const raw = await SearchExploreSettingsStore.getString(store, SearchExploreSettingsStore.KEY_CHANGE_SOURCE_SCOPE_GROUPS, '');
    scope.groups = SearchExploreSettingsStore.decodeGroups(raw);
    scope.mode = mode === SearchExploreSettingsStore.CHANGE_SOURCE_SCOPE_GROUP && scope.groups.length > 0 ?
      SearchExploreSettingsStore.CHANGE_SOURCE_SCOPE_GROUP : SearchExploreSettingsStore.CHANGE_SOURCE_SCOPE_ALL;
    SearchExploreSettingsStore.changeSourceScope = SearchExploreSettingsStore.cloneChangeSourceScope(scope);
    return scope;
  }

  static async saveChangeSourceScope(context: Context, scope: ChangeSourceScope): Promise<void> {
    const next = SearchExploreSettingsStore.cloneChangeSourceScope(scope);
    next.groups = SearchExploreSettingsStore.decodeGroups(JSON.stringify(next.groups));
    if (next.mode !== SearchExploreSettingsStore.CHANGE_SOURCE_SCOPE_GROUP || next.groups.length === 0) {
      next.mode = SearchExploreSettingsStore.CHANGE_SOURCE_SCOPE_ALL;
    }
    SearchExploreSettingsStore.changeSourceScope = next;
    const store = await preferences.getPreferences(context, SearchExploreSettingsStore.STORE_NAME);
    await store.put(SearchExploreSettingsStore.KEY_CHANGE_SOURCE_SCOPE_MODE, next.mode);
    // 选“全部”时分组照留，下次切回组内直接沿用。
    await store.put(SearchExploreSettingsStore.KEY_CHANGE_SOURCE_SCOPE_GROUPS, JSON.stringify(next.groups));
    await store.flush();
  }

  /** 书源管理里给分组改名时调用，换源范围记住的分组名跟着改。 */
  static async renameChangeSourceGroup(context: Context, oldName: string, newName: string): Promise<void> {
    const from = (oldName || '').trim();
    const to = (newName || '').trim();
    if (!from || !to || from === to) return;
    const scope = await SearchExploreSettingsStore.loadChangeSourceScope(context);
    if (!scope.groups.includes(from)) return;
    scope.groups = scope.groups.map((group: string): string => group === from ? to : group);
    await SearchExploreSettingsStore.saveChangeSourceScope(context, scope);
  }

  private static cloneChangeSourceScope(source: ChangeSourceScope): ChangeSourceScope {
    const scope = new ChangeSourceScope();
    scope.mode = source.mode;
    scope.groups = source.groups.slice();
    return scope;
  }

  private static decodeGroups(raw: string): string[] {
    const groups: string[] = [];
    try {
      const parsed: Object = JSON.parse(raw || '[]') as Object;
      if (!Array.isArray(parsed)) return groups;
      for (const item of parsed as Object[]) {
        const name = typeof item === 'string' ? (item as string).trim() : '';
        if (name && !groups.includes(name)) groups.push(name);
      }
    } catch (_e) {
      return groups;
    }
    return groups;
  }

  static applyToStorage(settings: SearchExploreSettings): void {
    SearchExploreSettingsStore.cachedSettings = SearchExploreSettingsStore.clone(settings);
    AppStorage.setOrCreate(SearchExploreSettingsStore.KEY_SHOW_RESULT_COVER, settings.showResultCover);
    AppStorage.setOrCreate(
      SearchExploreSettingsStore.KEY_SHOW_RESULT_COVER_BACKGROUND, settings.showResultCoverBackground);
    AppStorage.setOrCreate(
      SearchExploreSettingsStore.KEY_USE_BOOKSHELF_COVER_GALLERY,
      settings.useBookshelfCoverGallery);
    AppStorage.setOrCreate(SearchExploreSettingsStore.KEY_SHOW_RESULT_TAGS, settings.showResultTags);
    AppStorage.setOrCreate(
      SearchExploreSettingsStore.KEY_AGGREGATE_SEARCH_RESULTS,
      settings.aggregateSearchResults);
    AppStorage.setOrCreate(
      SearchExploreSettingsStore.KEY_PROMPT_ADD_TO_SHELF_ON_BACK,
      settings.promptAddToShelfOnBack);
    AppStorage.setOrCreate(SearchExploreSettingsStore.KEY_EXACT_SEARCH, settings.exactSearch);
    AppStorage.setOrCreate(
      SearchExploreSettingsStore.KEY_EXACT_SEARCH_MATCH_AUTHOR,
      settings.exactSearchMatchAuthor);
    AppStorage.setOrCreate(SearchExploreSettingsStore.KEY_SHOW_SEARCH_PROGRESS, settings.showSearchProgress);
    AppStorage.setOrCreate(SearchExploreSettingsStore.KEY_SEARCH_CONCURRENCY,
      SearchExploreSettingsStore.normalizeSearchConcurrency(settings.searchConcurrency));
    AppStorage.setOrCreate(SearchExploreSettingsStore.KEY_SELECTED_SOURCE_GROUPS, settings.selectedSourceGroupsRaw);
    AppStorage.setOrCreate(SearchExploreSettingsStore.KEY_SELECTED_SOURCE_URLS, settings.selectedSourceUrlsRaw);
    AppStorage.setOrCreate(SearchExploreSettingsStore.KEY_CUSTOM_SOURCE_URLS, settings.customSourceUrlsRaw);
    AppStorage.setOrCreate(SearchExploreSettingsStore.KEY_SCOPE_MODE, settings.scopeMode);
    AppStorage.setOrCreate(SearchExploreSettingsStore.KEY_SOURCE_SORT, settings.sourceSortRaw);
    AppStorage.setOrCreate(SearchExploreSettingsStore.KEY_EXPLORE_SOURCE_URL, settings.exploreSourceUrl);
    AppStorage.setOrCreate(SearchExploreSettingsStore.KEY_EXPLORE_PLATFORM, settings.explorePlatform);
    AppStorage.setOrCreate(SearchExploreSettingsStore.KEY_SEARCH_RESULT_LAYOUT,
      SearchExploreSettingsStore.normalizeResultLayout(settings.searchResultLayout));
    AppStorage.setOrCreate(SearchExploreSettingsStore.KEY_EXPLORE_RESULT_LAYOUT,
      SearchExploreSettingsStore.normalizeResultLayout(settings.exploreResultLayout));
  }

  static getSearchConcurrency(): number {
    const cached = SearchExploreSettingsStore.cachedSettings?.searchConcurrency;
    if (typeof cached === 'number' && cached > 0) {
      return cached;
    }
    const value = AppStorage.get<number>(SearchExploreSettingsStore.KEY_SEARCH_CONCURRENCY);
    return typeof value === 'number' && value > 0 ?
      SearchExploreSettingsStore.normalizeSearchConcurrency(value) :
      SearchExploreSettingsStore.DEFAULT_SEARCH_CONCURRENCY;
  }

  static normalizeSearchConcurrency(value: number): number {
    const parsed = Math.round(value);
    if (Number.isNaN(parsed)) {
      return SearchExploreSettingsStore.DEFAULT_SEARCH_CONCURRENCY;
    }
    return Math.max(
      SearchExploreSettingsStore.MIN_SEARCH_CONCURRENCY,
      Math.min(parsed, SearchExploreSettingsStore.MAX_SEARCH_CONCURRENCY)
    );
  }

  /** 发现页有列表、平铺、排行、榜单总览、侧栏五种；搜索层只按列表或平铺显示。 */
  private static normalizeResultLayout(value: string): string {
    return ExploreRankStyle.normalizeLayout(value);
  }

  private static async getBoolean(
    store: preferences.Preferences,
    key: string,
    fallback: boolean
  ): Promise<boolean> {
    const value = await store.get(key, fallback);
    return typeof value === 'boolean' ? value : fallback;
  }

  private static clone(source: SearchExploreSettings): SearchExploreSettings {
    const settings = new SearchExploreSettings();
    settings.showResultCover = source.showResultCover;
    settings.showResultCoverBackground = source.showResultCoverBackground !== false;
    settings.useBookshelfCoverGallery = source.useBookshelfCoverGallery;
    settings.showResultTags = source.showResultTags;
    settings.aggregateSearchResults = source.aggregateSearchResults !== false;
    settings.promptAddToShelfOnBack = source.promptAddToShelfOnBack;
    settings.exactSearch = source.exactSearch;
    settings.exactSearchMatchAuthor = source.exactSearchMatchAuthor;
    settings.showSearchProgress = source.showSearchProgress;
    settings.searchConcurrency = SearchExploreSettingsStore.normalizeSearchConcurrency(source.searchConcurrency);
    settings.selectedSourceGroupsRaw = source.selectedSourceGroupsRaw;
    settings.selectedSourceUrlsRaw = source.selectedSourceUrlsRaw || '';
    settings.customSourceUrlsRaw = source.customSourceUrlsRaw || '';
    settings.scopeMode = source.scopeMode || '';
    settings.sourceSortRaw = source.sourceSortRaw;
    settings.exploreSourceUrl = source.exploreSourceUrl;
    settings.explorePlatform = source.explorePlatform || '';
    settings.searchResultLayout = SearchExploreSettingsStore.normalizeResultLayout(source.searchResultLayout);
    settings.exploreResultLayout = SearchExploreSettingsStore.normalizeResultLayout(source.exploreResultLayout);
    return settings;
  }

  private static async getString(
    store: preferences.Preferences,
    key: string,
    fallback: string
  ): Promise<string> {
    const value = await store.get(key, fallback);
    return typeof value === 'string' ? value : fallback;
  }

  private static async getNumber(
    store: preferences.Preferences,
    key: string,
    fallback: number
  ): Promise<number> {
    const value = await store.get(key, fallback);
    if (typeof value === 'number' && !isNaN(value) && value > 0) {
      return SearchExploreSettingsStore.normalizeSearchConcurrency(value);
    }
    if (typeof value === 'string') {
      const parsed = Number(value);
      if (!Number.isNaN(parsed) && parsed > 0) {
        return SearchExploreSettingsStore.normalizeSearchConcurrency(parsed);
      }
    }
    return fallback;
  }

  private static syncFieldsChanged(left: SearchExploreSettings, right: SearchExploreSettings): boolean {
    return left.showResultCover !== right.showResultCover ||
      left.showResultCoverBackground !== right.showResultCoverBackground ||
      left.useBookshelfCoverGallery !== right.useBookshelfCoverGallery ||
      left.showResultTags !== right.showResultTags ||
      left.aggregateSearchResults !== right.aggregateSearchResults ||
      left.promptAddToShelfOnBack !== right.promptAddToShelfOnBack ||
      left.exactSearch !== right.exactSearch ||
      left.exactSearchMatchAuthor !== right.exactSearchMatchAuthor ||
      left.showSearchProgress !== right.showSearchProgress ||
      left.selectedSourceUrlsRaw !== right.selectedSourceUrlsRaw;
  }
}
