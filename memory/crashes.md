# Crash 与崩溃记录

## CRASH-1 PDF 视图搜索原生回调崩溃

**发现日期**：2026-11-01。
**环境**：Pura X Max，HarmonyOS 7.0.0.111，PDF Kit。
**现象**：调用 `PdfController.searchKey('probe', callback)`，在多次回调命中数量后发生 SIGSEGV。
**证据**：隔离为不运行后台导入的视图测试后仍复现。故障线程为主线程，栈顶 `napi_get_reference_value`，首个非运行时调用方为 `libpdfservice.z.so / PDFView::ExecuteCB`，地址为 `0x00554e4700000003`。原始日志保存在本地 `.hvigor/pdf-native-crash.txt`。
**责任边界**：当前证据将崩溃触发路径定位到原生视图搜索回调；没有系统实现的第一现场，不能据此证明内部指针损坏的具体原因。
**实现处理**：保留原生 PdfView 阅读，改用独立 TaskPool 文档搜索和视图矩形高亮，避免调用视图搜索。API 21+ 使用 PdfDocument 搜索，API 20 读取有序文本对象与字符矩形；不在 UI 线程扫描文档。
**验证**：后台导入、缩放、布局切换、跳页及后台搜索高亮组合测试通过。后续不要未经设备验证改回视图 `searchKey()`；该替代实现不代表修复了系统 PDF 库。
