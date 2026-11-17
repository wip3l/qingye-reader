/**
 * 自定义主题的文件变了（方案列表、主题包素材、启动封面与预览图）：通知云文件同步稍后对账。
 * 主题存储代码只依赖这个小模块，不直接引用同步模块，避免互相导入。
 */
export class CloudThemeChange {
  private static listener: (() => void) | null = null;

  static listen(listener: () => void): void {
    CloudThemeChange.listener = listener;
  }

  static notify(): void {
    const listener = CloudThemeChange.listener;
    if (listener) listener();
  }
}
