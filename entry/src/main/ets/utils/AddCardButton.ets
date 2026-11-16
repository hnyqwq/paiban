// 右上角「添加桌面卡片」按钮：选择卡片后打开本应用的卡片管理页
// 文档：formProvider.openFormManager(want)，want 携带 bundleName/abilityName/卡片名/尺寸
import { bundleManager, Want } from '@kit.AbilityKit';
import { formInfo, formProvider } from '@kit.FormKit';
import { promptAction } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';

@Component
export struct AddCardButton {
  // 三张卡：名称资源、卡片名（form_config.json 中注册）、尺寸
  private cardNames: Resource[] = [
    $r('app.string.form_today_card_name'),
    $r('app.string.form_week_card_name'),
    $r('app.string.form_month_card_name')
  ];
  private cardKeys: string[] = ['today_card', 'week_card', 'month_card'];
  private cardDims: number[] = [
    formInfo.FormDimension.Dimension_2_2,
    formInfo.FormDimension.Dimension_2_4,
    formInfo.FormDimension.Dimension_4_4
  ];

  open(index: number): void {
    try {
      const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      const want: Want = {
        bundleName: info.name,
        abilityName: 'EntryAbility',
        parameters: {
          'ohos.extra.param.key.form_dimension': this.cardDims[index],
          'ohos.extra.param.key.form_name': this.cardKeys[index],
          'ohos.extra.param.key.module_name': 'entry'
        }
      };
      formProvider.openFormManager(want);
    } catch (e) {
      const err = e as BusinessError;
      promptAction.showToast({ message: `${$r('app.string.card_add_failed')} (${err.code})` });
    }
  }

  build() {
    Button() {
      SymbolGlyph($r('sys.symbol.plus'))
        .fontSize(18)
        .fontColor([$r('sys.color.font_primary')])
    }
    .width(32)
    .height(32)
    .type(ButtonType.Capsule)
    .backgroundColor($r('sys.color.comp_background_tertiary'))
    .onClick(() => {
      promptAction.showDialog({
        title: $r('app.string.add_card_title'),
        buttons: [
          { text: this.cardNames[0], color: $r('sys.color.font_primary') },
          { text: this.cardNames[1], color: $r('sys.color.font_primary') },
          { text: this.cardNames[2], color: $r('sys.color.font_primary') }
        ]
      }).then((res) => {
        if (res.index >= 0 && res.index < this.cardKeys.length) {
          this.open(res.index);
        }
      }).catch((err: BusinessError) => {
        console.error('add card dialog failed: ' + JSON.stringify(err));
      });
    })
  }
}