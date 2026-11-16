// 「添加桌面卡片」：弹出三张服务卡片选择后打开本应用的卡片管理页
// 文档：formProvider.openFormManager(want)，want 携带 bundleName/abilityName/卡片名/尺寸
import { bundleManager, Want } from '@kit.AbilityKit';
import { formInfo, formProvider } from '@kit.FormKit';
import { promptAction } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';

const cardNames: Resource[] = [
  $r('app.string.form_today_card_name'),
  $r('app.string.form_week_card_name'),
  $r('app.string.form_month_card_name')
];
const cardKeys: string[] = ['today_card', 'week_card', 'month_card'];
const cardDims: number[] = [
  formInfo.FormDimension.Dimension_2_2,
  formInfo.FormDimension.Dimension_2_4,
  formInfo.FormDimension.Dimension_4_4
];

// 弹出卡片选择对话框并打开本应用的卡片管理页（按所选卡片预置名称与尺寸）
export function showAddCardDialog(): void {
  promptAction.showDialog({
    title: $r('app.string.add_card_title'),
    message: $r('app.string.add_card_msg'),
    buttons: [
      { text: cardNames[0], color: $r('sys.color.font_primary') },
      { text: cardNames[1], color: $r('sys.color.font_primary') },
      { text: cardNames[2], color: $r('sys.color.font_primary') }
    ]
  }).then((res) => {
    if (res.index < 0 || res.index >= cardKeys.length) {
      return;
    }
    try {
      const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      const want: Want = {
        bundleName: info.name,
        abilityName: 'EntryAbility',
        parameters: {
          'ohos.extra.param.key.form_dimension': cardDims[res.index],
          'ohos.extra.param.key.form_name': cardKeys[res.index],
          'ohos.extra.param.key.module_name': 'entry'
        }
      };
      formProvider.openFormManager(want);
    } catch (e) {
      const err = e as BusinessError;
      promptAction.showToast({ message: `${$r('app.string.card_add_failed')} (${err.code})` });
    }
  }).catch((err: BusinessError) => {
    console.error('add card dialog failed: ' + JSON.stringify(err));
  });
}