# 混淆规则。目前 release 没有开启 minifyEnabled（见 build.gradle），先把必须保留的类列好，开启时不会出错。

# 原生桥：ArkTS 侧按方法名反射调用 BridgePlugin 子类的公开方法，名字不能改、方法不能删。
-keep class * extends ohos.ace.adapter.capability.bridge.BridgePlugin {
    public <methods>;
}

# ArkUI-X 适配层经 JNI 和反射访问自己的类（含按类名查找的 <模块名><Ability 名>Activity）。
-keep class ohos.** { *; }
-keep class io.legado.read.EntryEntryAbilityActivity { *; }
-keep class io.legado.read.MyApplication { *; }

# 清单里声明的组件
-keep class io.legado.read.PlaybackService
-keep class io.legado.read.ShareProvider

# 保留行号，方便看崩溃堆栈
-keepattributes SourceFile,LineNumberTable

# sherpa-onnx：原生库经 JNI 按类名、字段名访问这些类。
-keep class com.k2fsa.sherpa.onnx.** { *; }
