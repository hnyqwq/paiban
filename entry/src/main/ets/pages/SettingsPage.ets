// 排班设置页（第四页）：排班规则 + 预设排班
import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import {
  Shift, ShiftRules, PresetShift, PRESET_COLORS, normalizeTime, minutesToHoursText
} from '../model/ScheduleTypes';
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

@Component
export struct SettingsPage {
  scroller: Scroller = new Scroller();
  @StorageProp('isWideLayout') isWideLayout: boolean = false; // 大屏（≥lg 断点）双栏布局
  @State rules: ShiftRules = new ShiftRules();
  @State expandedGroup: string = ''; // 当前展开的规则组：''=收起 'target'=目标 'work'=工时底线 'rest'=休息保障
  // 预设排班
  @State presets: PresetShift[] = [];
  @State showPresetEditor: boolean = false;
  @State editingPresetIndex: number = -1;
  @State presetName: string = '';
  @State presetColor: string = PRESET_COLORS[0];
  @State presetStart: string = '09:00';
  @State presetEnd: string = '17:00';
  @State presetBreak: number = 0;
  @State presetBreakDay: number = 0; // 休息归属日相对开始日：-1 昨日 0 开始日 +1 次日
  @State presetAutoFill: boolean = false; // 用于自动排班
  private presetColors: string[] = PRESET_COLORS;
  private service: ScheduleService = ScheduleService.getInstance();

  aboutToAppear(): void {
    this.rules = this.service.getRules();
    this.presets = this.service.getPresets();
  }

  // 打开/收起某个规则组
  openGroupEditor(group: string): void {
    if (this.expandedGroup === group) {
      this.expandedGroup = '';
      return;
    }
    this.expandedGroup = group;
  }

  saveRules(): void {
    this.service.saveRules(this.rules);
    // 保存后收起编辑器，回到展示态并刷新数值
    this.rules = this.service.getRules();
    this.expandedGroup = '';
    promptAction.showToast({ message: $r('app.string.rule_saved') });
  }

  // 取消编辑：丢弃未保存的修改，恢复为已存储的规则
  cancelEdit(): void {
    this.rules = this.service.getRules();
    this.expandedGroup = '';
  }

  // ===== 规则开关 =====
  // 关 = 存 0（不限制/不校验）；开 = 恢复关闭前的数值，无记录时用默认值

  private readonly ruleDefaults: Record<string, number> = {
    'minWorkHoursPerDay': 6,
    'dailyRestMinutes': 60,
    'maxContinuousWorkMinutes': 360,
    'restDaysPerMonth': 4,
    'restHoursPerMonth': 40,
    'maxConsecutiveWorkDays': 6
  };
  private ruleStash: Record<string, number> = {};

  ruleValue(key: string): number {
    if (key === 'minWorkHoursPerDay') {
      return this.rules.minWorkHoursPerDay;
    }
    if (key === 'dailyRestMinutes') {
      return this.rules.dailyRestMinutes;
    }
    if (key === 'maxContinuousWorkMinutes') {
      return this.rules.maxContinuousWorkMinutes;
    }
    if (key === 'restDaysPerMonth') {
      return this.rules.restDaysPerMonth;
    }
    if (key === 'restHoursPerMonth') {
      return this.rules.restHoursPerMonth;
    }
    return this.rules.maxConsecutiveWorkDays;
  }

  setRuleValue(key: string, v: number): void {
    if (key === 'minWorkHoursPerDay') {
      this.rules.minWorkHoursPerDay = v;
    } else if (key === 'dailyRestMinutes') {
      this.rules.dailyRestMinutes = v;
    } else if (key === 'maxContinuousWorkMinutes') {
      this.rules.maxContinuousWorkMinutes = v;
    } else if (key === 'restDaysPerMonth') {
      this.rules.restDaysPerMonth = v;
    } else if (key === 'restHoursPerMonth') {
      this.rules.restHoursPerMonth = v;
    } else {
      this.rules.maxConsecutiveWorkDays = v;
    }
  }

