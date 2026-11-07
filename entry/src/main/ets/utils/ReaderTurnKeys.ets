import { inputConsumer, KeyCode, Action, KeyEvent as InputKeyEvent } from '@kit.InputKit';
import { SmartControlKey } from './SmartControlKey';

/**
 * 阅读页接管音量键、智控键翻页：页面可见且对应开关打开时订阅，离开页面立即交还给系统。
 * 与普通阅读页、文件排版页同一组设置（音量键翻页、智控键翻页）。
 */
export class ReaderTurnKeys {
  private callbacks: Array<(event: InputKeyEvent) => void> = [];
  private readonly tag: string;

  constructor(tag: string) {
    this.tag = tag;
  }

  /** onTurn(direction)：-1 上一页，1 下一页。 */
  update(active: boolean, volume: boolean, smartKey: boolean, smartKeySupported: boolean,
    onTurn: (direction: number) => void): void {
    this.release();
    if (!active) return;
    if (volume) this.subscribe(KeyCode.KEYCODE_VOLUME_UP, KeyCode.KEYCODE_VOLUME_DOWN, onTurn, '音量键');
    const slideKeys: Array<KeyCode> = SmartControlKey.slideKeys();
    if (smartKey && smartKeySupported && slideKeys.length >= 2) {
      this.subscribe(slideKeys[0], slideKeys[1], onTurn, '智控键');
    }
  }

  release(): void {
    for (const callback of this.callbacks) {
      try {
        inputConsumer.off('keyPressed', callback);
      } catch (error) {
        console.warn(`[${this.tag}] 取消按键翻页失败:`, error);
      }
    }
    this.callbacks = [];
  }

  private subscribe(up: KeyCode, down: KeyCode, onTurn: (direction: number) => void, label: string): void {
    const onUp = (_event: InputKeyEvent): void => onTurn(-1);
    const onDown = (_event: InputKeyEvent): void => onTurn(1);
    try {
      inputConsumer.on('keyPressed', { key: up, action: Action.DOWN, isRepeat: false }, onUp);
      this.callbacks.push(onUp);
      inputConsumer.on('keyPressed', { key: down, action: Action.DOWN, isRepeat: false }, onDown);
      this.callbacks.push(onDown);
    } catch (error) {
      console.error(`[${this.tag}] 注册${label}翻页失败:`, error);
    }
  }
}
