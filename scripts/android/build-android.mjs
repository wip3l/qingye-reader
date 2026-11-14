// 生成并构建安卓版（ArkUI-X）。
//
// 共用代码只从 entry/src/main/ets/platform/ 取系统能力。本脚本把仓库源码同步到 build/android/project，
// 用 android/overlay 里的安卓实现替换 platform/，再做少量只在安卓成立的改写，然后交给 ArkUI-X 的 ace 打包。
// 仓库里的鸿蒙代码不会被改动，安卓专属代码也不会进鸿蒙包。
//
// 用法：node scripts/android/build-android.mjs [--abi arm64-v8a|x86_64] [--offline]
// 需要的环境（未设时用括号里的默认值）：
//   ANDROID_SDK_ROOT   安卓 SDK，含 platforms;android-33、build-tools;30.0.3、ndk、cmake
//   ARKUIX_SDK_HOME    ArkUI-X SDK 根目录（其下为 <版本>/arkui-x）
//   DEVECO_HOME        DevEco Studio 安装目录（C:/Program Files/Huawei/DevEco Studio）
//   JAVA_HOME          JDK 17
// ace 需要事先配置过（ace config --arkui-x-sdk / --android-sdk / --harmonyos-sdk），`ace check` 里
// ArkUI-X、HarmonyOS、Android 三项通过即可。联网一律直连，脚本会清掉代理环境变量。

import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const OUT = path.join(REPO, 'build', 'android');
const GEN = path.join(OUT, 'project');
const CACHE = path.join(OUT, 'cache');

// QuickJS 本体版本要和 harmony-book-source-engine/quickjs/src/main/cpp/include/quickjs.h 对应。
const QJS_VERSION = '2024-01-13';
const QJS_URL = `https://bellard.org/quickjs/quickjs-${QJS_VERSION}.tar.xz`;
const QJS_SHA256 = '3c4bf8f895bfa54beb486c8d1218112771ecfc5ac3be1036851ef41568212e03';
const ARKUIX_HVIGOR_PLUGIN = process.env.QINGYE_ARKUIX_HVIGOR_PLUGIN || '4.23.6';

const ABIS = {
  'arm64-v8a': { ace: 'arm64', hilogDir: 'android-arm64-release' },
  'x86_64': { ace: 'x86_64', hilogDir: 'android-x86_64' }
};

const args = process.argv.slice(2);
const abi = args.includes('--abi') ? args[args.indexOf('--abi') + 1] : 'arm64-v8a';
const offline = args.includes('--offline');
if (!ABIS[abi]) fail(`不支持的 --abi ${abi}，可选：${Object.keys(ABIS).join('、')}`);

function fail(message) {
  console.error(`[android] ${message}`);
  process.exit(1);
}

function step(message) {
  console.log(`[android] ${message}`);
}

function directEnv(extra = {}) {
  const env = { ...process.env, ...extra };
  for (const key of Object.keys(env)) {
    if (/^(http_proxy|https_proxy|all_proxy)$/i.test(key)) delete env[key];
  }
  return env;
}

function run(command, commandArgs, options = {}) {
  if (options.shell) {
    // 经 shell 执行时（Windows 上的 .bat）Node 不会替我们加引号，带空格的路径要自己包起来。
    const quote = (value) => (/[\s&()]/.test(value) ? `"${value}"` : value);
    command = quote(command);
    commandArgs = commandArgs.map(quote);
  }
  const result = spawnSync(command, commandArgs, {
    cwd: options.cwd || REPO,
    env: directEnv(options.env),
    stdio: options.capture ? ['ignore', 'pipe', 'pipe'] : 'inherit',
    shell: options.shell || false,
    encoding: 'utf8',
    maxBuffer: 256 * 1024 * 1024
  });
  if (result.error) fail(`${command} 无法执行：${result.error.message}`);
  if (result.status !== 0 && !options.allowFailure) {
    if (options.capture) console.error((result.stdout || '') + (result.stderr || ''));
    fail(`${path.basename(command)} ${commandArgs.slice(0, 3).join(' ')} 失败（退出码 ${result.status}）`);
  }
  return result;
}

