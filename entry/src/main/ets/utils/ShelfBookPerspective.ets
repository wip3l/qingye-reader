import { matrix4 } from '@kit.ArkUI';

/** 一本侧转的立体书投到屏幕上之后各个面的位置。长度单位 vp，矩阵里的坐标是 px。 */
export class ShelfBookShape {
  /** 投影后整本书（封面加书口）占的宽度。 */
  stageWidth: number = 0;
  /** 书的厚度，也是书口那个面变换前的宽度。 */
  depth: number = 0;
  /** 封面面板变换前的排版位置：与投影后的封面水平居中对齐，开书动画量到的位置才落在看得见的封面上。 */
  coverX: number = 0;
  sideX: number = 0;
  /** 书口面上书页的起点与宽度：侧转时两头各让出一块硬壳的厚度，平放时只在右边让出封底的飘口。 */
  pagesX: number = 0;
  pagesWidth: number = 0;
  /** 平放（不侧转）的书：两个矩阵都是单位矩阵，书页纸纹用疏密不匀的那一套。 */
  flat: boolean = false;
  /** 书页比硬壳上下各短的一截。 */
  pageInset: number = 0;
  /**
   * 投影后封面的四个角，整本书舞台的坐标（vp），左上起顺时针共 8 个数；平放的书为空。
   * 开书、关书动画据此算出整页要落到的那块（见 coverLanding）。
   */
  coverQuad: number[] = [];
  coverMatrix: matrix4.Matrix4Transit = matrix4.identity();
  sideMatrix: matrix4.Matrix4Transit = matrix4.identity();
}

/**
 * 陪伴书架的立体书：书绕竖轴侧转，右边（书口一侧）离眼睛近，封面近大远小，书口成一个往里收的面。
 * 这里只算几何：把封面和书口两个矩形各自映射到投影后的四边形，组件用 transform 套上矩阵即可。
 * 封面右边那条棱放在不缩放的平面上，其余都比它远，所以整本书不会超出原来的高度。
 */
export class ShelfBookPerspective {
  private static cache: Map<string, ShelfBookShape> = new Map<string, ShelfBookShape>();

  /** 视点到书的距离按封面宽度的倍数算，大书小书的透视感一致。 */
  private static readonly CAMERA_DISTANCE_RATIO: number = 7;

  static shape(coverWidth: number, coverHeight: number, angle: number, depthRatio: number,
    density: number): ShelfBookShape {
    const key = `${coverWidth}|${coverHeight}|${angle}|${depthRatio}|${density}`;
    const cached = ShelfBookPerspective.cache.get(key);
    if (cached) return cached;

    const radians = angle * Math.PI / 180;
    const sin = Math.sin(radians);
    const cos = Math.cos(radians);
    const depth = Math.max(6, Math.round(coverWidth * depthRatio));
    const camera = coverWidth * ShelfBookPerspective.CAMERA_DISTANCE_RATIO;

    // 以封面右棱为原点：封面左棱在左后方，书口的后棱在右后方。视点对准整本书的水平中点。
    const leftX = -coverWidth * cos;
    const backX = depth * sin;
    const leftScale = camera / (camera + coverWidth * sin);
    const backScale = camera / (camera + depth * cos);
    const centerX = (leftX + backX) / 2;
    const projectedLeft = centerX + (leftX - centerX) * leftScale;
    const projectedBack = centerX + (backX - centerX) * backScale;
    const edgeX = -projectedLeft;
    const stageWidth = projectedBack - projectedLeft;

    const shape = new ShelfBookShape();
    shape.stageWidth = Math.ceil(stageWidth);
    shape.depth = depth;
    shape.coverX = Math.round((edgeX - coverWidth) / 2);
    shape.sideX = Math.round(edgeX);
    shape.pagesX = Math.max(1.5, coverWidth * 0.02);
    shape.pagesWidth = depth - shape.pagesX * 2;
    shape.pageInset = Math.max(2, Math.round(coverWidth * 0.025));
    const half = coverHeight / 2;
    shape.coverQuad = [
      0, half - half * leftScale,
      edgeX, 0,
      edgeX, coverHeight,
      0, half + half * leftScale
    ];
    shape.coverMatrix = ShelfBookPerspective.quad(coverWidth, coverHeight, shape.coverX,
      0, leftScale, edgeX, 1, density);
    shape.sideMatrix = ShelfBookPerspective.quad(depth, coverHeight, shape.sideX,
      edgeX, 1, stageWidth, backScale, density);

    if (ShelfBookPerspective.cache.size > 512) ShelfBookPerspective.cache.clear();
    ShelfBookPerspective.cache.set(key, shape);
    return shape;
  }

