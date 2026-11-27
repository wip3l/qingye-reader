export const MIMO_VOICES: string[] = ['白桦', '苏打', '茉莉', '冰糖'];

/** A non-MiMo voice a character speaks with: an installed offline voice ('local') or a custom voice ('http'). */
export class CastVoiceRef {
  kind: string = '';
  id: string = '';
  name: string = '';
}

export class MimoRole {
  id: string = 'narrator';
  name: string = '旁白';
  aliases: string[] = [];
  voice: string = '白桦';
  locked: boolean = false;
  manual: boolean = false;
  age: string = 'unknown';
  gender: string = 'unknown';
  ageEvidence: string = '';
  preset?: MimoVoicePreset;
  /** Marked by the user as a lead; leads speak with the scheme's lead voice. */
  lead?: boolean;
  /** Offline/custom voice for multi-voice reading: a pool pick kept stable across chapters, or a manual choice. */
  castVoice?: CastVoiceRef;
  castManual?: boolean;
  /** 正文人名上色：色板下标；没有为自动分配，-1 为不上色（见 ReaderNameStyle）。 */
  nameColor?: number;
  /** 这个人单独设的人名样式（一条强调规则的 JSON）；空为跟随本书的人名样式。 */
  nameRule?: string;
}

export class MimoUnit {
  id: number = 0;
  start: number = 0;
  end: number = 0;
  text: string = '';
  roleId: string = 'narrator';
  emotion: string = '平静';
  uncertain: boolean = false;
}

export class MimoRoleProposal {
  id: string = '';
  name: string = '';
  aliases: string[] = [];
  gender: string = '';
  age: string = 'unknown';
  ageEvidence: string = '';
  ageConfidence: number = 0;
}

export class MimoAssignment {
  unitId: number = -1;
  roleId: string = 'narrator';
  emotion: string = '平静';
  confidence: number = 0;
}

export class MimoAnalysis {
  roles: MimoRoleProposal[] = [];
  assignments: MimoAssignment[] = [];
}

/** Pure policy: every byte of spoken text comes from the original, never the model. */
export class MimoPolicy {
  static split(text: string, limit: number = 100): MimoUnit[] {
    const units: MimoUnit[] = [];
    let start = 0;
    let quoted = false;
    const append = (end: number): void => {
      if (end <= start) return;
      const unit = new MimoUnit();
      unit.id = units.length;
      unit.start = start;
      unit.end = end;
      unit.text = text.slice(start, end);
      units.push(unit);
      start = end;
    };
    // 超长时往回找断点：先找句末标点，再找逗号一类，都不在后三分之二里才按字数硬切，免得切在词中间。
    // 断点后紧跟的标点（“……”“！？”）一并留在前一句。
    const softCut = (end: number): number => {
      const floor = start + Math.floor(limit / 3);
      for (const mark of [/[。！？!?…]/, /[，,、；;：:—]/]) {
        for (let k = end - 1; k >= floor; k--) {
          if (!mark.test(text[k])) continue;
          let cut = k + 1;
          while (cut < end && /[。！？!?…—，,、；;：:]/.test(text[cut])) cut++;
          return cut;
        }
      }
      return end;
    };
    for (let i = 0; i < text.length; i++) {
      const ch = text[i];
      const opening = ch === '“' || ch === '「' || ch === '『' || (ch === '"' && !quoted);
      const closing = ch === '”' || ch === '」' || ch === '』' || (ch === '"' && quoted);
      if (opening) { append(i); quoted = true; }
      if (closing) { quoted = false; append(i + 1); }
      else if (ch === '\n') {
        // 一段引语跨好几段时，中文习惯每段只有开引号、最后一段才收引号；引号状态带过换行会让后面几段
        // 都不按句号断，只能按字数硬切到句子中间。引语以段为界。
        quoted = false;
        append(i + 1);
      } else if (!quoted && /[。！？!?]/.test(ch)) {
        append(i + 1);
      } else if (i - start + 1 >= limit) {
        const cut = softCut(i + 1);
        const code = text.charCodeAt(i);
        if (cut <= i || code < 0xD800 || code > 0xDBFF) append(cut);
      }
    }
    append(text.length);
    const merged: MimoUnit[] = [];
    for (const unit of units) {
      const previous = merged.length > 0 ? merged[merged.length - 1] : undefined;
      if (previous && (!/[\p{L}\p{N}]/u.test(unit.text) || !/[\p{L}\p{N}]/u.test(previous.text))) {
        previous.end = unit.end;
        previous.text += unit.text;
      } else {
        unit.id = merged.length;
        merged.push(unit);
      }
    }
    return merged;
  }

