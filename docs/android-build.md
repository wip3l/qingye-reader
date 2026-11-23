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
| `SpeechKit.ts` | 转出 `textToSpeech` | 替身：经 `TtsBridge.java` 用安卓系统朗读合成 WAV，按鸿蒙引擎的 onStart/onData/onComplete 回调 PCM |
| `MediaSession.ts` | 转出 `avSession` | 替身：经 `MediaBridge.java` 用安卓 `MediaSession`，锁屏、耳机、通知栏命令回调回来 |
| `BackgroundTasks.ts` | 转出 `backgroundTaskManager` | 长时任务对应前台服务 `PlaybackService`（通知栏播放控件） |
| `LaunchAgent.ts` | `wantAgent.getWantAgent` 拉起 EntryAbility | 返回占位对象（拉起意图由 `PlaybackService` 设置） |
| `KeyConsumer.ts` | 转出 `inputConsumer` | 经 `KeyBridge.java` 在 Activity 的 `dispatchKeyEvent` 里接管按键（音量键翻页） |

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
- `HdsTabs` 是例外：它带专属属性，转一手导出后编译器认不出，使用处用 `import lazy { HdsTabs } from '@kit.UIDesignKit'` 直接引入，要系统包里的类型时用 `import type`。延迟加载的模块只在第一次用到时才加载，这些分支都在 `ImmersiveMaterialRuntime.supportsHdsTabs()` 为真时才走，安卓上不会加载这个包。构建脚本和 CI 检查都会拦下非延迟的引用。

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
- **朗读与听书**：音频焦点在 `MediaBridge` 里处理：来电、其它应用播放时发 pause 命令，短暂失去焦点结束后发 play 续播。
  离线朗读：鸿蒙上 sherpa_onnx 是只有鸿蒙原生库的 NAPI 包，安卓上整文件替换 `utils/localtts/LocalTtsEngine.ets`，经
  `SherpaBridge.java` 用 sherpa-onnx 的安卓 Java 接口（版本与鸿蒙端一致）。构建脚本从 GitHub 发布页下载 jar 和原生库、按 sha256
  校验后放进包里（只放目标架构的 `libsherpa-onnx-jni.so`、`libonnxruntime.so`，约 13 MB）。
- **手表翻页**：Wear Engine 是华为健康的系统共享包，ArkUI-X 实例化模块时就去加载，安卓上找不到直接终止进程，
  `import lazy` 也拦不住。安卓上整文件替换 `utils/WatchRemoteBridge.ets`（空实现）和 `utils/WatchTurnFeature.ts`（总开关恒为 false）。
- **整文件替换**：平台层之外只有上面三处，登记在 `platform-parity-check.mjs` 的 `WHOLE_FILE_OVERLAYS` 里；检查脚本核对导出名和
  类的公开静态成员，并禁止其它文件引用 `@kit.WearEngine`。
- **系统栏**：ArkUI-X 的 `getWindowAvoidArea` 在安卓上返回全 0，高度经 `SystemBridge.getSystemInsets` 读。状态栏图标深浅只认
  两个约定色（`#66000000` 深色图标、`#E5FFFFFF` 浅色图标），别的颜色不理，所以 `statusBarContentColor` 一律经
  `platform/SystemInsets.systemBarContentColor` 取。阅读正文时安卓总是收起导航栏（三键导航栏、手势条都会压住页脚），从边缘滑动可临时唤出；
  三键导航栏会接走落在上面的点击，实色底栏（非 HDS）因此整条抬到导航栏上面（`NAVIGATION_BAR_TAKES_TOUCHES`）。
- **网络超时**：ArkUI-X 安卓版的网络栈把 `readTimeout` 当成整个请求的时限（不是多久没数据），大文件下到一半就被掐断。
  流式下载的 `readTimeout` 一律经 `platform/HttpTimeouts.streamReadTimeout(空闲时限, 总时限)` 取，安卓上取总时限。
- **文件地址**：`@ohos.file.fileuri` 在安卓上没有实现，一律从 `platform/FileUri` 取 `fileUri`（检查脚本会拦）。
- **截图**：离屏组件截图（`getComponentSnapshot().get` 截被盖住的页面）在安卓上会连续超时三次、每次卡住渲染 2 秒。
  书架点按时截首页给“书籍打开动画”用，安卓上量不到封面位置（`componentUtils` 缺失），动画本来就做不出，所以安卓上关掉动画和截图，
  设置里也不显示开关。屏幕上可见组件的截图（仿真翻页、日夜切换揭开动画）正常。
- **打包时的插件库**：ace 按 ArkTS 编译产出的 `module_collection.json` 决定打进哪些插件库，增量编译时它只列重编的文件，
  会漏库（首选项、数据库等整个模块为空）。构建脚本每次清掉 ArkTS 编译缓存做全量编译，并检查清单是否完整。
