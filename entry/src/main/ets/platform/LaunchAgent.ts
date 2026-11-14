// 点通知、媒体控件时拉起应用用的 WantAgent。安卓构建会用 android/overlay 里的同名文件替换本文件。
import { common, WantAgent, wantAgent } from '@kit.AbilityKit';

/** 拉起 EntryAbility；parameters 原样放进 Want。 */
export async function createLaunchAgent(context: common.UIAbilityContext, requestCode: number,
  parameters?: Record<string, Object>): Promise<WantAgent> {
  const want: Record<string, Object> = {
    bundleName: context.abilityInfo.bundleName,
    abilityName: 'EntryAbility'
  };
  if (parameters) want['parameters'] = parameters;
  return await wantAgent.getWantAgent({
    wants: [want],
    actionType: wantAgent.OperationType.START_ABILITY,
    requestCode: requestCode,
    actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
  });
}
