/**
 * 听书字幕的文字整理：把识别结果的 token 和时间戳还原成逐字时间，插回标点模型给的标点，再切成一行一行的字幕。
 * 不碰系统接口，Worker 和 Node 回归脚本都能直接用。
 */

/** 一行字幕，时间是章节内的绝对毫秒。 */
export class SubtitleCue {
  startMs: number = 0;
  endMs: number = 0;
  text: string = '';
}

/** 一个字（或一个标点、一个空格）和它开始的时间。 */
export class SubtitleChar {
  text: string = '';
  ms: number = 0;
  punct: boolean = false;

  constructor(text: string, ms: number, punct: boolean = false) {
    this.text = text;
    this.ms = ms;
    this.punct = punct;
  }
}

/** 句末：一定换行。 */
const STRONG_BREAK = '。！？；…!?;';
/** 句中停顿：行够长时在这里换行。 */
const WEAK_BREAK = '，、：,:';
const PUNCTUATION = STRONG_BREAK + WEAK_BREAK + '“”‘’"\'（）()《》〈〉「」『』—-·.';
/** 行至少这么多字才在逗号处换行，免得出现一两个字的碎行。 */
const MIN_WEAK_LINE = 6;
/** 超过这么多字时，在下一个停顿或空格处换行。 */
const SOFT_LINE = 18;
/** 一行最多这么多字，没有停顿也硬换行。 */
const HARD_LINE = 26;
/** 两个字之间停顿超过这么久就换行。 */
const PAUSE_BREAK_MS = 700;
/** 一行的结束时间：最后一个字开始后再留这么久。 */
const LINE_TAIL_MS = 450;

/**
 * sherpa-onnx 的字节级 BPE 用可见字符代表字节：0–31 是 U+0100 起的 32 个字符，32–126 是 ASCII 本身，
 * 127–255 是 U+0120–U+01A6 里去掉 6 个码位后的 129 个字符（见 sherpa-onnx csrc/bbpe.cc）。
 */
function buildByteTable(): Map<number, number> {
  const table = new Map<number, number>();
  for (let b = 0; b < 32; b++) table.set(0x100 + b, b);
  const skipped = [0x132, 0x133, 0x13f, 0x140, 0x149, 0x17f];
  let value = 127;
  for (let code = 0x120; code <= 0x1a6; code++) {
    if (skipped.indexOf(code) >= 0) continue;
    table.set(code, value++);
  }
  return table;
}

const BYTE_TABLE: Map<number, number> = buildByteTable();
const WORD_START = 0x2581; // ▁

function isCjk(char: string): boolean {
  const code = char.codePointAt(0) || 0;
  return (code >= 0x3400 && code <= 0x9fff) || (code >= 0xf900 && code <= 0xfaff) ||
    (code >= 0x20000 && code <= 0x2fa1f) || (code >= 0x3000 && code <= 0x303f) || (code >= 0xff00 && code <= 0xffef);
}

function isPunctuation(char: string): boolean {
  return PUNCTUATION.indexOf(char) >= 0;
}

function utf8Bytes(char: string): number[] {
  const code = char.codePointAt(0) || 0;
  if (code < 0x80) return [code];
  if (code < 0x800) return [0xc0 | (code >> 6), 0x80 | (code & 0x3f)];
  if (code < 0x10000) return [0xe0 | (code >> 12), 0x80 | ((code >> 6) & 0x3f), 0x80 | (code & 0x3f)];
  return [0xf0 | (code >> 18), 0x80 | ((code >> 12) & 0x3f), 0x80 | ((code >> 6) & 0x3f), 0x80 | (code & 0x3f)];
}

function sequenceLength(lead: number): number {
  if (lead < 0x80) return 1;
  if (lead >= 0xc2 && lead <= 0xdf) return 2;
  if (lead >= 0xe0 && lead <= 0xef) return 3;
  if (lead >= 0xf0 && lead <= 0xf4) return 4;
  return 0;
}

function decodeSequence(bytes: number[]): string {
  let code = 0;
  if (bytes.length === 1) code = bytes[0];
  else if (bytes.length === 2) code = ((bytes[0] & 0x1f) << 6) | (bytes[1] & 0x3f);
  else if (bytes.length === 3) code = ((bytes[0] & 0x0f) << 12) | ((bytes[1] & 0x3f) << 6) | (bytes[2] & 0x3f);
  else code = ((bytes[0] & 0x07) << 18) | ((bytes[1] & 0x3f) << 12) | ((bytes[2] & 0x3f) << 6) | (bytes[3] & 0x3f);
  for (let i = 1; i < bytes.length; i++) if ((bytes[i] & 0xc0) !== 0x80) return '';
  return code > 0 && code <= 0x10ffff ? String.fromCodePoint(code) : '';
}

