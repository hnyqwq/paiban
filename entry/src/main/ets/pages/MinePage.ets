// 第三页：我的 —— 仅放额外设置（外观/规则/数据/关于）
import { pasteboard } from '@kit.BasicServicesKit';
import { promptAction } from '@kit.ArkUI';
import { ShiftRules } from '../model/ScheduleTypes';
import { ScheduleService } from '../service/ScheduleService';

@Component
export struct MinePage {
  scroller: Scroller = new Scroller();
  @State appearanceMode: number = 0; // 0 跟随系统 1 浅色 2 深色
  @State rules: ShiftRules = new ShiftRules();
  @State showRuleEditor: boolean = false;
  private service: ScheduleService = ScheduleService.getInstance();

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
  appearanceRow(mode: number) {
    Row() {
      Text(mode === 0 ? $r('app.string.follow_system') : (mode === 1 ? $r('app.string.light_mode') : $r('app.string.dark_mode')))
        .fontSize(15)
        .fontColor(this.appearanceMode === mode ? $r('sys.color.brand') : $r('sys.color.font_primary'))
      Blank()
      if (this.appearanceMode === mode) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(18)
          .fontColor([$r('sys.color.brand')])
      }
    }
    .width('100%')
    .padding(12)
    .onClick(() => {
      this.appearanceMode = mode;
      this.service.setAppearanceMode(mode);
    })
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
          this.appearanceRow(0)
          Divider().strokeWidth(0.5)
          this.appearanceRow(1)
          Divider().strokeWidth(0.5)
          this.appearanceRow(2)
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

          if (this.showRuleEditor) {
            this.ruleEditor()
          } else {
            Button($r('app.string.edit_rules'))
              .width('100%')
              .buttonStyle(ButtonStyleMode.NORMAL)
              .margin({ top: 12, bottom: 12 })
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
          Button($r('app.string.export_data'))
            .width('100%')
            .buttonStyle(ButtonStyleMode.NORMAL)
            .margin({ top: 12 })
            .onClick(() => this.exportData())
          Button($r('app.string.clear_data'))
            .width('100%')
            .buttonStyle(ButtonStyleMode.NORMAL)
            .fontColor($r('sys.color.warning'))
            .margin({ top: 8, bottom: 12 })
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
          .padding(12)
          Row() {
            Text($r('app.string.storage_label'))
              .fontSize(15)
            Blank()
            Text($r('app.string.storage_value'))
              .fontSize(13)
              .fontColor($r('sys.color.font_tertiary'))
          }
          .width('100%')
          .padding({ left: 12, right: 12, bottom: 12 })
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
