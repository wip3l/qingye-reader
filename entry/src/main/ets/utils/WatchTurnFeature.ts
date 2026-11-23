/**
 * 手表翻页总开关。Wear Engine 权限在开发者联盟批下来之前，手机端接口一律报 1008500004，
 * 所以先整体关掉：设置页不出现“手表翻页”这一行、设置搜索搜不到、已存的开关值也不注册接收。
 * 权限通过后改成 true 即可恢复，其余代码不用动。
 * 纯 TS，设置搜索索引与 Node 检查脚本也读它。
 */
export const WATCH_TURN_AVAILABLE: boolean = false;