  toggleRule(key: string, isOn: boolean): void {
    if (isOn) {
      const stash = this.ruleStash[key];
      this.setRuleValue(key, stash !== undefined ? stash : this.ruleDefaults[key]);
    } else {
      this.ruleStash[key] = this.ruleValue(key);
      this.setRuleValue(key, 0);
    }
  }

  // ===== 预设排班 =====

  // 编辑器里的净工时（分钟）= 起止跨度 - 休息时长
  presetNetMinutes(): number {
    return Math.max(0, Shift.spanMinutes(this.presetStart, this.presetEnd) - Math.max(0, this.presetBreak));
  }

  // 预设是否跨天（结束早于开始），用于显示休息归属日选择
  presetCrossesDay(): boolean {
    const sMin = Shift.minutesBetween(this.presetStart.trim());
    const eMin = Shift.minutesBetween(this.presetEnd.trim());
    return sMin !== eMin && eMin < sMin;
  }

  // index < 0 表示新增，否则编辑对应预设
  openPresetEditor(index: number): void {
    if (index >= 0 && index < this.presets.length) {
      const preset = this.presets[index];
      this.editingPresetIndex = index;
      this.presetName = preset.name;
      this.presetColor = preset.color;
      this.presetStart = preset.start;
      this.presetEnd = preset.end;
      this.presetBreak = preset.breakMinutes;
      this.presetBreakDay = preset.breakDayOffset;
      this.presetAutoFill = preset.autoFill;
    } else {
      this.editingPresetIndex = -1;
      this.presetName = '';
      this.presetColor = PRESET_COLORS[0];
      this.presetStart = '09:00';
      this.presetEnd = '17:00';
      this.presetBreak = 0;
      this.presetBreakDay = 0;
      this.presetAutoFill = false;
    }
    this.showPresetEditor = true;
  }

  cancelPresetEdit(): void {
    this.showPresetEditor = false;
    this.editingPresetIndex = -1;
  }

  savePreset(): void {
    const start = normalizeTime(this.presetStart.trim());
    const end = normalizeTime(this.presetEnd.trim());
    const timePattern = /^\d{1,2}:\d{2}$/;
    if (!timePattern.test(start) || !timePattern.test(end)) {
      promptAction.showToast({ message: $r('app.string.preset_time_invalid') });
      return;
    }
    // 与排班页一致：结束早于开始视为跨天，弹窗确认
    if (Shift.minutesBetween(end) < Shift.minutesBetween(start)) {
      promptAction.showDialog({
        title: $r('app.string.shift_next_day'),
        message: $r('app.string.seg_next_day_hint'),
        buttons: [
          { text: $r('app.string.cancel'), color: $r('sys.color.font_secondary') },
          { text: $r('app.string.seg_label_confirm'), color: $r('sys.color.font_primary') }
        ]
      }).then((res) => {
        if (res.index === 1) {
          this.doSavePreset(start, end);
        }
      });
      return;
    }
    this.doSavePreset(start, end);
  }

  doSavePreset(start: string, end: string): void {
    const name = this.presetName.trim();
    if (name === '') {
      promptAction.showToast({ message: $r('app.string.preset_name_required') });
      return;
    }
    let breakMinutes = Math.floor(this.presetBreak);
    if (Number.isNaN(breakMinutes) || breakMinutes < 0) {
      breakMinutes = 0;
    }
    if (breakMinutes > 24 * 60) {
      breakMinutes = 24 * 60;
    }
    const next: PresetShift[] = this.presets.slice();
    const preset = new PresetShift();
    if (this.editingPresetIndex >= 0 && this.editingPresetIndex < next.length) {
      preset.id = next[this.editingPresetIndex].id;
    } else {
      preset.id = `p_${Date.now()}_${Math.floor(Math.random() * 1000)}`;
    }
    preset.name = name;
    preset.color = this.presetColor;
    preset.start = start;
    preset.end = end;
    preset.breakMinutes = breakMinutes;
    preset.breakDayOffset = this.presetBreakDay;
    preset.autoFill = this.presetAutoFill;
    if (this.editingPresetIndex >= 0 && this.editingPresetIndex < next.length) {
      next[this.editingPresetIndex] = preset;
    } else {
      next.push(preset);
    }
    this.presets = next;
    this.service.savePresets(next);
    this.showPresetEditor = false;
    this.editingPresetIndex = -1;
    promptAction.showToast({ message: $r('app.string.preset_saved') });
  }

