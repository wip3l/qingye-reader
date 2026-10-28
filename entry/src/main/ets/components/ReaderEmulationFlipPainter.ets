import image from '@ohos.multimedia.image';

/**
 * 卷曲起始区域，对应官方示例 EmulationFlipPage 的 DrawPosition。
 */
export enum ReaderEmulationFlipRegion {
  TOP = 0,
  MIDDLE = 1,
  BOTTOM = 2
}

interface FoldPoint {
  x: number;
  y: number;
}

interface FoldGeometry {
  a: FoldPoint;
  b: FoldPoint;
  c: FoldPoint;
  d: FoldPoint;
  e: FoldPoint;
  f: FoldPoint;
  h: FoldPoint;
  j: FoldPoint;
  k: FoldPoint;
  i: FoldPoint;
  leftShadowDistance: number;
  rightShadowDistance: number;
  topCorner: boolean;
  middleCorner: boolean;
}

/**
 * 仿真翻页（页角卷曲）绘制。
 *
 * 几何与明暗算法移植自 HarmonyOS 最佳实践《阅读器翻页》的官方示例
 * （HarmonyOS_Samples/PageFlip: EmulationFlipPage.ets + PageNodeController.ets + Constants.ets，
 * Apache-2.0）。原实现用 NodeContainer + RenderNode + @ohos.graphics.drawing 绘制；这里改用
 * 仓库既有的 Canvas 管线，几何点位、路径、阴影着色与官方保持一致。
 *
 * 单页不用官方的卷曲构造，而是平面折页（drawFlatFold）：纸边上的一个抓取点被手指拖着走，
 * 折线是抓取点与其当前位置连线的中垂线，折线外侧的纸张按折线镜像盖回当前页上。上/下部起手抓
 * 页角，中部起手抓右边缘与手指同高的点，因此拖动时手指上下移动会让折线跟着倾斜。纸背是当前页的
 * 镜像贴图加一层薄罩色，能透出背面的正文与背景图。
 *
 * 与官方示例的差异：
 * 1. 官方由手指的页角坐标驱动。本实现的翻页状态仍由进度驱动（进度 0 表示纸张平铺，1 表示完全翻出），
 *    起始区域按手指落点取上/中/下；单页拖动时抓取点跟随手指（见 dragCorner），松手后从松手位置
 *    滑到终点或弹回原处。点击翻页按进度走固定轨迹。
 * 2. 官方只在右侧卷曲；向前翻页时这里对整个画布做一次水平镜像，把折角移到左侧，仅在绘制纸张
 *    正面贴图时再抵消一次镜像，保证正文文字不被镜像。阴影旋转角仍按官方公式在原始坐标系中计算，
 *    这样镜像后不会出现错位的斜向阴影。
 * 3. 左右双页复用同一套平折几何和跟手轨迹，纸张宽度取半页，折起部分可跨过书脊。
 *    纸背使用目标对开页对应列的贴图，终点精确落在另一列，正文不镜像。
 * 4. 纸背罩色、阴影和纸边描线由当前主题的纸张底色推导，不再使用官方固定的米黄与深灰，
 *    夜间主题下折页同样能看出层次。
 */
export class ReaderEmulationFlipPainter {
  // 对应 Constants.SIXTY_PERCENT。
  private readonly cornerRadiusRatio: number = 0.6;
  // 对应 drawPathAHorizontalShadow 中的 maxShadowWidth 与 +70。
  private readonly horizontalShadowMaxWidth: number = 30;
  private readonly horizontalShadowRightExtend: number = 70;
  private readonly finishedProgress: number = 0.995;
  // 双页卷曲页角点的总行程（页宽的倍数）。纸背一直画到折线为止，折线移出左边缘需要页角点越过左边缘
  // 约一个页宽；取 2.1 时折线在进度约 0.94 处从页面顶角扫出窗口，提交目标页时不会有残留的
  // 纸条突然消失。
  private readonly travelOvershoot: number = 2.1;
  // 页角从页面角落移到手指下方的过渡距离（vp）：拖动刚开始时页角还在角上，拖过这段距离后贴住手指。
  private readonly cornerFollowRamp: number = 56;
  // 卷曲带（C/J 到折线 EH 的距离）最宽占页宽的比例；拖动较短时仍按官方的 AF/4。
  private readonly curlBandMaxRatio: number = 0.08;
  private static readonly CORNER_TRAJECTORY: number = 0;
  private static readonly CORNER_DRAGGING: number = 1;
  private static readonly CORNER_RELEASED: number = 2;
  // 页角点的来源：固定轨迹、跟随手指，或松手后从松手位置插值。
  private cornerMode: number = ReaderEmulationFlipPainter.CORNER_TRAJECTORY;
  private fingerX: number = 0;
  private fingerY: number = 0;
  // 最近一次绘制用的页角点与进度（镜像后的坐标系），松手时作为插值起点。
  private lastCornerX: number = 0;
  private lastCornerY: number = 0;
  private lastCornerProgress: number = -1;
  private releaseCornerX: number = 0;
  private releaseCornerY: number = 0;
  private releaseProgress: number = 0;
  // 拖动起手时手指的纵坐标；中部起手的平折抓取点取右边缘上的这一高度。
  private grabY: number = -1;
  // 中部起手时折线相对竖直方向的最大倾斜（tan 值），手指稍微上下晃动不会把整页斜着折过去。
  private readonly flatTiltLimit: number = 0.42;
  // 平折的抓取点终点在左边缘外 flatTravelEnd 个页宽处：折线刚好在动画结束时扫出左边缘，
  // 不像卷曲那样多走一段空行程，否则可见的后半程会被压缩得很快。
  private readonly flatTravelEnd: number = 1.02;
  // 官方样例的绘制坐标是 px，本绘制器使用 vp；阴影的绝对像素常量需要按该比例换算。
  private vpPerPx: number = 1;
  // paperColor 为官方米黄兜底色；其余颜色由 applyPalette 按主题纸色推导。
  private readonly paperColor: string = 'rgb(255,235,195)';
  private activePaperColor: string = 'rgb(255,235,195)';
  private paletteKey: string = '';
  private darkPaper: boolean = false;
  private backTintColor: string = 'rgba(186,172,145,0.78)';
  private shadowDeepColor: string = 'rgba(17,17,17,0.5)';
  private shadowLightColor: string = 'rgba(17,17,17,0)';
  private shadowBackDeepColor: string = 'rgba(17,17,17,0.53)';
  private creaseShadowColor: string = 'rgba(17,17,17,0.42)';
  private edgeShadowColor: string = 'rgba(17,17,17,0.3)';
  private paperEdgeColor: string = 'rgba(0,0,0,0.1)';
  // 平折纸背的薄罩色：夜间主题提亮一点，日间主题用纸色压淡背面的镜像文字，像纸张透墨。
  private flatBackWashColor: string = 'rgba(245,235,215,0.45)';
  private flatFlapCreaseColor: string = 'rgba(17,17,17,0.1)';
  private flatFlapShadowColor: string = 'rgba(17,17,17,0.22)';

