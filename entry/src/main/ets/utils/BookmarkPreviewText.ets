import { ReaderActionMarker } from '@legado/sourceengine';
import { ReaderImageMarker } from '../core/book/ReaderImageMarker';

/**
 * 书签预览文字：去掉段评/互动标记和图片标记，只留正文。
 * 旧书签保存时没清理，且被截到 90 字，末尾可能残留半截标记（没有结尾的 ]]），
 * 所以除了按完整标记剥离，还要把没闭合的标记从前缀起整段丢掉。
 */
export function bookmarkPreviewText(raw: string, maxLength: number = 0): string {
  let text = ReaderActionMarker.strip(raw || '', false);
  for (const prefix of [ReaderImageMarker.PREFIX, ReaderActionMarker.PREFIX, ReaderActionMarker.LEGACY_PREFIX,
    ReaderActionMarker.ORIGINAL_PREFIX]) {
    let start = text.indexOf(prefix);
    while (start >= 0) {
      const suffix = text.indexOf(']]', start + prefix.length);
      text = suffix >= 0 ? `${text.substring(0, start)}${text.substring(suffix + 2)}` : text.substring(0, start);
      start = text.indexOf(prefix, start);
    }
  }
  text = text.replace(/\s+/g, ' ').trim();
  if (maxLength > 0 && text.length > maxLength) {
    return `${text.substring(0, maxLength)}…`;
  }
  return text;
}
