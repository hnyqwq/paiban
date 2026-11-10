// 第三页：我的 —— 仅放额外设置（外观/规则/数据/关于）
import { pasteboard, BusinessError } from '@kit.BasicServicesKit';
import { promptAction, SegmentButtonV2Items, CapsuleSegmentButtonV2 } from '@kit.ArkUI';
import { common, bundleManager } from '@kit.AbilityKit';
import { updateManager } from '@kit.AppGalleryKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
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
      Row() {
        Button($r('app.string.paste'))
          .buttonStyle(ButtonStyleMode.NORMAL)
          .fontSize(13)
          .onClick(() => {
            pasteboard.getSystemPasteboard().getData().then((data: pasteboard.PasteData) => {
              const text = data.getPrimaryText();
              if (text !== '') {
                this.text = text;
              } else {
                promptAction.showToast({ message: $r('app.string.clipboard_empty') });
              }
            }).catch(() => {
              promptAction.showToast({ message: $r('app.string.clipboard_empty') });
            });
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)

      TextArea({ text: this.text, placeholder: $r('app.string.import_hint') })
        .width('100%')
        .height(140)
        .margin({ top: 8 })
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
  @State bundleName: string = '';
  @State versionName: string = '';
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
    this.loadBundleInfo();
  }

  // 通过 bundleManager 实时读取包名与版本号
  loadBundleInfo(): void {
    try {
      const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      this.bundleName = info.name;
      this.versionName = info.versionName;
    } catch (e) {
      hilog.error(0x0000, 'testTag', 'Failed to load bundle info. Cause: %{public}s', JSON.stringify(e));
    }
  }

  saveRules(): void {
    this.service.saveRules(this.rules);
    // 保存后收起编辑器，回到展示态并刷新数值
    this.rules = this.service.getRules();
    this.showRuleEditor = false;
    promptAction.showToast({ message: $r('app.string.rule_saved') });
  }

  // 星期名，从资源按名取（wd_0..wd_6）
  weekdayName(wd: number): string {
    try {
      const context = AppStorage.get<common.UIAbilityContext>('context');
      if (context === undefined) {
        return '';
      }
      return context.resourceManager.getStringByNameSync(`wd_${wd}`);
    } catch (e) {
      return '';
    }
  }

  // 展示已选的固定休息日，未选显示「无」
  restWeekdaysText(): string {
    if (this.rules.restWeekdays.length === 0) {
      try {
        const context = AppStorage.get<common.UIAbilityContext>('context');
        if (context !== undefined) {
          return context.resourceManager.getStringByNameSync('rule_rest_weekdays_none');
        }
      } catch (e) {
        // 取不到就用默认
      }
      return '';
    }
    const sorted = this.rules.restWeekdays.slice().sort((a: number, b: number) => a - b);
    return sorted.map((wd: number) => this.weekdayName(wd)).join('、');
  }

  toggleRestWeekday(wd: number): void {
    const arr = this.rules.restWeekdays.slice();
    const idx = arr.indexOf(wd);
    if (idx >= 0) {
      arr.splice(idx, 1);
    } else {
      arr.push(wd);
    }
    arr.sort((a: number, b: number) => a - b);
    this.rules.restWeekdays = arr;
  }

  // 展示固定班次模板，未设置显示「无」
  shiftTemplateText(): string {
    if (this.rules.shiftTemplate.trim() === '') {
      try {
        const context = AppStorage.get<common.UIAbilityContext>('context');
        if (context !== undefined) {
          return context.resourceManager.getStringByNameSync('rule_shift_template_none');
        }
      } catch (e) {
        // 取不到就用默认
      }
      return '';
    }
    return this.rules.shiftTemplate;
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

      Text($r('app.string.rule_workday_min'))
        .fontSize(13)
        .margin({ top: 10 })
      TextInput({ text: `${this.rules.workdayMinHours}` })
        .type(InputType.Number)
        .width('100%')
        .onChange((v: string) => {
          this.rules.workdayMinHours = Number(v) || 0;
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

      Text($r('app.string.rule_rest_weekdays'))
        .fontSize(13)
        .margin({ top: 10 })
      Row({ space: 6 }) {
        ForEach([0, 1, 2, 3, 4, 5, 6], (wd: number) => {
          Text(this.weekdayName(wd))
            .fontSize(13)
            .textAlign(TextAlign.Center)
            .padding({ top: 6, bottom: 6, left: 10, right: 10 })
            .borderRadius(8)
            .backgroundColor(this.rules.restWeekdays.includes(wd) ? $r('sys.color.brand') : $r('sys.color.comp_background_tertiary'))
            .fontColor(this.rules.restWeekdays.includes(wd) ? '#FFFFFF' : $r('sys.color.font_primary'))
            .onClick(() => this.toggleRestWeekday(wd))
        }, (wd: number) => `${wd}-${this.rules.restWeekdays.includes(wd)}`)
      }
      .width('100%')
      .margin({ top: 6 })

      Text($r('app.string.rule_shift_template'))
        .fontSize(13)
        .margin({ top: 10 })
      TextInput({ text: this.rules.shiftTemplate, placeholder: $r('app.string.rule_shift_template_hint') })
        .type(InputType.Normal)
        .width('100%')
        .fontSize(13)
        .onChange((v: string) => {
          this.rules.shiftTemplate = v;
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
          this.ruleRow($r('app.string.rule_workday_min'), this.rules.workdayMinHours, $r('app.string.unit_hours'))
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
          Divider().strokeWidth(0.5)
          Row() {
            Text($r('app.string.rule_shift_template'))
              .fontSize(15)
            Blank()
            Text(this.shiftTemplateText())
              .fontSize(13)
              .fontColor($r('sys.color.font_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .constraintSize({ maxWidth: '60%' })
          }
          .width('100%')
          .padding(12)
          Row() {
            Text($r('app.string.rule_rest_weekdays'))
              .fontSize(15)
            Blank()
            Text(this.restWeekdaysText())
              .fontSize(15)
              .fontColor($r('sys.color.font_secondary'))
          }
          .width('100%')
          .padding(12)

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
            Text($r('app.string.EntryAbility_label'))
              .fontSize(15)
            Blank()
            Text(this.bundleName)
              .fontSize(15)
              .fontColor($r('sys.color.font_secondary'))
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 12, bottom: 4 })
          Row() {
            Text($r('app.string.version_label'))
              .fontSize(15)
            Blank()
            Text(this.versionName)
              .fontSize(15)
              .fontColor($r('sys.color.font_secondary'))
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 4, bottom: 4 })
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