function requireDir(dir, hint) {
  if (!dir || !fs.existsSync(dir)) fail(`找不到 ${hint}：${dir || '(未设置)'}`);
  return dir.replace(/\\/g, '/');
}

// ---------- 环境 ----------

const androidSdk = requireDir(process.env.ANDROID_SDK_ROOT || process.env.ANDROID_HOME, '安卓 SDK（ANDROID_SDK_ROOT）');
const arkuixHome = requireDir(process.env.ARKUIX_SDK_HOME, 'ArkUI-X SDK（ARKUIX_SDK_HOME）');
const devecoHome = requireDir(process.env.DEVECO_HOME || 'C:/Program Files/Huawei/DevEco Studio', 'DevEco Studio（DEVECO_HOME）');
const javaHome = requireDir(process.env.JAVA_HOME, 'JDK（JAVA_HOME）');

function readJson5Field(file, field) {
  const match = fs.readFileSync(file, 'utf8').match(new RegExp(`"${field}"\\s*:\\s*("?)([^",\\n}]+)\\1`));
  return match ? match[2].trim() : '';
}

const targetApi = readJson5Field(path.join(REPO, 'AppScope', 'app.json5'), 'targetAPIVersion');
const versionCode = readJson5Field(path.join(REPO, 'AppScope', 'app.json5'), 'versionCode');
const versionName = readJson5Field(path.join(REPO, 'AppScope', 'app.json5'), 'versionName');
const bundleName = readJson5Field(path.join(REPO, 'AppScope', 'app.json5'), 'bundleName');

function findArkuixSdk() {
  // hvigor 要求 ArkUI-X SDK 与编译用的 API 版本同号，按 app.json5 的 targetAPIVersion 找。
  for (const name of fs.readdirSync(arkuixHome)) {
    const meta = path.join(arkuixHome, name, 'arkui-x', 'arkui-x.json');
    if (!fs.existsSync(meta)) continue;
    if (String(JSON.parse(fs.readFileSync(meta, 'utf8')).apiVersion) === String(targetApi)) {
      return path.join(arkuixHome, name, 'arkui-x').replace(/\\/g, '/');
    }
  }
  fail(`${arkuixHome} 下没有 API ${targetApi} 的 ArkUI-X SDK，请在 DevEco Studio › Settings › ArkUI-X 里安装`);
  return '';
}

const arkuixSdk = findArkuixSdk();
const aceTools = path.join(arkuixSdk, 'toolchains', 'ace_tools', 'lib', 'ace_tools.js');
const ohpm = path.join(devecoHome, 'tools', 'ohpm', 'bin', process.platform === 'win32' ? 'ohpm.bat' : 'ohpm');

// ---------- 1. 同步源码 ----------

const SKIP_DIRS = new Set(['build', 'oh_modules', '.cxx', '.hvigor', '.preview', '.test', 'ohosTest', 'test', 'example']);

function syncDir(relative) {
  const from = path.join(REPO, relative);
  const to = path.join(GEN, relative);
  if (!fs.existsSync(from)) fail(`缺少 ${relative}，子模块是否已初始化（git submodule update --init）？`);
  // 只清源码，保留生成工程里的 build / oh_modules 缓存。oh_modules 里是指向本地模块的链接，绝不递归删除。
  if (fs.existsSync(to)) {
    for (const entry of fs.readdirSync(to, { withFileTypes: true })) {
      if (SKIP_DIRS.has(entry.name)) continue;
      fs.rmSync(path.join(to, entry.name), { recursive: true, force: true });
    }
  }
  fs.cpSync(from, to, {
    recursive: true,
    filter: (source) => !SKIP_DIRS.has(path.basename(source))
  });
}

function write(relative, text) {
  const file = path.join(GEN, relative);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, text);
}

