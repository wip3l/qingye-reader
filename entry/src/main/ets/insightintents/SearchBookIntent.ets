import { insightIntent, InsightIntentEntry, InsightIntentEntryExecutor } from '@kit.AbilityKit';
import { AppIntentActions } from '../utils/AppIntentActions';

@InsightIntentEntry({
  intentName: 'SearchBook',
  domain: 'ReadingDomain',
  intentVersion: '1.0.0',
  displayName: '搜索书籍',
  displayDescription: '用已启用的书源搜索书名或作者',
  llmDescription: '在开源轻页里按书名或作者搜索小说、漫画和有声书，打开搜索结果页',
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
    if (!keyword) return { code: 1, result: '' };
    AppIntentActions.search(keyword);
    return { code: 0, result: keyword };
  }
}