  /**
   * 按主题纸色推导折页用色。纸背是纸色稍微压暗（夜间主题为提亮）后的不透明罩色，
   * 只隐约透出背面的镜像文字；夜间主题的阴影更重，并靠纸边描线区分层次。
   */
  private applyPalette(paperColor: string, dark: boolean): void {
    const key = `${paperColor}_${dark ? 1 : 0}`;
    if (key === this.paletteKey) {
      return;
    }
    this.paletteKey = key;
    this.darkPaper = dark;
    const rgb = this.parseColor(paperColor);
    const shift = dark ? 22 : -16;
    const tintR = Math.max(0, Math.min(255, rgb[0] + shift));
    const tintG = Math.max(0, Math.min(255, rgb[1] + shift));
    const tintB = Math.max(0, Math.min(255, rgb[2] + shift));
    this.backTintColor = `rgba(${tintR},${tintG},${tintB},0.8)`;
    this.shadowDeepColor = dark ? 'rgba(0,0,0,0.72)' : 'rgba(17,17,17,0.5)';
    this.shadowLightColor = dark ? 'rgba(0,0,0,0)' : 'rgba(17,17,17,0)';
    this.shadowBackDeepColor = dark ? 'rgba(0,0,0,0.6)' : 'rgba(17,17,17,0.45)';
    this.creaseShadowColor = dark ? 'rgba(0,0,0,0.66)' : 'rgba(17,17,17,0.42)';
    this.edgeShadowColor = dark ? 'rgba(0,0,0,0.55)' : 'rgba(17,17,17,0.3)';
    this.paperEdgeColor = dark ? 'rgba(255,255,255,0.2)' : 'rgba(0,0,0,0.12)';
    this.flatBackWashColor = dark ? 'rgba(255,255,255,0.1)' :
      `rgba(${Math.max(0, rgb[0] - 6)},${Math.max(0, rgb[1] - 6)},${Math.max(0, rgb[2] - 6)},0.45)`;
    this.flatFlapCreaseColor = dark ? 'rgba(0,0,0,0.22)' : 'rgba(17,17,17,0.1)';
    this.flatFlapShadowColor = dark ? 'rgba(0,0,0,0.4)' : 'rgba(17,17,17,0.22)';
  }