step(`生成工程 ${path.relative(REPO, GEN)}（${versionName}，${abi}）`);
fs.mkdirSync(GEN, { recursive: true });
const MODULES = [
  { name: 'entry', dir: 'entry' },
  { name: 'sourceengine', dir: 'harmony-book-source-engine/sourceengine' },
  { name: 'quickjs', dir: 'harmony-book-source-engine/quickjs' },
  { name: 'aiengine', dir: 'harmony-book-ai-engine/aiengine' }
];
syncDir('AppScope');
for (const module of MODULES) syncDir(module.dir);
// 安卓首版不带眼动翻页（EyeTurnController 在安卓上不启动），人脸关键点模型（约 7 MB）不打进包。
const ANDROID_EXCLUDED_ASSETS = ['harmony-book-ai-engine/aiengine/src/main/resources/rawfile/face-landmarks'];
for (const relative of ANDROID_EXCLUDED_ASSETS) fs.rmSync(path.join(GEN, relative), { recursive: true, force: true });
fs.copyFileSync(path.join(REPO, 'oh-package.json5'), path.join(GEN, 'oh-package.json5'));

const compatibleSdk = readJson5Field(path.join(REPO, 'build-profile.json5'), 'compatibleSdkVersion');
const targetSdk = readJson5Field(path.join(REPO, 'build-profile.json5'), 'targetSdkVersion');
write('build-profile.json5', JSON.stringify({
  app: {
    signingConfigs: [],
    products: [{
      name: 'default',
      signingConfig: 'default',
      compatibleSdkVersion: compatibleSdk,
      targetSdkVersion: targetSdk,
      runtimeOS: 'HarmonyOS',
      buildOption: { strictMode: { caseSensitiveCheck: true, useNormalizedOHMUrl: true } }
    }],
    buildModeSet: [{ name: 'debug' }, { name: 'release' }]
  },
  modules: MODULES.map((module) => module.name === 'entry'
    ? { name: module.name, srcPath: `./${module.dir}`, targets: [{ name: 'default', applyToProducts: ['default'] }] }
    : { name: module.name, srcPath: `./${module.dir}` })
}, null, 2));
write('hvigor/hvigor-config.json5', JSON.stringify({
  modelVersion: readJson5Field(path.join(REPO, 'hvigor', 'hvigor-config.json5'), 'modelVersion'),
  dependencies: { '@ohos/hvigor-ohos-arkui-x-plugin': ARKUIX_HVIGOR_PLUGIN }
}, null, 2));
write('hvigorfile.ts', "export { AppTasksForArkUIX } from '@ohos/hvigor-ohos-arkui-x-plugin';\n");
write('entry/hvigorfile.ts', "export { HapTasks } from '@ohos/hvigor-ohos-arkui-x-plugin';\n");
write('.projectInfo', JSON.stringify({ projectTemplate: 'app', moduleInfo: [], abilityInfo: [], platforms: ['android'] }, null, 2));
write('local.properties', `arkui-x.dir=${arkuixHome.replace(/:/g, '\\:')}\n`);
// ignoreCrossPlatform：把“不支持跨平台的接口”从报错降为警告。警告清单就是还没收进 platform/ 的系统调用。
write('.arkui-x/arkui-x-config.json5', JSON.stringify({
  crossplatform: true,
  modules: ['entry'],
  buildOption: { ignoreCrossPlatform: true }
}, null, 2));
// ace 在 useNormalizedOHMUrl 下会往 ios 目录写 pkgContextInfo.json，目录不存在就中止。
fs.mkdirSync(path.join(GEN, '.arkui-x', 'ios', 'arkui-x', 'entry'), { recursive: true });

// 安卓工程壳
const shell = path.join(GEN, '.arkui-x', 'android');
fs.cpSync(path.join(REPO, 'android', 'project'), shell, { recursive: true });
fs.copyFileSync(
  path.join(arkuixSdk, 'toolchains', 'ace_tools', 'templates', 'android', 'gradle', 'wrapper', 'gradle-wrapper.jar'),
  path.join(shell, 'gradle', 'wrapper', 'gradle-wrapper.jar'));
