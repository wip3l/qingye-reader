import { WebParseSettingsStore } from '../utils/WebParseSettingsStore';
import { insightIntent, InsightIntentEntry, InsightIntentEntryExecutor } from '@kit.AbilityKit';
import { AppIntentActions } from '../utils/AppIntentActions';

@InsightIntentEntry({
  intentName: 'SearchBook',
  domain: 'ReadingDomain',
  intentVersion: '1.0.0',
  displayName: '搜索书籍',
  displayDescription: '按书名或作者搜索书籍',
  llmDescription: '在开源轻页里按书名或作者搜索书籍，打开搜索结果页；需要用户已在“我的 › 在线阅读”开启网页解析',
  keywords: ['搜索书籍', '搜小说', '找书', 'SearchBook'],
  abilityName: 'EntryAbility',
  executeMode: [insightIntent.ExecuteMode.UI_ABILITY_FOREGROUND],
  parameters: {
    'type': 'object',
    'properties': {
      'keyword': {
        'type': 'string',
        'description': '要搜索的书名或作者'
      }
    },
    'required': ['keyword']
  }
})
export default class SearchBookIntent extends InsightIntentEntryExecutor<string> {
  keyword: string = '';

  async onExecute(): Promise<insightIntent.IntentResult<string>> {
    const keyword = (this.keyword || '').trim();
    if (!keyword || !WebParseSettingsStore.enabled()) return { code: 1, result: '' };
    AppIntentActions.search(keyword);
    return { code: 0, result: keyword };
  }
}
