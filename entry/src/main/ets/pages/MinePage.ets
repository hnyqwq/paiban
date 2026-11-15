// 第三页：我的 —— 仅放额外设置（外观/规则/数据/关于）
import { pasteboard, BusinessError } from '@kit.BasicServicesKit';
import { promptAction, SegmentButtonV2Items, CapsuleSegmentButtonV2 } from '@kit.ArkUI';
import { common, bundleManager } from '@kit.AbilityKit';
import { updateManager } from '@kit.AppGalleryKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ShiftRules, Shift, PresetShift, PRESET_COLORS, normalizeTime, minutesToHoursText } from '../model/ScheduleTypes';
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

// 固定班次模板的一段（开始-结束）
class TemplateSeg {
  start: string = '';
  end: string = '';
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
  @State weekStart: number = 0; // 0 周日开始 1 周一开始
  @State rules: ShiftRules = new ShiftRules();
  @State showRuleEditor: boolean = false;
  @State templateSegs: TemplateSeg[] = []; // 模板逐段编辑状态
  // 预设排班
  @State presets: PresetShift[] = [];
  @State showPresetEditor: boolean = false;
  @State editingPresetIndex: number = -1;
  @State presetName: string = '';
  @State presetColor: string = PRESET_COLORS[0];
  @State presetStart: string = '09:00';
  @State presetEnd: string = '17:00';
  @State presetBreak: number = 0;
  private presetColors: string[] = PRESET_COLORS;
  @State bundleName: string = '';
  @State versionName: string = '';
  private service: ScheduleService = ScheduleService.getInstance();
  @State showImportEditor: boolean = false;
  @State importText: string = '';

  // 确认导入：解析并写入，成功后广播刷新
  confirmImport(): void {
    const trimmed = this.importText.trim();
    if (trimmed === '') {
      promptAction.showToast({ message: $r('app.string.import_empty') });
      return;
    }
    if (this.service.importDays(trimmed)) {
      promptAction.showToast({ message: $r('app.string.import_success') });
      this.showImportEditor = false;
      this.importText = '';
    } else {
      promptAction.showToast({ message: $r('app.string.import_failed_len', trimmed.length) });
    }
  }

  aboutToAppear(): void {
    this.appearanceMode = this.service.getAppearanceMode();
    this.weekStart = this.service.getWeekStart();
    this.rules = this.service.getRules();
    this.presets = this.service.getPresets();
    this.loadBundleInfo();
  }

  // 通过 bundleManager 实时读取包名与版本号
  loadBundleInfo(): void {
    try {
      const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      this.bundleName = info.name;
      this.versionName = `${info.versionName} (${info.versionCode})`;
    } catch (e) {
      hilog.error(0x0000, 'testTag', 'Failed to load bundle info. Cause: %{public}s', JSON.stringify(e));
    }
  }

  // 打开规则编辑器：把模板字符串解析成一段一段
  openRuleEditor(): void {
    const segs: TemplateSeg[] = [];
    const parts = this.rules.shiftTemplate.split(',');
    for (const p of parts) {
      const s = p.split('-');
      if (s.length === 2) {
        const seg = new TemplateSeg();
        seg.start = s[0].trim();
        seg.end = s[1].trim();
        segs.push(seg);
      }
    }
    this.templateSegs = segs;
    this.showRuleEditor = true;
  }

  // 逐段编辑结果自动拼回模板字符串（完整的段才计入）
  syncTemplate(): void {
    const parts: string[] = [];
    for (const seg of this.templateSegs) {
      if (seg.start.trim() !== '' && seg.end.trim() !== '') {
        parts.push(`${seg.start.trim()}-${seg.end.trim()}`);
      }
    }
    this.rules.shiftTemplate = parts.join(',');
  }

  addSegment(): void {
    this.templateSegs.push(new TemplateSeg());
  }

  removeSegment(index: number): void {
    this.templateSegs.splice(index, 1);
    this.syncTemplate();
  }

  saveRules(): void {
    this.service.saveRules(this.rules);
    // 保存后收起编辑器，回到展示态并刷新数值
    this.rules = this.service.getRules();
    this.showRuleEditor = false;
    promptAction.showToast({ message: $r('app.string.rule_saved') });
  }

  // 取消编辑：丢弃未保存的修改，恢复为已存储的规则
  cancelEdit(): void {
    this.rules = this.service.getRules();
    this.showRuleEditor = false;
  }

