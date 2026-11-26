import { CastVoiceRef, MimoRole } from './MimoPolicy';
export { CastVoiceRef } from './MimoPolicy';

export const CAST_AGES: string[] = ['unknown', 'child', 'teen', 'young', 'middle', 'elder'];
export const CAST_AGE_LABELS: string[] = ['未标', '儿童', '少年', '青年', '中年', '老年'];
export const CAST_GENDERS: string[] = ['unknown', 'male', 'female'];
export const CAST_GENDER_LABELS: string[] = ['不限', '男', '女'];
/** Scheme slots, in the order the editor shows them. */
export const CAST_SLOTS: string[] = ['narrator', 'maleLead', 'femaleLead', 'malePool', 'femalePool', 'unknown'];
export const CAST_SLOT_LABELS: string[] = ['旁白', '男主角', '女主角', '男配角', '女配角', '性别不明'];

/** What the user said about a voice. Voices without a tag are never picked automatically. */
export class CastVoiceTag {
  key: string = '';
  gender: string = 'unknown';
  age: string = 'unknown';
  narrator: boolean = false;
}

/**
 * Narrator and the two leads have one voice each; supporting characters draw from a pool by gender.
 * An empty `unknown` means characters of unknown gender speak with the narrator's voice.
 */
export class CastScheme {
  id: string = '';
  name: string = '';
  narrator: CastVoiceRef = new CastVoiceRef();
  maleLead: CastVoiceRef = new CastVoiceRef();
  femaleLead: CastVoiceRef = new CastVoiceRef();
  malePool: CastVoiceRef[] = [];
  femalePool: CastVoiceRef[] = [];
  unknown: CastVoiceRef = new CastVoiceRef();
}

/** One saved OpenAI-compatible endpoint that can tell who is speaking. Its key lives in secure storage, by id. */
export class CastAnalysisEndpoint {
  id: string = '';
  name: string = '';
  /** Full chat-completions URL. */
  url: string = '';
  model: string = '';
  /** Passed its test with the key saved on this device. */
  verified: boolean = false;
}

/** Which text model tells who is speaking: the saved MiMo key, or one of the saved endpoints. */
export class CastAnalysisModel {
  /** Id of the endpoint in use; '' means MiMo. */
  activeId: string = '';
  endpoints: CastAnalysisEndpoint[] = [];
}

export class CastLibrary {
  enabled: boolean = false;
  analysis: CastAnalysisModel = new CastAnalysisModel();
  schemes: CastScheme[] = [];
  schemeId: string = 'default';
  tags: CastVoiceTag[] = [];
  /** Custom voices whose audio could not be decoded to PCM, so they cannot share the output stream. */
  undecodable: string[] = [];
  revision: number = 0;
}

export class CastVoiceMatch {
  ref: CastVoiceRef = new CastVoiceRef();
  /** Slot label shown beside the character, e.g. 男主角 / 女配角 / 已指定. */
  slot: string = '';
  /** `role.castVoice` was written and the cast needs saving. */
  changed: boolean = false;
}

/** Pure policy for multi-voice reading with offline and custom voices. */
export class CastVoicePolicy {
  static readonly POOL_LIMIT: number = 12;
  /** Loudness every voice is brought to: RMS of the spoken parts, about -20 dBFS. */
  static readonly TARGET_LEVEL: number = 3200;