write('.arkui-x/android/local.properties', `sdk.dir=${androidSdk.replace(/:/g, '\\:')}\n`);
// 应用图标：鸿蒙分层图标的两层直接做安卓自适应图标（mipmap-anydpi-v26/ic_launcher.xml）的两层。
const shellRes = path.join(shell, 'app', 'src', 'main', 'res');
fs.rmSync(path.join(shellRes, 'drawable', 'app_icon.png'), { force: true });
fs.mkdirSync(path.join(shellRes, 'drawable-nodpi'), { recursive: true });
for (const [from, to] of [['background.png', 'ic_launcher_background.png'], ['foreground.png', 'ic_launcher_foreground.png']]) {
  fs.copyFileSync(path.join(REPO, 'AppScope', 'resources', 'base', 'media', from), path.join(shellRes, 'drawable-nodpi', to));
}
// 应用名跟鸿蒙端一致。
const appNameMatch = fs.readFileSync(path.join(REPO, 'AppScope', 'resources', 'base', 'element', 'string.json'), 'utf8')
  .match(/"name"\s*:\s*"app_name"\s*,\s*"value"\s*:\s*"([^"]+)"/);
if (!appNameMatch) fail('AppScope/resources/base/element/string.json 里没有 app_name');
const xmlEscape = (value) => value.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/'/g, "\\'");
write('.arkui-x/android/app/src/main/res/values/strings.xml',
  `<resources>\n    <string name="app_name">${xmlEscape(appNameMatch[1])}</string>\n</resources>\n`);
const gradleAppId = (fs.readFileSync(path.join(shell, 'app', 'build.gradle'), 'utf8').match(/applicationId\s+"([^"]+)"/) || [])[1];
if (gradleAppId !== bundleName) {
  fail(`android/project/app/build.gradle 的 applicationId（${gradleAppId}）必须等于 app.json5 的 bundleName（${bundleName}）`);
}

// ---------- 2. 套用安卓实现 ----------

fs.cpSync(path.join(REPO, 'android', 'overlay'), GEN, { recursive: true });

// ---------- 3. 只在安卓成立的改写 ----------

function listSources(dir, out = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (SKIP_DIRS.has(entry.name)) continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) listSources(full, out);
    else if (/\.(ets|ts)$/.test(entry.name) && !entry.name.endsWith('.d.ts')) out.push(full);
  }
  return out;
}

// @kit.UIDesignKit 是鸿蒙的系统共享包，安卓上静态引用会在启动时终止进程。共用代码里只有 HdsTabs 直接从它引入
// （带专属属性，转一手导出后编译器认不出），且一律用 `import lazy`：只在 supportsHdsTabs() 为真时才加载，安卓上不会。
// 只用作类型的 `import type` 编译后不留痕迹，也允许。这里只检查，不改写：发现会在运行时加载的引用就停下。
const entrySources = listSources(path.join(GEN, 'entry', 'src', 'main', 'ets'));
for (const file of entrySources) {
  const source = fs.readFileSync(file, 'utf8');
  if (/^\s*import\s+(?!lazy\b|type\b)[^;]*from\s*'@kit\.UIDesignKit'/m.test(source)) {
    fail(`${path.relative(GEN, file)} 静态引用了 @kit.UIDesignKit：HdsTabs 请用 import lazy，其它 HDS 符号从 platform/Hds 引入`);
  }
}

