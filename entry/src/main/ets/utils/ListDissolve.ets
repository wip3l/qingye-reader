import { DeleteParticleBurst, DeleteParticles } from '../components/common/DeleteParticles';

/** 列表消散时喷粒子用的配置：覆盖层所在根节点、卡片元素 id、颗粒颜色，以及往覆盖层里加减颗粒的回调。 */
export class ListDissolveParticles {
  /** 覆盖层（DeleteParticleLayer）铺满的那个节点的 id，卡片位置按它换算。 */
  rootId: string = '';
  colors: string[] = [];
  elementIdOf: (key: string) => string = (key: string): string => key;
  show: (bursts: DeleteParticleBurst[]) => void = (_bursts: DeleteParticleBurst[]): void => {
  };
  hide: (ids: number[]) => void = (_ids: number[]): void => {
  };
}

/**
 * 列表删除的消散：被删的项淡出、缩小、模糊，同时在卡片区域喷出颗粒；播完再从数据里拿掉，其余项随补位动画滑上来。
 * 书架删书走 BookshelfPage 自己的流程（颗粒取封面颜色），这里给各列表共用同一套时长与数值。
 *
 * 接入方式：页面持有“正在消散的 key”数组和颗粒数组两个状态，列表项内容的根节点按 isOn 设置 opacity / scale / blur
 * 并带上 elementIdOf(key) 的 id，根层放一个 DeleteParticleLayer；删除时先 await fadeOut，再调用 commit。
 */
export class ListDissolve {
  static readonly FADE_MS: number = 380;
  static readonly CLOSE_MS: number = 280;
  /** 确认框关闭动画的时长：从弹窗里点删除时等它退场再开始，否则消散被遮罩挡住。 */
  static readonly AFTER_DIALOG_MS: number = 240;
  /** 批量删除时相邻两项错开的时间，最多错开 MAX_STAGGER_STEPS 步。 */
  static readonly STAGGER_MS: number = 30;
  static readonly MAX_STAGGER_STEPS: number = 8;
  /** 同时喷粒子的卡片数上限，更多的只淡出。 */
  static readonly MAX_BURSTS: number = 16;
  /**
   * 被拿掉的项在补位动画里还会播一段系统默认的消失转场，期间节点仍在画；消散标记要等这段结束再清，
   * 否则透明度先回到 1，已经散掉的项会重新露出一下再淡出。
   */
  static readonly CLEAR_DELAY_MS: number = 600;

  static opacity(isOn: boolean): number {
    return isOn ? 0 : 1;
  }

  static scale(isOn: boolean): ScaleOptions {
    const value = isOn ? 0.94 : 1;
    return { x: value, y: value };
  }

  static blur(isOn: boolean): number {
    return isOn ? 12 : 0;
  }

  /**
   * 依次把 keys 交给 add 加进消散数组（批量时错开一点），同时在看得见的卡片上喷粒子，等最后一项淡出完再返回。
   * add 里要给数组赋新值，状态变化才会被观察到。delayMs 用于等确认框退场。
   */
  static async fadeOut(ui: UIContext, keys: string[], add: (key: string) => void,
    particles?: ListDissolveParticles, delayMs: number = 0): Promise<void> {
    if (keys.length === 0) return;
    if (delayMs > 0) await ListDissolve.sleep(delayMs);
    if (particles) ListDissolve.emitParticles(ui, keys, particles);
    // 前几项各自错开起步，其余的合在最后一步一起加，批量删几百项时也只发起有限几次动画。
    const lastStep = ListDissolve.MAX_STAGGER_STEPS;
    for (let index = 0; index < Math.min(keys.length, lastStep); index++) {
      const key = keys[index];
      ui.animateTo({ duration: ListDissolve.FADE_MS, delay: index * ListDissolve.STAGGER_MS, curve: Curve.EaseIn }, () => {
        add(key);
      });
    }
    if (keys.length > lastStep) {
      const rest = keys.slice(lastStep);
      ui.animateTo({ duration: ListDissolve.FADE_MS, delay: lastStep * ListDissolve.STAGGER_MS, curve: Curve.EaseIn }, () => {
        for (const key of rest) add(key);
      });
    }
    const steps = Math.min(keys.length - 1, lastStep);
    await ListDissolve.sleep(ListDissolve.FADE_MS + steps * ListDissolve.STAGGER_MS);
  }