  static key(ref: CastVoiceRef | undefined): string {
    return ref && ref.kind && ref.id ? ref.kind + ':' + ref.id : '';
  }
  static ref(kind: string, id: string, name: string): CastVoiceRef {
    const ref = new CastVoiceRef(); ref.kind = kind; ref.id = id; ref.name = name; return ref;
  }
  static clone(ref: CastVoiceRef | undefined): CastVoiceRef {
    return ref ? CastVoicePolicy.ref(ref.kind, ref.id, ref.name) : new CastVoiceRef();
  }
  static valid(ref: CastVoiceRef | undefined): boolean {
    return !!ref && (ref.kind === 'local' || ref.kind === 'http') && typeof ref.id === 'string' &&
      ref.id.length > 0 && ref.id.length <= 200 && typeof ref.name === 'string' && ref.name.length <= 80;
  }
  static sourceLabel(kind: string): string { return kind === 'local' ? '离线' : kind === 'http' ? '自定义' : ''; }
  static ageLabel(age: string): string { return CAST_AGE_LABELS[CAST_AGES.indexOf(age)] || '未标'; }
  static genderLabel(gender: string): string { return CAST_GENDER_LABELS[CAST_GENDERS.indexOf(gender)] || '不限'; }
  static tagged(tag: CastVoiceTag | undefined): boolean {
    return !!tag && (tag.gender !== 'unknown' || tag.age !== 'unknown' || tag.narrator);
  }
  static tagLabel(tag: CastVoiceTag | undefined): string {
    if (!CastVoicePolicy.tagged(tag)) return '未标';
    const parts: string[] = [];
    if (tag!.gender !== 'unknown') parts.push(CastVoicePolicy.genderLabel(tag!.gender));
    if (tag!.age !== 'unknown') parts.push(CastVoicePolicy.ageLabel(tag!.age));
    if (tag!.narrator) parts.push('旁白');
    return parts.join(' · ');
  }

  static scheme(id: string, name: string): CastScheme {
    const scheme = new CastScheme(); scheme.id = id; scheme.name = name; return scheme;
  }
  static cloneScheme(source: CastScheme): CastScheme {
    const scheme = CastVoicePolicy.scheme(source.id, source.name);
    scheme.narrator = CastVoicePolicy.clone(source.narrator);
    scheme.maleLead = CastVoicePolicy.clone(source.maleLead);
    scheme.femaleLead = CastVoicePolicy.clone(source.femaleLead);
    scheme.malePool = source.malePool.map((ref: CastVoiceRef): CastVoiceRef => CastVoicePolicy.clone(ref));
    scheme.femalePool = source.femalePool.map((ref: CastVoiceRef): CastVoiceRef => CastVoicePolicy.clone(ref));
    scheme.unknown = CastVoicePolicy.clone(source.unknown);
    return scheme;
  }
  static defaults(): CastLibrary {
    const library = new CastLibrary();
    library.schemes = [CastVoicePolicy.scheme('default', '默认方案')];
    return library;
  }
  /** Every distinct voice a scheme uses. */
  static schemeVoices(scheme: CastScheme): CastVoiceRef[] {
    const seen: Set<string> = new Set<string>();
    const result: CastVoiceRef[] = [];
    const all = [scheme.narrator, scheme.maleLead, scheme.femaleLead].concat(scheme.malePool, scheme.femalePool, [scheme.unknown]);
    for (const ref of all) {
      const key = CastVoicePolicy.key(ref);
      if (!key || seen.has(key)) continue;
      seen.add(key); result.push(ref);
    }
    return result;
  }