// 书源内核里没有跨平台实现的接口：改成运行时动态取用，取不到就走原有的异常兜底。
// 内核分支 arkuix-compat 已经把同样的写法做进源码；子模块指针更新到包含它的提交后，下面每个文件都会因为
// 已有标记而跳过，届时删掉这一段。marker 是改写后才有的文字。
let engineFilesPatched = 0;
function patchEngine(relative, marker, replacements) {
  const file = path.join(GEN, 'harmony-book-source-engine', 'sourceengine', 'src', 'main', 'ets', relative);
  let text = fs.readFileSync(file, 'utf8');
  if (text.includes(marker)) return;
  engineFilesPatched++;
  for (const [from, to, all] of replacements) {
    if (!text.includes(from)) fail(`内核改写失效：${relative} 里找不到 “${from.slice(0, 60)}”，内核代码变了，请同步更新 build-android.mjs`);
    text = all ? text.split(from).join(to) : text.replace(from, to);
  }
  fs.writeFileSync(file, text);
}

patchEngine('core/http/CookieStore.ts', 'const webCookieManager: any', [
  ['webview.WebCookieManager.', 'webCookieManager.', true],
  ['export class CookieStore {', 'const webCookieManager: any = webview.WebCookieManager;\n\nexport class CookieStore {']
]);
patchEngine('core/http/HttpFinalUrlObserver.ts', 'const httpDynamic: any', [
  ['export class HttpFinalUrlObserver {', 'const httpDynamic: any = http;\n\nexport class HttpFinalUrlObserver {'],
  ['new http.HttpInterceptorChain()', 'new httpDynamic.HttpInterceptorChain()'],
  ['const interceptor: http.HttpInterceptor = {', 'const interceptor: any = {'],
  ['http.InterceptorType.FINAL_RESPONSE', 'httpDynamic.InterceptorType.FINAL_RESPONSE'],
  ['async (request: http.HttpRequestContext, _response: http.HttpResponse): Promise<boolean> => {',
    'async (request: any, _response: any): Promise<boolean> => {'],
  ['const interceptors: http.HttpInterceptor[] = [];', 'const interceptors: any[] = [];'],
  ['http.InterceptorType.REDIRECTION', 'httpDynamic.InterceptorType.REDIRECTION'],
  ['async (_request: http.HttpRequestContext, _response: http.HttpResponse): Promise<boolean> => false',
    'async (_request: any, _response: any): Promise<boolean> => false']
]);
patchEngine('core/http/HttpClient.ts', '(options as any).remoteValidation', [
  ["options.remoteValidation = 'skip';", "(options as any).remoteValidation = 'skip';"]
]);
patchEngine('core/http/RawHttpTextClient.ts', '(connection as any).getAddressesByName', [
  ['await connection.getAddressesByName(target.host)', 'await (connection as any).getAddressesByName(target.host)']
]);
patchEngine('core/nativesource/NativeSourceService.ts', '(deviceInfo as any).ODID', [
  ["return deviceInfo.ODID || '';", "return (deviceInfo as any).ODID || '';"]
]);
step(engineFilesPatched ? `改写书源内核：${engineFilesPatched} 个文件（内核尚未包含 arkuix-compat）` : '书源内核已包含 ArkUI-X 兼容写法，无需改写');

// ---------- 4. QuickJS ----------

function sha256(file) {
  return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
}

function newestMtime(dir) {
  let newest = 0;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    newest = Math.max(newest, entry.isDirectory() ? newestMtime(full) : fs.statSync(full).mtimeMs);
  }
  return newest;
}

