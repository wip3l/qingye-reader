import image from '@ohos.multimedia.image';

interface CurlPoint {
  x: number;
  y: number;
  face: number;
  shade: number;
}

interface CurlTriangle {
  sx0: number;
  sy0: number;
  sx1: number;
  sy1: number;
  sx2: number;
  sy2: number;
  d0: CurlPoint;
  d1: CurlPoint;
  d2: CurlPoint;
  face: number;
  shade: number;
}

/**
 * Paints a page as a mesh wrapped around a travelling cylinder. The model is deliberately
 * two-dimensional: it keeps the text snapshot sharp while reproducing the broad S-shaped
 * fold, visible paper back and moving cast shadow from the reference reader.
 */
export class ReaderPageCurlPainter {
  // The curl is almost linear on the vertical axis. A shallow vertical mesh keeps the S-shaped
  // fold while cutting clipped PixelMap draws substantially. A double-page leaf is only half as
  // wide, so eight columns retain roughly the same visual sampling density as a full-width leaf.
  private readonly singlePageMeshColumns: number = 8;
  private readonly doublePageMeshColumns: number = 5;
  // mapPoint keeps Y unchanged, so additional horizontal rows produce identical geometry while multiplying
  // full-page PixelMap draws. One row preserves the vertical fold exactly and substantially reduces UI work.
  private readonly meshRows: number = 1;
  // The fold radius is still about 0.115 leaf widths at the final frame. Travelling beyond
  // 1 + radius keeps the last folded strip fully outside the viewport instead of freezing
  // visibly while the reader commits the incoming page.
  private readonly pageTravelFactor: number = 1.14;

  draw(context: CanvasRenderingContext2D, front: image.PixelMap, back: image.PixelMap,
    canvasWidth: number, canvasHeight: number, progress: number, direction: number,
    doublePage: boolean, darkMode: boolean, doubleLeafWidth: number = 0,
    doubleRightOrigin: number = 0, paperColor: string = ''): void {
    const width = Math.max(1, canvasWidth);
    const height = Math.max(1, canvasHeight);
    const leafWidth = doublePage && doubleLeafWidth > 0 ? Math.min(width, doubleLeafWidth) :
      (doublePage ? width / 2 : width);
    const rightOrigin = doublePage && doubleRightOrigin > 0 ?
      Math.min(width - leafWidth, doubleRightOrigin) : width - leafWidth;
    const safeProgress = Math.max(0, Math.min(1, progress));
    context.clearRect(0, 0, width, height);
    context.imageSmoothingEnabled = true;
    context.save();
    if (safeProgress <= 0.001) {
      const startX = doublePage && direction > 0 ? rightOrigin : 0;
      if (paperColor) {
        context.fillStyle = paperColor;
        context.fillRect(startX, 0, leafWidth, height);
      }
      context.drawImage(front, startX, 0, leafWidth, height);
      context.restore();
      return;
    }

    this.drawCastShadow(context, width, height, leafWidth, rightOrigin, safeProgress, direction, doublePage,
      darkMode);
    const triangles = this.buildTriangles(width, height, leafWidth, rightOrigin, safeProgress, direction,
      doublePage);
    this.drawFace(context, triangles, front, leafWidth, height, 1, darkMode, false, paperColor);
    // The landed double-page mesh reverses its horizontal axis when the right leaf moves onto
    // the left side (and vice versa). Pre-mirror only the paper-back texture so the composed
    // preview keeps its normal reading orientation throughout the turn.
    this.drawFace(context, triangles, back, leafWidth, height, -1, darkMode, doublePage, paperColor);
    context.restore();
  }