  private static one(value: CastVoiceRef | undefined): CastVoiceRef {
    return CastVoicePolicy.valid(value) ? CastVoicePolicy.clone(value) : new CastVoiceRef();
  }
  private static pool(value: CastVoiceRef[] | undefined): CastVoiceRef[] {
    const seen: Set<string> = new Set<string>();
    const result: CastVoiceRef[] = [];
    for (const ref of Array.isArray(value) ? value : []) {
      if (!CastVoicePolicy.valid(ref) || seen.has(CastVoicePolicy.key(ref)) || result.length >= CastVoicePolicy.POOL_LIMIT) continue;
      seen.add(CastVoicePolicy.key(ref)); result.push(CastVoicePolicy.clone(ref));
    }
    return result;
  }
  /** Drops anything malformed instead of failing: a damaged file must not take reading down with it. */
  static normalize(value: CastLibrary | undefined): CastLibrary {
    const result = new CastLibrary();
    if (!value || typeof value !== 'object') return CastVoicePolicy.defaults();
    result.enabled = value.enabled === true;
    result.analysis = CastVoicePolicy.normalizeAnalysis(value.analysis);
    const ids: Set<string> = new Set<string>();
    for (const item of Array.isArray(value.schemes) ? value.schemes.slice(0, 50) : []) {
      if (!item || typeof item.id !== 'string' || !item.id || item.id.length > 80 || ids.has(item.id) ||
        typeof item.name !== 'string' || !item.name.trim() || item.name.length > 30) continue;
      const scheme = CastVoicePolicy.scheme(item.id, item.name.trim());
      scheme.narrator = CastVoicePolicy.one(item.narrator);
      scheme.maleLead = CastVoicePolicy.one(item.maleLead);
      scheme.femaleLead = CastVoicePolicy.one(item.femaleLead);
      scheme.malePool = CastVoicePolicy.pool(item.malePool);
      scheme.femalePool = CastVoicePolicy.pool(item.femalePool);
      scheme.unknown = CastVoicePolicy.one(item.unknown);
      ids.add(scheme.id); result.schemes.push(scheme);
    }
    if (result.schemes.length === 0) result.schemes = CastVoicePolicy.defaults().schemes;
    result.schemeId = typeof value.schemeId === 'string' && result.schemes.some((s: CastScheme): boolean => s.id === value.schemeId) ?
      value.schemeId : result.schemes[0].id;
    const keys: Set<string> = new Set<string>();
    for (const item of Array.isArray(value.tags) ? value.tags.slice(0, 2000) : []) {
      if (!item || typeof item.key !== 'string' || !item.key || item.key.length > 220 || keys.has(item.key)) continue;
      const tag = new CastVoiceTag(); tag.key = item.key;
      tag.gender = CAST_GENDERS.includes(item.gender) ? item.gender : 'unknown';
      tag.age = CAST_AGES.includes(item.age) ? item.age : 'unknown';
      tag.narrator = item.narrator === true;
      keys.add(tag.key); result.tags.push(tag);
    }
    result.undecodable = Array.isArray(value.undecodable) ? Array.from(new Set<string>(value.undecodable.filter(
      (key: string): boolean => typeof key === 'string' && key.length > 0 && key.length <= 220))).slice(0, 500) : [];
    result.revision = Number.isInteger(value.revision) ? Math.max(0, value.revision) : 0;
    return result;
  }

  /**
   * 1 fits, 0 acceptable or unknown, -1 clashes. Analysis ages are child/teen/adult/elder; voice tags split
   * adults in two. A child and a teen voice can stand in for each other when the exact one is taken.
   */
  static ageFit(tagAge: string, roleAge: string): number {
    if (!tagAge || tagAge === 'unknown' || !roleAge || roleAge === 'unknown') return 0;
    if (roleAge === 'child') return tagAge === 'child' ? 1 : (tagAge === 'teen' ? 0 : -1);
    if (roleAge === 'teen') return tagAge === 'teen' ? 1 : (tagAge === 'child' ? 0 : -1);
    if (roleAge === 'adult') return tagAge === 'young' || tagAge === 'middle' ? 1 : -1;
    if (roleAge === 'elder') return tagAge === 'elder' ? 1 : (tagAge === 'middle' ? 0 : -1);
    return 0;
  }

