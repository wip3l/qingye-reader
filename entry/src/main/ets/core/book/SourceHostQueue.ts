import { BookSource } from '@legado/sourceengine';

/**
 * 批量校验时给并发的工作协程分配书源：同一站点最多同时跑 perHost 个，其余站点的书源先上。
 * 同一站点的多个书源一起打过去容易触发站点限流，把本来能用的书源误判成临时错误。
 */
export class SourceHostQueue {
  private readonly hosts: string[];
  private readonly remaining: number[];
  private readonly active: Map<string, number> = new Map<string, number>();
  private readonly perHost: number;
  private waiters: (() => void)[] = [];

  constructor(sources: BookSource[], perHost: number) {
    this.hosts = sources.map((source: BookSource): string => SourceHostQueue.hostKey(source.bookSourceUrl || ''));
    this.remaining = sources.map((_: BookSource, index: number): number => index);
    this.perHost = Math.max(1, Math.floor(perHost));
  }

  /** 站点键：协议后的主机名（小写、去掉 www.）；不是网址的书源地址按原样各自成组。 */
  static hostKey(url: string): string {
    const value = (url || '').trim();
    const match = value.match(/^[a-z][a-z0-9+.-]*:\/\/([^/?#:@]+)/i);
    if (!match) return value.toLowerCase();
    return match[1].toLowerCase().replace(/^www\./, '');
  }

  /**
   * 取下一个可以开跑的书源下标；全部分完返回 -1。剩下的书源都卡在站点上限时等别的协程交还。
   * 拿到的下标用完必须 release。
   */
  async next(cancelled: () => boolean): Promise<number> {
    while (!cancelled()) {
      if (this.remaining.length === 0) return -1;
      const position = this.remaining.findIndex((index: number): boolean =>
        (this.active.get(this.hosts[index]) || 0) < this.perHost);
      if (position >= 0) {
        const index = this.remaining.splice(position, 1)[0];
        const host = this.hosts[index];
        this.active.set(host, (this.active.get(host) || 0) + 1);
        return index;
      }
      // 能走到这里说明有站点正被占着，占用的协程收尾时一定会 release 把这里叫醒。
      await new Promise<void>((resolve: () => void): void => {
        this.waiters.push(resolve);
      });
    }
    return -1;
  }

  release(index: number): void {
    const host = this.hosts[index];
    if (host === undefined) return;
    const count = (this.active.get(host) || 0) - 1;
    if (count > 0) this.active.set(host, count);
    else this.active.delete(host);
    const waiters = this.waiters;
    this.waiters = [];
    for (const wake of waiters) wake();
  }
}