  private buildTriangles(canvasWidth: number, canvasHeight: number, leafWidth: number, rightOrigin: number,
    progress: number, direction: number, doublePage: boolean): CurlTriangle[] {
    const triangles: CurlTriangle[] = [];
    const points: CurlPoint[] = [];
    const meshColumns = doublePage ? this.doublePageMeshColumns : this.singlePageMeshColumns;
    const dx = leafWidth / meshColumns;
    const dy = canvasHeight / this.meshRows;
    for (let row = 0; row <= this.meshRows; row++) {
      const y = row * dy;
      for (let column = 0; column <= meshColumns; column++) {
        points.push(this.mapPoint(column * dx, y, canvasWidth, leafWidth, rightOrigin, progress,
          direction, doublePage));
      }
    }
    const rowLength = meshColumns + 1;
    for (let row = 0; row < this.meshRows; row++) {
      const y0 = row * dy;
      const y1 = (row + 1) * dy;
      for (let column = 0; column < meshColumns; column++) {
        const x0 = column * dx;
        const x1 = (column + 1) * dx;
        const topLeft = row * rowLength + column;
        const p00 = points[topLeft];
        const p10 = points[topLeft + 1];
        const p01 = points[topLeft + rowLength];
        const p11 = points[topLeft + rowLength + 1];
        triangles.push(this.makeTriangle(x0, y0, x1, y0, x1, y1, p00, p10, p11));
        triangles.push(this.makeTriangle(x0, y0, x1, y1, x0, y1, p00, p11, p01));
      }
    }
    return triangles;
  }

  private makeTriangle(sx0: number, sy0: number, sx1: number, sy1: number, sx2: number, sy2: number,
    d0: CurlPoint, d1: CurlPoint, d2: CurlPoint): CurlTriangle {
    const face = d0.face + d1.face + d2.face >= 0 ? 1 : -1;
    return {
      sx0: sx0,
      sy0: sy0,
      sx1: sx1,
      sy1: sy1,
      sx2: sx2,
      sy2: sy2,
      d0: d0,
      d1: d1,
      d2: d2,
      face: face,
      shade: (d0.shade + d1.shade + d2.shade) / 3
    };
  }

  private mapPoint(sourceX: number, sourceY: number, canvasWidth: number, leafWidth: number,
    rightOrigin: number,
    progress: number, direction: number, doublePage: boolean): CurlPoint {
    const canonicalX = direction > 0 ? sourceX : leafWidth - sourceX;
    // Keep the curl axis vertical. The previous tilted-axis projection mixed the horizontal curl distance into
    // every texture point's Y coordinate, so the rasterized正文 appeared to sink and then rise during a turn.
    // A real page may bend in depth, but its top/bottom registration must remain stable in this 2D projection.
    const normal = canonicalX;
    const axis = leafWidth * (1 - progress * this.pageTravelFactor);
    const radius = leafWidth * (0.115 + 0.065 * Math.sin(progress * Math.PI));
    const distance = normal - axis;
    let mappedNormal = normal;
    let face = 1;
    let shade = 0;
    if (distance > 0) {
      const angle = distance / Math.max(1, radius);
      if (angle < Math.PI) {
        mappedNormal = axis + radius * Math.sin(angle);
        face = Math.cos(angle) >= 0 ? 1 : -1;
        shade = Math.min(1, Math.abs(Math.sin(angle)) * 0.82 + (face < 0 ? 0.18 : 0));
      } else {
        mappedNormal = axis - (distance - Math.PI * radius);
        face = -1;
        shade = Math.max(0.16, 0.46 - Math.min(0.3, (angle - Math.PI) * 0.07));
      }
    }
    if (doublePage) {
      // Unlike a single sheet, a double-page leaf must finish by lying flat on the opposite half
      // of the spread. Keeping the normal curl radius through progress=1 leaves a narrow folded
      // strip parked at the spine; it then appears frozen while ArkUI commits the new spread.
      // Blend that strip into its exact landed geometry during the final part of the motion.
      const settle = this.doublePageSettleProgress(progress);
      if (settle > 0) {
        mappedNormal += (-normal - mappedNormal) * settle;
        // A negative shade carries the landing blend to drawFace without expanding every mesh type.
        // It removes the paper-back dimming as the leaf becomes the fully lit destination page.
        shade = -settle;
        if (settle >= 0.9) face = -1;
      }
    }
    const mappedX = mappedNormal;
    // The physical spread contains a divider between leaves. Start the moving sheet at the real right-page
    // origin, then close only that divider gap as the sheet settles onto the opposite page. Keeping the origin
    // at width/2 throughout either displaced the live right page initially or left the landed page shifted by
    // the divider width.
    const landingSettle = doublePage ? this.doublePageSettleProgress(progress) : 0;
    const pageGap = Math.max(0, rightOrigin - leafWidth);
    const canonicalOrigin = doublePage ? leafWidth + pageGap * (1 - landingSettle) : 0;
    const canonicalGlobalX = canonicalOrigin + mappedX;
    return {
      x: direction > 0 ? canonicalGlobalX : canvasWidth - canonicalGlobalX,
      y: sourceY,
      face: face,
      shade: shade
    };
  }