  /**
   * The voice a character speaks with. Narrator, leads and unknown-gender characters follow the scheme
   * live, so editing the scheme changes them at once. Supporting characters keep the pool voice they
   * were first given (stored in `role.castVoice`) so a voice never changes mid-book; they are given a
   * new one only when theirs left the pool or can no longer be used.
   * An empty result means the scheme has no usable narrator voice.
   */
  static voiceFor(role: MimoRole, roles: MimoRole[], scheme: CastScheme,
    available: (ref: CastVoiceRef) => boolean, tagAge: (key: string) => string): CastVoiceMatch {
    const match = new CastVoiceMatch();
    const usable = (ref: CastVoiceRef | undefined): boolean => !!ref && CastVoicePolicy.key(ref).length > 0 && available(ref);
    const narrator = usable(scheme.narrator) ? scheme.narrator : new CastVoiceRef();
    if (role.castManual && role.castVoice && usable(role.castVoice)) {
      match.ref = CastVoicePolicy.clone(role.castVoice); match.slot = '已指定'; return match;
    }
    if (role.id === 'narrator') { match.ref = CastVoicePolicy.clone(narrator); match.slot = '旁白'; return match; }
    const male = role.gender === 'male', female = role.gender === 'female';
    if (!male && !female) {
      match.ref = CastVoicePolicy.clone(usable(scheme.unknown) ? scheme.unknown : narrator);
      match.slot = '性别不明'; return match;
    }
    const lead = male ? scheme.maleLead : scheme.femaleLead;
    if (role.lead && usable(lead)) {
      match.ref = CastVoicePolicy.clone(lead); match.slot = male ? '男主角' : '女主角'; return match;
    }
    match.slot = male ? '男配角' : '女配角';
    const pool = (male ? scheme.malePool : scheme.femalePool).filter(usable);
    if (pool.length === 0) { match.ref = CastVoicePolicy.clone(narrator); match.slot += ' · 暂用旁白'; return match; }
    const kept = CastVoicePolicy.key(role.castVoice);
    if (!role.castManual && kept && pool.some((ref: CastVoiceRef): boolean => CastVoicePolicy.key(ref) === kept)) {
      match.ref = CastVoicePolicy.clone(role.castVoice); return match;
    }
    const uses: Map<string, number> = new Map<string, number>();
    for (const other of roles) {
      if (other.id === role.id || other.id === 'narrator') continue;
      const key = CastVoicePolicy.key(other.castVoice);
      if (key) uses.set(key, (uses.get(key) || 0) + 1);
    }
    let best = 0;
    for (let index = 1; index < pool.length; index++) {
      const a = CastVoicePolicy.key(pool[index]), b = CastVoicePolicy.key(pool[best]);
      const useA = uses.get(a) || 0, useB = uses.get(b) || 0;
      if (useA !== useB) { if (useA < useB) best = index; continue; }
      if (CastVoicePolicy.ageFit(tagAge(a), role.age) > CastVoicePolicy.ageFit(tagAge(b), role.age)) best = index;
    }
    match.ref = CastVoicePolicy.clone(pool[best]);
    role.castVoice = CastVoicePolicy.clone(pool[best]); role.castManual = false;
    match.changed = true;
    return match;
  }

