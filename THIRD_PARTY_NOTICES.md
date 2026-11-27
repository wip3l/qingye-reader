# 第三方开源软件声明

本项目及其发行的 HAP 包含下列第三方开源软件。项目自身的 GPL-3.0 许可证不替代这些组件各自的许可证、版权声明或免责声明。

## ohos_quickjs

- 组件：`@devzeng/quickjs` / `ohos_quickjs`
- 上游项目：https://github.com/hhtczengjing/ohos_quickjs
- 许可证：MIT
- 版权所有：Copyright (c) 2026 zengjing

本项目对该组件进行了 HarmonyOS 集成、稳定性和能力扩展方面的修改。该组件随书源解析内核一起放在子模块 `harmony-book-source-engine/quickjs/`，原始 MIT 许可见 [harmony-book-source-engine/quickjs/LICENSE](harmony-book-source-engine/quickjs/LICENSE)，发行包内许可合集见 [THIRD_PARTY_LICENSES.txt](entry/src/main/resources/rawfile/licenses/THIRD_PARTY_LICENSES.txt)。

## QuickJS

- 组件：QuickJS JavaScript Engine
- 上游项目：https://bellard.org/quickjs/
- 许可证：MIT
- 版权所有：Copyright (c) 2017-2021 Fabrice Bellard；Copyright (c) 2017-2021 Charlie Gordon

## PocketPy

- 组件：PocketPy Lightweight Python 3 Interpreter（v1.4.6 单头文件，位于 `pluginengine/src/main/cpp/third_party/pocketpy/`）
- 上游项目：https://github.com/pocketpy/pocketpy
- 许可证：MIT
- 版权所有：Copyright (c) 2023 blueloveTH

用于插件引擎（`@legado/pluginengine`）里沙箱化的 Python 插件运行时（关闭操作系统模块，只暴露受控的宿主接口）。原始 MIT 许可见 [pluginengine/src/main/cpp/third_party/pocketpy/LICENSE](pluginengine/src/main/cpp/third_party/pocketpy/LICENSE)，发行包内的许可合集见 [THIRD_PARTY_LICENSES.txt](entry/src/main/resources/rawfile/licenses/THIRD_PARTY_LICENSES.txt)。

## OpenHarmony / Huawei N-API 封装代码

- 组件：带有 Huawei Device Co., Ltd. 版权头的 N-API 封装源文件
- 许可证：Apache License 2.0
- 版权所有：Copyright (c) 2021-2022 Huawei Device Co., Ltd.

本项目修改过的相关文件继续保留原始版权和许可证头；修改内容主要包括 QuickJS 运行时适配、句柄安全、受限执行和 HarmonyOS 应用集成。

## acorn

- 组件：acorn JavaScript 解析器（压缩后内置于 `harmony-book-source-engine/sourceengine/src/main/ets/core/book/StageScriptParserSource.ts`，由 `harmony-book-source-engine/scripts/generate-stage-script-parser.mjs` 生成）
- 上游项目：https://github.com/acornjs/acorn
- 许可证：MIT
- 版权所有：Copyright (C) 2012-2022 by various contributors

用于在分阶段运行时里解析兼容书源脚本，使脚本返回值与 Android 端 Rhino 一致。

## OpenCC 繁简字典

- 上游：https://github.com/BYVoid/OpenCC/tree/ver.1.1.9
- 版本：ver.1.1.9；作者：BYVoid and OpenCC contributors
- 文件：TSCharacters.txt、TSPhrases.txt、STCharacters.txt、STPhrases.txt、TWVariants.txt（未修改）
- 许可证：Apache-2.0
- 用途：漫画识别文本与小说正文的繁→简转换、搜索关键词的简繁互转（台湾用字），应用自行实现词组最长匹配适配器，不包含完整 OpenCC 引擎。
- 字典、来源校验及完整许可证见 `harmony-book-ai-engine/aiengine/src/main/resources/rawfile/opencc/`，由 HAR 合并到 HAP，应用开源许可页面显示许可全文。

## Manga-Colorizer 着色模型

- 固定上游来源、权重和转换参数见 [model.json](harmony-book-ai-engine/aiengine/src/main/resources/rawfile/comic-colorizer/model.json)。
- 上游仓库 MIT 声明及完整许可随模型保存在 [LICENSE](harmony-book-ai-engine/aiengine/src/main/resources/rawfile/comic-colorizer/LICENSE)，由 AI HAR 合并到 HAP。

## MediaPipe 人脸关键点模型

- 上游：MediaPipe Face Landmarker v1（float16），作者：The MediaPipe Authors
- 许可证：Apache-2.0
- 用途：转换为 MindSpore Lite 格式，在设备上估计视线方向，用于眼动翻页；相机画面只在本机处理。
- 来源、转换参数与 SHA-256 见 [model.json](harmony-book-ai-engine/aiengine/src/main/resources/rawfile/face-landmarks/model.json)，声明见 [LICENSE](harmony-book-ai-engine/aiengine/src/main/resources/rawfile/face-landmarks/LICENSE)，由 AI HAR 合并到 HAP。

## 听书 AI 字幕模型（按需下载，不随安装包分发）

- 语音识别：sherpa-onnx 中文 Zipformer CTC int8（2025-07-03），作者：Xiaomi Corporation and the k2-fsa authors，许可证：Apache-2.0
- 标点：CT-Transformer zh-en vocab272727 int8，原始模型来自阿里达摩院 FunASR（ModelScope `iic/punc_ct-transformer_zh-cn-common-vocab272727-pytorch`），许可证：Apache-2.0
- 用途：在设备上把有声书音频识别成字幕并加标点，音频不上传。下载来源、版本与 SHA-256 固定在 `entry/src/main/ets/utils/subtitle/SubtitleModelStore.ets`。

## 完整许可文本

为确保源码和二进制发行均携带必要声明，MIT 与 Apache-2.0 的完整许可文本统一存放于：

- [entry/src/main/resources/rawfile/licenses/THIRD_PARTY_LICENSES.txt](entry/src/main/resources/rawfile/licenses/THIRD_PARTY_LICENSES.txt)

该文件会作为 rawfile 打包进入最终 HAP，并可在应用“关于 → 开源许可”中查看。
