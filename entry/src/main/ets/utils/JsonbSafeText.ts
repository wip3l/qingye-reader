/**
 * The sync server stores payloads as PostgreSQL jsonb, which rejects U+0000 and unpaired
 * UTF-16 surrogates. They reach payloads through mis-decoded local files or book-source
 * scripts, and one such string fails the whole sync batch. Clean them before upload: drop
 * NUL, replace a lone surrogate with U+FFFD, keep valid surrogate pairs (emoji) intact.
 */
const SURROGATE_UNIT = /[\ud800-\udbff][\udc00-\udfff]|[\ud800-\udfff]/g;
// JSON.stringify writes NUL and lone surrogates as escapes; raw forms cover older runtimes.
const ESCAPED_UNSAFE = /\\u0000|\\ud[89a-f][0-9a-f]{2}/i;

export function jsonbSafeString(value: string): string {
  let result = value.indexOf('\u0000') >= 0 ? value.split('\u0000').join('') : value;
  if (/[\ud800-\udfff]/.test(result)) {
    result = result.replace(SURROGATE_UNIT, (unit: string): string => unit.length === 2 ? unit : '\ufffd');
  }
  return result;
}

function clean(value: unknown): unknown {
  if (typeof value === 'string') return jsonbSafeString(value);
  if (Array.isArray(value)) return value.map(clean);
  if (value !== null && typeof value === 'object') {
    return Object.fromEntries(Object.entries(value as Record<string, unknown>)
      .map(([key, item]): [string, unknown] => [jsonbSafeString(key), clean(item)]));
  }
  return value;
}

function hasRawUnsafe(json: string): boolean {
  if (json.indexOf('\u0000') >= 0) return true;
  if (!/[\ud800-\udfff]/.test(json)) return false;
  SURROGATE_UNIT.lastIndex = 0;
  let match: RegExpExecArray | null;
  while ((match = SURROGATE_UNIT.exec(json)) !== null) {
    if (match[0].length === 1) return true;
  }
  return false;
}

/** Returns JSON text safe for jsonb; the input is returned unchanged when already safe. */
export function jsonbSafeJson(json: string): string {
  if (!ESCAPED_UNSAFE.test(json) && !hasRawUnsafe(json)) return json;
  return JSON.stringify(clean(JSON.parse(json)));
}
