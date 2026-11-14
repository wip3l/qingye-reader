import taskpool from '@ohos.taskpool';
import { Book, BudgetedRegexReplace, JavaRegexCompat } from '@legado/sourceengine';
import { ReaderReplaceRule } from '../../utils/ReaderReplaceRuleStore';

/**
 * Pure TaskPool entry. It deliberately owns no UI or database state. Running off the UI thread is
 * not enough on its own: a long regex call here blocks shared-heap GC and the UI thread with it,
 * so rules run through BudgetedRegexReplace (short native calls plus a time budget).
 */
@Concurrent
function applyReaderRulesInTask(text: string, rulesJson: string, scopeText: string): string {
  let rules: Record<string, Object>[] = [];
  try {
    const parsed = JSON.parse(rulesJson || '[]') as Object;
    if (Array.isArray(parsed)) rules = parsed as Record<string, Object>[];
  } catch (_) {
    return text;
  }
  // Reader action markers are app-internal interaction metadata (paragraph-comment bubbles,
  // source buttons) baked into the content text. They are not book prose, and cleaning rules
  // such as `\[.*?\]` or "strip non-CJK" must never destroy them, so every rule is applied per
  // plain-text segment and the markers are reattached verbatim afterwards.
  // EPUB image markers carry percent-encoded absolute paths (local books) or image URLs (online
  // comics) — the same exemption applies: a rule matching inside an encoded payload corrupts the
  // path (e.g. "base" -> "ba色") and every comic page then fails to load.
  const hasMarkers = (text || '').indexOf('[[LEGADO_') >= 0;
  let segments: string[] = hasMarkers ?
    (text || '').split(/(\[\[LEGADO_(?:READER_ACTION(?:_V[23])?|EPUB_IMAGE):[\s\S]*?\]\])/g) : [text || ''];
  // For every action marker: whether its line holds nothing but markers. Compared before and after the rules,
  // so a bubble whose paragraph a rule deleted goes with it (Android keeps the bubble inside the line as an
  // <img>, where a whole-line rule removes both) instead of staying behind on a line of its own.
  const markerAlone = (parts: string[]): boolean[] => {
    const alone: boolean[] = [];
    const blank = new RegExp('^[\\s' + String.fromCharCode(0x200B, 0x2060, 0xFEFF) + ']*$');
    for (let si = 1; si < parts.length; si += 2) {
      let hasText = false;
      for (let left = si - 1; left >= 0 && !hasText; left -= 2) {
        const part = parts[left] || '';
        const cut = part.lastIndexOf('\n');
        hasText = !blank.test(part.substring(cut + 1));
        if (cut >= 0) break;
      }
      for (let right = si + 1; right < parts.length && !hasText; right += 2) {
        const part = parts[right] || '';
        const cut = part.indexOf('\n');
        hasText = !blank.test(cut >= 0 ? part.substring(0, cut) : part);
        if (cut >= 0) break;
      }
      alone.push(!hasText);
    }
    return alone;
  };
  const aloneBefore: boolean[] = hasMarkers ? markerAlone(segments) : [];
  const target = (scopeText || '').toLowerCase();
  const textHasCarriageReturn = (text || '').indexOf('\r') >= 0;
  // A regex running here still stalls the UI thread through shared-heap GC, so every rule gets a
  // time budget (its own timeoutMs, 3 s at most) and the whole task a hard ceiling.
  const taskDeadline = Date.now() + 8000;
  for (let index = 0; index < rules.length; index++) {
    const rule = rules[index];
    const ruleStartedAt = Date.now();
    if (ruleStartedAt >= taskDeadline) {
      console.warn('[ReaderPreprocessor] task budget exhausted, remaining rules skipped from #' + index);
      break;
    }
    if (rule['enabled'] === false || rule['applyToContent'] === false) continue;
    const pattern = String(rule['pattern'] || '');
    if (!pattern || pattern.length > 4096) continue;

    let scopeAllowed = true;
    const includeTokens = String(rule['scope'] || '').split(/[\n,，;；]+/)
      .map((value: string): string => value.trim().toLowerCase())
      .filter((value: string): boolean => !!value);
    if (includeTokens.length > 0) {
      scopeAllowed = false;
      for (let tokenIndex = 0; tokenIndex < includeTokens.length; tokenIndex++) {
        const token = includeTokens[tokenIndex];
        let matches = false;
        if (token.startsWith('/') && token.lastIndexOf('/') > 0) {
          const end = token.lastIndexOf('/');
          try { matches = new RegExp(token.substring(1, end), token.substring(end + 1)).test(target); } catch (_) {}
        } else if (token.includes('*')) {
          const escaped = token.replace(/[.+?^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '.*');
          try { matches = new RegExp(escaped, 'i').test(target); } catch (_) {}
        } else {
          matches = target.includes(token);
        }
        if (matches) {
          scopeAllowed = true;
          break;
        }
      }
    }
    if (!scopeAllowed) continue;
    const excludeTokens = String(rule['excludeScope'] || '').split(/[\n,，;；]+/)
      .map((value: string): string => value.trim().toLowerCase())
      .filter((value: string): boolean => !!value);
    let excluded = false;
    for (let tokenIndex = 0; tokenIndex < excludeTokens.length; tokenIndex++) {
      const token = excludeTokens[tokenIndex];
      let matches = false;
      if (token.startsWith('/') && token.lastIndexOf('/') > 0) {
        const end = token.lastIndexOf('/');
        try { matches = new RegExp(token.substring(1, end), token.substring(end + 1)).test(target); } catch (_) {}
      } else if (token.includes('*')) {
        const escaped = token.replace(/[.+?^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '.*');
        try { matches = new RegExp(escaped, 'i').test(target); } catch (_) {}
      } else {
        matches = target.includes(token);
      }
      if (matches) {
        excluded = true;
        break;
      }
    }
    if (excluded) continue;

    try {
      let replacement = String(rule['replacement'] || '');
      let matcher: BudgetedRegexReplace | null = null;
      let plain = '';
      let budget = Number(rule['timeoutMs']);
      if (!(budget > 0)) budget = 3000;
      const deadline = Math.min(taskDeadline, ruleStartedAt + Math.min(3000, Math.max(100, budget)));
      if (rule['isRegex'] !== false) {
        // 规则多数来自 Android 阅读，按 Java 正则方言转换后再编译，与标题净化和规则检查页保持一致。
        const conversion = JavaRegexCompat.convert(pattern, 'g');
        // Nested unbounded quantifiers are a common source of catastrophic backtracking. Imported
        // rules with this shape are skipped instead of occupying a TaskPool worker indefinitely.
        // The guard reads the converted source: a Java possessive quantifier such as `[abc]*+` is
        // already downgraded to a plain greedy one there and must not be mistaken for nesting.
        if (/(?:\([^)]*[+*][^)]*\)|\[[^\]]+\][+*])[+*{]/.test(conversion.source)) continue;
        matcher = new BudgetedRegexReplace(conversion.source, conversion.flags, textHasCarriageReturn);
        replacement = JavaRegexCompat.convertReplacement(replacement);
      } else {
        plain = pattern;
      }
      // Even indices are plain text; odd indices are captured markers kept out of rule scope.
      // A rule is applied to a copy and committed only when it finishes inside its budget, so a
      // timed-out rule leaves the text exactly as the previous rule produced it.
      const next: string[] = segments.slice();
      let timedOut = false;
      for (let si = 0; si < next.length; si += 2) {
        const segment = next[si];
        if (!segment) continue;
        if (matcher !== null) {
          const replaced = matcher.replace(segment, replacement, deadline);
          if (replaced === null) {
            timedOut = true;
            break;
          }
          next[si] = replaced;
        } else {
          next[si] = segment.split(plain).join(replacement);
        }
      }
      if (timedOut) {
        console.warn('[ReaderPreprocessor] rule timed out and was skipped: ' + String(rule['name'] || rule['id'] || index));
      } else {
        segments = next;
      }
    } catch (_) {
    }
  }
  if (hasMarkers) {
    const aloneAfter = markerAlone(segments);
    for (let index = 0; index < aloneAfter.length; index++) {
      const si = index * 2 + 1;
      if (aloneAfter[index] && !aloneBefore[index] && segments[si].startsWith('[[LEGADO_READER_ACTION')) {
        segments[si] = '';
      }
    }
  }
  return segments.join('');
}

export class ReaderContentPreprocessor {
  static hasActiveContentRules(rules: ReaderReplaceRule[]): boolean {
    return rules.some((rule: ReaderReplaceRule): boolean =>
      rule.enabled !== false && rule.applyToContent !== false && !!rule.pattern);
  }

  static async apply(text: string, rules: ReaderReplaceRule[], book: Book | null): Promise<string> {
    if (!text || !ReaderContentPreprocessor.hasActiveContentRules(rules)) return text;
    const scopeText = book ? `${book.name || ''}\n${book.author || ''}\n${book.originName || ''}\n` +
      `${book.origin || ''}\n${book.bookUrl || ''}` : '';
    try {
      const value = await taskpool.execute(applyReaderRulesInTask, text, JSON.stringify(rules), scopeText);
      return typeof value === 'string' ? value : text;
    } catch (error) {
      console.warn('[ReaderPreprocessor] TaskPool failed, keep original content:', error);
      return text;
    }
  }
}