function buildQuickJs() {
  const wrapDir = path.join(REPO, 'harmony-book-source-engine', 'quickjs', 'src', 'main', 'cpp');
  const output = path.join(CACHE, 'quickjs', abi, 'libquickjs.so');
  const cmakeLists = path.join(REPO, 'android', 'quickjs');
  const inputsMtime = Math.max(newestMtime(wrapDir), newestMtime(cmakeLists));
  if (fs.existsSync(output) && fs.statSync(output).mtimeMs > inputsMtime) return output;

  const sourceDir = path.join(CACHE, `quickjs-${QJS_VERSION}`);
  if (!fs.existsSync(path.join(sourceDir, 'quickjs.c'))) {
    const archive = path.join(CACHE, `quickjs-${QJS_VERSION}.tar.xz`);
    fs.mkdirSync(CACHE, { recursive: true });
    if (!fs.existsSync(archive)) {
      if (offline) fail(`离线模式下缺少 ${archive}`);
      step(`下载 QuickJS ${QJS_VERSION} 源码`);
      run('curl', ['-L', '--fail', '--noproxy', '*', '-sS', '-o', archive, QJS_URL]);
    }
    if (sha256(archive) !== QJS_SHA256) fail(`${archive} 校验值不符，已中止`);
    run('tar', ['-xJf', path.basename(archive)], { cwd: CACHE });
  }

  const ndkRoot = path.join(androidSdk, 'ndk');
  const ndkVersion = fs.existsSync(ndkRoot) ? fs.readdirSync(ndkRoot).sort().pop() : '';
  if (!ndkVersion) fail(`${ndkRoot} 下没有 NDK，请用 sdkmanager 安装 ndk`);
  const cmakeRoot = path.join(androidSdk, 'cmake');
  const cmakeVersion = fs.existsSync(cmakeRoot) ? fs.readdirSync(cmakeRoot).sort().pop() : '';
  if (!cmakeVersion) fail(`${cmakeRoot} 下没有 CMake，请用 sdkmanager 安装 cmake`);
  const exe = process.platform === 'win32' ? '.exe' : '';
  const cmake = path.join(cmakeRoot, cmakeVersion, 'bin', `cmake${exe}`);
  const ninja = path.join(cmakeRoot, cmakeVersion, 'bin', `ninja${exe}`);
  const ndk = path.join(ndkRoot, ndkVersion);
  const buildDir = path.join(CACHE, 'quickjs', abi, 'cmake');

  step(`编译 libquickjs.so（${abi}，NDK ${ndkVersion}）`);
  const forward = (value) => value.replace(/\\/g, '/');
  run(cmake, ['-S', forward(cmakeLists), '-B', forward(buildDir), '-G', 'Ninja',
    `-DCMAKE_MAKE_PROGRAM=${forward(ninja)}`,
    `-DCMAKE_TOOLCHAIN_FILE=${forward(path.join(ndk, 'build', 'cmake', 'android.toolchain.cmake'))}`,
    `-DANDROID_ABI=${abi}`, '-DANDROID_PLATFORM=android-26', '-DANDROID_STL=c++_static', '-DCMAKE_BUILD_TYPE=Release',
    `-DQJS_SRC_DIR=${forward(sourceDir)}`, `-DWRAP_SRC_DIR=${forward(wrapDir)}`,
    `-DARKUIX_SDK=${arkuixSdk}`, `-DQJS_VERSION=${QJS_VERSION}`], { capture: true });
  run(cmake, ['--build', forward(buildDir)], { capture: true });
  const hostTag = process.platform === 'win32' ? 'windows-x86_64' : process.platform === 'darwin' ? 'darwin-x86_64' : 'linux-x86_64';
  const strip = path.join(ndk, 'toolchains', 'llvm', 'prebuilt', hostTag, 'bin', `llvm-strip${exe}`);
  const built = path.join(buildDir, 'libquickjs.so');
  run(strip, ['--strip-unneeded', built]);
  fs.copyFileSync(built, output);
  return output;
}

const quickJsLib = buildQuickJs();

// ---------- 5. ArkTS 编译与打包 ----------

step('安装依赖（ohpm）');
run(ohpm, ['install'], { cwd: GEN, capture: true, shell: process.platform === 'win32' });

// ace 按 ArkTS 编译产出的 module_collection.json 决定打进哪些插件库（首选项、数据库、网络等）。
// 增量编译时这个文件只列本次重编的源文件，没列到的模块的库就漏打，运行时整个模块是空的。
// 所以每次都清掉 ArkTS 编译缓存做全量编译；跨平台警告数也只有全量编译时才完整。
const arkTsCache = path.join(GEN, 'entry', 'build', 'default', 'cache', 'default', 'default@CompileArkTS');
fs.rmSync(arkTsCache, { recursive: true, force: true });

