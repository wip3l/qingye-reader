import { effectKit } from '@kit.ArkGraphics2D';
import { image } from '@kit.ImageKit';

/** 被删卡片在覆盖层里的位置（vp）、颗粒颜色、总数和喷完所用的时间。 */
export class DeleteParticleBurst {
  id: number = 0;
  x: number = 0;
  y: number = 0;
  width: number = 0;
  height: number = 0;
  colors: string[] = [];
  count: number = 0;
  /** 颗粒在这段时间里陆续喷完，与卡片淡出同步。 */
  emitMs: number = 460;
  /** 取色用的元素 id（书架是封面）。 */
  coverId: string = '';
}

/**
 * 删除时的粒子消散。系统没有现成的消散接口，这里用 Particle 在被删卡片的区域里喷颗粒，卡片本身由调用方同时
 * 淡出、缩小、模糊。书架取被删封面截图里的主色，列表卡片底色单一，用主题的强调色与文字色。
 * 覆盖层（DeleteParticleLayer）要铺在与位置换算所用根节点相同的位置上。
 */
export class DeleteParticles {
  /** 书架卡片淡出的时长，也是默认的喷射时间；颗粒喷完后再飘一会儿才消失。 */
  static readonly FADE_MS: number = 460;
  static readonly PARTICLE_LIFETIME_MS: number = 1000;
  static readonly PARTICLE_LIFETIME_RANGE_MS: number = 400;
  /** 覆盖层保留多久后移除，要盖住最晚喷出的颗粒的寿命。 */
  static readonly LAYER_MS: number = 1900;
  /** 颗粒飘出卡片后仍要画得到：Particle 只在自身范围内绘制，四周留出余量。 */
  static readonly PAD_SIDE: number = 56;
  static readonly PAD_TOP: number = 110;
  static readonly PAD_BOTTOM: number = 36;
  /** 批量删除时同屏颗粒总数上限，书多时每张卡分到的颗粒相应减少。 */
  static readonly TOTAL_BUDGET: number = 1400;

  private static nextId: number = 1;

  static newId(): number {
    return DeleteParticles.nextId++;
  }

  /** 按面积分配颗粒：约每 120 平方 vp 一粒，单张卡 60~260 粒。 */
  static particleCount(width: number, height: number, cards: number): number {
    const byArea = Math.round(width * height / 120);
    const perCard = Math.floor(DeleteParticles.TOTAL_BUDGET / Math.max(1, cards));
    return Math.max(24, Math.min(260, byArea, perCard));
  }

  /** 截下封面取占比最高的三种颜色；截不到时用给定的兜底色。截图缩到两成，只为取色。 */
  static async pickColors(ui: UIContext, elementId: string, fallback: string[]): Promise<string[]> {
    let pixelMap: image.PixelMap | undefined = undefined;
    try {
      pixelMap = await ui.getComponentSnapshot().get(elementId, { scale: 0.2 });
      const picker = await effectKit.createColorPicker(pixelMap);
      const colors: string[] = [];
      for (const color of picker.getTopProportionColors(3)) {
        if (color) colors.push(DeleteParticles.hex(color.red, color.green, color.blue));
      }
      return DeleteParticles.fill(colors.length > 0 ? colors : fallback);
    } catch (error) {
      return DeleteParticles.fill(fallback);
    } finally {
      pixelMap?.release();
    }
  }

  private static fill(colors: string[]): string[] {
    const result = colors.length > 0 ? colors.slice(0, 3) : ['#9AA0A6'];
    while (result.length < 3) result.push(result[result.length - 1]);
    return result;
  }

  private static hex(r: number, g: number, b: number): string {
    const part = (value: number): string => Math.max(0, Math.min(255, Math.round(value))).toString(16).padStart(2, '0');
    return `#${part(r)}${part(g)}${part(b)}`;
  }
}

@Component
export struct DeleteParticleLayer {
  @Prop bursts: DeleteParticleBurst[] = [];

  build() {
    Stack() {
      ForEach(this.bursts, (burst: DeleteParticleBurst) => {
        this.burstView(burst)
      }, (burst: DeleteParticleBurst) => `${burst.id}`)
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None)
    .accessibilityLevel('no-hide-descendants')
  }