  private doublePageSettleProgress(progress: number): number {
    const start = 0.78;
    if (progress <= start) return 0;
    const value = Math.max(0, Math.min(1, (progress - start) / (1 - start)));
    return value * value * (3 - 2 * value);
  }

  private drawFace(context: CanvasRenderingContext2D, triangles: CurlTriangle[], texture: image.PixelMap,
    leafWidth: number, leafHeight: number, face: number, darkMode: boolean, flipTextureX: boolean,
    paperColor: string): void {
    for (const triangle of triangles) {
      if (triangle.face !== face) continue;
      const settle = Math.max(0, Math.min(1, -triangle.shade));
      const physicalShade = Math.max(0, triangle.shade);
      this.drawTexturedTriangle(context, triangle, texture, leafWidth, leafHeight,
        face < 0 ? 0.83 + settle * 0.17 : 1, flipTextureX, paperColor);
      const alpha = face < 0 ? (0.13 + physicalShade * 0.26) * (1 - settle) : physicalShade * 0.12;
      if (alpha > 0.01) {
        this.fillTriangle(context, triangle, darkMode ? '#05080B' : (face < 0 ? '#D8D2C6' : '#5D554A'),
          alpha);
      }
    }
  }

  private drawTexturedTriangle(context: CanvasRenderingContext2D, triangle: CurlTriangle,
    texture: image.PixelMap, leafWidth: number, leafHeight: number, alpha: number,
    flipTextureX: boolean, paperColor: string): void {
    const sourceX0 = flipTextureX ? leafWidth - triangle.sx0 : triangle.sx0;
    const sourceX1 = flipTextureX ? leafWidth - triangle.sx1 : triangle.sx1;
    const sourceX2 = flipTextureX ? leafWidth - triangle.sx2 : triangle.sx2;
    const sx1 = sourceX1 - sourceX0;
    const sy1 = triangle.sy1 - triangle.sy0;
    const sx2 = sourceX2 - sourceX0;
    const sy2 = triangle.sy2 - triangle.sy0;
    const determinant = sx1 * sy2 - sx2 * sy1;
    if (Math.abs(determinant) < 0.0001) return;
    const dx1 = triangle.d1.x - triangle.d0.x;
    const dy1 = triangle.d1.y - triangle.d0.y;
    const dx2 = triangle.d2.x - triangle.d0.x;
    const dy2 = triangle.d2.y - triangle.d0.y;
    const a = (dx1 * sy2 - dx2 * sy1) / determinant;
    const b = (dy1 * sy2 - dy2 * sy1) / determinant;
    const c = (-dx1 * sx2 + dx2 * sx1) / determinant;
    const d = (-dy1 * sx2 + dy2 * sx1) / determinant;
    const e = triangle.d0.x - a * sourceX0 - c * triangle.sy0;
    const f = triangle.d0.y - b * sourceX0 - d * triangle.sy0;
    context.save();
    this.trianglePath(context, triangle);
    context.clip();
    if (paperColor) {
      // 带透明区域的贴图（漫画跟随主题时的留白）先垫纸色，否则卷起的纸露出下面的目标页。
      context.globalAlpha = alpha;
      context.fillStyle = paperColor;
      context.fill();
    }
    context.transform(a, b, c, d, e, f);
    context.globalAlpha = alpha;
    context.drawImage(texture, 0, 0, leafWidth, leafHeight);
    context.restore();
  }