  /**
   * A voice that is not streamed is heard only after its whole first segment has been synthesised, so a
   * long opening sentence means a long wait before anything plays. Cut the first spoken unit at a comma
   * near the front. Quoted speech is left whole so its speaker is judged on the full line.
   */
  static shortenHead(units: MimoUnit[], max: number = 40): MimoUnit[] {
    const index = units.findIndex((unit: MimoUnit): boolean => /[\p{L}\p{N}]/u.test(unit.text));
    if (index < 0 || units[index].text.length <= max) return units;
    const text = units[index].text;
    if ('“「『"'.includes(text.trimStart().charAt(0))) return units;
    let cut = -1;
    for (let position = 10; position < Math.min(text.length - 6, max); position++) {
      if ('，,、；;：:'.includes(text[position])) cut = position + 1;
    }
    if (cut < 0) return units;
    const head = new MimoUnit();
    head.start = units[index].start; head.end = head.start + cut; head.text = text.slice(0, cut);
    const tail = new MimoUnit();
    tail.start = head.end; tail.end = units[index].end; tail.text = text.slice(cut);
    const result = units.slice(0, index).concat([head, tail], units.slice(index + 1));
    result.forEach((unit: MimoUnit, id: number): void => { unit.id = id; });
    return result;
  }

  static validate(result: MimoAnalysis, units: MimoUnit[]): void {
    if (!result || !Array.isArray(result.assignments) || !Array.isArray(result.roles) ||
      result.roles.length > 64 || result.assignments.length !== units.length) {
      throw new Error('角色分析结果不完整，请重试或改用单音色朗读');
    }
    const ids: Set<number> = new Set<number>();
    for (const item of result.assignments) {
      if (!item || !Number.isInteger(item.unitId) || ids.has(item.unitId) ||
        !units.some((unit: MimoUnit): boolean => unit.id === item.unitId) ||
        typeof item.roleId !== 'string' || typeof item.confidence !== 'number' ||
        !Number.isFinite(item.confidence) || item.confidence < 0 || item.confidence > 1) {
        throw new Error('角色标注无法与原文对应，请重试');
      }
      ids.add(item.unitId);
    }
    const roleIds: Set<string> = new Set<string>();
    for (const role of result.roles) {
      if (!role || typeof role.id !== 'string' || !/^[a-zA-Z0-9_-]{1,64}$/.test(role.id) ||
        roleIds.has(role.id) || typeof role.name !== 'string' || !role.name.trim() || role.name.length > 40 ||
        !Array.isArray(role.aliases) || role.aliases.length > 12 ||
        role.aliases.some((alias: string): boolean => typeof alias !== 'string' || alias.length > 40)) {
        throw new Error('角色档案格式无效，请重试');
      }
      roleIds.add(role.id);
    }
  }

  /** Analysis batches: a small first batch so the opening starts quickly, then larger ones. */
  // 第一批只有 5 句，起播不用久等；之后每批 30 句：一段来回的对话尽量落在同一批里，模型才分得清谁接谁的话。
  static batchStart(index: number): number {
    return index < 5 ? 0 : 5 + Math.floor((index - 5) / MimoPolicy.BATCH) * MimoPolicy.BATCH;
  }
  static readonly BATCH: number = 30;

  static batchEnd(start: number, total: number): number {
    return Math.min(total, start === 0 ? 5 : start + MimoPolicy.BATCH);
  }