  /** Fills the empty slots of a scheme from tagged voices; used once, for a scheme the user has not set up. */
  static autoFill(scheme: CastScheme, voices: CastVoiceRef[], tagOf: (key: string) => CastVoiceTag | undefined): boolean {
    let changed = false;
    const tagged = voices.filter((ref: CastVoiceRef): boolean => CastVoicePolicy.tagged(tagOf(CastVoicePolicy.key(ref))));
    const gender = (ref: CastVoiceRef): string => tagOf(CastVoicePolicy.key(ref))!.gender;
    const taken: Set<string> = new Set<string>();
    const take = (candidates: CastVoiceRef[]): CastVoiceRef | undefined => {
      const found = candidates.find((ref: CastVoiceRef): boolean => !taken.has(CastVoicePolicy.key(ref)));
      if (found) taken.add(CastVoicePolicy.key(found));
      return found;
    };
    if (!CastVoicePolicy.key(scheme.narrator)) {
      const narrator = take(tagged.filter((ref: CastVoiceRef): boolean => tagOf(CastVoicePolicy.key(ref))!.narrator)) || take(tagged);
      if (narrator) { scheme.narrator = CastVoicePolicy.clone(narrator); changed = true; }
    } else taken.add(CastVoicePolicy.key(scheme.narrator));
    const males = tagged.filter((ref: CastVoiceRef): boolean => gender(ref) === 'male');
    const females = tagged.filter((ref: CastVoiceRef): boolean => gender(ref) === 'female');
    if (!CastVoicePolicy.key(scheme.maleLead)) {
      const lead = take(males); if (lead) { scheme.maleLead = CastVoicePolicy.clone(lead); changed = true; }
    }
    if (!CastVoicePolicy.key(scheme.femaleLead)) {
      const lead = take(females); if (lead) { scheme.femaleLead = CastVoicePolicy.clone(lead); changed = true; }
    }
    if (scheme.malePool.length === 0) {
      for (let voice = take(males); voice && scheme.malePool.length < 4; voice = take(males)) {
        scheme.malePool.push(CastVoicePolicy.clone(voice)); changed = true;
      }
    }
    if (scheme.femalePool.length === 0) {
      for (let voice = take(females); voice && scheme.femalePool.length < 4; voice = take(females)) {
        scheme.femalePool.push(CastVoicePolicy.clone(voice)); changed = true;
      }
    }
    return changed;
  }

  static readonly ENDPOINT_LIMIT: number = 20;
  /** The single endpoint saved before there was a list; its key keeps the old alias. */
  static readonly LEGACY_ENDPOINT_ID: string = 'legacy';

  private static endpoint(value: CastAnalysisEndpoint | undefined, id: string): CastAnalysisEndpoint | undefined {
    if (!value || typeof value !== 'object') return undefined;
    const url = typeof value.url === 'string' && CastVoicePolicy.validUrl(value.url) ? value.url.trim() : '';
    const model = typeof value.model === 'string' && value.model.length <= 120 ? value.model.trim() : '';
    if (!url || !model || !/^[A-Za-z0-9_-]{1,40}$/.test(id)) return undefined;
    const result = new CastAnalysisEndpoint();
    result.id = id; result.url = url; result.model = model;
    result.name = typeof value.name === 'string' ? value.name.trim().slice(0, 30) : '';
    result.verified = value.verified === true;
    return result;
  }
  /** Also reads the older single-endpoint shape `{ provider, url, model, verified }`. */
  static normalizeAnalysis(value: CastAnalysisModel | undefined): CastAnalysisModel {
    const result = new CastAnalysisModel();
    if (!value || typeof value !== 'object') return result;
    if (Array.isArray(value.endpoints)) {
      const ids: Set<string> = new Set<string>();
      for (const item of value.endpoints) {
        const endpoint = CastVoicePolicy.endpoint(item, item && typeof item.id === 'string' ? item.id : '');
        if (!endpoint || ids.has(endpoint.id) || result.endpoints.length >= CastVoicePolicy.ENDPOINT_LIMIT) continue;
        ids.add(endpoint.id); result.endpoints.push(endpoint);
      }
      if (typeof value.activeId === 'string' && ids.has(value.activeId)) result.activeId = value.activeId;
      return result;
    }
    const old = value as Object as Record<string, Object>;
    const endpoint = CastVoicePolicy.endpoint(old as Object as CastAnalysisEndpoint, CastVoicePolicy.LEGACY_ENDPOINT_ID);
    if (endpoint) {
      result.endpoints.push(endpoint);
      if (old['provider'] === 'custom') result.activeId = endpoint.id;
    }
    return result;
  }
  static activeEndpoint(analysis: CastAnalysisModel): CastAnalysisEndpoint | undefined {
    return analysis.activeId ? analysis.endpoints.find((item: CastAnalysisEndpoint): boolean => item.id === analysis.activeId) : undefined;
  }
  static endpointTitle(endpoint: CastAnalysisEndpoint): string { return endpoint.name || endpoint.model; }
  /** "api.example.com" from the endpoint URL, for the list's second line. */
  static endpointHost(url: string): string {
    const match = /^https?:\/\/([^\s/]+)/i.exec(url || '');
    return match ? match[1] : '';
  }

