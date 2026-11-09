// 第三页：我的 —— 仅放额外设置（外观/规则/数据/关于）
import { pasteboard } from '@kit.BasicServicesKit';
import { promptAction, SegmentButtonV2Items, CapsuleSegmentButtonV2 } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { updateManager } from '@kit.AppGalleryKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ShiftRules } from '../model/ScheduleTypes';
import { ScheduleService } from '../service/ScheduleService';

function segString(res: Resource): string {
  try {
    const context = AppStorage.get<common.UIAbilityContext>('context');
    if (context === undefined) {
      return '';
    }
    return context.resourceManager.getStringSync(res);
  } catch (e) {
    return '';
  }
}

// 导入弹窗：粘贴导出的 JSON 后写入
@CustomDialog
struct ImportDialog {
  controller?: CustomDialogController;
  onConfirm: (text: string) => void = (_text: string) => {};
  @State text: string = '';

  build() {
    Column() {
      TextArea({ text: this.text, placeholder: $r('app.string.import_hint') })
        .width('100%')
        .height(140)
      Row() {
        Button($r('app.string.cancel'))
          .buttonStyle(ButtonStyleMode.NORMAL)
          .layoutWeight(1)
          .onClick(() => {
            this.controller?.close();
          })
        Button($r('app.string.import_data'))
          .layoutWeight(1)
          .margin({ left: 12 })
          .onClick(() => {
            this.onConfirm(this.text);
            this.controller?.close();
          })
      }
      .width('100%')
      .margin({ top: 12 })
    }
    .padding(20)
  }
}

// 外观选择：胶囊型分段按钮（@ComponentV2）
@ComponentV2
struct AppearanceSegment {
  @Param selected: number = 0;
  @Event onSelect: (index: number) => void = (_index: number) => {};
  private items: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: segString($r('app.string.follow_system')) },
    { text: segString($r('app.string.light_mode')) },
    { text: segString($r('app.string.dark_mode')) },
  ]);

  build() {
    Row() {
      CapsuleSegmentButtonV2({
        items: this.items,
        selectedIndex: this.selected,
        onItemClicked: (index: number) => {
          this.onSelect(index);
        }
      })
    }
    .width('100%')
  }
}

@Component
export struct MinePage {
  scroller: Scroller = new Scroller();
  @State appearanceMode: number = 0; // 0 跟随系统 1 浅色 2 深色
  @State rules: ShiftRules = new ShiftRules();
  @State showRuleEditor: boolean = false;
  private service: ScheduleService = ScheduleService.getInstance();
  private importDialog: CustomDialogController = new CustomDialogController({
    builder: ImportDialog({
      onConfirm: (text: string) => {
        const trimmed = text.trim();
        if (trimmed === '') {
          promptAction.showToast({ message: $r('app.string.import_empty') });
          return;
        }
        if (this.service.importDays(trimmed)) {
          AppStorage.setOrCreate('dataCleared', Date.now());
          promptAction.showToast({ message: $r('app.string.import_success') });
        } else {
          promptAction.showToast({ message: $r('app.string.import_failed_len', trimmed.length) });
        }
      }
    }),
    autoCancel: true
  });

  aboutToAppear(): void {
    this.appearanceMode = this.service.getAppearanceMode();
    this.rules = this.service.getRules();
  }

  saveRules(): void {
    this.service.saveRules(this.rules);
    // 保存后收起编辑器，回到展示态并刷新数值
    this.rules = this.service.getRules();
    this.showRuleEditor = false;
    promptAction.showToast({ message: $r('app.string.rule_saved') });
  }

