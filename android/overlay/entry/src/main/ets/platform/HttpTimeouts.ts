// platform/HttpTimeouts.ts 的安卓实现。
// ArkUI-X 安卓版的网络栈把 readTimeout 当成整个请求的时限（实测 62 MB 的音色下到一半，正好 60 秒被 CURLE_OPERATION_TIMEDOUT 掐断），
// 所以流式下载用这次下载的总时限。
export function streamReadTimeout(_idleMs: number, totalMs: number): number {
  return totalMs;
}
