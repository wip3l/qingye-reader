import { util } from '@kit.ArkTS';

/**
 * 手表与手机之间的消息格式，与 entry 模块 utils/WatchRemoteBridge.ets 一致，改动时两边一起改。
 * - 手表 → 手机：{t:'hello'}、{t:'turn', d:1|-1}
 * - 手机 → 手表：{t:'state', st, why, book, chap, page, pages, prog, nc}
 */
export enum PhoneReaderState {
  READY = 'ready',
  NO_BOOK = 'noBook',
  BUSY = 'busy',
  OFF = 'off'
}

export class PhoneState {
  st: string = PhoneReaderState.NO_BOOK;
  why: string = '';
  book: string = '';
  chap: string = '';
  page: number = 0;
  pages: number = 0;
  prog: number = 0;
  nc: boolean = false;
}

interface PhoneStateJson {
  t?: string;
  st?: string;
  why?: string;
  book?: string;
  chap?: string;
  page?: number;
  pages?: number;
  prog?: number;
  nc?: boolean;
}

interface WatchOutbound {
  t: string;
  d?: number;
}

export class WatchRemoteProtocol {
  static hello(): Uint8Array {
    const message: WatchOutbound = { t: 'hello' };
    return WatchRemoteProtocol.encode(message);
  }

  static turn(direction: number): Uint8Array {
    const message: WatchOutbound = { t: 'turn', d: direction < 0 ? -1 : 1 };
    return WatchRemoteProtocol.encode(message);
  }

  /** 不是 state 消息或解析失败时返回 null。 */
  static decodeState(content: Uint8Array): PhoneState | null {
    try {
      const json = JSON.parse(util.TextDecoder.create('utf-8').decodeToString(content)) as PhoneStateJson;
      if (json.t !== 'state') return null;
      const state = new PhoneState();
      state.st = json.st ?? PhoneReaderState.NO_BOOK;
      state.why = json.why ?? '';
      state.book = json.book ?? '';
      state.chap = json.chap ?? '';
      state.page = Number(json.page) || 0;
      state.pages = Number(json.pages) || 0;
      state.prog = Math.max(0, Math.min(1, Number(json.prog) || 0));
      state.nc = json.nc === true;
      return state;
    } catch (error) {
      return null;
    }
  }

  private static encode(message: WatchOutbound): Uint8Array {
    return new util.TextEncoder().encodeInto(JSON.stringify(message));
  }
}