- **书源内核**：内核分支 `arkuix-compat` 有两个安卓相关提交：ArkUI-X 缺失接口改成运行时取用；QuickJS 脚本会话的调用结果
  先移出等待表再兑现（否则安卓上同一会话连续的图片脚本调用会被当成“忙”）。子模块指针还没指向它时，构建脚本对前者做同样的
  文本改写，后者没有改写——用主线内核打出的安卓包，图片脚本同一会话连续调用会失败。分支推到内核主线、指针更新后，删掉
  `patchEngine` 那一段。验收：实验室 › 后台脚本线程验证 29/29 通过。

## 构建

```bash
node scripts/android/build-android.mjs --abi arm64-v8a
```

`--abi x86_64` 用于模拟器，`--offline` 不联网。产物在 `build/android/qingye-<版本>-<架构>.apk`，日志在 `build/android/ace-build.log`。

脚本做的事：

1. 把 `AppScope`、`entry`、书源内核、QuickJS、AI 引擎的源码同步到 `build/android/project`，写入安卓用的构建配置和 `android/project` 里的安卓工程壳。
2. 用 `android/overlay` 覆盖 `platform/`。
3. 检查共用代码没有静态引用 `@kit.UIDesignKit`；内核还没包含 ArkUI-X 兼容写法时，把几处没有跨平台实现的接口改成运行时动态取用。
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

## 真机验收

Redmi Note 11 Pro（Android 13，MIUI，三键导航，arm64）。

- 通过：本地导入（单本、文件夹全选 40 本）、阅读与续读、点按与滑动翻页、跨章、仿真翻页、字号实时重排、日夜切换（含状态栏图标）、
  系统朗读（后台 25 秒持续、媒体通知、耳机暂停/继续键）、密钥库加解密（重启后解密成功）。
- 冷启动（到首个界面）2.0–2.3 秒，装好后第一次 5.5 秒。打开书约 1.0 秒。
- 帧率：翻页动画 60 帧（每页约 14 帧、16 ms）；书架 41 本快速滑动平均 16.6–17.0 ms，最坏 33 ms；“我的”页平均 17.6 ms。
- 内存（PSS）：书架约 360 MB（41 本时约 470 MB），阅读页约 480 MB；其中原生堆 85–160 MB。
- 会员账号：登录、云同步（含自定义主题图片）、在线朗读额度显示正常；离线音色（超文，62 MB）下载、校验、sherpa-onnx 加载（1.5 秒）并播放。
- 网页解析书源：用本机测试源（`adb reverse` 转到电脑上的小服务器）走通导入、搜索、详情、目录、正文、预读下一章；书源调试页全链路通过。
  注意“精确搜索”时书名要和关键词一致才算命中。
- 未测：指纹解锁（要先录入指纹）。
- MIUI 第一次朗读会弹出系统语音引擎自己的同意页，要用户点同意。

## 发布

- **签名**：本机已生成发布密钥 `C:/Users/apart/.qingye/qingye-android-release.jks`（别名 `qingye`，RSA 4096，有效期约 27 年，
  证书 SHA-256 `6B:0D:09:2B:0D:B9:34:74:24:51:BD:63:D1:42:29:EB:46:0C:88:90:D6:C7:58:F2:FE:84:A3:BA:00:D5:64:9A`），
  口令在同目录的 `qingye-android-release.env`。**务必另外备份这两个文件**：丢了以后已发布的安装包无法再升级。
  发布构建前在 Git Bash 里 `set -a; . ~/.qingye/qingye-android-release.env; set +a`。
  原有说明：设置环境变量 `QINGYE_ANDROID_KEYSTORE`（keystore 路径）、`QINGYE_ANDROID_KEYSTORE_PASSWORD`、
  `QINGYE_ANDROID_KEY_ALIAS`、`QINGYE_ANDROID_KEY_PASSWORD` 后构建即用正式签名（V1 + V2）；缺任何一个都退回调试签名，
  Gradle 会给出警告，这样的包不能发布。
- **版本号**：`versionCode`、`versionName` 由构建脚本从 `AppScope/app.json5` 读取，与鸿蒙端一致。
- **混淆**：`minifyEnabled` 暂未开启（Java 代码只有几个原生桥）。规则已写在 `proguard-rules.pro`：原生桥的公开方法由
  ArkTS 按名字反射调用，必须保留。
- **包体积**：arm64 约 113 MB（含离线朗读的原生库约 13 MB），其中 ArkUI-X 引擎库 `libarkui_android.so` 压缩后约 36 MB。只发 arm64；眼动翻页用的人脸关键点
  模型（约 7 MB）不打进安卓包。
- **CI**：`.github/workflows/quality.yml` 跑 `scripts/android/platform-parity-check.mjs`，检查平台层两份实现一一对应、原生桥已注册、
  共用代码没有绕过平台层直接调系统能力。完整的安卓构建需要 ArkUI-X SDK 和 DevEco Studio 工具链，目前只能在本机或自建构建机上跑。
- **构建工具的绕过**（跟进 ArkUI-X 正式版后复查）：打 x86_64 包时补拷 `libhilog.so`；每次全量编译 ArkTS 以免插件库漏打；
  `ace` 在 `useNormalizedOHMUrl` 下要求 `.arkui-x/ios` 目录存在。