  /**
   * 平放的书：封面正对着，右边露出一截书页。封底与封面齐平，书页上下各缩一截、右边让出一线封底。
   * 书口那块左端有 UNDERLAP 藏在封面下面，封面右上右下的圆角处透出的是封底的颜色。
   */
  static flat(coverWidth: number, coverHeight: number, pagesRatio: number): ShelfBookShape {
    const key = `flat|${coverWidth}|${coverHeight}|${pagesRatio}`;
    const cached = ShelfBookPerspective.cache.get(key);
    if (cached) return cached;

    const underlap = 4;
    const pages = Math.max(4, Math.round(coverWidth * pagesRatio));
    const overhang = Math.max(1.5, coverWidth * 0.016);
    const shape = new ShelfBookShape();
    shape.flat = true;
    shape.stageWidth = Math.ceil(coverWidth + pages + overhang);
    shape.depth = underlap + pages + overhang;
    shape.coverX = 0;
    shape.sideX = coverWidth - underlap;
    shape.pagesX = underlap - 1;
    shape.pagesWidth = pages + 1;
    shape.pageInset = Math.max(2.5, coverWidth * 0.028);

    if (ShelfBookPerspective.cache.size > 512) ShelfBookPerspective.cache.clear();
    ShelfBookPerspective.cache.set(key, shape);
    return shape;
  }

  /**
   * 把封面四角从整本书舞台的坐标搬到窗口里。originX/originY 是舞台左上角在窗口里的位置，stageHeight 是舞台高度，
   * lean 是整本书以舞台底边中点为轴斜靠的角度（顺时针为正，与 rotate 一致）。
   */
  static coverQuadInWindow(shape: ShelfBookShape, stageHeight: number, originX: number, originY: number,
    lean: number): number[] {
    const radians = lean * Math.PI / 180;
    const sin = Math.sin(radians);
    const cos = Math.cos(radians);
    const pivotX = shape.stageWidth / 2;
    const quad: number[] = [];
    for (let index = 0; index + 1 < shape.coverQuad.length; index += 2) {
      const dx = shape.coverQuad[index] - pivotX;
      const dy = shape.coverQuad[index + 1] - stageHeight;
      quad.push(originX + pivotX + dx * cos - dy * sin);
      quad.push(originY + stageHeight + dx * sin + dy * cos);
    }
    return quad;
  }

  /**
   * 开书、关书时整页落到的那块：与封面四边形最贴近的矩形（宽是上下两边中点的间距，高取左右两条边的平均，远的
   * 那条边比它短一点、近的长一点，差不到封面高度的百分之几），斜靠的书这块跟着转。返回 [左上角 x, 左上角 y, 宽, 高]，
   * 左上角是转过之后的位置，整页以它为轴转 lean 度即可对上。
   *
   * 不直接把整页变成四边形：带透视的矩阵交给系统后，在整窗缩到一本书这么大的幅度下画出来的形状不对（真机实测，
   * 传入的四角正确、画出的上下边反向倾斜），而缩放、平移、平面旋转是可靠的。
   */
  static coverLanding(quad: number[], lean: number): number[] {
    const leftX = (quad[0] + quad[6]) / 2;
    const leftY = (quad[1] + quad[7]) / 2;
    const rightX = (quad[2] + quad[4]) / 2;
    const rightY = (quad[3] + quad[5]) / 2;
    const width = Math.hypot(rightX - leftX, rightY - leftY);
    const height = (Math.hypot(quad[6] - quad[0], quad[7] - quad[1]) +
      Math.hypot(quad[4] - quad[2], quad[5] - quad[3])) / 2;
    const radians = lean * Math.PI / 180;
    const sin = Math.sin(radians);
    const cos = Math.cos(radians);
    // 从左边中点沿书的竖直方向往上走半个高度，就是这块矩形转过之后的左上角。
    return [leftX + sin * height / 2, leftY - cos * height / 2, width, height];
  }

  /**
   * 把 width×height 的矩形映射成左右两条竖边分别在 leftX、rightX 处、按各自远近缩放过高度的四边形。
   * originX 是这个矩形变换前的排版位置，矩阵坐标以矩形左上角为原点。
   */
  private static quad(width: number, height: number, originX: number, leftX: number, leftScale: number,
    rightX: number, rightScale: number, density: number): matrix4.Matrix4Transit {
    const half = height / 2;
    const src: matrix4.Point[] = [
      { x: 0, y: 0 },
      { x: width * density, y: 0 },
      { x: width * density, y: height * density },
      { x: 0, y: height * density }
    ];
    const dst: matrix4.Point[] = [
      { x: (leftX - originX) * density, y: (half - half * leftScale) * density },
      { x: (rightX - originX) * density, y: (half - half * rightScale) * density },
      { x: (rightX - originX) * density, y: (half + half * rightScale) * density },
      { x: (leftX - originX) * density, y: (half + half * leftScale) * density }
    ];
    return matrix4.identity().setPolyToPoly({ src: src, srcIndex: 0, dst: dst, dstIndex: 0, pointCount: 4 });
  }
}