  private fillTriangle(context: CanvasRenderingContext2D, triangle: CurlTriangle, color: string,
    alpha: number): void {
    context.save();
    this.trianglePath(context, triangle);
    context.globalAlpha = Math.max(0, Math.min(1, alpha));
    context.fillStyle = color;
    context.fill();
    context.restore();
  }

  private trianglePath(context: CanvasRenderingContext2D, triangle: CurlTriangle): void {
    const centerX = (triangle.d0.x + triangle.d1.x + triangle.d2.x) / 3;
    const centerY = (triangle.d0.y + triangle.d1.y + triangle.d2.y) / 3;
    context.beginPath();
    this.moveToExpandedPoint(context, triangle.d0, centerX, centerY, true);
    this.moveToExpandedPoint(context, triangle.d1, centerX, centerY, false);
    this.moveToExpandedPoint(context, triangle.d2, centerX, centerY, false);
    context.closePath();
  }

  private moveToExpandedPoint(context: CanvasRenderingContext2D, point: CurlPoint,
    centerX: number, centerY: number, move: boolean): void {
    const dx = point.x - centerX;
    const dy = point.y - centerY;
    const length = Math.max(0.01, Math.sqrt(dx * dx + dy * dy));
    const overlap = 0.72;
    const x = point.x + dx / length * overlap;
    const y = point.y + dy / length * overlap;
    if (move) context.moveTo(x, y);
    else context.lineTo(x, y);
  }

  private drawCastShadow(context: CanvasRenderingContext2D, canvasWidth: number, canvasHeight: number,
    leafWidth: number, rightOrigin: number, progress: number, direction: number, doublePage: boolean,
    darkMode: boolean): void {
    const shadowWidth = leafWidth * (0.12 + 0.11 * Math.sin(progress * Math.PI));
    const edge: CurlPoint[] = [];
    for (let index = 0; index <= 10; index++) {
      const y = canvasHeight * index / 10;
      const sourceX = leafWidth * Math.min(1, Math.max(0, 1 - progress * this.pageTravelFactor +
        (0.5 * Math.PI) * (0.115 + 0.065 * Math.sin(progress * Math.PI))));
      edge.push(this.mapPoint(direction > 0 ? sourceX : leafWidth - sourceX, y, canvasWidth,
        leafWidth, rightOrigin, progress, direction, doublePage));
    }
    context.save();
    context.beginPath();
    context.moveTo(edge[0].x, edge[0].y);
    for (let index = 1; index < edge.length; index++) context.lineTo(edge[index].x, edge[index].y);
    for (let index = edge.length - 1; index >= 0; index--) {
      context.lineTo(edge[index].x + (direction > 0 ? shadowWidth : -shadowWidth), edge[index].y);
    }
    context.closePath();
    let minX = edge[0].x;
    let maxX = edge[0].x;
    for (const point of edge) {
      minX = Math.min(minX, point.x);
      maxX = Math.max(maxX, point.x);
    }
    const gradient = direction > 0 ?
      context.createLinearGradient(minX, 0, maxX + shadowWidth, 0) :
      context.createLinearGradient(minX - shadowWidth, 0, maxX, 0);
    if (direction > 0) {
      gradient.addColorStop(0, darkMode ? '#99000000' : '#72000000');
      gradient.addColorStop(1, '#00000000');
    } else {
      gradient.addColorStop(0, '#00000000');
      gradient.addColorStop(1, darkMode ? '#99000000' : '#72000000');
    }
    // Fade the cast shadow with the departing edge. A non-zero shadow on the final frame made
    // the completed page look stationary until the declarative surface handoff finished.
    const finishFade = Math.max(0, Math.min(1, (1 - progress) / 0.12));
    context.globalAlpha = (0.25 + 0.42 * Math.sin(progress * Math.PI)) * finishFade;
    context.fillStyle = gradient;
    context.fill();
    context.restore();
  }
}
