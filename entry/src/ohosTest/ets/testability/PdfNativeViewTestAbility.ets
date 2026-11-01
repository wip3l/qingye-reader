import { UIAbility } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { syncSystemBars } from '../../../main/ets/utils/SystemBars';

export default class PdfNativeViewTestAbility extends UIAbility {
  onWindowStageCreate(stage: window.WindowStage): void {
    stage.loadContent('pages/PdfNativeViewTest', (): void => { syncSystemBars(this.context, false); });
  }
}