  confirmDeletePreset(index: number): void {
    if (index < 0 || index >= this.presets.length) {
      return;
    }
    const preset = this.presets[index];
    promptAction.showDialog({
      title: $r('app.string.preset_delete_title'),
      message: $r('app.string.preset_delete_msg', preset.name),
      buttons: [
        { text: $r('app.string.cancel'), color: $r('sys.color.font_secondary') },
        { text: $r('app.string.delete'), color: $r('sys.color.warning') }
      ]
    }).then((res) => {
      if (res.index !== 1) {
        return;
      }
      const next: PresetShift[] = this.presets.slice();
      next.splice(index, 1);
      this.presets = next;
      this.service.savePresets(next);
      if (this.editingPresetIndex === index) {
        this.showPresetEditor = false;
        this.editingPresetIndex = -1;
      } else if (this.editingPresetIndex > index) {
        // 删除靠前的预设后，正在编辑的下标要跟着前移
        this.editingPresetIndex -= 1;
      }
      promptAction.showToast({ message: $r('app.string.preset_deleted') });
    });
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

  // 按资源名取参数化文案
  resText(name: string, a?: number): string {
    try {
      const context = AppStorage.get<common.UIAbilityContext>('context');
      if (context === undefined) {
        return '';
      }
      if (a === undefined) {
        return context.resourceManager.getStringByNameSync(name);
      }
      return context.resourceManager.getStringByNameSync(name, a);
    } catch (e) {
      return '';
    }
  }

  // 三组规则的展示摘要：关闭（值为 0）的规则不在摘要中显示
  targetSummary(): string {
    return `${this.rules.monthlyTargetHours} ${segString($r('app.string.unit_hours'))}`;
  }

  workSummary(): string {
    const parts: string[] = [];
    if (this.rules.minWorkHoursPerDay > 0) {
      parts.push(this.resText('sum_min_hours', this.rules.minWorkHoursPerDay));
    }
    if (this.rules.dailyRestMinutes > 0) {
      parts.push(this.resText('sum_gap', this.rules.dailyRestMinutes));
    }
    if (this.rules.maxContinuousWorkMinutes > 0) {
      parts.push(this.resText('sum_continuous', this.rules.maxContinuousWorkMinutes));
    }
    return parts.join('  ');
  }

  restSummary(): string {
    const parts: string[] = [];
    if (this.rules.restDaysPerMonth > 0) {
      parts.push(this.resText('sum_rest_days', this.rules.restDaysPerMonth));
    }
    if (this.rules.restHoursPerMonth > 0) {
      parts.push(this.resText('sum_rest_hours', this.rules.restHoursPerMonth));
    }
    if (this.rules.maxConsecutiveWorkDays > 0) {
      parts.push(this.resText('sum_streak', this.rules.maxConsecutiveWorkDays));
    }
    const wd = this.restWeekdaysText();
    if (wd !== '') {
      parts.push(wd);
    }
    if (this.rules.skipHolidays) {
      parts.push(this.resText('sum_skip_holidays'));
    }
    return parts.join('  ');
  }

  @Builder
  sectionTitle(title: Resource | string) {
    Text(title)
      .fontSize(13)
      .fontColor($r('sys.color.font_tertiary'))
      .width('100%')
      .margin({ top: 16, bottom: 6 })
  }

  // 规则组标题行：组名 + 摘要 + 箭头，点击展开/收起该组编辑器
  @Builder
  groupHeader(title: Resource | string, summary: string, group: string) {
    Row() {
      Text(title)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
      Blank()
      Text(summary)
        .fontSize(12)
        .fontColor($r('sys.color.font_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.MARQUEE })
        .marqueeOptions({
          start: true,
          step: 2,        // 慢速滚动
          loop: -1,
          fromStart: true,
          delay: 1500     // 停留 1.5s 后再滚动
        })
        .constraintSize({ maxWidth: '70%' })
      if (this.expandedGroup === group) {
        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(16)
          .width(16)
          .height(16)
          .fontColor([$r('sys.color.font_tertiary')])
          .margin({ left: 8 })
      } else {
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(16)
          .width(16)
          .height(16)
          .fontColor([$r('sys.color.font_tertiary')])
          .margin({ left: 8 })
      }
    }
    .width('100%')
    .padding(12)
    .onClick(() => this.openGroupEditor(group))
  }

  // 分组编辑器底部：取消 / 保存
  @Builder
  editorFooter() {
    Row({ space: 12 }) {
      Button($r('app.string.cancel'))
        .buttonStyle(ButtonStyleMode.NORMAL)
        .layoutWeight(1)
        .margin({ top: 14, bottom: 4 })
        .onClick(() => this.cancelEdit())
      Button($r('app.string.save_rules'))
        .layoutWeight(1)
        .margin({ top: 14, bottom: 4 })
        .onClick(() => this.saveRules())
    }
    .width('100%')
  }

  // 带生效开关的规则行：标题放大靠左，右侧开关控制是否生效，打开才显示数值输入框
  @Builder
  ruleFieldWithToggle(label: Resource | string, key: string) {
    Column() {
      Row() {
        Text(label)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.ruleValue(key) > 0 ? $r('sys.color.font_primary') : $r('sys.color.font_tertiary'))
          .layoutWeight(1)
        Text(this.ruleValue(key) > 0
          ? $r('app.string.rule_enabled') : $r('app.string.rule_disabled'))
          .fontSize(12)
          .fontColor($r('sys.color.font_tertiary'))
          .margin({ right: 8 })
        Toggle({ type: ToggleType.Switch, isOn: this.ruleValue(key) > 0 })
          .onChange((isOn: boolean) => {
            this.toggleRule(key, isOn);
          })
      }
      .width('100%')

      if (this.ruleValue(key) > 0) {
        TextInput({ text: `${this.ruleValue(key)}` })
          .type(InputType.Number)
          .width('100%')
          .margin({ top: 6 })
          .onChange((v: string) => {
            this.setRuleValue(key, Number(v) || 0);
          })
      }
    }
    .width('100%')
    .margin({ top: 12 })
  }

  // 目标组编辑器：目标工时
  @Builder
  editorTarget() {
    Column() {
      Text($r('app.string.rule_target'))
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
      TextInput({ text: `${this.rules.monthlyTargetHours}` })
        .type(InputType.Number)
        .width('100%')
        .margin({ top: 6 })
        .onChange((v: string) => {
          this.rules.monthlyTargetHours = Number(v) || 0;
        })

      this.editorFooter()
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 4, bottom: 12 })
  }

  // 工时底线组编辑器：每日最少工时、班次间隔、单段最长连续（含超限强制休息）
  @Builder
  editorWork() {
    Column() {
      this.ruleFieldWithToggle($r('app.string.rule_min_daily'), 'minWorkHoursPerDay')

      this.ruleFieldWithToggle($r('app.string.rule_gap'), 'dailyRestMinutes')

      this.ruleFieldWithToggle($r('app.string.rule_max_continuous'), 'maxContinuousWorkMinutes')

      if (this.rules.maxContinuousWorkMinutes > 0) {
        Text($r('app.string.rule_mandatory_rest'))
          .fontSize(11)
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')
          .margin({ top: 6 })
        TextInput({ text: `${this.rules.mandatoryRestMinutes}` })
          .type(InputType.Number)
          .width('100%')
          .onChange((v: string) => {
            this.rules.mandatoryRestMinutes = Number(v) || 0;
          })
      }

      this.editorFooter()
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 4, bottom: 12 })
  }