  static validUrl(value: string): boolean {
    const url = (value || '').trim();
    return url.length <= 500 && /^https?:\/\/[^\s/]+\/\S*$/i.test(url);
  }
  /** "https://host/v1" and "https://host/v1/" are completed to the chat-completions path; a full path is kept. */
  static completionsUrl(value: string): string {
    const url = (value || '').trim().replace(/\/+$/, '');
    if (!url) return '';
    return /\/chat\/completions$/i.test(url) ? url : url + '/chat/completions';
  }

  /**
   * Loudness of 16-bit mono speech: RMS over the 20 ms windows that are not silence, so pauses and
   * trailing silence do not make a voice look quieter than it sounds. 0 when there is no speech.
   */
  static level(pcm: ArrayBuffer, sampleRate: number): number {
    const samples = new Int16Array(pcm, 0, Math.floor(pcm.byteLength / 2));
    const window = Math.max(1, Math.round(sampleRate / 50));
    let total = 0;
    let count = 0;
    for (let start = 0; start + window <= samples.length; start += window) {
      let sum = 0;
      for (let index = start; index < start + window; index++) sum += samples[index] * samples[index];
      const mean = sum / window;
      if (mean < 200 * 200) continue;
      total += mean; count++;
    }
    return count > 0 ? Math.sqrt(total / count) : 0;
  }
  /**
   * Gain that brings a voice to the shared loudness. It is limited so one quiet clip is not blown up
   * (at most +9 dB), and so the loudest sample of this clip never clips.
   */
  static gain(level: number, peak: number): number {
    if (level <= 0) return 1;
    let gain = Math.max(0.35, Math.min(2.8, CastVoicePolicy.TARGET_LEVEL / level));
    if (peak > 0) gain = Math.min(gain, 32000 / peak);
    return Math.abs(gain - 1) < 0.05 ? 1 : gain;
  }
  static peak(pcm: ArrayBuffer): number {
    const samples = new Int16Array(pcm, 0, Math.floor(pcm.byteLength / 2));
    let peak = 0;
    for (let index = 0; index < samples.length; index++) {
      const value = samples[index] < 0 ? -samples[index] : samples[index];
      if (value > peak) peak = value;
    }
    return peak;
  }
  static amplify(pcm: ArrayBuffer, gain: number): ArrayBuffer {
    if (gain === 1) return pcm;
    const source = new Int16Array(pcm, 0, Math.floor(pcm.byteLength / 2));
    const target = new Int16Array(source.length);
    for (let index = 0; index < source.length; index++) {
      const value = Math.round(source[index] * gain);
      target[index] = value > 32767 ? 32767 : (value < -32768 ? -32768 : value);
    }
    return target.buffer;
  }
  /** Float samples in [-1, 1] (what the audio decoder returns) to 16-bit PCM. */
  static floatToPcm(samples: Float32Array): ArrayBuffer {
    const target = new Int16Array(samples.length);
    for (let index = 0; index < samples.length; index++) {
      const value = Math.round(samples[index] * 32767);
      target[index] = value > 32767 ? 32767 : (value < -32768 ? -32768 : value);
    }
    return target.buffer;
  }

  /**
   * How many requests a custom voice may have in flight, read from its concurrentRate the same way the
   * regular reader does. Empty means no limit (3 at most here). A plain number is the legado format for
   * "at least this many milliseconds between requests" and the request layer runs such voices one at a
   * time, so a plain "3" means one request at a time, not three. "n/ms" allows n requests per window,
   * so up to n (at most 3) run together.
   */
  static httpConcurrency(concurrentRate: string): number {
    const raw = (concurrentRate || '').trim();
    if (!raw || raw === '0') return 3;
    const window = raw.match(/^(\d+)\s*\/\s*(\d+)$/);
    if (window) return Math.max(1, Math.min(3, Number(window[1]) || 1));
    return 1;
  }

