import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { ScheduleService } from '../service/ScheduleService';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
    // 上下文供页面使用（照搬 hny）
    AppStorage.setOrCreate('context', this.context);
    // 初始化排班本地存储（含外观设置应用）
    ScheduleService.getInstance().init(this.context);
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });

    // 窗口初始化：安全区避让（照搬 hny）
    try {
      const mainWindow = windowStage.getMainWindowSync();
      const updateTopAvoid = (): void => {
        const systemArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
        const cutoutArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_CUTOUT);
        const topPx = Math.max(systemArea.topRect.height, cutoutArea.topRect.height);
        AppStorage.setOrCreate('topRectHeight', topPx);
      };
      updateTopAvoid();
      mainWindow.on('avoidAreaChange', () => {
        updateTopAvoid();
      });
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to get avoid area. Cause: %{public}s', JSON.stringify(err));
    }

    // 颜色模式由 ScheduleService.init 按用户保存的外观设置应用，这里不再强制重置
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}