// 桌面服务卡片生命周期：提供今日/本周/本月三张卡片的数据
import { formBindingData, FormExtensionAbility, formInfo, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { FormCardData } from '../form/FormCardData';

export default class EntryFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    // 卡片模板名（today_card / week_card / month_card）由系统通过 parameters 传入
    let formName = '';
    const params = want.parameters;
    if (params !== undefined) {
      const raw = params[formInfo.FormParam.NAME_KEY];
      if (typeof raw === 'string') {
        formName = raw;
      }
    }
    const data: Record<string, string> = { 'payload': FormCardData.build(this.context, formName) };
    console.info(`EntryFormAbility onAddForm: ${formName}, payload length ${data.payload.length}`);
    return formBindingData.createFormBindingData(data);
  }

  onUpdateForm(formId: string): void {
    // 定时刷新 / 使用方请求刷新：先查回卡片模板名，再推送最新数据
    formProvider.getPublishedRunningFormInfoById(formId).then((info: formInfo.RunningFormInfo) => {
      const data: Record<string, string> = { 'payload': FormCardData.build(this.context, info.formName) };
      return formProvider.updateForm(formId, formBindingData.createFormBindingData(data));
    }).catch((err: BusinessError) => {
      console.error('form update failed: ' + JSON.stringify(err));
    });
  }

  onRemoveForm(formId: string): void {
    // 卡片被移除，无需额外处理
  }

  onAcquireFormState(want: Want): formInfo.FormState {
    return formInfo.FormState.READY;
  }
}
