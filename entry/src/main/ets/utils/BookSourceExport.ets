import { BookSource, NativeSourceService } from '@legado/sourceengine';

export class BookSourceExport {
  static toObject(source: BookSource): Object {
    if (NativeSourceService.isNative(source)) return BookSourceExport.nativeObject(source);
    let result: Record<string, Object> = {};
    try {
      const parsed = JSON.parse(source.rawSourceJson || '{}') as Object;
      if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
        result = parsed as Record<string, Object>;
      }
    } catch (_) {}
    result['bookSourceUrl'] = source.bookSourceUrl;
    result['bookSourceName'] = source.bookSourceName;
    result['bookSourceType'] = source.bookSourceType;
    result['bookSourceGroup'] = source.bookSourceGroup;
    result['bookSourceComment'] = source.bookSourceComment;
    result['bookUrlPattern'] = source.bookUrlPattern;
    result['customOrder'] = source.customOrder;
    result['enabled'] = source.enabled;
    result['enabledExplore'] = source.enabledExplore;
    result['enabledCookieJar'] = source.enabledCookieJar;
    result['jsLib'] = source.jsLib;
    result['header'] = source.header;
    result['loginUrl'] = source.loginUrl;
    result['loginUi'] = source.loginUi;
    result['loginCheckJs'] = source.loginCheckJs;
    result['searchUrl'] = source.searchUrl;
    result['exploreUrl'] = source.exploreUrl;
    result['ruleSearch'] = BookSourceExport.mergeRuleForExport(result['ruleSearch'], source.searchRule);
    result['ruleExplore'] = BookSourceExport.mergeRuleForExport(result['ruleExplore'], source.exploreRule);
    result['ruleBookInfo'] = BookSourceExport.mergeRuleForExport(result['ruleBookInfo'], source.bookInfoRule);
    result['ruleToc'] = BookSourceExport.mergeRuleForExport(result['ruleToc'], source.tocRule);
    result['ruleContent'] = BookSourceExport.mergeRuleForExport(result['ruleContent'], source.contentRule);
    result['variableComment'] = source.variableComment;
    result['lastUpdateTime'] = source.lastUpdateTime;
    result['respondTime'] = source.respondTime;
    result['weight'] = source.weight;
    result['concurrentRate'] = source.concurrentRate;
    result['customButton'] = source.customButton;
    result['eventListener'] = source.eventListener;
    if (source.isPinned || result['isPinned'] !== undefined) result['isPinned'] = source.isPinned;
    if (source.isLocked || result['isLocked'] !== undefined) result['isLocked'] = source.isLocked;
    return result;
  }

  /**
   * 原生书源的定义打包在 jsLib 里，只在导入或编辑保存时写入；之后在列表里改分组、开关只改数据库列。
   * 导出和编辑页都要用列里的现值覆盖定义里的旧值，否则导出再导入（或编辑后保存）会退回旧分组。
   */
  static nativeObject(source: BookSource): Object {
    const definition = NativeSourceService.exportObject(source) as Record<string, Object>;
    const group = (source.bookSourceGroup || '').trim();
    const result: Record<string, Object> = {};
    for (const key of Object.keys(definition)) {
      if (key !== 'group') result[key] = definition[key];
      // 原位置写回，字段顺序不变；没写过分组的定义追加在末尾。
      if (key === 'group' && group) result[key] = group;
    }
    if (group && definition['group'] === undefined) result['group'] = group;
    // 定义里缺省即为开启，只在已写出或现值为关闭时才写，避免给每个导出都加上默认字段。
    if (result['enabled'] !== undefined || !source.enabled) result['enabled'] = source.enabled;
    if (result['enabledExplore'] !== undefined || !source.enabledExplore) {
      result['enabledExplore'] = source.enabledExplore;
    }
    return result;
  }

  private static mergeRuleForExport(rawRule: Object | undefined, storedRule: Object): Object {
    const merged: Record<string, Object> = {};
    if (rawRule && typeof rawRule === 'object' && !Array.isArray(rawRule)) {
      const rawRecord = rawRule as Record<string, Object>;
      for (const key of Object.keys(rawRecord)) merged[key] = rawRecord[key];
    }
    const stored = JSON.parse(JSON.stringify(storedRule || {})) as Record<string, Object>;
    for (const key of Object.keys(stored)) merged[key] = stored[key];
    return merged;
  }

}
