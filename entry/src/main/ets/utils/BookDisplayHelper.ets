import { Book } from '@legado/sourceengine';
import { CoverUrlNormalizer } from './CoverUrlNormalizer';
import { CoverFailures } from './CoverFailures';
import { GlassTagModifier, ImmersiveTagModifier } from './ImmersiveMaterialRuntime';

class CoverData {
  covers: string[] = [];
}

export class BookDisplayHelper {
  static splitTags(kind?: string, customTag?: string): string[] {
    const tags: string[] = [];
    BookDisplayHelper.appendTags(tags, kind || '');
    BookDisplayHelper.appendTags(tags, customTag || '');
    return tags;
  }

  static joinTags(tags: string[]): string {
    const cleaned: string[] = [];
    for (const tag of tags) {
      const value = tag.trim();
      if (value && !cleaned.includes(value)) {
        cleaned.push(value);
      }
    }
    return cleaned.join(',');
  }

  static getBookTags(book: Book): string[] {
    const sourceTags = BookDisplayHelper.splitTags(book.kind, book.status);
    const customTokens = BookDisplayHelper.splitTags('', book.customTag);
    const hiddenTags: string[] = [];
    const customTags: string[] = [];
    for (const token of customTokens) {
      if (token.startsWith('!')) {
        const hidden = token.substring(1).trim();
        if (hidden && !hiddenTags.includes(hidden)) {
          hiddenTags.push(hidden);
        }
      } else if (token && !customTags.includes(token)) {
        customTags.push(token);
      }
    }
    const visible: string[] = [];
    for (const tag of sourceTags) {
      if (!hiddenTags.includes(tag) && !visible.includes(tag)) {
        visible.push(tag);
      }
    }
    for (const tag of customTags) {
      if (!visible.includes(tag)) {
        visible.push(tag);
      }
    }
    return visible;
  }

  static getLastUpdateText(book: Book): string {
    return BookDisplayHelper.extractLastUpdateText(book.updateTime) ||
      BookDisplayHelper.extractLastUpdateText(book.kind);
  }

  /**
   * Shelf-facing form of the last update time, always expressed as "x分钟前 / x小时前 / x天前".
   * The raw field is written by book sources as either an absolute date ("2026-09-13 14:30") or
   * already-relative wording ("3天前"); both are normalised through the same formatter so the
   * shelf rows stay visually consistent.
   */
  static getLastUpdateRelativeText(book: Book): string {
    const raw = BookDisplayHelper.getLastUpdateText(book);
    if (!raw) {
      return '';
    }
    const timestamp = BookDisplayHelper.parseUpdateTimestamp(raw);
    return timestamp > 0 ? BookDisplayHelper.formatRelativeTime(timestamp) : raw;
  }