  // 支持 #RGB、#RRGGBB、#AARRGGBB 与 rgb()/rgba()；无法识别时退回官方米黄。
  private parseColor(color: string): number[] {
    const fallback: number[] = [255, 235, 195];
    const value = (color || '').trim();
    if (value.startsWith('#')) {
      let hex = value.substring(1);
      if (hex.length === 3) {
        hex = `${hex.charAt(0)}${hex.charAt(0)}${hex.charAt(1)}${hex.charAt(1)}${hex.charAt(2)}${hex.charAt(2)}`;
      }
      if (hex.length === 8) {
        hex = hex.substring(2);
      }
      if (hex.length !== 6 || !/^[0-9a-fA-F]{6}$/.test(hex)) {
        return fallback;
      }
      return [parseInt(hex.substring(0, 2), 16), parseInt(hex.substring(2, 4), 16),
        parseInt(hex.substring(4, 6), 16)];
    }
    const matched = value.match(/^rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)/i);
    if (matched) {
      return [Math.min(255, Number(matched[1])), Math.min(255, Number(matched[2])),
        Math.min(255, Number(matched[3]))];
    }
    return fallback;
  }

  /** 拖动中：记录手指在画布上的位置，之后的绘制让页角点跟随它。 */
  dragCorner(x: number, y: number): void {
    if (!Number.isFinite(x) || !Number.isFinite(y)) {
      return;
    }
    if (this.cornerMode !== ReaderEmulationFlipPainter.CORNER_DRAGGING) {
      this.grabY = y;
    }
    this.fingerX = x;
    this.fingerY = y;
    this.cornerMode = ReaderEmulationFlipPainter.CORNER_DRAGGING;
  }

  /**
   * 松手：冻结当前页角点。之后进度继续增大时页角从这里滑向翻出终点，进度减小时弹回页面角落，
   * 与松手前的画面连续。没有跟手绘制过（点击翻页等）时回到固定轨迹。
   */
  releaseCorner(): void {
    if (this.cornerMode !== ReaderEmulationFlipPainter.CORNER_DRAGGING || this.lastCornerProgress < 0) {
      this.clearCorner();
      return;
    }
    this.releaseCornerX = this.lastCornerX;
    this.releaseCornerY = this.lastCornerY;
    this.releaseProgress = this.lastCornerProgress;
    this.cornerMode = ReaderEmulationFlipPainter.CORNER_RELEASED;
  }

  /** 一次翻页结束或被取消：回到固定轨迹。 */
  clearCorner(): void {
    this.cornerMode = ReaderEmulationFlipPainter.CORNER_TRAJECTORY;
    this.lastCornerProgress = -1;
    this.grabY = -1;
  }

  /**
   * 单页平折松手后抓取点还要走的路程占全程（右边缘到终点）的比例，供页面按剩余的可见行程定补完时长。
   * 拖动的翻页进度只记手指位移，抓取点却直接贴着手指，两者差得很多，按进度算时长会让补完显得过快。
   * 没有松手位置（点击翻页等）时返回 -1。
   */
  flatRemainingFraction(width: number, leafOrigin: number = 0): number {
    if (this.cornerMode !== ReaderEmulationFlipPainter.CORNER_RELEASED || this.lastCornerProgress < 0) {
      return -1;
    }
    const safeWidth = Math.max(1, width);
    const endX = leafOrigin > 0 ? -leafOrigin : -this.flatTravelEnd * safeWidth;
    return Math.max(0, Math.min(1, (this.releaseCornerX - endX) / (safeWidth - endX)));
  }

  draw(context: CanvasRenderingContext2D, page: image.PixelMap, backPage: image.PixelMap | null,
    canvasWidth: number, canvasHeight: number, progress: number, direction: number, region: number,
    doublePage: boolean, columnWidth: number, rightOrigin: number, vpPerPx: number,
    paperColor: string, dark: boolean): void {
    this.vpPerPx = vpPerPx > 0 ? vpPerPx : 1;
    // 折页背面必须用当前主题的纸张底色，否则会和页面底色不一致，看起来像另一块纸贴在上面。
    this.activePaperColor = paperColor && paperColor.length > 0 ? paperColor : this.paperColor;
    this.applyPalette(this.activePaperColor, dark);
    const width = Math.max(1, canvasWidth);
    const height = Math.max(1, canvasHeight);
    const curl = Math.max(0, Math.min(1, progress));
    context.clearRect(0, 0, width, height);
    context.imageSmoothingEnabled = true;
    if (!page) {
      return;
    }
    if (doublePage) {
      const leafWidth = Math.max(1, columnWidth);
      if (curl <= 0 || curl >= 1) {
        const texture = curl <= 0 ? page : backPage;
        const origin = (curl <= 0 ? direction > 0 : direction < 0) ? rightOrigin : 0;
        if (texture) context.drawImage(texture, origin, 0, leafWidth, height);
        return;
      }
      this.drawFlatFold(context, page, leafWidth, height, curl, direction, region, backPage, width, rightOrigin);
      return;
    }
    if (curl <= 0.004 || curl >= this.finishedProgress) {
      // 平铺与翻出到底都不再需要卷曲层：前者直接铺满当前页，后者由底层目标页接管。
      if (curl <= 0.004) {
        context.drawImage(page, 0, 0, width, height);
      }
      return;
    }
    this.drawFlatFold(context, page, width, height, curl, direction, region);
  }

  /**
   * 单页平面折页。镜像后的坐标系里抓取点 G 总在右边缘，T 是它此刻被拖到的位置：
   * 折线为 GT 的中垂线，G 一侧的纸张抬起、露出底层目标页，并按折线镜像成纸背盖在当前页上。
   */
  private drawFlatFold(context: CanvasRenderingContext2D, page: image.PixelMap, width: number, height: number,
    curl: number, direction: number, region: number, backPage: image.PixelMap | null = null,
    spreadWidth: number = width, leafOrigin: number = 0): void {
    const doublePage = leafOrigin > 0;
    const mirrored = direction < 0;
    const grab = this.flatGrabPoint(width, height, region);
    const target = this.flatFoldTarget(width, height, curl, region, grab, mirrored, spreadWidth, leafOrigin);
    const span = Math.hypot(grab.x - target.x, grab.y - target.y);
    if (span < 0.5) {
      context.drawImage(page, mirrored ? spreadWidth - leafOrigin - width : leafOrigin, 0, width, height);
      return;
    }
    const normal: FoldPoint = { x: (grab.x - target.x) / span, y: (grab.y - target.y) / span };
    const mid: FoldPoint = { x: (grab.x + target.x) / 2, y: (grab.y + target.y) / 2 };
    const sheet: FoldPoint[] = [{ x: 0, y: 0 }, { x: width, y: 0 }, { x: width, y: height }, { x: 0, y: height }];
    const flat = this.clipHalfPlane(sheet, mid, normal, false);
    const lifted = this.clipHalfPlane(sheet, mid, normal, true);
    const flap = lifted.map((point: FoldPoint): FoldPoint => this.reflectPoint(point, mid, normal));
    const flatPath = this.polygonPath(flat);
    const liftedPath = this.polygonPath(lifted);
    const flapPath = this.polygonPath(flap);
    // 双页落地时恢复目标页原色，阴影随纸张放平消失；单页保持原有透墨效果。
    const foldLift = doublePage ? Math.sin(Math.PI * Math.max(0, Math.min(1, span / (width + leafOrigin)))) : 1;

    // 向前翻页：整体水平镜像，把右侧折角搬到左侧。镜像变换是自逆的，绘制正文贴图时再应用一次即可抵消。
    context.save();
    if (mirrored) {
      context.translate(spreadWidth, 0);
      context.scale(-1, 1);
    }
    context.translate(leafOrigin, 0);
    // 1) 尚未抬起的当前页。
    if (flat.length >= 3) {
      context.save();
      context.clip(flatPath);
      if (mirrored) {
        context.translate(width, 0);
        context.scale(-1, 1);
      }
      context.drawImage(page, 0, 0, width, height);
      context.restore();
    }
    if (lifted.length < 3) {
      context.restore();
      return;
    }
    // 2) 折线处落在目标页上的投影：贴着折线，纸翻得越开越宽。
    context.save();
    context.globalAlpha = doublePage ? foldLift * 0.55 : 1;
    const creaseShadowWidth = Math.min(width * (doublePage ? 0.12 : 0.07), span * 0.3);
    context.fillStyle = this.easedGradient(context, mid, normal, creaseShadowWidth, this.creaseShadowColor);
    context.fill(liftedPath);
    // 3) 纸背在当前页上的投影：沿纸背的每条外侧纸边向外落一窄条。
    if (doublePage || flat.length >= 3) {
      const receivingPath = doublePage ? this.polygonPath([{ x: -leafOrigin, y: 0 },
        { x: width, y: 0 }, { x: width, y: height }, { x: -leafOrigin, y: height }]) : flatPath;
      this.drawFlapEdgeShadows(context, receivingPath, lifted, flap, mid, normal,
        Math.min(width * (doublePage ? 0.06 : 0.03), span * 0.12));
    }
    context.restore();
    // 4) 单页用当前页透墨；双页用目标背页，先抵消落地时的水平镜像。
    context.save();
    context.clip(flapPath);
    context.fillStyle = this.activePaperColor;
    context.fill(flapPath);
    const dot = mid.x * normal.x + mid.y * normal.y;
    context.transform(1 - 2 * normal.x * normal.x, -2 * normal.x * normal.y, -2 * normal.x * normal.y,
      1 - 2 * normal.y * normal.y, 2 * dot * normal.x, 2 * dot * normal.y);
    if (backPage ? !mirrored : mirrored) {
      context.translate(width, 0);
      context.scale(-1, 1);
    }
    context.drawImage(backPage ? backPage : page, 0, 0, width, height);
    context.restore();
    context.save();
    context.globalAlpha = foldLift;
    context.fillStyle = this.flatBackWashColor;
    context.fill(flapPath);
    // 纸背靠折线一侧略暗，提示纸张在这里弯折。
    const flapCreaseWidth = Math.min(width * 0.1, span * 0.25);
    const inward: FoldPoint = { x: -normal.x, y: -normal.y };
    context.fillStyle = this.easedGradient(context, mid, inward, flapCreaseWidth, this.flatFlapCreaseColor);
    context.fill(flapPath);
    this.strokeFlapEdges(context, lifted, flap, mid, normal);
    context.restore();
    context.restore();
  }

  // 平折的抓取点（镜像后坐标系）：上/下部起手抓对应页角，中部起手抓右边缘与起手手指同高的点。
  private flatGrabPoint(width: number, height: number, region: number): FoldPoint {
    if (region === ReaderEmulationFlipRegion.TOP) {
      return { x: width, y: 0 };
    }
    if (region === ReaderEmulationFlipRegion.MIDDLE && this.grabY >= 0) {
      return { x: width, y: Math.max(0, Math.min(height, this.grabY)) };
    }
    return { x: width, y: height };
  }

  /**
   * 抓取点此刻的位置。拖动时贴住手指（起手一小段距离内从纸边平滑过渡过去），并受纸张不可拉长的约束；
   * 松手后从松手位置直线滑到翻出终点或弹回抓取点；没有手指时按进度走固定轨迹。
   */
  private flatFoldTarget(width: number, height: number, progress: number, region: number, grab: FoldPoint,
    mirrored: boolean, spreadWidth: number = width, leafOrigin: number = 0): FoldPoint {
    const corner = region !== ReaderEmulationFlipRegion.MIDDLE || this.grabY < 0;
    const endX = leafOrigin > 0 ? -leafOrigin : -this.flatTravelEnd * width;
    if (this.cornerMode === ReaderEmulationFlipPainter.CORNER_TRAJECTORY) {
      // 没有手指时抓取点随进度匀速走完全程，节奏完全交给动画曲线，折线不会在收尾时越走越快。
      const trajectoryX = width + (endX - width) * progress;
      if (corner) {
        const arcY = this.cornerArcY(width, height, trajectoryX, endX, grab.y <= 0);
        // 单页的轨迹为避免退化保留 1vp；双页必须在终点完全放平，才能与对面的正文重合。
        return { x: trajectoryX, y: leafOrigin > 0 ? arcY + (grab.y <= 0 ? -1 : 1) : arcY };
      }
      return { x: trajectoryX, y: grab.y };
    }
    let x = grab.x;
    let y = grab.y;
    if (this.cornerMode === ReaderEmulationFlipPainter.CORNER_DRAGGING) {
      const fingerX = (mirrored ? spreadWidth - this.fingerX : this.fingerX) - leafOrigin;
      // 拖动刚开始时抓取点还在纸边上，随拖动距离平滑移到手指下方，避免起手瞬间整张纸跳到手指处。
      const ramp = Math.max(0, Math.min(1, progress * spreadWidth / this.cornerFollowRamp));
      const follow = ramp * ramp * (3 - 2 * ramp);
      x = Math.min(grab.x - 0.5, grab.x + (fingerX - grab.x) * follow);
      y = Math.max(0, Math.min(height, grab.y + (this.fingerY - grab.y) * follow));
      if (!corner) {
        const maxTilt = (grab.x - x) * this.flatTiltLimit;
        y = Math.max(grab.y - maxTilt, Math.min(grab.y + maxTilt, y));
      }
      // 纸张不能被拉长：书脊一侧的两个页角不能被掀起，抓取点到它们的距离不超过原来的距离。
      for (let pass = 0; pass < 2; pass++) {
        for (let index = 0; index < 2; index++) {
          const spineY = index === 0 ? 0 : height;
          const limit = Math.hypot(grab.x, grab.y - spineY);
          const distance = Math.hypot(x, y - spineY);
          if (distance > limit) {
            x = x * limit / distance;
            y = spineY + (y - spineY) * limit / distance;
          }
        }
      }
    } else if (progress >= this.releaseProgress) {
      // 松手后继续翻出：从松手位置直线滑到终点，折线逐渐立直并在进度到 1 之前扫出窗口。
      const remaining = Math.max(0.0001, 1 - this.releaseProgress);
      const t = Math.max(0, Math.min(1, (progress - this.releaseProgress) / remaining));
      x = this.releaseCornerX + (endX - this.releaseCornerX) * t;
      y = this.releaseCornerY + (grab.y - this.releaseCornerY) * t;
    } else {
      // 松手后弹回：从松手位置回到抓取点。
      const t = Math.max(0, Math.min(1, progress / Math.max(0.0001, this.releaseProgress)));
      x = grab.x + (this.releaseCornerX - grab.x) * t;
      y = grab.y + (this.releaseCornerY - grab.y) * t;
    }
    this.lastCornerX = x;
    this.lastCornerY = y;
    this.lastCornerProgress = progress;
    return { x: x, y: y };
  }

  // 保留多边形在半平面 (p - origin)·normal >= 0（positive）或 <= 0 内的部分。
  private clipHalfPlane(polygon: FoldPoint[], origin: FoldPoint, normal: FoldPoint, positive: boolean): FoldPoint[] {
    const result: FoldPoint[] = [];
    const sign = positive ? 1 : -1;
    for (let index = 0; index < polygon.length; index++) {
      const current = polygon[index];
      const next = polygon[(index + 1) % polygon.length];
      const currentSide = sign * ((current.x - origin.x) * normal.x + (current.y - origin.y) * normal.y);
      const nextSide = sign * ((next.x - origin.x) * normal.x + (next.y - origin.y) * normal.y);
      if (currentSide >= 0) {
        result.push(current);
      }
      if ((currentSide >= 0) !== (nextSide >= 0)) {
        const t = currentSide / (currentSide - nextSide);
        result.push({ x: current.x + (next.x - current.x) * t, y: current.y + (next.y - current.y) * t });
      }
    }
    return result;
  }

  private reflectPoint(point: FoldPoint, origin: FoldPoint, normal: FoldPoint): FoldPoint {
    const side = (point.x - origin.x) * normal.x + (point.y - origin.y) * normal.y;
    return { x: point.x - 2 * side * normal.x, y: point.y - 2 * side * normal.y };
  }

  private polygonPath(polygon: FoldPoint[]): Path2D {
    const path = new Path2D();
    if (polygon.length === 0) {
      return path;
    }
    path.moveTo(polygon[0].x, polygon[0].y);
    for (let index = 1; index < polygon.length; index++) {
      path.lineTo(polygon[index].x, polygon[index].y);
    }
    path.closePath();
    return path;
  }

  // 被抬起部分的边里，不在折线上的就是纸张原来的外边，镜像后成为纸背的外侧纸边。
  private isFoldEdge(start: FoldPoint, end: FoldPoint, mid: FoldPoint, normal: FoldPoint): boolean {
    const startSide = (start.x - mid.x) * normal.x + (start.y - mid.y) * normal.y;
    const endSide = (end.x - mid.x) * normal.x + (end.y - mid.y) * normal.y;
    return Math.abs(startSide) < 0.5 && Math.abs(endSide) < 0.5;
  }

  private drawFlapEdgeShadows(context: CanvasRenderingContext2D, flatPath: Path2D, lifted: FoldPoint[],
    flap: FoldPoint[], mid: FoldPoint, normal: FoldPoint, shadowWidth: number): void {
    if (shadowWidth <= 0.5) {
      return;
    }
    let centerX = 0;
    let centerY = 0;
    for (let index = 0; index < flap.length; index++) {
      centerX += flap[index].x / flap.length;
      centerY += flap[index].y / flap.length;
    }
    context.save();
    context.clip(flatPath);
    for (let index = 0; index < lifted.length; index++) {
      const next = (index + 1) % lifted.length;
      if (this.isFoldEdge(lifted[index], lifted[next], mid, normal)) {
        continue;
      }
      const start = flap[index];
      const end = flap[next];
      const length = Math.hypot(end.x - start.x, end.y - start.y);
      if (length < 0.5) {
        continue;
      }
      // 纸边的外法线：垂直于纸边、背离纸背中心。
      let outX = -(end.y - start.y) / length;
      let outY = (end.x - start.x) / length;
      if ((start.x - centerX) * outX + (start.y - centerY) * outY < 0) {
        outX = -outX;
        outY = -outY;
      }
      const out: FoldPoint = { x: outX, y: outY };
      const strip = this.polygonPath([start, end, { x: end.x + outX * shadowWidth, y: end.y + outY * shadowWidth },
        { x: start.x + outX * shadowWidth, y: start.y + outY * shadowWidth }]);
      context.fillStyle = this.easedGradient(context, start, out, shadowWidth, this.flatFlapShadowColor);
      context.fill(strip);
    }
    context.restore();
  }

  // 纸背的外侧纸边描一条细线，把纸背和下层页面分开。
  private strokeFlapEdges(context: CanvasRenderingContext2D, lifted: FoldPoint[], flap: FoldPoint[], mid: FoldPoint,
    normal: FoldPoint): void {
    context.save();
    context.beginPath();
    for (let index = 0; index < lifted.length; index++) {
      const next = (index + 1) % lifted.length;
      if (this.isFoldEdge(lifted[index], lifted[next], mid, normal)) {
        continue;
      }
      context.moveTo(flap[index].x, flap[index].y);
      context.lineTo(flap[next].x, flap[next].y);
    }
    context.lineWidth = Math.max(0.5, this.vpPerPx);
    context.strokeStyle = this.paperEdgeColor;
    context.stroke();
    context.restore();
  }

  private trajectoryCorner(width: number, height: number, progress: number, topCorner: boolean): FoldPoint {
    // 起步时页角与进度 1:1 同行，后段逐渐加速，到进度 1 时走完 travelOvershoot 个页宽。
    const travel = progress * (1 + (this.travelOvershoot - 1) * progress * progress);
    const endX = (1 - this.travelOvershoot) * (width - 1);
    let ax = (1 - travel) * (width - 1);
    ax = Math.max(endX, Math.min(width - 1, ax));
    // 官方对"中部起手"把页角点固定在页面下边缘，折线会退化成一条垂直线，翻过去只剩一条竖窄条，
    // 不是正常翻折。这里始终按上/下角做带圆弧约束的斜向折角（对应 calcPointAByTouchPoint）。
    // 页角先沿圆弧抬到最高点，之后按余弦平滑回落到页边：折线逐渐立直并从侧边扫出窗口，
    // 不会像整段半圆那样在收尾处突然立直。
    return { x: ax, y: this.cornerArcY(width, height, ax, endX, topCorner) };
  }

  // 页角沿轨迹走到 ax 时的纵坐标：先沿圆弧抬起，越过圆心后按余弦回落，到 endX 时回到页边。
  private cornerArcY(width: number, height: number, ax: number, endX: number, topCorner: boolean): number {
    const radius = this.cornerRadiusRatio * width;
    const centerX = width - radius;
    let offset = 0;
    if (ax >= centerX) {
      offset = Math.sqrt(Math.max(0, radius * radius - (ax - centerX) * (ax - centerX)));
    } else {
      const fall = Math.min(1, (centerX - ax) / Math.max(1, centerX - endX));
      offset = radius * Math.cos(fall * Math.PI / 2);
    }
    return Math.max(1, Math.min(height - 1, topCorner ? offset : height - offset));
  }

  private buildGeometry(width: number, height: number, progress: number, region: number): FoldGeometry | null {
    const topCorner = region === ReaderEmulationFlipRegion.TOP;
    const f: FoldPoint = { x: width, y: topCorner ? 0 : height };
    const middleCorner = false;
    const a = this.trajectoryCorner(width, height, progress, topCorner);
    const g: FoldPoint = { x: (a.x + f.x) / 2, y: (a.y + f.y) / 2 };
    const denominatorE = f.x - g.x;
    const denominatorH = f.y - g.y;
    if (Math.abs(denominatorE) < 0.0001 || Math.abs(denominatorH) < 0.0001) {
      return null;
    }
    const e: FoldPoint = { x: g.x - (f.y - g.y) * (f.y - g.y) / denominatorE, y: f.y };
    const h: FoldPoint = { x: f.x, y: g.y - (f.x - g.x) * (f.x - g.x) / denominatorH };
    // 官方让卷曲起点 C/J 离折线 EH 的距离恒为 AF/4，页角拖得越远卷曲越粗：可见折线 DI 退到 EH 内侧
    // AF/8，正面页的切口在折线两端甩出折页尖很远，看起来上下折叠处对不齐。这里把卷曲宽度封顶。
    const aToF = Math.max(0.0001, Math.hypot(f.x - a.x, f.y - a.y));
    const curlScale = 1 + Math.min(0.5, 2 * this.curlBandMaxRatio * width / aToF);
    const c: FoldPoint = { x: f.x + (e.x - f.x) * curlScale, y: f.y };
    const j: FoldPoint = { x: f.x, y: f.y + (h.y - f.y) * curlScale };
    const b = this.intersectionPoint(a, e, c, j);
    const k = this.intersectionPoint(a, h, c, j);
    const d: FoldPoint = { x: (c.x + 2 * e.x + b.x) / 4, y: (2 * e.y + c.y + b.y) / 4 };
    const i: FoldPoint = { x: (j.x + 2 * h.x + k.x) / 4, y: (2 * h.y + j.y + k.y) / 4 };
    // 正面曲线、纸背折线与阴影共用原始几何点。分别收缩离屏控制点会改变曲线，
    // 让中点 D/I 脱离纸背边界，产生错位楔形；离屏部分交给画布统一裁剪。
    return {
      a: a,
      b: b,
      c: c,
      d: d,
      e: e,
      f: f,
      h: h,
      j: j,
      k: k,
      i: i,
      leftShadowDistance: this.pointToLineDistance(d, a, e),
      rightShadowDistance: this.pointToLineDistance(i, a, h),
      topCorner: topCorner,
      middleCorner: middleCorner
    };
  }

  private intersectionPoint(lineOneStart: FoldPoint, lineOneEnd: FoldPoint, lineTwoStart: FoldPoint,
    lineTwoEnd: FoldPoint): FoldPoint {
    const x1 = lineOneStart.x;
    const y1 = lineOneStart.y;
    const x2 = lineOneEnd.x;
    const y2 = lineOneEnd.y;
    const x3 = lineTwoStart.x;
    const y3 = lineTwoStart.y;
    const x4 = lineTwoEnd.x;
    const y4 = lineTwoEnd.y;
    const denominatorOne = (x3 - x4) * (y1 - y2) - (x1 - x2) * (y3 - y4);
    const denominatorTwo = (y1 - y2) * (x3 - x4) - (x1 - x2) * (y3 - y4);
    if (Math.abs(denominatorOne) < 0.0001 || Math.abs(denominatorTwo) < 0.0001) {
      return { x: lineOneStart.x, y: lineOneStart.y };
    }
    const x = ((x1 - x2) * (x3 * y4 - x4 * y3) - (x3 - x4) * (x1 * y2 - x2 * y1)) / denominatorOne;
    const y = ((y1 - y2) * (x3 * y4 - x4 * y3) - (x1 * y2 - x2 * y1) * (y3 - y4)) / denominatorTwo;
    return { x: x, y: y };
  }

  private pointToLineDistance(point: FoldPoint, lineStart: FoldPoint, lineEnd: FoldPoint): number {
    const a = lineStart.y - lineEnd.y;
    const b = lineEnd.x - lineStart.x;
    const c = lineStart.x * lineEnd.y - lineEnd.x * lineStart.y;
    const length = Math.hypot(a, b);
    if (length < 0.0001) {
      return 0;
    }
    return Math.abs((a * point.x + b * point.y + c) / length);
  }

  private pathA(geometry: FoldGeometry, width: number, height: number): Path2D {
    const path = new Path2D();
    const a = geometry.a;
    const b = geometry.b;
    const c = geometry.c;
    const e = geometry.e;
    const k = geometry.k;
    const h = geometry.h;
    const j = geometry.j;
    if (geometry.topCorner) {
      // drawing.Path 在 reset() 后首个 lineTo 隐含从 (0,0) 起画，因此 pathA 是整页减去折角。
      path.moveTo(0, 0);
      path.lineTo(c.x, c.y);
      path.quadraticCurveTo(e.x, e.y, b.x, b.y);
      path.lineTo(a.x, a.y);
      path.lineTo(k.x, k.y);
      path.quadraticCurveTo(h.x, h.y, j.x, j.y);
      path.lineTo(width, height);
      path.lineTo(0, height);
    } else {
      path.moveTo(0, 0);
      path.lineTo(0, height);
      path.lineTo(c.x, c.y);
      path.quadraticCurveTo(e.x, e.y, b.x, b.y);
      path.lineTo(a.x, a.y);
      path.lineTo(k.x, k.y);
      path.quadraticCurveTo(h.x, h.y, j.x, j.y);
      path.lineTo(width, 0);
    }
    path.closePath();
    return path;
  }

  private pathC(geometry: FoldGeometry, width: number, height: number): Path2D {
    const path = new Path2D();
    const a = geometry.a;
    const b = geometry.b;
    const d = geometry.d;
    const k = geometry.k;
    const i = geometry.i;
    path.moveTo(i.x, i.y);
    path.lineTo(d.x, d.y);
    path.lineTo(b.x, b.y);
    path.lineTo(a.x, a.y);
    path.lineTo(k.x, k.y);
    path.closePath();
    return path;
  }

  // 纸张翻起部分的两条实体纸边（原下边与原侧边），描一条细线把纸背和下层页面分开。
  private strokePaperEdge(context: CanvasRenderingContext2D, geometry: FoldGeometry, width: number,
    height: number): void {
    const a = geometry.a;
    const k = geometry.k;
    context.save();
    context.beginPath();
    context.moveTo(geometry.b.x, geometry.b.y);
    context.lineTo(a.x, a.y);
    context.lineTo(k.x, k.y);
    context.lineWidth = Math.max(0.5, this.vpPerPx);
    context.strokeStyle = this.paperEdgeColor;
    context.stroke();
    context.restore();
  }

  // 对应 drawPathC：纸张背面区域 + 反射内容 + 背页阴影。
  private drawPathC(context: CanvasRenderingContext2D, page: image.PixelMap, geometry: FoldGeometry,
    width: number, height: number, mirrored: boolean): void {
    const path = this.pathC(geometry, width, height);
    context.save();
    context.fillStyle = this.activePaperColor;
    context.fill(path);

    const e = geometry.e;
    const f = geometry.f;
    const h = geometry.h;
    const foldLength = Math.hypot(f.x - e.x, h.y - f.y);
    if (foldLength > 0.0001) {
      const sin = (f.x - e.x) / foldLength;
      const cos = (h.y - f.y) / foldLength;
      context.save();
      context.clip(path);
      context.translate(e.x, e.y);
      context.transform(-(1 - 2 * sin * sin), 2 * sin * cos, 2 * sin * cos, 1 - 2 * sin * sin, 0, 0);
      context.translate(-e.x, -e.y);
      // Reflect the same source sheet as the front when turning toward the previous page.
      if (mirrored) {
        context.translate(width, 0);
        context.scale(-1, 1);
      }
      context.drawImage(page, 0, 0, width, height);
      context.restore();
    }

    context.fillStyle = this.backTintColor;
    context.fill(path);
    context.restore();

    context.save();
    context.clip(path);
    this.drawPathCShadow(context, geometry, width, height);
    context.restore();
    this.strokePaperEdge(context, geometry, width, height);
  }

  // 对应 drawPathCShadow。
  private drawPathCShadow(context: CanvasRenderingContext2D, geometry: FoldGeometry, width: number,
    height: number): void {
    const c = geometry.c;
    const e = geometry.e;
    const f = geometry.f;
    const h = geometry.h;
    const j = geometry.j;
    const top = c.y;
    const bottom = Math.hypot(width, height) + c.y;
    const midCE = (c.x + e.x) / 2;
    const midJH = (j.y + h.y) / 2;
    const controlDistance = Math.min(Math.abs(midCE - e.x), Math.abs(midJH - h.y));
    let left = 0;
    let right = 0;
    if (geometry.topCorner) {
      left = c.x - this.vpPerPx;
      right = c.x + controlDistance;
    } else {
      left = c.x - controlDistance;
      right = c.x + this.vpPerPx;
    }
    const rotateDegrees = this.rotationDegrees(h.y - f.y, e.x - f.x);
    const startX = geometry.topCorner ? right : left;
    const endX = geometry.topCorner ? left : right;
    this.paintRotatedShadow(context, null, left, top, right, bottom, rotateDegrees, c.x, c.y, endX, top, startX,
      top, [this.shadowLightColor, this.shadowBackDeepColor]);
  }

  // 对应 drawPathBShadow：折页投射到下一页上的阴影。
  private drawPathBShadow(context: CanvasRenderingContext2D, geometry: FoldGeometry, width: number,
    height: number): void {
    const a = geometry.a;
    const c = geometry.c;
    const e = geometry.e;
    const f = geometry.f;
    const h = geometry.h;
    const aToF = Math.hypot(a.x - f.x, a.y - f.y);
    const top = c.y;
    const bottom = Math.hypot(width, height) + c.y;
    // 官方取 aToF/4 作为投影带宽，纸张翻得越深带宽越大，看起来会和纸脱开。
    // 这里把带宽收窄并封顶，使阴影始终贴着折线。
    const bandWidth = Math.min(aToF / 4, width * 0.06);
    let left = 0;
    let right = 0;
    if (geometry.topCorner) {
      left = c.x;
      right = c.x + bandWidth;
    } else {
      left = c.x - bandWidth;
      right = c.x;
    }
    const rotateDegrees = this.rotationDegrees(h.y - f.y, e.x - f.x);
    const startX = geometry.topCorner ? right : left;
    const endX = geometry.topCorner ? left : right;
    this.paintRotatedShadow(context, null, left, top, right, bottom, rotateDegrees, c.x, c.y, endX, top, startX,
      top, [this.shadowDeepColor, this.shadowLightColor]);
  }

  // 对应 drawPathAContent：纸张正面剩余区域 + 页内阴影。
  private drawPathAContent(context: CanvasRenderingContext2D, page: image.PixelMap, geometry: FoldGeometry,
    width: number, height: number, mirrored: boolean): void {
    const path = this.pathA(geometry, width, height);
    context.save();
    context.clip(path);
    // 纸张正面始终按原方向绘制，保证正文不镜像。镜像变换自逆，再应用一次即可抵消。
    if (mirrored) {
      context.translate(width, 0);
      context.scale(-1, 1);
    }
    context.drawImage(page, 0, 0, width, height);
    context.restore();

    if (geometry.middleCorner) {
      this.drawPathAHorizontalShadow(context, geometry, path, width, height);
    } else {
      this.drawPathALeftShadow(context, geometry, path, width, height);
      this.drawPathARightShadow(context, geometry, path, width, height);
    }
  }

  // 对应 drawPathALeftShadow。
  private drawPathALeftShadow(context: CanvasRenderingContext2D, geometry: FoldGeometry, pathA: Path2D,
    width: number, height: number): void {
    const a = geometry.a;
    const d = geometry.d;
    const e = geometry.e;
    const top = e.y;
    const bottom = e.y + height;
    let left = 0;
    let right = 0;
    if (geometry.topCorner) {
      left = e.x - geometry.leftShadowDistance / 2;
      right = e.x;
    } else {
      left = e.x;
      right = e.x + geometry.leftShadowDistance / 2;
    }
    const rotateDegrees = this.rotationDegrees(a.y - e.y, e.x - a.x);
    const startX = geometry.topCorner ? right : left;
    const endX = geometry.topCorner ? left : right;
    const clip = new Path2D();
    const clipHalf = Math.max(geometry.rightShadowDistance, geometry.leftShadowDistance) / 2;
    clip.moveTo(a.x - clipHalf, a.y);
    clip.lineTo(d.x, d.y);
    clip.lineTo(e.x, e.y);
    clip.lineTo(a.x, a.y);
    clip.closePath();
    this.paintRotatedShadow(context, pathA, left, top, right, bottom, rotateDegrees, e.x, e.y, endX, top, startX,
      top, [this.shadowLightColor, this.shadowBackDeepColor], clip);
  }

  // 对应 drawPathARightShadow。
  private drawPathARightShadow(context: CanvasRenderingContext2D, geometry: FoldGeometry, pathA: Path2D,
    width: number, height: number): void {
    const a = geometry.a;
    const h = geometry.h;
    const diagonal = Math.hypot(width, height);
    const left = h.x;
    const right = h.x + diagonal * 10;
    let top = 0;
    let bottom = 0;
    if (geometry.topCorner) {
      top = h.y - geometry.rightShadowDistance / 2;
      bottom = h.y;
    } else {
      top = h.y;
      bottom = h.y + geometry.rightShadowDistance / 2;
    }
    const rotateDegrees = this.rotationDegrees(a.x - h.x, a.y - h.y);
    const startTop = geometry.topCorner ? top : bottom;
    const endTop = geometry.topCorner ? bottom : top;
    const clip = new Path2D();
    const clipHalf = Math.max(geometry.rightShadowDistance, geometry.leftShadowDistance) / 2;
    clip.moveTo(a.x - clipHalf, a.y);
    clip.lineTo(h.x, h.y);
    clip.lineTo(a.x, a.y);
    clip.closePath();
    this.paintRotatedShadow(context, pathA, left, top, right, bottom, rotateDegrees, h.x, h.y, left, endTop, left,
      startTop, [this.shadowDeepColor, this.shadowLightColor, this.shadowLightColor, this.shadowLightColor], clip);
  }

  // 对应 drawPathAHorizontalShadow。
  private drawPathAHorizontalShadow(context: CanvasRenderingContext2D, geometry: FoldGeometry, pathA: Path2D,
    width: number, height: number): void {
    const a = geometry.a;
    const left = a.x - Math.min(this.horizontalShadowMaxWidth * this.vpPerPx,
      geometry.rightShadowDistance / 2);
    const right = a.x + this.horizontalShadowRightExtend * this.vpPerPx;
    this.paintRotatedShadow(context, pathA, left, 0, right, height, 0, 0, 0, left, 0, right, 0,
      [this.shadowLightColor, this.shadowBackDeepColor]);
  }

  /**
   * 从 origin 沿 direction 方向 length 长度内，由 color（最深）按 (1-t)² 衰减到全透明的线性渐变；
   * 起点之外取最深色、终点之外全透明，填充时需用路径限定范围。
   * 两端都是线性渐变时，起止处的亮度折点会被眼睛放大成一条硬边，多段并排就成了条纹。
   */
  private easedGradient(context: CanvasRenderingContext2D, origin: FoldPoint, direction: FoldPoint, length: number,
    color: string): CanvasGradient {
    const rgba = color.match(/^rgba\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*([\d.]+)\s*\)$/i);
    const rgb = rgba ? `${rgba[1]},${rgba[2]},${rgba[3]}` : '0,0,0';
    const alpha = rgba ? Number(rgba[4]) : 0.3;
    const extent = Math.max(0.5, length);
    const gradient = context.createLinearGradient(origin.x, origin.y, origin.x + direction.x * extent,
      origin.y + direction.y * extent);
    const steps = 6;
    for (let index = 0; index <= steps; index++) {
      const t = index / steps;
      const strength = (1 - t) * (1 - t);
      gradient.addColorStop(t, `rgba(${rgb},${(alpha * strength).toFixed(4)})`);
    }
    return gradient;
  }

  private rotationDegrees(deltaX: number, deltaY: number): number {
    if (Math.abs(deltaX) < 0.0001 && Math.abs(deltaY) < 0.0001) {
      return 0;
    }
    return Math.atan2(deltaY, deltaX) * 180 / Math.PI;
  }

  /**
   * 在可选裁剪区域内，围绕 (centerX, centerY) 旋转后填充一段线性渐变矩形。
   * gradientStart → gradientEnd 的用法与官方 createLinearGradient(endPt, startPt, colors) 对应。
   */
  private paintRotatedShadow(context: CanvasRenderingContext2D, clipPath: Path2D | null, left: number, top: number,
    right: number, bottom: number, rotateDegrees: number, centerX: number, centerY: number, gradientStartX: number,
    gradientStartY: number, gradientEndX: number, gradientEndY: number, colors: string[],
    intersectPath: Path2D | null = null): void {
    context.save();
    if (clipPath) {
      context.clip(clipPath);
    }
    if (intersectPath) {
      context.clip(intersectPath);
    }
    if (Math.abs(rotateDegrees) > 0.0001) {
      context.translate(centerX, centerY);
      context.rotate(rotateDegrees * Math.PI / 180);
      context.translate(-centerX, -centerY);
    }
    const gradient = context.createLinearGradient(gradientStartX, gradientStartY, gradientEndX, gradientEndY);
    for (let index = 0; index < colors.length; index++) {
      gradient.addColorStop(colors.length <= 1 ? 0 : index / (colors.length - 1), colors[index]);
    }
    context.fillStyle = gradient;
    context.fillRect(left, top, Math.max(1, right - left), Math.max(1, bottom - top));
    context.restore();
  }
}