  // ===== 预设排班 =====

  // 编辑器里的净工时（分钟）= 起止跨度 - 休息时长
  presetNetMinutes(): number {
    return Math.max(0, Shift.spanMinutes(this.presetStart, this.presetEnd) - Math.max(0, this.presetBreak));
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
    } else {
      this.editingPresetIndex = -1;
      this.presetName = '';
      this.presetColor = PRESET_COLORS[0];
      this.presetStart = '09:00';
      this.presetEnd = '17:00';
      this.presetBreak = 0;
    }
    this.showPresetEditor = true;
  }

  cancelPresetEdit(): void {
    this.showPresetEditor = false;
    this.editingPresetIndex = -1;
  }

  savePreset(): void {
    const name = this.presetName.trim();
    if (name === '') {
      promptAction.showToast({ message: $r('app.string.preset_name_required') });
      return;
    }
    const start = normalizeTime(this.presetStart.trim());
    const end = normalizeTime(this.presetEnd.trim());
    const timePattern = /^\d{1,2}:\d{2}$/;
    if (!timePattern.test(start) || !timePattern.test(end)) {
      promptAction.showToast({ message: $r('app.string.preset_time_invalid') });
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

  // 打开隐私协议（系统浏览器）
  openPrivacy(): void {
    const ctx = AppStorage.get<common.UIAbilityContext>('context');
    if (ctx === undefined) {
      return;
    }
    ctx.openLink('https://agreement-drcn.hispace.dbankcloud.cn/index.html?lang=zh&agreementId=2082051778836223232');
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
      ForEach(this.templateSegs, (seg: TemplateSeg, i: number) => {
        Row() {
          TextInput({ text: seg.start, placeholder: '08:00' })
            .type(InputType.Normal)
            .layoutWeight(1)
            .onChange((v: string) => {
              seg.start = v;
              this.syncTemplate();
            })
            .onBlur(() => {
              const n = normalizeTime(seg.start);
              if (n !== seg.start) {
                seg.start = n;
                this.templateSegs.splice(i, 1, seg);
                this.syncTemplate();
              }
            })
          Text('→').margin({ left: 6, right: 6 })
          TextInput({ text: seg.end, placeholder: '12:00' })
            .type(InputType.Normal)
            .layoutWeight(1)
            .onChange((v: string) => {
              seg.end = v;
              this.syncTemplate();
            })
            .onBlur(() => {
              const n = normalizeTime(seg.end);
              if (n !== seg.end) {
                seg.end = n;
                this.templateSegs.splice(i, 1, seg);
                this.syncTemplate();
              }
            })
          Text($r('app.string.delete'))
            .fontSize(13)
            .fontColor($r('sys.color.warning'))
            .margin({ left: 10 })
            .onClick(() => this.removeSegment(i))
        }
        .width('100%')
        .margin({ top: 6 })
      }, (seg: TemplateSeg, i: number) => `${i}-${seg.start}-${seg.end}`)
      Button($r('app.string.add_segment'))
        .width('100%')
        .buttonStyle(ButtonStyleMode.NORMAL)
        .fontSize(12)
        .margin({ top: 6 })
        .onClick(() => this.addSegment())

      Text($r('app.string.rule_mandatory_rest'))
        .fontSize(13)
        .margin({ top: 10 })
      TextInput({ text: `${this.rules.mandatoryRestMinutes}` })
        .type(InputType.Number)
        .width('100%')
        .onChange((v: string) => {
          this.rules.mandatoryRestMinutes = Number(v) || 0;
        })

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
    .width('100%')
    .padding(12)
    .borderRadius(12)
    .backgroundColor($r('sys.color.background_primary'))
    .border({ width: 0.5, color: $r('sys.color.comp_divider') })
    .margin({ top: 8 })
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
          Text(`${preset.start} - ${preset.end}`)
            .fontSize(12)
            .fontColor($r('sys.color.font_secondary'))
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
              Text('✓')
                .fontSize(13)
                .fontWeight(FontWeight.Bold)
                .fontColor(Color.White)
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
        .margin({ top: 10 })
      TextInput({ text: `${this.presetBreak}`, placeholder: $r('app.string.preset_break_hint') })
        .type(InputType.Number)
        .width('100%')
        .onChange((v: string) => {
          const n = Number(v);
          this.presetBreak = Number.isNaN(n) || n < 0 ? 0 : n;
        })

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

  build() {
    Scroll(this.scroller) {
      Column() {
        this.sectionTitle($r('app.string.section_rules'))
        Column() {
          if (!this.showRuleEditor) {
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
          }

          if (this.showRuleEditor) {
            this.ruleEditor()
          } else {
            Button($r('app.string.edit_rules'))
              .width('calc(100% - 24vp)')
              .buttonStyle(ButtonStyleMode.NORMAL)
              .margin({ top: 12, bottom: 12, left: 12, right: 12 })
              .onClick(() => {
                this.openRuleEditor();
              })
          }
        }
        .width('100%')
        .borderRadius(12)
        .backgroundColor($r('sys.color.background_primary'))
        .border({ width: 0.5, color: $r('sys.color.comp_divider') })

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
                `${preset.id}-${preset.name}-${preset.color}-${preset.start}-${preset.end}-${preset.breakMinutes}`)
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
              .onClick(() => {
                this.importText = '';
                this.showImportEditor = true;
              })
          }
          .width('100%')
          if (this.showImportEditor) {
            // 导入在主窗口内联执行：安全控件 PasteButton 在子窗口（CustomDialog）中拿不到临时授权
            Column() {
              Row() {
                PasteButton()
                  .fontSize(13)
                  .onClick((event: ClickEvent, result: PasteButtonOnClickResult) => {
                    if (result !== PasteButtonOnClickResult.SUCCESS) {
                      return;
                    }
                    try {
                      const text = pasteboard.getSystemPasteboard().getDataSync().getPrimaryText();
                      if (text !== '') {
                        this.importText = text;
                      } else {
                        promptAction.showToast({ message: $r('app.string.clipboard_empty') });
                      }
                    } catch (e) {
                      promptAction.showToast({ message: $r('app.string.clipboard_empty') });
                    }
                  })
              }
              .width('100%')
              .justifyContent(FlexAlign.Start)

              TextArea({ text: this.importText, placeholder: $r('app.string.import_hint') })
                .width('100%')
                .height(140)
                .margin({ top: 8 })
                .onChange((v: string) => {
                  this.importText = v;
                })
              Row() {
                Button($r('app.string.cancel'))
                  .buttonStyle(ButtonStyleMode.NORMAL)
                  .layoutWeight(1)
                  .onClick(() => {
                    this.showImportEditor = false;
                    this.importText = '';
                  })
                Button($r('app.string.import_data'))
                  .layoutWeight(1)
                  .margin({ left: 12 })
                  .onClick(() => this.confirmImport())
              }
              .width('100%')
              .margin({ top: 12 })
            }
            .width('calc(100% - 24vp)')
            .margin({ left: 12, right: 12, top: 8 })
          }
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

          Row() {
            Text($r('app.string.week_start_title'))
              .fontSize(14)
              .layoutWeight(1)
            Button($r('app.string.week_start_sun'))
              .buttonStyle(this.weekStart === 0 ? ButtonStyleMode.EMPHASIZED : ButtonStyleMode.NORMAL)
              .fontSize(12)
              .onClick(() => {
                this.weekStart = 0;
                this.service.setWeekStart(0);
              })
            Button($r('app.string.week_start_mon'))
              .buttonStyle(this.weekStart === 1 ? ButtonStyleMode.EMPHASIZED : ButtonStyleMode.NORMAL)
              .fontSize(12)
              .margin({ left: 8 })
              .onClick(() => {
                this.weekStart = 1;
                this.service.setWeekStart(1);
              })
          }
          .width('calc(100% - 24vp)')
          .margin({ left: 12, right: 12, bottom: 12 })
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

        // 隐私协议
        Row() {
          Text($r('app.string.privacy_policy'))
            .fontSize(15)
            .fontColor($r('sys.color.brand'))
          Blank()
          Text('›')
            .fontSize(16)
            .fontColor($r('sys.color.font_tertiary'))
        }
        .width('100%')
        .padding(12)
        .borderRadius(12)
        .backgroundColor($r('sys.color.background_primary'))
        .border({ width: 0.5, color: $r('sys.color.comp_divider') })
        .margin({ top: 12 })
        .onClick(() => this.openPrivacy())

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