  private static parseUpdateTimestamp(value: string): number {
    const text = (value || '').trim();
    if (!text) {
      return 0;
    }
    const now = Date.now();
    if (text === '刚刚' || text === '今天') {
      return now;
    }
    if (text === '昨天' || text === '昨日') {
      return now - 24 * 3600 * 1000;
    }
    if (text === '前天') {
      return now - 48 * 3600 * 1000;
    }
    const relativeMatch = text.match(/^(\d+)(秒|分钟|小时|天|周|月|年)前$/);
    if (relativeMatch) {
      const amount = Number(relativeMatch[1]);
      const unitMs = BookDisplayHelper.relativeUnitMs(relativeMatch[2]);
      if (amount > 0 && unitMs > 0) {
        return now - amount * unitMs;
      }
    }
    const absoluteMatch = text.match(
      /^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})(?:[ T](\d{1,2})[:：](\d{1,2})(?:[:：](\d{1,2}))?)?$/);
    if (absoluteMatch) {
      // Local time on purpose: book sources publish wall-clock update times without a timezone.
      const parsed = new Date(
        Number(absoluteMatch[1]),
        Number(absoluteMatch[2]) - 1,
        Number(absoluteMatch[3]),
        absoluteMatch[4] ? Number(absoluteMatch[4]) : 0,
        absoluteMatch[5] ? Number(absoluteMatch[5]) : 0,
        absoluteMatch[6] ? Number(absoluteMatch[6]) : 0);
      const time = parsed.getTime();
      return Number.isNaN(time) ? 0 : time;
    }
    return 0;
  }

  private static relativeUnitMs(unit: string): number {
    if (unit === '秒') {
      return 1000;
    }
    if (unit === '分钟') {
      return 60 * 1000;
    }
    if (unit === '小时') {
      return 3600 * 1000;
    }
    if (unit === '天') {
      return 24 * 3600 * 1000;
    }
    if (unit === '周') {
      return 7 * 24 * 3600 * 1000;
    }
    if (unit === '月') {
      return 30 * 24 * 3600 * 1000;
    }
    if (unit === '年') {
      return 365 * 24 * 3600 * 1000;
    }
    return 0;
  }

  private static formatRelativeTime(timestamp: number): string {
    const elapsed = Math.max(0, Date.now() - timestamp);
    const minutes = Math.floor(elapsed / (60 * 1000));
    if (minutes < 1) {
      return '刚刚';
    }
    if (minutes < 60) {
      return `${minutes}分钟前`;
    }
    const hours = Math.floor(minutes / 60);
    if (hours < 24) {
      return `${hours}小时前`;
    }
    const days = Math.floor(hours / 24);
    if (days < 30) {
      return `${days}天前`;
    }
    const months = Math.floor(days / 30);
    if (months < 12) {
      return `${months}个月前`;
    }
    return `${Math.floor(months / 12)}年前`;
  }

  static getCover(book: Book): string {
    const covers = BookDisplayHelper.getCoverList(book);
    if (covers.length > 0) {
      return BookDisplayHelper.pickCover(covers);
    }
    return CoverUrlNormalizer.normalize(book.coverUrl);
  }

  /** 书有单独设置的封面（网络、本地上传或从图集选的）：它比图集、主题封面都优先。 */
  /** 单独设置的封面里显示得出来的那些；确认取不到的（见 CoverFailures）不算。编辑封面时要完整列表，用 decodeCoverList。 */
  static usableCustomCovers(book: Book | null | undefined): string[] {
    return book ? CoverFailures.usable(BookDisplayHelper.decodeCoverList(book.customCoverUrl)) : [];
  }

  /** 这本书有没有显示得出来的单独封面：决定取图顺序用。 */
  static hasCustomCover(book: Book | null | undefined): boolean {
    return BookDisplayHelper.usableCustomCovers(book).length > 0;
  }

  /** 这本书自己的封面（单独设置的优先，其次书源给的），已去掉确认取不到的；空表示按“没有封面”处理。 */
  static getCoverList(book: Book): string[] {
    const customCovers = BookDisplayHelper.usableCustomCovers(book);
    if (customCovers.length > 0) {
      return customCovers;
    }
    return CoverFailures.usable(BookDisplayHelper.cleanCoverList(book.coverUrl ? [book.coverUrl] : []));
  }

  static encodeCustomCovers(covers: string[]): string {
    const cleaned = BookDisplayHelper.cleanCoverList(covers);
    if (cleaned.length === 0) {
      return '';
    }
    if (cleaned.length === 1) {
      return cleaned[0];
    }
    const data = new CoverData();
    data.covers = cleaned;
    return JSON.stringify(data);
  }

  static decodeCoverList(raw?: string): string[] {
    const value = (raw || '').trim();
    if (!value) {
      return [];
    }
    if (!value.startsWith('{') && !value.startsWith('[')) {
      return BookDisplayHelper.cleanCoverList([value]);
    }
    try {
      const parsed = JSON.parse(value) as CoverData | string[];
      if (Array.isArray(parsed)) {
        return BookDisplayHelper.cleanCoverList(parsed as string[]);
      }
      return BookDisplayHelper.cleanCoverList((parsed as CoverData).covers || []);
    } catch (e) {
      return BookDisplayHelper.cleanCoverList([value]);
    }
  }

  static pickCover(covers: string[]): string {
    const cleaned = BookDisplayHelper.cleanCoverList(covers);
    if (cleaned.length === 0) {
      return '';
    }
    if (cleaned.length === 1) {
      return cleaned[0];
    }
    const index = Math.floor(Date.now() / 4000) % cleaned.length;
    return cleaned[index];
  }

  /** 没有封面时书架画的首字色块的底色（按书名取色），阅读页扉页的书封跟着用。 */
  static initialCoverColor(name: string): string {
    if (!name) return '#007DFF';
    const colors = ['#007DFF', '#E53935', '#43A047', '#EF6C00', '#8E24AA', '#00ACC1', '#D81B60', '#5E35B1'];
    let hash = 0;
    for (let i = 0; i < name.length; i++) {
      hash = name.charCodeAt(i) + ((hash << 5) - hash);
    }
    return colors[Math.abs(hash) % colors.length];
  }

  static getTagTextColor(index: number, darkMode: boolean): string {
    const dark = ['#8FB4FF', '#7DD89B', '#FFCA80', '#D6A4FF', '#80D8E8', '#FF9EA8'];
    const light = ['#3568D4', '#0A7D36', '#A15C00', '#7434A4', '#006C7A', '#B32636'];
    const palette = darkMode ? dark : light;
    return palette[index % palette.length];
  }

  /** 标签配色里绿色的序号，“已在书架”等表示正向状态的标签用它。 */
  static readonly TAG_GREEN_INDEX: number = 1;

  /** 彩色标签的沉浸光感底，配色与 getTagBackgroundColor / getTagTextColor 同序号。 */
  static getTagModifier(index: number, darkMode: boolean): ImmersiveTagModifier {
    return new ImmersiveTagModifier(BookDisplayHelper.getTagBackgroundColor(index, darkMode),
      BookDisplayHelper.getTagTextColor(index, darkMode), darkMode);
  }

  /** 放在图像背景上的白玻璃标签；文字色由调用处按 getTagTextColor 同序号设置。 */
  static getGlassTagModifier(_index: number, darkMode: boolean): GlassTagModifier {
    return new GlassTagModifier(darkMode);
  }

  static getTagBackgroundColor(index: number, darkMode: boolean): string {
    const dark = ['#1C3558', '#173B24', '#493114', '#351F49', '#173A40', '#4A2027'];
    const light = ['#EAF1FF', '#E8F5E9', '#FFF3E0', '#F3E8FF', '#E0F7FA', '#FCE8EA'];
    const palette = darkMode ? dark : light;
    return palette[index % palette.length];
  }

  private static appendTags(target: string[], raw: string): void {
    const protectedDateTimes: string[] = [];
    const protectedRaw = BookDisplayHelper.protectDateTimes(raw || '', protectedDateTimes);
    const normalized = protectedRaw
      .replace(/<[^>]+>/g, ' ')
      .replace(/&nbsp;/gi, ' ')
      .replace(/[|/;；、，,·•●▪]+/g, ',')
      .replace(/\s*[:：]\s*/g, ',')
      .replace(/\s+/g, ',');
    const pieces = normalized.split(',');
    for (const piece of pieces) {
      const tag = BookDisplayHelper.restoreDateTimes(piece.trim(), protectedDateTimes);
      // Some aggregate sources put an update timestamp, a play count or an internal id in
      // `kind`.  Those values have no label once rendered as a tag and used to show up as chips
      // such as "1928748800".  Keep meaningful short numeric values (for example a 9.4 score),
      // but do not expose an unlabelled long integer as a category.
      if (tag && !BookDisplayHelper.isUnlabelledLongNumber(tag) && !target.includes(tag)) {
        target.push(tag);
      }
    }
  }

  private static protectDateTimes(raw: string, protectedValues: string[]): string {
    const labelledDateTime = /(?:最后更新|更新时间|更新于|更新)\s*[:：]?\s*\d{4}[-/.年]\d{1,2}[-/.月]\d{1,2}(?:日)?(?:[ T]\d{1,2}[:：]\d{1,2}(?:[:：]\d{1,2})?)?/g;
    let result = raw.replace(labelledDateTime, (value: string): string =>
      BookDisplayHelper.dateTimeMarker(value, protectedValues));
    const dateTime = /\d{4}[-/.年]\d{1,2}[-/.月]\d{1,2}(?:日)?(?:[ T]\d{1,2}[:：]\d{1,2}(?:[:：]\d{1,2})?)?/g;
    result = result.replace(dateTime, (value: string): string =>
      BookDisplayHelper.dateTimeMarker(value, protectedValues));
    return result;
  }

  private static dateTimeMarker(value: string, protectedValues: string[]): string {
    const index = protectedValues.length;
    protectedValues.push(value.replace(/\s+/g, ' ').trim());
    return `\uE000${index}\uE001`;
  }

  private static restoreDateTimes(value: string, protectedValues: string[]): string {
    return value.replace(/\uE000(\d+)\uE001/g, (marker: string, rawIndex: string): string => {
      const index = Number(rawIndex);
      return index >= 0 && index < protectedValues.length ? protectedValues[index] : marker;
    }).trim();
  }

  private static isUnlabelledLongNumber(value: string): boolean {
    return /^\d{7,}$/.test(value);
  }

  private static extractLastUpdateText(raw: string): string {
    const value = raw || '';
    const labelledMatch = value.match(/(?:最后更新|更新时间|更新于|更新)\s*[:：]?\s*(\d{4}[-/.年]\d{1,2}[-/.月]\d{1,2}(?:日)?(?:\s+\d{1,2}[:：]\d{1,2}(?:[:：]\d{1,2})?)?)/);
    const dateTimeMatch = labelledMatch ? labelledMatch : value.match(/\d{4}[-/.年]\d{1,2}[-/.月]\d{1,2}(?:日)?(?:\s+\d{1,2}[:：]\d{1,2}(?:[:：]\d{1,2})?)?/);
    if (dateTimeMatch) {
      const matchText = labelledMatch ? dateTimeMatch[1] : dateTimeMatch[0];
      return matchText.replace(/[年月]/g, '-').replace(/日/g, '').replace(/：/g, ':').trim();
    }
    const relativeMatch = value.match(/(?:刚刚|\d+\s*(?:秒|分钟|小时|天|周|月|年)前|昨日|昨天|今天|前天)/);
    return relativeMatch ? relativeMatch[0].replace(/\s+/g, '') : '';
  }

  private static cleanCoverList(covers: string[]): string[] {
    const cleaned: string[] = [];
    for (const cover of covers) {
      const value = CoverUrlNormalizer.normalize(cover);
      if (value && !cleaned.includes(value)) {
        cleaned.push(value);
      }
    }
    return cleaned;
  }
}
