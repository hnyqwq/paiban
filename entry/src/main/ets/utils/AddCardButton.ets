// 「添加桌面卡片」：直接打开本应用的卡片管理页（页面内可选要添加的卡片与尺寸）
import { bundleManager, Want } from '@kit.AbilityKit';
import { formProvider } from '@kit.FormKit';
import { promptAction } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';

// 直接打开本应用的卡片管理页（页面内可选要添加的卡片与尺寸）
export function openCardManager(): void {
  try {
    const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
    const want: Want = {
      bundleName: info.name,
      abilityName: 'EntryAbility'
    };
    formProvider.openFormManager(want);
  } catch (e) {
    const err = e as BusinessError;
    promptAction.showToast({ message: `${$r('app.string.card_add_failed')} (${err.code})` });
  }
}