/** 去掉中文旁边的空格，连续空格并成一个。 */
function tidySpaces(chars: SubtitleChar[]): SubtitleChar[] {
  const result: SubtitleChar[] = [];
  for (let i = 0; i < chars.length; i++) {
    const char = chars[i];
    if (char.text !== ' ') {
      result.push(char);
      continue;
    }
    const before = result.length > 0 ? result[result.length - 1].text : '';
    const after = i + 1 < chars.length ? chars[i + 1].text : '';
    // 全角标点也在 isCjk 的范围里，所以“，”后面的空格会去掉，英文逗号后面的保留。
    if (!before || !after || before === ' ' || after === ' ' || isCjk(before) || isCjk(after)) continue;
    result.push(char);
  }
  return result;
}

function visibleLength(chars: SubtitleChar[]): number {
  let count = 0;
  for (const char of chars) if (char.text !== ' ') count++;
  return count;
}

export class SubtitleText {
  /**
   * token → 逐字时间。每个字记成它第一个字节所在 token 的时间；解不出来的字节丢掉。
   * 不是字节级 BPE 的模型（token 直接是汉字）同样适用：不在表里的字符按它自己的 UTF-8 字节处理。
   */
  static decodeTokens(tokens: string[], timestamps: number[], offsetMs: number): SubtitleChar[] {
    const chars: SubtitleChar[] = [];
    let pending: number[] = [];
    let pendingMs = 0;
    let need = 0;
    for (let i = 0; i < tokens.length; i++) {
      const ms = offsetMs + Math.round((timestamps[i] ?? timestamps[timestamps.length - 1] ?? 0) * 1000);
      for (const symbol of Array.from(tokens[i] || '')) {
        const code = symbol.codePointAt(0) || 0;
        let bytes: number[];
        if (code === WORD_START) bytes = [32];
        else if (BYTE_TABLE.has(code)) bytes = [BYTE_TABLE.get(code) as number];
        else bytes = utf8Bytes(symbol);
        for (const byte of bytes) {
          if (need === 0) {
            const length = sequenceLength(byte);
            if (length === 0) continue;
            pending = [byte];
            pendingMs = ms;
            need = length - 1;
          } else if ((byte & 0xc0) === 0x80) {
            pending.push(byte);
            need--;
          } else {
            // 序列没收完就来了新的首字节：丢掉半截的，从这个字节重新开始。
            const length = sequenceLength(byte);
            need = 0;
            pending = [];
            if (length === 0) continue;
            pending = [byte];
            pendingMs = ms;
            need = length - 1;
          }
          if (need === 0 && pending.length > 0) {
            const text = decodeSequence(pending);
            pending = [];
            if (text && text !== '⁇') chars.push(new SubtitleChar(text, pendingMs));
          }
        }
      }
    }
    return tidySpaces(chars);
  }

  /** 送给标点模型的文字。 */
  static plainText(chars: SubtitleChar[]): string {
    return chars.map((char: SubtitleChar): string => char.text).join('');
  }

  /**
   * 把标点模型的输出对回逐字时间：相同的字沿用原来的时间，新插入的标点用前一个字的时间。
   * 模型改动了原字（对不上）时放弃标点，返回原样，字幕照样能显示。
   */
  static applyPunctuation(chars: SubtitleChar[], punctuated: string): SubtitleChar[] {
    if (!punctuated) return chars;
    const result: SubtitleChar[] = [];
    let j = 0;
    for (const symbol of Array.from(punctuated)) {
      if (symbol === ' ') {
        if (j < chars.length && chars[j].text === ' ') {
          result.push(chars[j]);
          j++;
        }
        continue;
      }
      // 原文这里有空格时，先看空格后面的字对不对得上；对不上才当成插入的标点，标点放在空格前面。
      let k = j;
      while (k < chars.length && chars[k].text === ' ') k++;
      if (k < chars.length && (chars[k].text === symbol || chars[k].text.toLowerCase() === symbol.toLowerCase())) {
        for (; j <= k; j++) result.push(chars[j]);
        continue;
      }
      if (isPunctuation(symbol)) {
        const ms = result.length > 0 ? result[result.length - 1].ms : (chars[j]?.ms ?? 0);
        result.push(new SubtitleChar(symbol, ms, true));
        continue;
      }
      return chars;
    }
    for (; j < chars.length; j++) result.push(chars[j]);
    return tidySpaces(result);
  }

  /** 只留开始时间落在 [startMs, endMs) 的字。窗口前后多解的那段音频只用来给边界的字补上下文。 */
  static clip(chars: SubtitleChar[], startMs: number, endMs: number): SubtitleChar[] {
    const kept = chars.filter((char: SubtitleChar): boolean => char.ms >= startMs && char.ms < endMs);
    // 开头的标点属于上一段的最后一个字。
    while (kept.length > 0 && (kept[0].punct || kept[0].text === ' ')) kept.shift();
    return kept;
  }