  /**
   * 原文里写明了是谁说的对白，不必问模型：引号前紧挨着“林晚轻声说：”，或引号后紧跟着“林晚笑道。”这类说话提示。
   * 说话提示要以人物的名字或别名开头（两个字以上，取最长的那个），并且含有说话的动词；
   * 用“他”“她”指代、名字不在开头（“听见林晚说”）、几个人物同名的，都不认，留给模型判断。
   * prev / next 是这句前后紧挨着的原文。返回人物 id，认不出返回空串。
   */
  static taggedSpeaker(prev: string, unit: string, next: string, roles: MimoRole[]): string {
    if (!/^[“「『"]/.test(unit.trimStart())) return '';
    const speakerOf = (clause: string): string => {
      const text = clause.trim();
      if (!text || !MimoPolicy.SPEECH_VERB.test(text)) return '';
      let best = '';
      let bestLength = 0;
      let ambiguous = false;
      for (const role of roles) {
        if (role.id === 'narrator') continue;
        for (const name of [role.name].concat(role.aliases || [])) {
          const value = (name || '').trim();
          if (value.length < 2 || !text.startsWith(value)) continue;
          if (value.length > bestLength) { best = role.id; bestLength = value.length; ambiguous = false; }
          else if (value.length === bestLength && role.id !== best) ambiguous = true;
        }
      }
      return ambiguous ? '' : best;
    };
    // 引号前：上一段以冒号或逗号收尾，取最后一个分句（“这时，林晚轻声说：” → “林晚轻声说”）。
    const before = prev.replace(/\s+$/, '');
    if (/[：:，,]$/.test(before)) {
      const clauses = before.slice(0, -1).split(/[。！？!?…\n”」』，,；;]/);
      const speaker = speakerOf(clauses[clauses.length - 1] || '');
      if (speaker) return speaker;
    }
    // 引号后：下一段不是对白、也不是在引出下一句对白（以冒号或逗号收尾），取它的第一个分句（“林晚笑道。”）。
    const after = next.replace(/^\s+/, '');
    if (after && !/^[“「『"]/.test(after) && !/[：:，,]\s*$/.test(after)) {
      const first = after.split(/[，,。！？!?：:；;…\n]/)[0];
      return speakerOf(first);
    }
    return '';
  }
  private static readonly SPEECH_VERB: RegExp =
    /说|道|问|答|喊|叫|嚷|吼|笑|叹|骂|劝|应|哭|嘀咕|低语|开口|补充|解释|追问|反问|喝|吩咐|嘟囔|喃喃|吐槽|感慨|提醒|安慰|命令|回应|回答/;

  static letters(text: string): number {
    const matches = text.match(/[\p{L}\p{N}]/gu);
    return matches ? matches.length : 0;
  }

  /**
   * Short pieces such as a speech tag ("林晚答：") get their own request only at the cost of a gap;
   * merge them into a neighbour that shares the same voice and style instead.
   */
  static canMerge(group: string, next: string): boolean {
    return group.length + next.length <= 120 && (MimoPolicy.letters(group) < 12 || MimoPolicy.letters(next) < 12);
  }

  static emotion(value: string): string {
    return ['平静', '开心', '悲伤', '愤怒', '恐惧', '惊讶', '温柔', '紧张', '低语'].includes(value) ? value : '平静';
  }

  /** Token Plan keys (personal tp-, team ttp-) only work on their dedicated host; pay-as-you-go keys (sk-) use the public API. */
  static isTokenPlan(key: string): boolean { return key.startsWith('tp-') || key.startsWith('ttp-'); }

  static endpoint(key: string): string {
    return MimoPolicy.isTokenPlan(key) ? 'https://token-plan-cn.xiaomimimo.com/v1/chat/completions' :
      'https://api.xiaomimimo.com/v1/chat/completions';
  }

  /** Pulls the human-readable reason out of an error body, for display only. */
  static errorDetail(body: string): string {
    let detail = '';
    try {
      const parsed = JSON.parse(body) as Record<string, Object>;
      const error = parsed.error;
      if (typeof error === 'string') detail = error;
      else if (error && typeof (error as Record<string, Object>).message === 'string') {
        detail = (error as Record<string, Object>).message as string;
      } else if (typeof parsed.message === 'string') detail = parsed.message as string;
    } catch (_) {}
    detail = detail.replace(/[\u0000-\u001f\u007f]+/g, ' ').trim();
    return detail.length > 120 ? detail.slice(0, 120) + '…' : detail;
  }

  static error(status: number, detail: string = '', tokenPlan: boolean = false): string {
    let message: string;
    if (status === 401) {
      message = tokenPlan ? 'Token Plan 密钥无效，或该套餐不支持此功能，可改用按量付费的 sk- 密钥' :
        'MiMo API Key 无效，请检查或更换密钥';
    } else if (status === 402) {
      message = '小米账户余额不足。即使模型限时免费，平台也可能要求账户有可用余额，请到控制台查看';
    } else if (status === 403) {
      message = 'MiMo 拒绝访问：当前地区不支持或密钥被风控，可新建密钥后重试';
    } else if (status === 404) {
      message = '当前密钥无法使用所需的 MiMo 模型，请检查账号的模型权限';
    } else if (status === 421) {
      message = '这段内容被小米审核拦截，无法合成';
    } else if (status === 429) {
      message = tokenPlan ? 'Token Plan 额度已用完或请求过快，请稍后重试' : 'MiMo 请求过快被限流，请稍后重试';
    } else if (status >= 500) {
      message = 'MiMo 服务暂时不可用，请稍后重试';
    } else if (status === 0) {
      message = 'MiMo 网络连接失败，请检查网络后重试';
    } else {
      message = `MiMo 请求未完成（HTTP ${status}），请检查账号的模型可用性`;
    }
    return detail ? `${message}（小米返回：${detail}）` : message;
  }
}

/** SSE events may span HTTP packets, contain CRLF, and carry multiple data lines. */
export class MimoSseParser {
  private pending: string = '';
  private data: string[] = [];
  push(text: string): string[] {
    this.pending += text;
    if (this.pending.length > 8 * 1024 * 1024) throw new Error('MiMo 响应超过安全大小');
    const events: string[] = [];
    let newline = this.pending.indexOf('\n');
    while (newline >= 0) {
      const line = this.pending.slice(0, newline).replace(/\r$/, '');
      this.pending = this.pending.slice(newline + 1);
      if (line === '') {
        if (this.data.length > 0) events.push(this.data.join('\n'));
        this.data = [];
      } else if (line.startsWith('data:')) {
        this.data.push(line.slice(5).replace(/^ /, ''));
      }
      newline = this.pending.indexOf('\n');
    }
    return events;
  }
  finish(): string[] { return this.push('\n\n'); }
}
/** Immutable-by-convention snapshot stored with each character. */
export class MimoVoicePreset {
  id: string = '';
  name: string = '';
  voice: string = '白桦';
  prompt: string = '';
  age: string = 'unknown';
  gender: string = 'unknown';
  revision: number = 1;
}
