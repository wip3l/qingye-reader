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
| `Files.ts` | 选择器、保存面板、`fs.copy` 原样调用 | 经原生文件桥（`FileBridge.java`）读写 `content://` 地址 |
| `TextCompare.ts` | `localeCompare` 原样调用 | ICU 不认的区域标记逐级退回 |
| `WindowBrightness.ts` | `setWindowBrightness` | 经 `SystemBridge.java` 改窗口亮度（ArkUI-X 不接受 -1“跟随系统”） |
| `SystemInsets.ts` | 返回 `null`，安全区由避让区接口决定 | 经 `SystemBridge.java` 读状态栏、导航栏高度（ArkUI-X 的避让区接口返回全 0） |
| `Cookies.ts` | `AppCookies` 即内核 `CookieStore`，不装端口 | 经 `CookieBridge.java` 读写安卓 `CookieManager`，并作为 Cookie 端口装进内核 |
| `KeystoreCipher.ts` | HUKS 的 AES-256-CBC | 经 `SecretBridge.java` 用安卓密钥库，参数相同 |

原生桥都在 `android/project/app/src/main/java/io/legado/read/` 下，在 `EntryEntryAbilityActivity.onCreate` 里注册；
返回值约定为 JSON 字符串，失败时带 `error` 字段（`CookieBridge` 返回纯字符串，供同步调用）。

规则：

- 共用代码不直接引用安卓上不存在、且一引用就出问题的模块，改从 `platform/` 取。目前有两类：
  - `@kit.UIDesignKit`：系统共享包，安卓上静态引用会在启动时终止进程。
  - 对没有跨平台实现的模块做命名导入（如按键码枚举）：会让整个页面加载失败。
- 其余没有跨平台实现的模块用默认导入时只是取到空值，用到才报错，可以先留着；它们在安卓构建日志里表现为“不支持跨平台”的警告，数量就是还没收进平台层的调用。
- 静态字段初始化里不要读系统模块的枚举或常量，改用取值函数。模块加载时系统没有这个模块，整页会加载失败。
- `PlatformInfo.ANDROID` 只用来关掉安卓上没有的系统能力，不用它分叉业务逻辑。
- 给 `platform/` 加符号时，两份实现要一起补。
- `HdsTabs` 是例外：它带专属属性，转一手导出后编译器认不出，使用处直接从 `@kit.UIDesignKit` 引入。这些分支都在 `ImmersiveMaterialRuntime.supportsHdsTabs()` 为真时才走，安卓构建脚本会把它们改写成普通 `Tabs` 以通过编译。

### 选文件、存文件

共用代码不直接调 `DocumentViewPicker`、`PhotoViewPicker` 和 `fs.copy`，改用 `platform/Files` 的
`selectDocuments`、`selectImages`、`saveDocuments`、`copyFile`、`writeTextFile`。

- 安卓的选择器返回 `content://` 地址，ArkUI-X 的 `fs` 打不开。安卓实现选完后经文件桥把每个文件复制到
  `<cacheDir>/picked/<批次>/<序号>/<原文件名>`，返回沙箱路径，文件名和后缀保持原样。所以选文件的结果要按
  “以 `/` 开头的是沙箱路径，其余是地址”对待，现有的 `uri.startsWith('/') ? getUriFromPath(uri) : uri` 写法正好适用。
  缓存里的副本一天后清掉，要长期保留的应自己再复制一份。
- `fileSuffixFilters` 照鸿蒙写法给。ArkUI-X 的安卓选择器会把每项过滤条件猜成一个 MIME 类型，猜不出就整类变灰，
  所以安卓实现不交给选择器过滤，选完再按后缀筛掉不符合的。
- 安卓上没有 `PhotoViewPicker`，`selectImages` 用文档选择器按图片类型选。
- 写往保存地址：`copyFile(沙箱路径, 地址)`，或用 `writeTextFile` 直接写文本。
- 原生侧在 `android/project/app/src/main/java/io/legado/read/FileBridge.java`，桥名 `io.legado.read/file`，
  在 `EntryEntryAbilityActivity.onCreate` 里注册。ArkTS 发起的调用由 ArkUI-X 放在后台线程执行。

### 其它安卓差异

- **Cookie**：内核取 Cookie 一律经 `CookieStore.forSource`，装了端口就走端口。应用代码读写 Cookie 用 `AppCookies`，
  不直接调 `CookieStore` 的静态方法，这样安卓上书源请求和网页组件（登录页、验证页）共用同一个 Cookie 库。
- **隐藏的 Web 运行环境**（书源脚本用的 1×1 `Web`）要设 `.focusable(false)`：安卓上 Web 拿到焦点会吞掉返回键。
- **沉浸光感**：安卓上没有系统材质，`ImmersiveMaterialRuntime.effectiveLevel` 把跟随系统/高档按弱档（实色底）画。
- **握姿、智控键**：安卓上关闭，设置页不显示握姿开关。
- **书源内核**：内核分支 `arkuix-compat` 把 ArkUI-X 缺失接口改成了运行时取用。子模块指针还没指向它时，构建脚本
  做同样的文本改写；指过去之后脚本会跳过，届时删掉 `patchEngine` 那一段。

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
