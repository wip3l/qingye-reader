import { KeyCode } from '@kit.InputKit';

/** Device-local bindings; independent of book, theme and cloud preferences. */
export class ReaderKeyboardSettings {
  enabled: boolean = false;
  previous: number = KeyCode.KEYCODE_PAGE_UP;
  next: number = KeyCode.KEYCODE_PAGE_DOWN;
}

export class ReaderKeyboard {
  private pressed: Set<string> = new Set<string>();
  private consumed: Set<string> = new Set<string>();

  static hasModifiers(event: KeyEvent): boolean {
    try {
      return event.metaKey !== 0 || event.getModifierKeyState?.(['Ctrl']) === true ||
        event.getModifierKeyState?.(['Alt']) === true || event.getModifierKeyState?.(['Shift']) === true;
    } catch (error) {
      return true;
    }
  }

  static isBindable(code: number): boolean {
    return Number.isInteger(code) && (
      (code >= KeyCode.KEYCODE_0 && code <= KeyCode.KEYCODE_9) ||
      (code >= KeyCode.KEYCODE_DPAD_UP && code <= KeyCode.KEYCODE_DPAD_RIGHT) ||
      (code >= KeyCode.KEYCODE_A && code <= KeyCode.KEYCODE_PERIOD) ||
      (code >= KeyCode.KEYCODE_GRAVE && code <= KeyCode.KEYCODE_PLUS) ||
      (code >= KeyCode.KEYCODE_F1 && code <= KeyCode.KEYCODE_F12) ||
      (code >= KeyCode.KEYCODE_NUMPAD_0 && code <= KeyCode.KEYCODE_NUMPAD_EQUALS) ||
      code === KeyCode.KEYCODE_SPACE || code === KeyCode.KEYCODE_ENTER ||
      code === KeyCode.KEYCODE_PAGE_UP || code === KeyCode.KEYCODE_PAGE_DOWN);
  }

  static label(code: number): string {
    if (code >= KeyCode.KEYCODE_A && code <= KeyCode.KEYCODE_Z) {
      return String.fromCharCode(65 + code - KeyCode.KEYCODE_A);
    }
    if (code >= KeyCode.KEYCODE_0 && code <= KeyCode.KEYCODE_9) return `${code - KeyCode.KEYCODE_0}`;
    if (code >= KeyCode.KEYCODE_F1 && code <= KeyCode.KEYCODE_F12) return `F${code - KeyCode.KEYCODE_F1 + 1}`;
    if (code >= KeyCode.KEYCODE_NUMPAD_0 && code <= KeyCode.KEYCODE_NUMPAD_9) {
      return `小键盘 ${code - KeyCode.KEYCODE_NUMPAD_0}`;
    }
    switch (code) {
      case KeyCode.KEYCODE_PAGE_UP: return 'PageUp';
      case KeyCode.KEYCODE_PAGE_DOWN: return 'PageDown';
      case KeyCode.KEYCODE_DPAD_UP: return '↑';
      case KeyCode.KEYCODE_DPAD_DOWN: return '↓';
      case KeyCode.KEYCODE_DPAD_LEFT: return '←';
      case KeyCode.KEYCODE_DPAD_RIGHT: return '→';
      case KeyCode.KEYCODE_SPACE: return '空格';
      case KeyCode.KEYCODE_ENTER: return 'Enter';
      case KeyCode.KEYCODE_COMMA: return ',';
      case KeyCode.KEYCODE_PERIOD: return '.';
      case KeyCode.KEYCODE_GRAVE: return '`';
      case KeyCode.KEYCODE_MINUS: return '-';
      case KeyCode.KEYCODE_EQUALS: return '=';
      case KeyCode.KEYCODE_LEFT_BRACKET: return '[';
      case KeyCode.KEYCODE_RIGHT_BRACKET: return ']';
      case KeyCode.KEYCODE_BACKSLASH: return '\\';
      case KeyCode.KEYCODE_SEMICOLON: return ';';
      case KeyCode.KEYCODE_APOSTROPHE: return "'";
      case KeyCode.KEYCODE_SLASH: return '/';
      case KeyCode.KEYCODE_AT: return '@';
      case KeyCode.KEYCODE_PLUS: return '+';
      case KeyCode.KEYCODE_NUMPAD_DIVIDE: return '小键盘 /';
      case KeyCode.KEYCODE_NUMPAD_MULTIPLY: return '小键盘 *';
      case KeyCode.KEYCODE_NUMPAD_SUBTRACT: return '小键盘 -';
      case KeyCode.KEYCODE_NUMPAD_ADD: return '小键盘 +';
      case KeyCode.KEYCODE_NUMPAD_DOT: return '小键盘 .';
      case KeyCode.KEYCODE_NUMPAD_COMMA: return '小键盘 ,';
      case KeyCode.KEYCODE_NUMPAD_ENTER: return '小键盘 Enter';
      case KeyCode.KEYCODE_NUMPAD_EQUALS: return '小键盘 =';
      default: return `按键 ${code}`;
    }
  }

  static normalize(source: ReaderKeyboardSettings): ReaderKeyboardSettings {
    const result = new ReaderKeyboardSettings();
    result.enabled = typeof source.enabled === 'boolean' ? source.enabled : false;
    if (ReaderKeyboard.isBindable(source.previous)) result.previous = source.previous;
    if (ReaderKeyboard.isBindable(source.next)) result.next = source.next;
    if (result.previous === result.next) {
      result.previous = KeyCode.KEYCODE_PAGE_UP;
      result.next = KeyCode.KEYCODE_PAGE_DOWN;
    }
    return result;
  }

  /** Keep held keys until Up, even when a panel blocks the initial Down. */
  press(code: number, device: number): boolean {
    const token = `${device}:${code}`;
    if (this.pressed.has(token)) return false;
    this.pressed.add(token);
    return true;
  }

  consume(code: number, device: number): void {
    this.consumed.add(`${device}:${code}`);
  }

  release(code: number, device: number): boolean {
    const token = `${device}:${code}`;
    this.pressed.delete(token);
    const handled = this.consumed.has(token);
    this.consumed.delete(token);
    return handled;
  }

  reset(): void {
    this.pressed.clear();
    this.consumed.clear();
  }
}
