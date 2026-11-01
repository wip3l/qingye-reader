/** Incremental JSON array reader: retain at most one bounded record, never the whole backup file. */
export class AndroidBackupJsonReader {
  private started: boolean = false;
  private ended: boolean = false;
  private singleObject: boolean = false;
  private needsSeparator: boolean = false;
  private allowEnd: boolean = true;
  private active: boolean = false;
  private depth: number = 0;
  private inString: boolean = false;
  private escaped: boolean = false;
  private parts: string[] = [];
  private itemLength: number = 0;
  private readonly maxItemLength: number = 8 * 1024 * 1024;

  private fileName: string;

  constructor(fileName: string) { this.fileName = fileName; }

  private invalid(): Error { return new Error(`${this.fileName} 不是完整有效的 JSON 数组或对象`); }

  private appendPart(part: string): void {
    this.itemLength += part.length;
    if (this.itemLength > this.maxItemLength) throw new Error(`${this.fileName} 单条数据过大，无法安全导入`);
    this.parts.push(part);
  }

  private finishItem(records: Record<string, Object>[]): void {
    const parsed = JSON.parse(this.parts.join('')) as Object;
    if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
      records.push(parsed as Record<string, Object>);
    }
    this.parts = [];
    this.itemLength = 0;
    this.active = false;
    this.needsSeparator = true;
    this.allowEnd = true;
  }

  append(chunk: string): Record<string, Object>[] {
    const records: Record<string, Object>[] = [];
    let partStart = this.active ? 0 : -1;
    for (let index = 0; index < chunk.length; index++) {
      const ch = chunk[index];
      if (!this.started) {
        if (ch.trim() === '' || ch.charCodeAt(0) === 0xFEFF) continue;
        this.started = true;
        if (ch === '[') continue;
        if (ch !== '{') throw this.invalid();
        this.singleObject = true;
      }
      if (this.ended) {
        if (ch.trim() !== '') throw this.invalid();
        continue;
      }
      if (!this.active) {
        if (ch.trim() === '') continue;
        if (!this.singleObject && ch === ']') {
          if (!this.allowEnd) throw this.invalid();
          this.ended = true;
          continue;
        }
        if (this.needsSeparator) {
          if (ch !== ',') throw this.invalid();
          this.needsSeparator = false;
          this.allowEnd = false;
          continue;
        }
        if (ch === ',') throw this.invalid();
        this.active = true;
        partStart = index;
      }
      if (this.inString) {
        if (this.escaped) this.escaped = false;
        else if (ch === '\\') this.escaped = true;
        else if (ch === '"') this.inString = false;
        continue;
      }
      if (ch === '"') { this.inString = true; continue; }
      if (ch === '{' || ch === '[') {
        if (++this.depth > 128) throw new Error(`${this.fileName} 数据嵌套过深，无法安全导入`);
        continue;
      }
      if ((ch === '}' || ch === ']') && this.depth > 0) {
        this.depth--;
        if (this.singleObject && this.depth === 0) {
          this.appendPart(chunk.substring(partStart, index + 1));
          this.finishItem(records);
          this.ended = true;
          partStart = -1;
        }
        continue;
      }
      if ((ch === ',' || ch === ']') && this.depth === 0) {
        this.appendPart(chunk.substring(partStart, index));
        this.finishItem(records);
        partStart = -1;
        if (ch === ']') this.ended = true;
        else { this.needsSeparator = false; this.allowEnd = false; }
      }
    }
    if (this.active) this.appendPart(chunk.substring(partStart));
    return records;
  }

  finish(): void {
    if (!this.ended || this.active || this.inString || this.depth !== 0) throw this.invalid();
  }
}
