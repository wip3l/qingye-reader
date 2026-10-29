/** 转场记录的窗口内矩形；未测量或原位置已移出窗口时使用触点附近的安全起点。 */
export class SharedElementBounds {
  x: number;
  y: number;
  width: number;
  height: number;

  constructor(x: number = 0, y: number = 0, width: number = 64, height: number = 88) {
    this.x = x;
    this.y = y;
    this.width = width;
    this.height = height;
  }

  static resolve(measured: SharedElementBounds | undefined, touchX: number, touchY: number,
    viewportWidth: number, viewportHeight: number): SharedElementBounds {
    if (measured && measured.width > 0 && measured.height > 0 &&
      measured.x >= 0 && measured.y >= 0 && measured.x + measured.width <= viewportWidth + 1 &&
      measured.y + measured.height <= viewportHeight + 1) {
      return new SharedElementBounds(measured.x, measured.y, measured.width, measured.height);
    }
    return new SharedElementBounds(Math.max(0, Math.min(viewportWidth - 64, touchX - 32)),
      Math.max(0, Math.min(viewportHeight - 88, touchY - 44)));
  }
}
