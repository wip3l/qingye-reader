// platform/Hds.ets 的安卓实现。@kit.UIDesignKit 在安卓上不存在，这里给共用代码用到的符号提供同名替身，
// 全部退化成普通组件或空实现；能力开关（ImmersiveMaterialRuntime.supportsHds 等）在安卓上恒为 false，
// 所以带系统材质的分支不会走到。HdsTabs 不在这里：使用处直接引用组件库，由安卓构建脚本改写。新增 HDS 符号时两边的 Hds.ets 要一起补。
import { UIContext } from '@kit.ArkUI';
import { ListItemModifier } from '@ohos.arkui.modifier';

export interface IconOptions {
  enable?: boolean;
  accessibilityText?: ResourceStr;
  accessibilityDescription?: ResourceStr;
  accessibilityLevel?: string;
}

export interface SwipeIconConfigurations {
  icon: Object;
  backgroundColor?: ResourceColor;
  iconOptions?: IconOptions;
  onAction?: () => void;
}

export interface DeleteIconOptions {
  backgroundColor?: ResourceColor;
  iconColor?: ResourceColor;
  iconOptions?: IconOptions;
  onAction?: () => void;
}

export interface FullDeleteOptions {
  isFullDelete?: boolean;
  onFullDeleteAction?: () => void;
  enableVibration?: boolean;
}

export interface HdsSwipeActionOptions {
  icons?: Array<SwipeIconConfigurations>;
  deleteIconOptions?: DeleteIconOptions;
  fullDeleteOptions?: FullDeleteOptions;
  onStateChange?: (state: SwipeActionState) => void;
}

export interface MenuStyle {
  responseType?: ResponseType;
  menuOptions?: ContextMenuOptions;
}

export interface HdsListItemStateStylesOptions {
  selectedBackgroundColor?: ResourceColor;
  normalBackgroundColor?: ResourceColor;
}

@Builder
function emptyShimBuilder() {
}

@Component
export struct HdsListItem {
  @BuilderParam customItemBuilder: () => void = emptyShimBuilder;
  @BuilderParam menuBuilder: () => void = emptyShimBuilder;
  listItemModifier?: ListItemModifier;
  swipeActionOptions?: HdsSwipeActionOptions | SwipeActionOptions;
  @Prop menuStyle?: MenuStyle;
  @Prop isSelected?: boolean;
  @Prop listItemStateStyles?: HdsListItemStateStylesOptions;

  build() {
    ListItem() {
      this.customItemBuilder()
    }
  }
}

export enum HdsAnimationMode {
  DEFAULT = 0,
  SCROLL_ANIMATION = 1
}

export interface HdsBarWidthRangeOptions {
  smallWidth?: Length;
  mediumWidth?: Length;
  largeWidth?: Length;
}

export class HdsTabsController extends TabsController {
  applyHideAnimation(mode?: HdsAnimationMode): void {
  }

  applyShowAnimation(mode?: HdsAnimationMode): void {
  }

  // 以下三个只为与鸿蒙的 HdsTabsController 类型兼容（HdsTabs 用 import lazy 引入后要能编过），安卓上不会被调用。
  bindScroller(_scroller: Scroller): void {
  }

  unbindScroller(_scroller: Scroller): void {
  }

  applyMiniBarStyle(_style?: Object): void {
  }
}

export namespace hdsMaterial {
  export enum MaterialType {
    NONE = 0,
    ADAPTIVE = 100,
    IMMERSIVE = 101
  }

  export enum MaterialLevel {
    EXQUISITE = 0,
    GENTLE = 1,
    SMOOTH = 2,
    ADAPTIVE = 10
  }

  export function getSystemMaterialTypes(): Array<MaterialType> {
    return [];
  }
}

export interface SnackBarIconOptions {
  icon?: ResourceStr;
}

export interface SnackBarMessageOptions {
  title?: ResourceStr;
  content?: ResourceStr;
}

export enum SnackBarOperationType {
  TEXT_ONLY = 0,
  CLOSE_BUTTON_ONLY = 1,
  TEXT_WITH_ARROW = 2,
  TEXT_WITH_CLOSE = 3,
  HIGHLIGHT_TEXT_WITH_CLOSE = 4
}

export interface SnackBarOperationOptions {
  operationType?: SnackBarOperationType;
  content?: ResourceStr;
}

export class HdsSnackBar {
  constructor(uiContext: UIContext) {
    throw new Error('HdsSnackBar 在安卓上不可用');
  }

  show(icon: SnackBarIconOptions, message: SnackBarMessageOptions, operation: SnackBarOperationOptions): void {
  }

  dismiss(): void {
  }
}

export enum HdsColorPickerTabType {
  GRID = 0,
  SPECTRUM = 1,
  SLIDERS = 2
}

export interface HdsColorPickerOptions {
  circleRadius?: number;
  tabs?: HdsColorPickerTabType[];
}

@ComponentV2
export struct HdsColorPicker {
  @Param initialColor?: string = undefined;
  @Event onColorSelected: (selectedColor: string) => void = (selectedColor: string) => {
  };
  @Param @Once initialFavoriteColors?: Array<string> = undefined;
  @Event onFavoriteColorsUpdate?: (favoritesList: Array<string>) => void = undefined;
  @Param options?: HdsColorPickerOptions = undefined;

  build() {
    Column()
  }
}
