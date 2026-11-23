/**
 * 手势事件里第一根还按着的手指。fingerList 按手指编号放，不是紧凑数组：先落下的手指抬起后，
 * 0 号位是空的而 length 仍大于 0，直接取 fingerList[0] 的坐标会抛 TypeError 让应用闪退。
 */
export function firstGestureFinger(event: GestureEvent | undefined): FingerInfo | undefined {
  const fingers = event?.fingerList;
  if (!fingers) return undefined;
  for (let index = 0; index < fingers.length; index++) {
    const finger = fingers[index] as FingerInfo | undefined;
    if (finger) return finger;
  }
  return undefined;
}