  exportData(): void {
    const json = JSON.stringify(this.service.getDays());
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, json);
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      promptAction.showToast({ message: $r('app.string.exported') });
    }).catch((_err: Error) => {
      promptAction.showToast({ message: $r('app.string.export_failed') });
    });
  }

  // 检查更新（照搬 hny：AppGallery updateManager）
  checkUpdate(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    updateManager.checkAppUpdate(context).then((checkResult: updateManager.CheckUpdateResult) => {
      if (checkResult.updateAvailable) {
        updateManager.showUpdateDialog(context).catch((_error: BusinessError) => {
          promptAction.showToast({ message: $r('app.string.update_dialog_failed') });
        });
      } else {
        promptAction.showToast({ message: $r('app.string.already_latest') });
      }
    }).catch((_error: BusinessError) => {
      promptAction.showToast({ message: $r('app.string.check_update_failed') });
    });
  }

  clearData(): void {
    promptAction.showDialog({
      title: $r('app.string.clear_confirm_title'),
      message: $r('app.string.clear_confirm_msg'),
      buttons: [
        { text: $r('app.string.cancel'), color: $r('sys.color.font_secondary') },
        { text: $r('app.string.btn_clear'), color: $r('sys.color.warning') }
      ]
    }).then((res) => {
      if (res.index === 1) {
        this.service.clearAll();
        // 通知各页面重新加载数据
        AppStorage.setOrCreate('dataCleared', Date.now());
        promptAction.showToast({ message: $r('app.string.cleared') });
      }
    });
  }

  @Builder
  sectionTitle(title: Resource | string) {
    Text(title)
      .fontSize(13)
      .fontColor($r('sys.color.font_tertiary'))
      .width('100%')
      .margin({ top: 16, bottom: 6 })
  }

  @Builder
  ruleRow(label: Resource | string, value: number, unit: Resource | string) {
    Row() {
      Text(label)
        .fontSize(15)
      Blank()
      Text(`${value}`)
        .fontSize(15)
        .fontColor($r('sys.color.font_secondary'))
      Text(unit)
        .fontSize(15)
        .fontColor($r('sys.color.font_secondary'))
        .margin({ left: 4 })
    }
    .width('100%')
    .padding(12)
  }

  @Builder
  ruleEditor() {
    Column() {
      Text($r('app.string.rule_target'))
        .fontSize(13)
      TextInput({ text: `${this.rules.monthlyTargetHours}` })
        .type(InputType.Number)
        .width('100%')
        .onChange((v: string) => {
          this.rules.monthlyTargetHours = Number(v) || 0;
        })

      Text($r('app.string.rule_min_daily'))
        .fontSize(13)
        .margin({ top: 10 })
      TextInput({ text: `${this.rules.minWorkHoursPerDay}` })
        .type(InputType.Number)
        .width('100%')
        .onChange((v: string) => {
          this.rules.minWorkHoursPerDay = Number(v) || 0;
        })

      Text($r('app.string.rule_gap'))
        .fontSize(13)
        .margin({ top: 10 })
      TextInput({ text: `${this.rules.dailyRestMinutes}` })
        .type(InputType.Number)
        .width('100%')
        .onChange((v: string) => {
          this.rules.dailyRestMinutes = Number(v) || 0;
        })

      Text($r('app.string.rule_rest_days'))
        .fontSize(13)
        .margin({ top: 10 })
      TextInput({ text: `${this.rules.restDaysPerMonth}` })
        .type(InputType.Number)
        .width('100%')
        .onChange((v: string) => {
          this.rules.restDaysPerMonth = Number(v) || 0;
        })

      Text($r('app.string.rule_rest_hours'))
        .fontSize(13)
        .margin({ top: 10 })
      TextInput({ text: `${this.rules.restHoursPerMonth}` })
        .type(InputType.Number)
        .width('100%')
        .onChange((v: string) => {
          this.rules.restHoursPerMonth = Number(v) || 0;
        })

      Text($r('app.string.rule_max_streak'))
        .fontSize(13)
        .margin({ top: 10 })
      TextInput({ text: `${this.rules.maxConsecutiveWorkDays}` })
        .type(InputType.Number)
        .width('100%')
        .onChange((v: string) => {
          this.rules.maxConsecutiveWorkDays = Number(v) || 0;
        })

      Text($r('app.string.rule_max_continuous'))
        .fontSize(13)
        .margin({ top: 10 })
      TextInput({ text: `${this.rules.maxContinuousWorkMinutes}` })
        .type(InputType.Number)
        .width('100%')
        .onChange((v: string) => {
          this.rules.maxContinuousWorkMinutes = Number(v) || 0;
        })

      Text($r('app.string.rule_mandatory_rest'))
        .fontSize(13)
        .margin({ top: 10 })
      TextInput({ text: `${this.rules.mandatoryRestMinutes}` })
        .type(InputType.Number)
        .width('100%')
        .onChange((v: string) => {
          this.rules.mandatoryRestMinutes = Number(v) || 0;
        })

      Button($r('app.string.save_rules'))
        .width('100%')
        .margin({ top: 14, bottom: 4 })
        .onClick(() => this.saveRules())
    }
    .width('100%')
    .padding(12)
    .borderRadius(12)
    .backgroundColor($r('sys.color.background_primary'))
    .border({ width: 0.5, color: $r('sys.color.comp_divider') })
  }

  build() {
    Scroll(this.scroller) {
      Column() {
        this.sectionTitle($r('app.string.section_appearance'))
        Column() {
          AppearanceSegment({
            selected: this.appearanceMode,
            onSelect: (index: number) => {
              this.appearanceMode = index;
              this.service.setAppearanceMode(index);
            }
          })
            .width('calc(100% - 24vp)')
            .margin({ left: 12, right: 12, top: 12, bottom: 12 })
        }
        .width('100%')
        .borderRadius(12)
        .backgroundColor($r('sys.color.background_primary'))
        .border({ width: 0.5, color: $r('sys.color.comp_divider') })

        this.sectionTitle($r('app.string.section_rules'))
        Column() {
          this.ruleRow($r('app.string.rule_target'), this.rules.monthlyTargetHours, $r('app.string.unit_hours'))
          Divider().strokeWidth(0.5)
          this.ruleRow($r('app.string.rule_min_daily'), this.rules.minWorkHoursPerDay, $r('app.string.unit_hours'))
          Divider().strokeWidth(0.5)
          this.ruleRow($r('app.string.rule_gap'), this.rules.dailyRestMinutes, $r('app.string.unit_minutes'))
          Divider().strokeWidth(0.5)
          this.ruleRow($r('app.string.rule_rest_days'), this.rules.restDaysPerMonth, $r('app.string.unit_days'))
          Divider().strokeWidth(0.5)
          this.ruleRow($r('app.string.rule_rest_hours'), this.rules.restHoursPerMonth, $r('app.string.unit_hours'))
          Divider().strokeWidth(0.5)
          this.ruleRow($r('app.string.rule_max_streak'), this.rules.maxConsecutiveWorkDays, $r('app.string.unit_days'))
          Divider().strokeWidth(0.5)
          this.ruleRow($r('app.string.rule_max_continuous'), this.rules.maxContinuousWorkMinutes, $r('app.string.unit_minutes'))
          Divider().strokeWidth(0.5)
          this.ruleRow($r('app.string.rule_mandatory_rest'), this.rules.mandatoryRestMinutes, $r('app.string.unit_minutes'))

          if (this.showRuleEditor) {
            this.ruleEditor()
          } else {
            Button($r('app.string.edit_rules'))
              .width('calc(100% - 24vp)')
              .buttonStyle(ButtonStyleMode.NORMAL)
              .margin({ top: 12, bottom: 12, left: 12, right: 12 })
              .onClick(() => {
                this.showRuleEditor = true;
              })
          }
        }
        .width('100%')
        .borderRadius(12)
        .backgroundColor($r('sys.color.background_primary'))
        .border({ width: 0.5, color: $r('sys.color.comp_divider') })

        this.sectionTitle($r('app.string.section_data'))
        Column() {
          Row({ space: 8 }) {
            Button($r('app.string.export_data'))
              .buttonStyle(ButtonStyleMode.NORMAL)
              .fontSize(13)
              .layoutWeight(1)
              .margin({ top: 12, bottom: 4, left: 12 })
              .onClick(() => this.exportData())
            Button($r('app.string.import_data'))
              .buttonStyle(ButtonStyleMode.NORMAL)
              .fontSize(13)
              .layoutWeight(1)
              .margin({ top: 12, bottom: 4, right: 12 })
              .onClick(() => this.importDialog.open())
          }
          .width('100%')
          Button($r('app.string.clear_data'))
            .width('calc(100% - 24vp)')
            .buttonStyle(ButtonStyleMode.NORMAL)
            .fontColor($r('sys.color.warning'))
            .margin({ top: 8, bottom: 12, left: 12, right: 12 })
            .onClick(() => this.clearData())
        }
        .width('100%')
        .borderRadius(12)
        .backgroundColor($r('sys.color.background_primary'))
        .border({ width: 0.5, color: $r('sys.color.comp_divider') })

        this.sectionTitle($r('app.string.section_about'))
        Column() {
          Row() {
            Text($r('app.string.version_label'))
              .fontSize(15)
            Blank()
            Text('1.0.0')
              .fontSize(15)
              .fontColor($r('sys.color.font_secondary'))
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 12, bottom: 4 })
          Row() {
            Text($r('app.string.check_update'))
              .fontSize(15)
            Blank()
            Text('›')
              .fontSize(16)
              .fontColor($r('sys.color.font_tertiary'))
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 4, bottom: 12 })
          .onClick(() => this.checkUpdate())
        }
        .width('100%')
        .borderRadius(12)
        .backgroundColor($r('sys.color.background_primary'))
        .border({ width: 0.5, color: $r('sys.color.comp_divider') })

        Text('')
          .height(100)
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 110 })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .align(Alignment.Top)
    .backgroundColor($r('sys.color.background_secondary'))
  }
}