step('ace build apk（ArkTS 编译 + 首次打包）');
const aceLog = path.join(OUT, 'ace-build.log');
const ace = run(process.execPath, [aceTools, 'build', 'apk', '--target-platform', ABIS[abi].ace], {
  cwd: GEN, capture: true, allowFailure: true,
  env: { ANDROID_HOME: androidSdk, ANDROID_SDK_ROOT: androidSdk, JAVA_HOME: javaHome }
});
const aceOutput = ((ace.stdout || '') + (ace.stderr || '')).replace(/\x1b\[[0-9;]*[A-Za-z]/g, '');
fs.writeFileSync(aceLog, aceOutput);
const crossPlatformWarnings = (aceOutput.match(/can't support crossplatform application/g) || []).length;
if (ace.status !== 0 || !/APK file built successfully/.test(aceOutput)) {
  const errors = aceOutput.split(/\r?\n/).filter((line) => /^\d+ ERROR|hvigor ERROR|Error Message|Compile failed|FAILED/.test(line));
  console.error(errors.slice(0, 40).join('\n'));
  fail(`ace build 失败，完整日志见 ${path.relative(REPO, aceLog)}`);
}
step(`ArkTS 编译通过；尚未收进 platform/ 的跨平台警告 ${crossPlatformWarnings} 处`);

// 兜底：模块清单若只覆盖少数源文件，说明又走了增量编译，打出来的包会缺库。
const moduleCollection = path.join(arkTsCache, 'esmodule', 'release', 'module_collection.json');
const collectedFiles = fs.existsSync(moduleCollection) ?
  Object.keys(JSON.parse(fs.readFileSync(moduleCollection, 'utf8'))).length : 0;
const sourceFiles = entrySources.length;
// 只有引用了系统模块的文件才会列出（全量编译时约占一半），远低于此就是增量编译的结果。
if (collectedFiles < sourceFiles / 4) {
  fail(`module_collection.json 只列了 ${collectedFiles} 个源文件（共 ${sourceFiles} 个），插件库会漏打，请删掉 ${path.relative(REPO, GEN)} 后重试`);
}

// ace 每次都会重置 app/libs，自己编的库和它漏拷的库要在它之后补上，再重新打包。
const libDir = path.join(shell, 'app', 'libs', abi);
fs.copyFileSync(quickJsLib, path.join(libDir, 'libquickjs.so'));
const hilog = path.join(arkuixSdk, 'plugins', 'api', 'lib', 'hilog', ABIS[abi].hilogDir, 'libhilog.so');
if (!fs.existsSync(path.join(libDir, 'libhilog.so')) && fs.existsSync(hilog)) {
  // ArkUI-X 26.0.0.28 打 x86_64 包时漏拷日志库，一用 hilog 就白屏。
  fs.copyFileSync(hilog, path.join(libDir, 'libhilog.so'));
}

step('gradle assembleRelease');
const gradlew = path.join(shell, process.platform === 'win32' ? 'gradlew.bat' : 'gradlew');
run(gradlew, ['assembleRelease', '-q', `-PqingyeVersionCode=${versionCode}`, `-PqingyeVersionName=${versionName}`,
  ...(offline ? ['--offline'] : [])], {
  cwd: shell, capture: true, shell: process.platform === 'win32',
  env: { ANDROID_HOME: androidSdk, ANDROID_SDK_ROOT: androidSdk, JAVA_HOME: javaHome }
});

const builtApk = path.join(shell, 'app', 'build', 'outputs', 'apk', 'release', 'app-release.apk');
if (!fs.existsSync(builtApk)) fail('没有找到打包产物 app-release.apk');
const finalApk = path.join(OUT, `qingye-${versionName}-${abi}.apk`);
fs.copyFileSync(builtApk, finalApk);
step(`完成：${path.relative(REPO, finalApk)}（${(fs.statSync(finalApk).size / 1048576).toFixed(1)} MB）`);
