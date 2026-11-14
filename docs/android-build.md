# 安卓版构建与平台层

安卓版用 ArkUI-X 把同一套 ArkTS 代码跑在安卓上。界面和业务逻辑两端共用，系统能力的差异收在平台层里。

## 平台层

`entry/src/main/ets/platform/` 是共用代码取系统能力的出口，每个文件有两份实现：

| 文件 | 鸿蒙实现（主代码树） | 安卓实现（`android/overlay/` 下同路径） |
| --- | --- | --- |
| `Hds.ets` | 转出 `@kit.UIDesignKit` 的符号 | 同名替身，退化成普通组件或空实现 |
| `FileUri.ts` | 转出 `fileUri` | 路径与 `file://` 地址互转的本地实现 |
| `InputKeys.ts` | 转出 `KeyCode`、`Action` | 数值一致的枚举 |
| `PlatformInfo.ts` | `ANDROID = false` | `ANDROID = true` |

规则：

- 共用代码不直接引用安卓上不存在、且一引用就出问题的模块，改从 `platform/` 取。目前有两类：
  - `@kit.UIDesignKit`：系统共享包，安卓上静态引用会在启动时终止进程。
  - 对没有跨平台实现的模块做命名导入（如按键码枚举）：会让整个页面加载失败。
- 其余没有跨平台实现的模块用默认导入时只是取到空值，用到才报错，可以先留着；它们在安卓构建日志里表现为“不支持跨平台”的警告，数量就是还没收进平台层的调用。
- 静态字段初始化里不要读系统模块的枚举或常量，改用取值函数。模块加载时系统没有这个模块，整页会加载失败。
- `PlatformInfo.ANDROID` 只用来关掉安卓上没有的系统能力，不用它分叉业务逻辑。
- 给 `platform/` 加符号时，两份实现要一起补。
- `HdsTabs` 是例外：它带专属属性，转一手导出后编译器认不出，使用处直接从 `@kit.UIDesignKit` 引入。这些分支都在 `ImmersiveMaterialRuntime.supportsHdsTabs()` 为真时才走，安卓构建脚本会把它们改写成普通 `Tabs` 以通过编译。

## 构建

```bash
node scripts/android/build-android.mjs --abi arm64-v8a
```

`--abi x86_64` 用于模拟器，`--offline` 不联网。产物在 `build/android/qingye-<版本>-<架构>.apk`，日志在 `build/android/ace-build.log`。

脚本做的事：

1. 把 `AppScope`、`entry`、书源内核、QuickJS、AI 引擎的源码同步到 `build/android/project`，写入安卓用的构建配置和 `android/project` 里的安卓工程壳。
2. 用 `android/overlay` 覆盖 `platform/`。
3. 做只在安卓成立的改写：`HdsTabs` 换成 `Tabs`；书源内核里几处没有跨平台实现的接口改成运行时动态取用。
4. 用 NDK 编译安卓版 `libquickjs.so`（QuickJS 源码首次构建时从 bellard.org 下载并校验）。
5. 调 ArkUI-X 的 `ace build apk` 编译打包，补上自己编的库后再用 Gradle 重新打包。

仓库里的源码不会被改动，生成工程可以随时删掉重来。

### 环境

| 变量 | 内容 |
| --- | --- |
| `ANDROID_SDK_ROOT` | 安卓 SDK，需要 `platforms;android-33`、`build-tools;30.0.3`、`ndk`、`cmake` |
| `ARKUIX_SDK_HOME` | ArkUI-X SDK 根目录。其中要有与 `AppScope/app.json5` 的 `targetAPIVersion` 同号的版本，在 DevEco Studio › Settings › ArkUI-X 里安装 |
| `DEVECO_HOME` | DevEco Studio 安装目录，默认 `C:/Program Files/Huawei/DevEco Studio` |
| `JAVA_HOME` | JDK 17 |

另需用 ArkUI-X SDK 里的 `ace config` 配置好 `--arkui-x-sdk`、`--android-sdk`、`--harmonyos-sdk`，`ace check` 里这三项通过。

### 约束

- `android/project/app/build.gradle` 的 `applicationId` 必须等于 `AppScope/app.json5` 的 `bundleName`，否则运行时找不到页面。
- 安卓模拟器要用本机显卡渲染（`-gpu host`），软件渲染下打开阅读页模拟器会崩溃。