  /** 切行：句末必换，逗号处够长才换，停顿太久换，太长时找停顿或空格换，实在没有就硬换。 */
  static buildCues(chars: SubtitleChar[]): SubtitleCue[] {
    const cues: SubtitleCue[] = [];
    let line: SubtitleChar[] = [];
    const flush = (): void => {
      while (line.length > 0 && line[line.length - 1].text === ' ') line.pop();
      const text = line.map((char: SubtitleChar): string => char.text).join('').trim();
      const first = line.find((char: SubtitleChar): boolean => !char.punct && char.text !== ' ');
      if (text && first) {
        const last = line[line.length - 1];
        const cue = new SubtitleCue();
        cue.startMs = Math.max(0, first.ms);
        cue.endMs = last.ms + LINE_TAIL_MS;
        cue.text = text;
        cues.push(cue);
      }
      line = [];
    };
    for (let i = 0; i < chars.length; i++) {
      const char = chars[i];
      const next = i + 1 < chars.length ? chars[i + 1] : null;
      if (line.length === 0 && (char.text === ' ' || (char.punct && cues.length > 0))) {
        // 行首的标点并到上一行末尾。
        if (char.punct) cues[cues.length - 1].text += char.text;
        continue;
      }
      line.push(char);
      const length = visibleLength(line);
      const nextIsPunct = !!next && next.punct;
      if (nextIsPunct) continue;
      if (STRONG_BREAK.indexOf(char.text) >= 0) {
        flush();
      } else if (WEAK_BREAK.indexOf(char.text) >= 0 && length >= MIN_WEAK_LINE) {
        flush();
      } else if (next && next.ms - char.ms > PAUSE_BREAK_MS && length >= 2) {
        flush();
      } else if (length >= SOFT_LINE && (char.text === ' ' || (next !== null && next.text === ' ') ||
        WEAK_BREAK.indexOf(char.text) >= 0)) {
        flush();
      } else if (length >= HARD_LINE) {
        flush();
      }
    }
    flush();
    return cues;
  }

  /**
   * 合并各段的字幕：按开始时间排好，每行的结束时间不晚于下一行开始。
   * 同一时间有重复（两段重叠识别）时留先出现的。
   */
  static merge(groups: SubtitleCue[][]): SubtitleCue[] {
    const all: SubtitleCue[] = [];
    for (let g = 0; g < groups.length; g++) {
      const group = groups[g];
      for (let i = 0; i < group.length; i++) {
        const cue = group[i];
        const previous = all.length > 0 ? all[all.length - 1] : null;
        // 段与段交界处被切开的半句（“是我告”“诉你的”）接回一行。
        if (i === 0 && g > 0 && previous && SubtitleText.joinsAcrossChunks(previous, cue)) {
          const joined = new SubtitleCue();
          joined.startMs = previous.startMs;
          joined.endMs = cue.endMs;
          joined.text = previous.text + (/[A-Za-z0-9]$/.test(previous.text) && /^[A-Za-z0-9]/.test(cue.text) ? ' ' : '') +
            cue.text;
          all[all.length - 1] = joined;
          continue;
        }
        all.push(cue);
      }
    }
    all.sort((a: SubtitleCue, b: SubtitleCue): number => a.startMs - b.startMs);
    const result: SubtitleCue[] = [];
    for (const cue of all) {
      const previous = result.length > 0 ? result[result.length - 1] : null;
      if (previous && previous.startMs === cue.startMs && previous.text === cue.text) continue;
      if (previous && previous.endMs > cue.startMs) previous.endMs = Math.max(previous.startMs + 1, cue.startMs);
      const copy = new SubtitleCue();
      copy.startMs = cue.startMs;
      copy.endMs = cue.endMs;
      copy.text = cue.text;
      result.push(copy);
    }
    return result;
  }

  /**
   * 上一段的最后一行和下一段的第一行能不能接起来：上一行没有以标点结束、两行之间没有明显停顿、
   * 接起来不太长。段边界是按固定 16 秒切的，常常正好切在一句话中间。
   */
  private static joinsAcrossChunks(previous: SubtitleCue, next: SubtitleCue): boolean {
    const last = previous.text.charAt(previous.text.length - 1);
    if (!last || isPunctuation(last)) return false;
    const lastCharMs = previous.endMs - LINE_TAIL_MS;
    // 只接时间上紧挨着的后一段；传进来的段不一定按时间排好。
    if (next.startMs < lastCharMs || next.startMs - lastCharMs > PAUSE_BREAK_MS) return false;
    return (previous.text + next.text).replace(/\s/g, '').length <= HARD_LINE + 6;
  }

  /** 当前播放位置对应的行：开始时间不晚于位置的最后一行；位置在第一行之前时为 -1。 */
  static indexAt(cues: SubtitleCue[], positionMs: number): number {
    let low = 0;
    let high = cues.length - 1;
    let found = -1;
    while (low <= high) {
      const middle = (low + high) >> 1;
      if (cues[middle].startMs <= positionMs) {
        found = middle;
        low = middle + 1;
      } else {
        high = middle - 1;
      }
    }
    return found;
  }
}