  // 休息保障组编辑器：月休天数/时长、连续上限、固定休息日、班次模板
  @Builder
  editorRest() {
    Column() {
      this.ruleFieldWithToggle($r('app.string.rule_rest_days'), 'restDaysPerMonth')

      this.ruleFieldWithToggle($r('app.string.rule_rest_hours'), 'restHoursPerMonth')

      this.ruleFieldWithToggle($r('app.string.rule_max_streak'), 'maxConsecutiveWorkDays')

      Text($r('app.string.rule_rest_weekdays'))
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .width('100%')
        .margin({ top: 12 })
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

      // 自动跳过法定节假日：开启后自动排班不会把班次排到节假日
      Row() {
        Text($r('app.string.rule_skip_holidays'))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
        Text(this.rules.skipHolidays ? $r('app.string.rule_enabled') : $r('app.string.rule_disabled'))
          .fontSize(12)
          .fontColor($r('sys.color.font_tertiary'))
          .margin({ right: 8 })
        Toggle({ type: ToggleType.Switch, isOn: this.rules.skipHolidays })
          .onChange((isOn: boolean) => {
            this.rules.skipHolidays = isOn;
          })
      }
      .width('100%')
      .margin({ top: 12 })

      this.editorFooter()
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 4, bottom: 12 })
  }

  // 预设排班列表行：颜色条 + 名称 + 时间段 + 净工时
  @Builder
  presetRow(preset: PresetShift, index: number) {
    Column() {
      Row() {
        Text('')
          .width(4)
          .height(34)
          .borderRadius(2)
          .backgroundColor(preset.color)
          .margin({ right: 10 })
        Column() {
          Text(preset.name)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
          Row() {
            Text(`${preset.start} - ${preset.end}`)
              .fontSize(12)
              .fontColor($r('sys.color.font_secondary'))
            if (preset.autoFill) {
              Text($r('app.string.preset_autofill'))
                .fontSize(9)
                .fontColor($r('sys.color.brand'))
                .border({ width: 0.5, color: $r('sys.color.brand'), radius: 4 })
                .padding({ left: 4, right: 4, top: 1, bottom: 1 })
                .margin({ left: 6 })
            }
          }
          .margin({ top: 1 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Text(minutesToHoursText(preset.netMinutes()))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(preset.color)
        Text($r('app.string.edit'))
          .fontSize(13)
          .fontColor($r('sys.color.brand'))
          .margin({ left: 12 })
          .onClick(() => this.openPresetEditor(index))
        Text($r('app.string.delete'))
          .fontSize(13)
          .fontColor($r('sys.color.warning'))
          .margin({ left: 10 })
          .onClick(() => this.confirmDeletePreset(index))
      }
      .width('100%')

      if (preset.breakMinutes > 0) {
        Text($r('app.string.preset_break_info', preset.breakMinutes))
          .fontSize(11)
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')
          .margin({ left: 14, top: 2 })
      }
    }
    .width('100%')
    .padding(10)
    .borderRadius(8)
    .backgroundColor($r('sys.color.comp_background_tertiary'))
    .margin({ top: 6 })
  }

  // 预设班次编辑器：名称、颜色、起止时间、休息时长，底部实时显示净工时
  @Builder
  presetEditor() {
    Column() {
      Text(this.editingPresetIndex >= 0 ? $r('app.string.preset_edit_title') : $r('app.string.preset_new_title'))
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .width('100%')

      Text($r('app.string.preset_name'))
        .fontSize(12)
        .fontColor($r('sys.color.font_tertiary'))
        .width('100%')
        .margin({ top: 10 })
      TextInput({ text: this.presetName, placeholder: $r('app.string.preset_name_hint') })
        .width('100%')
        .onChange((v: string) => {
          this.presetName = v;
        })

      Text($r('app.string.preset_color'))
        .fontSize(12)
        .fontColor($r('sys.color.font_tertiary'))
        .width('100%')
        .margin({ top: 10 })
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.presetColors, (c: string) => {
          Stack() {
            Text('')
              .width(26)
              .height(26)
              .borderRadius(13)
              .backgroundColor(c)
            if (this.presetColor === c) {
              SymbolGlyph($r('sys.symbol.checkmark'))
                .fontSize(13)
                .fontWeight(FontWeight.Bold)
                .fontColor([Color.White])
            }
          }
          .width(34)
          .height(34)
          .borderRadius(17)
          .border({ width: this.presetColor === c ? 2 : 0, color: $r('sys.color.font_primary') })
          .margin({ right: 8, bottom: 6 })
          .onClick(() => {
            this.presetColor = c;
          })
        }, (c: string) => c)
      }
      .width('100%')
      .margin({ top: 4 })

      Row({ space: 10 }) {
        Column() {
          Text($r('app.string.preset_start'))
            .fontSize(12)
            .fontColor($r('sys.color.font_tertiary'))
          TextInput({ text: this.presetStart })
            .type(InputType.Normal)
            .width('100%')
            .onChange((v: string) => {
              this.presetStart = v;
            })
            .onBlur(() => {
              this.presetStart = normalizeTime(this.presetStart.trim());
            })
        }
        .layoutWeight(1)

        Column() {
          Text($r('app.string.preset_end'))
            .fontSize(12)
            .fontColor($r('sys.color.font_tertiary'))
          TextInput({ text: this.presetEnd })
            .type(InputType.Normal)
            .width('100%')
            .onChange((v: string) => {
              this.presetEnd = v;
            })
            .onBlur(() => {
              this.presetEnd = normalizeTime(this.presetEnd.trim());
            })
        }
        .layoutWeight(1)
      }
      .width('100%')
      .margin({ top: 10 })
      .alignItems(VerticalAlign.Bottom)

      Text($r('app.string.preset_break'))
        .fontSize(12)
        .fontColor($r('sys.color.font_tertiary'))
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ top: 4 })
      // 休息时长输入 + 跨天时的归属日选择（同一行：输入占一半，选择放右边）
      Row() {
        TextInput({ text: `${this.presetBreak}`, placeholder: $r('app.string.preset_break_hint') })
          .type(InputType.Number)
          .layoutWeight(1)
          .onChange((v: string) => {
            const n = Number(v);
            this.presetBreak = Number.isNaN(n) || n < 0 ? 0 : n;
          })

        // 跨天预设：休息可选计入今日或次日（只给跨天区间的两天）
        if (this.presetCrossesDay()) {
          Text($r('app.string.today_label'))
            .fontSize(11)
            .fontColor(this.presetBreakDay === 0 ? '#FFFFFF' : $r('sys.color.font_secondary'))
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .borderRadius(6)
            .backgroundColor(this.presetBreakDay === 0 ? $r('sys.color.brand') : $r('sys.color.comp_background_tertiary'))
            .margin({ left: 6 })
            .onClick(() => {
              this.presetBreakDay = 0;
            })
          Text($r('app.string.shift_next_day'))
            .fontSize(11)
            .fontColor(this.presetBreakDay === 1 ? '#FFFFFF' : $r('sys.color.font_secondary'))
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .borderRadius(6)
            .backgroundColor(this.presetBreakDay === 1 ? $r('sys.color.brand') : $r('sys.color.comp_background_tertiary'))
            .margin({ left: 4 })
            .onClick(() => {
              this.presetBreakDay = 1;
            })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 用于自动排班开关：开启后自动填充按此预设排班
      Row() {
        Text($r('app.string.preset_autofill'))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.presetAutoFill })
          .onChange((isOn: boolean) => {
            this.presetAutoFill = isOn;
          })
      }
      .width('100%')
      .margin({ top: 10 })

      // 时间段 + 净工时预览：设置了休息则按扣除后的工时展示
      Column() {
        Row() {
          Text(`${this.presetStart} - ${this.presetEnd}`)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
          Blank()
          Text($r('app.string.preset_total', minutesToHoursText(this.presetNetMinutes())))
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.brand'))
        }
        .width('100%')

        if (this.presetBreak > 0) {
          Text($r('app.string.preset_deducted', minutesToHoursText(this.presetBreak)))
            .fontSize(11)
            .fontColor($r('sys.color.font_tertiary'))
            .width('100%')
            .margin({ top: 2 })
        }
      }
      .width('100%')
      .padding(10)
      .borderRadius(8)
      .backgroundColor($r('sys.color.background_primary'))
      .border({ width: 0.5, color: $r('sys.color.comp_divider') })
      .margin({ top: 10 })

      Row({ space: 12 }) {
        Button($r('app.string.cancel'))
          .buttonStyle(ButtonStyleMode.NORMAL)
          .layoutWeight(1)
          .margin({ top: 12, bottom: 4 })
          .onClick(() => this.cancelPresetEdit())
        Button($r('app.string.save'))
          .layoutWeight(1)
          .margin({ top: 12, bottom: 4 })
          .onClick(() => this.savePreset())
      }
      .width('100%')
    }
    .width('100%')
    .padding(12)
    .borderRadius(10)
    .backgroundColor($r('sys.color.comp_background_tertiary'))
    .margin({ top: 8 })
  }

  // 规则区（大屏双栏时放左侧，竖屏在页面顶部）
  @Builder
  rulesSection() {
    this.sectionTitle($r('app.string.section_rules'))
    Column() {
      this.groupHeader($r('app.string.rule_group_target'), this.targetSummary(), 'target')
      if (this.expandedGroup === 'target') {
        this.editorTarget()
      }
      Divider().strokeWidth(0.5)
      this.groupHeader($r('app.string.rule_group_work'), this.workSummary(), 'work')
      if (this.expandedGroup === 'work') {
        this.editorWork()
      }
      Divider().strokeWidth(0.5)
      this.groupHeader($r('app.string.rule_group_rest'), this.restSummary(), 'rest')
      if (this.expandedGroup === 'rest') {
        this.editorRest()
      }
    }
    .width('100%')
    .borderRadius(12)
    .backgroundColor($r('sys.color.background_primary'))
    .border({ width: 0.5, color: $r('sys.color.comp_divider') })
  }

  // 预设排班区（大屏双栏时放右侧）
  @Builder
  presetsSection() {
    this.sectionTitle($r('app.string.section_presets'))
    Column() {
      Text($r('app.string.presets_desc'))
        .fontSize(11)
        .fontColor($r('sys.color.font_tertiary'))
        .width('100%')
        .padding({ left: 12, right: 12, top: 10 })
      Column() {
        if (this.presets.length === 0) {
          Text($r('app.string.preset_empty'))
            .fontSize(13)
            .fontColor($r('sys.color.font_tertiary'))
            .width('100%')
            .padding({ top: 10, bottom: 4 })
        } else {
          ForEach(this.presets, (preset: PresetShift, index: number) => {
            this.presetRow(preset, index)
          }, (preset: PresetShift) =>
            `${preset.id}-${preset.name}-${preset.color}-${preset.start}-${preset.end}-${preset.breakMinutes}-${preset.autoFill}`)
        }
        if (this.showPresetEditor) {
          this.presetEditor()
        } else {
          Button($r('app.string.preset_add'))
            .width('100%')
            .buttonStyle(ButtonStyleMode.NORMAL)
            .margin({ top: 10 })
            .onClick(() => this.openPresetEditor(-1))
        }
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 2, bottom: 12 })
    }
    .width('100%')
    .borderRadius(12)
    .backgroundColor($r('sys.color.background_primary'))
    .border({ width: 0.5, color: $r('sys.color.comp_divider') })
  }

  build() {
    Scroll(this.scroller) {
      Column() {
        if (this.isWideLayout) {
          // 大屏双栏：规则在左，预设排班在右（两栏间距 8vp）
          Row({ space: 8 }) {
            Column() {
              this.rulesSection()
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            Column() {
              this.presetsSection()
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
        } else {
          this.rulesSection()
          this.presetsSection()
        }

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
    .clip(false)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .backgroundColor($r('sys.color.background_secondary'))
  }
}