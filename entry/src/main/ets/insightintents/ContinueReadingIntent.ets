import { insightIntent, InsightIntentEntry, InsightIntentEntryExecutor } from '@kit.AbilityKit';
import { AppIntentActions } from '../utils/AppIntentActions';
import { HdsFeedback } from '../utils/HdsFeedback';

@InsightIntentEntry({
  intentName: 'ContinueReading',
  domain: 'ReadingDomain',
  intentVersion: '1.0.0',
  displayName: '继续阅读',
  displayDescription: '打开最近在读的书，或书架里指定的书，回到上次读到的位置',
  llmDescription: '打开开源轻页书架中的书并跳到上次的阅读进度。用户说出书名时打开这本书，没说书名时打开最近在读的书',
  keywords: ['继续阅读', '继续看书', '接着读', '打开小说', 'ContinueReading'],
  abilityName: 'EntryAbility',
  executeMode: [insightIntent.ExecuteMode.UI_ABILITY_FOREGROUND],
  parameters: {
    'type': 'object',
    'properties': {
      'bookName': {
        'type': 'string',
        'description': '书名，可省略；省略时打开最近在读的书'
      }
    }
  }
})
export default class ContinueReadingIntent extends InsightIntentEntryExecutor<string> {
  bookName: string = '';

  async onExecute(): Promise<insightIntent.IntentResult<string>> {
    try {
      const book = await AppIntentActions.continueReading(this.bookName || '');
      if (book) return { code: 0, result: book.name };
      HdsFeedback.showToast(this.bookName ? `书架里没有找到《${this.bookName}》` : '书架里还没有在读的书');
      return { code: 1, result: '' };
    } catch (error) {
      console.warn('[ContinueReadingIntent] failed:', error);
      return { code: 2, result: '' };
    }
  }
}