  /** 在补位动画里执行 remove，CLEAR_DELAY_MS 后再执行 clear 清掉消散标记。 */
  static commit(ui: UIContext, remove: () => void, clear: () => void): void {
    ui.animateTo({ duration: ListDissolve.CLOSE_MS, curve: Curve.FastOutSlowIn }, remove);
    setTimeout(clear, ListDissolve.CLEAR_DELAY_MS);
  }

  /** 从数组里去掉这些 key，返回新数组。 */
  static without(current: string[], keys: string[]): string[] {
    return current.filter((key: string) => keys.indexOf(key) < 0);
  }

  /** 页面按 read/write 读写自己的颗粒数组状态，生成喷粒子配置。 */
  static particles(rootId: string, colors: string[], elementIdOf: (key: string) => string,
    read: () => DeleteParticleBurst[], write: (bursts: DeleteParticleBurst[]) => void): ListDissolveParticles {
    const particles = new ListDissolveParticles();
    particles.rootId = rootId;
    particles.colors = colors;
    particles.elementIdOf = elementIdOf;
    particles.show = (bursts: DeleteParticleBurst[]): void => write([...read(), ...bursts]);
    particles.hide = (ids: number[]): void =>
      write(read().filter((burst: DeleteParticleBurst) => ids.indexOf(burst.id) < 0));
    return particles;
  }

  /** 量出看得见的卡片（相对根节点，vp），每张喷一团颗粒；滚出可见范围、量不到的跳过。 */
  private static emitParticles(ui: UIContext, keys: string[], particles: ListDissolveParticles): void {
    let rootX = 0;
    let rootY = 0;
    let rootWidth = 0;
    let rootHeight = 0;
    try {
      const root = ui.getComponentUtils().getRectangleById(particles.rootId);
      rootX = root.windowOffset.x;
      rootY = root.windowOffset.y;
      rootWidth = ui.px2vp(root.size.width);
      rootHeight = ui.px2vp(root.size.height);
    } catch (error) {
      return;
    }
    if (rootWidth <= 0 || rootHeight <= 0) return;
    const bursts: DeleteParticleBurst[] = [];
    for (const key of keys) {
      if (bursts.length >= ListDissolve.MAX_BURSTS) break;
      try {
        const rect = ui.getComponentUtils().getRectangleById(particles.elementIdOf(key));
        const x = ui.px2vp(rect.windowOffset.x - rootX);
        const y = ui.px2vp(rect.windowOffset.y - rootY);
        const width = ui.px2vp(rect.size.width);
        const height = ui.px2vp(rect.size.height);
        if (width < 4 || height < 4 || x + width <= 0 || x >= rootWidth || y + height <= 0 || y >= rootHeight) continue;
        const burst = new DeleteParticleBurst();
        burst.x = x;
        burst.y = y;
        burst.width = width;
        burst.height = height;
        bursts.push(burst);
      } catch (error) {
        // 已回收或不在当前页面的条目没有位置，只淡出。
      }
    }
    if (bursts.length === 0) return;
    const colors = ListDissolve.fillColors(particles.colors);
    const ids: number[] = [];
    for (const burst of bursts) {
      burst.id = DeleteParticles.newId();
      burst.colors = colors;
      burst.emitMs = ListDissolve.FADE_MS;
      burst.count = DeleteParticles.particleCount(burst.width, burst.height, bursts.length);
      ids.push(burst.id);
    }
    particles.show(bursts);
    setTimeout(() => particles.hide(ids), DeleteParticles.LAYER_MS);
  }

  private static fillColors(colors: string[]): string[] {
    const result = colors.length > 0 ? colors.slice(0, 3) : ['#9AA0A6'];
    while (result.length < 3) result.push(result[result.length - 1]);
    return result;
  }

  private static sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(resolve, ms);
    });
  }
}
