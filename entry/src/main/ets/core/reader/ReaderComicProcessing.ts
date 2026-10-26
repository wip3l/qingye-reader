/** 每个漫画视图独立持有；只登记可见图片的任务，避免预加载和旧页面留下处理提示。 */
export class ReaderComicProcessing {
  private static nextOwner: number = 0;
  private readonly tasks: Map<number, number> = new Map<number, number>();
  private readonly listeners: Set<() => void> = new Set<() => void>();

  static owner(): number { return ++ReaderComicProcessing.nextOwner; }

  update(owner: number, enhance: boolean, translate: boolean): void {
    const flags = (enhance ? 1 : 0) | (translate ? 2 : 0);
    if ((this.tasks.get(owner) || 0) === flags) return;
    if (flags) this.tasks.set(owner, flags);
    else this.tasks.delete(owner);
    this.listeners.forEach((listener: () => void): void => listener());
  }

  message(coloring: boolean): string {
    let flags = 0;
    this.tasks.forEach((task: number): void => { flags |= task; });
    const labels: string[] = [];
    if (flags & 1) labels.push('AI 超分');
    if (coloring) labels.push('AI 着色');
    if (flags & 2) labels.push('AI 翻译');
    return labels.length ? `${labels.join(' / ')}处理中…` : '';
  }

  subscribe(listener: () => void): () => void {
    this.listeners.add(listener);
    return (): void => { this.listeners.delete(listener); };
  }
}
