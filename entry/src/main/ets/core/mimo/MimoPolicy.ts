export const MIMO_VOICES: string[] = ['白桦', '苏打', '茉莉', '冰糖'];

export class MimoRole {
  id: string = 'narrator';
  name: string = '旁白';
  aliases: string[] = [];
  voice: string = '白桦';
  locked: boolean = false;
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
    for (let i = 0; i < text.length; i++) {
      const ch = text[i];
      const opening = ch === '“' || ch === '「' || ch === '『' || (ch === '"' && !quoted);
      const closing = ch === '”' || ch === '」' || ch === '』' || (ch === '"' && quoted);
      if (opening) { append(i); quoted = true; }
      if (closing) { quoted = false; append(i + 1); }
      else if ((!quoted && /[。！？!?\n]/.test(ch)) || i - start + 1 >= limit) {
        const code = text.charCodeAt(i);
        if (code < 0xD800 || code > 0xDBFF) append(i + 1);
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

  static emotion(value: string): string {
    return ['平静', '开心', '悲伤', '愤怒', '恐惧', '惊讶', '温柔', '紧张', '低语'].includes(value) ? value : '平静';
  }

  static error(status: number): string {
    if (status === 401) return 'MiMo API Key 无效，请检查或更换密钥';
    if (status === 402) return 'MiMo 额度不足，请到小米控制台查看';
    if (status === 403) return 'MiMo 拒绝访问，请检查账号和模型权限';
    if (status === 429) return 'MiMo 请求限流或额度受限，请稍后重试并检查控制台';
    if (status >= 500) return 'MiMo 服务暂时不可用，请稍后重试';
    if (status === 0) return 'MiMo 网络连接失败，请检查网络后重试';
    return `MiMo 请求未完成（HTTP ${status}），请检查账号的模型可用性`;
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
