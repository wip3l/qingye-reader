// 沉浸光感组件库的统一出口。共用代码只从这里取 HDS 符号，不直接引用 @kit.UIDesignKit：
// 该组件库在鸿蒙上是系统共享包，安卓上不存在，静态引用会在启动时终止进程，
// 安卓构建会用 android/overlay 里的同名文件替换本文件。
// HdsTabs 例外：它带专属属性，转一手导出后编译器认不出配对的属性类，使用处直接从 @kit.UIDesignKit 引入。
export {
  HdsAnimationMode,
  HdsBarWidthRangeOptions,
  HdsColorPicker,
  HdsColorPickerOptions,
  HdsColorPickerTabType,
  HdsListItem,
  HdsSnackBar,
  HdsSwipeActionOptions,
  HdsTabsController,
  SnackBarIconOptions,
  SnackBarMessageOptions,
  SnackBarOperationOptions,
  SnackBarOperationType,
  hdsMaterial
} from '@kit.UIDesignKit';