  /**
   * Cuts a long passage into pieces for a voice that is not streamed. Such a voice is heard only after a
   * whole request has finished, and many custom endpoints synthesise at about real-time speed: one
   * 90-character sentence then blocks playback for as long as it lasts, while three pieces of 30 keep
   * flowing. Cuts fall on punctuation only; pieces are balanced so no short tail is left on its own.
   * Text of up to `whole` characters is not cut.
   */
  static synthesisPieces(text: string, whole: number = 56, target: number = 40): string[] {
    if (text.length <= whole) return [text];
    const clauses: string[] = [];
    let start = 0;
    for (let index = 0; index < text.length; index++) {
      if (!'，,、；;：:。！？!?…'.includes(text[index])) continue;
      // Keep a run of punctuation and any closing quote with the clause it ends.
      let end = index + 1;
      while (end < text.length && '，,、；;：:。！？!?…”’」』）)'.includes(text[end])) end++;
      clauses.push(text.slice(start, end));
      start = end; index = end - 1;
    }
    if (start < text.length) clauses.push(text.slice(start));
    if (clauses.length < 2) return [text];
    const count = Math.max(2, Math.round(text.length / target));
    const size = text.length / count;
    const pieces: string[] = [];
    let current = '';
    for (const clause of clauses) {
      // Close the piece once it is nearer the even size without this clause than with it.
      if (current && pieces.length < count - 1 &&
        Math.abs(current.length - size) <= Math.abs(current.length + clause.length - size)) {
        pieces.push(current); current = '';
      }
      current += clause;
    }
    if (current) pieces.push(current);
    // A piece without anything to say (only punctuation) joins its neighbour.
    const result: string[] = [];
    for (const piece of pieces) {
      if (result.length > 0 && !/[\p{L}\p{N}]/u.test(piece)) result[result.length - 1] += piece;
      else if (result.length > 0 && !/[\p{L}\p{N}]/u.test(result[result.length - 1])) result[result.length - 1] += piece;
      else result.push(piece);
    }
    return result;
  }

  /**
   * Order in which upcoming offline segments are synthesised. The offline engine holds one model at a
   * time, so segments are grouped by model, starting with the model of the segment needed first:
   * a narrator on one model and characters on another then cost two model loads per batch instead of
   * one per sentence. `models[i]` is the model of segment i, '' for segments that are not offline.
   */
  static synthesisOrder(models: string[]): number[] {
    const order: number[] = [];
    const seen: string[] = [];
    for (const model of models) {
      if (model && !seen.includes(model)) seen.push(model);
    }
    for (const model of seen) {
      for (let index = 0; index < models.length; index++) {
        if (models[index] === model) order.push(index);
      }
    }
    return order;
  }

  /** Linear resampling of 16-bit mono PCM, so voices recorded at different rates can share one output stream. */
  static resample(pcm: ArrayBuffer, from: number, to: number): ArrayBuffer {
    const source = new Int16Array(pcm, 0, Math.floor(pcm.byteLength / 2));
    if (from === to || from <= 0 || to <= 0 || source.length === 0) return pcm.slice(0, source.length * 2);
    const length = Math.max(1, Math.round(source.length * to / from));
    const target = new Int16Array(length);
    const step = from / to;
    for (let index = 0; index < length; index++) {
      const position = index * step;
      const left = Math.min(source.length - 1, Math.floor(position));
      const right = Math.min(source.length - 1, left + 1);
      const fraction = position - left;
      target[index] = Math.round(source[left] * (1 - fraction) + source[right] * fraction);
    }
    return target.buffer;
  }
}