  @Builder
  burstView(burst: DeleteParticleBurst) {
    // 主色占一半，其余两种各分一部分，颗粒大小、速度、寿命都带随机，往上偏右飘散。
    Particle({
      particles: [
        {
          emitter: {
            particle: {
              type: ParticleType.POINT,
              config: { radius: 1.7 },
              count: Math.max(12, Math.round(burst.count * 0.5)),
              lifetime: DeleteParticles.PARTICLE_LIFETIME_MS,
              lifetimeRange: DeleteParticles.PARTICLE_LIFETIME_RANGE_MS
            },
            emitRate: Math.max(30, Math.round(burst.count * 0.5 * 1000 / burst.emitMs)),
            shape: ParticleEmitterShape.RECTANGLE,
            position: [DeleteParticles.PAD_SIDE, DeleteParticles.PAD_TOP],
            size: [burst.width, burst.height]
          },
          color: { range: [burst.colors[0], burst.colors[0]] },
          opacity: {
            range: [0.85, 1.0],
            updater: {
              type: ParticleUpdater.CURVE,
              config: [{ from: 1.0, to: 0.0, startMillis: 0, endMillis: 1400, curve: Curve.EaseIn }]
            }
          },
          scale: {
            range: [0.7, 1.3],
            updater: {
              type: ParticleUpdater.CURVE,
              config: [{ from: 1.0, to: 0.3, startMillis: 0, endMillis: 1400, curve: Curve.EaseIn }]
            }
          },
          velocity: { speed: [16, 96], angle: [215, 345] },
          acceleration: { speed: { range: [20, 50] }, angle: { range: [260, 300] } }
        },
        {
          emitter: {
            particle: {
              type: ParticleType.POINT,
              config: { radius: 1.3 },
              count: Math.max(8, Math.round(burst.count * 0.3)),
              lifetime: DeleteParticles.PARTICLE_LIFETIME_MS,
              lifetimeRange: DeleteParticles.PARTICLE_LIFETIME_RANGE_MS
            },
            emitRate: Math.max(20, Math.round(burst.count * 0.3 * 1000 / burst.emitMs)),
            shape: ParticleEmitterShape.RECTANGLE,
            position: [DeleteParticles.PAD_SIDE, DeleteParticles.PAD_TOP],
            size: [burst.width, burst.height]
          },
          color: { range: [burst.colors[1], burst.colors[1]] },
          opacity: {
            range: [0.75, 1.0],
            updater: {
              type: ParticleUpdater.CURVE,
              config: [{ from: 1.0, to: 0.0, startMillis: 0, endMillis: 1300, curve: Curve.EaseIn }]
            }
          },
          scale: { range: [0.6, 1.2] },
          velocity: { speed: [20, 110], angle: [220, 340] },
          acceleration: { speed: { range: [24, 56] }, angle: { range: [255, 295] } }
        },
        {
          emitter: {
            particle: {
              type: ParticleType.POINT,
              config: { radius: 1.1 },
              count: Math.max(6, Math.round(burst.count * 0.2)),
              lifetime: DeleteParticles.PARTICLE_LIFETIME_MS,
              lifetimeRange: DeleteParticles.PARTICLE_LIFETIME_RANGE_MS
            },
            emitRate: Math.max(15, Math.round(burst.count * 0.2 * 1000 / burst.emitMs)),
            shape: ParticleEmitterShape.RECTANGLE,
            position: [DeleteParticles.PAD_SIDE, DeleteParticles.PAD_TOP],
            size: [burst.width, burst.height]
          },
          color: { range: [burst.colors[2], burst.colors[2]] },
          opacity: {
            range: [0.7, 1.0],
            updater: {
              type: ParticleUpdater.CURVE,
              config: [{ from: 1.0, to: 0.0, startMillis: 0, endMillis: 1200, curve: Curve.EaseIn }]
            }
          },
          scale: { range: [0.6, 1.1] },
          velocity: { speed: [24, 120], angle: [225, 335] },
          acceleration: { speed: { range: [28, 60] }, angle: { range: [250, 290] } }
        }
      ]
    })
      .width(burst.width + DeleteParticles.PAD_SIDE * 2)
      .height(burst.height + DeleteParticles.PAD_TOP + DeleteParticles.PAD_BOTTOM)
      .position({ x: burst.x - DeleteParticles.PAD_SIDE, y: burst.y - DeleteParticles.PAD_TOP })
  }
}
