// 排班页：月历 + 本月概览 + 排班/提醒批量工具
import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import {
  DayEntry, Shift, ShiftRules, MonthStats, TodoItem, PresetShift,
  dateKey, daysInMonth, minutesToHoursText, normalizeTime, shiftCrossesDay, shiftMinutesOnOffsetDay
} from '../model/ScheduleTypes';
import { ScheduleService } from '../service/ScheduleService';
import { addShiftToCalendar, addShiftAlarm } from '../utils/CalendarReminder';
import { CalendarView } from '../view/CalendarView';

class DateShift {
  date: string = '';
  shift: Shift = new Shift();
}

// 添加班次表单里的一段（开始-结束）
class SegStartEnd {
  start: string = '';
  end: string = '';
  startPrev: boolean = false; // 开始时间属于昨日
  endNext: boolean = false;   // 结束时间属于次日
}

// 昨日跨天班次落到当日的尾巴（只读展示）
class BorrowedTail {
  name: string = '';
  color: string = '';
  timeText: string = '';
  hoursText: string = '';
}

@Component
export struct SchedulingPage {
  scroller: Scroller = new Scroller();
  @StorageProp('isWideLayout') isWideLayout: boolean = false; // 大屏（≥lg 断点）双栏布局
  @StorageLink('calendarSelectedDate') @Watch('onSelectedDateChange') selectedDate: string = '';
  @State days: DayEntry[] = [];
  @State rules: ShiftRules = new ShiftRules();
  @State stats: MonthStats = new MonthStats();
  // 新增班次表单与编辑态
  @State showShiftForm: boolean = false;
  @State newSegs: SegStartEnd[] = []; // 表单里逐段编辑的班次
  @State autoFillPresetId: string = ''; // 自动排班选中的模板预设，空 = 全部勾选预设
  @State editShiftIndex: number = -1; // >=0 表示正在编辑该下标的班次
  // 代理提醒权限审核期间暂时屏蔽加闹钟入口；通过后改回 true 即可恢复全部闹钟 UI
  private readonly showAlarmFeature: boolean = true; // 代理提醒权限已通过
  @State selectedShifts: number[] = []; // 本日勾选的班次下标
  @State editing: boolean = false;      // 开始排班后才显示编辑按钮
  @State presets: PresetShift[] = [];    // 「我的」里自定义的预设排班
  @State appliedPresetId: string = '';   // 当前添加到表单的预设
  @StorageLink('scheduleDataVersion') @Watch('onDataChanged') scheduleDataVersion: number = 0;
  @StorageLink('rulesChanged') @Watch('onRulesChanged') rulesChanged: number = 0;
  @StorageLink('presetsChanged') @Watch('onPresetsChanged') presetsChanged: number = 0;
  @State renderTick: number = 0; // 数据/规则变化时自增，强制概览列表重建
  private service: ScheduleService = ScheduleService.getInstance();

  aboutToAppear(): void {
    this.loadDays();
    this.rules = this.service.getRules();
    this.presets = this.service.getPresets();
    this.refreshStats();
  }

  onPresetsChanged(): void {
    this.presets = this.service.getPresets();
  }

  onSelectedDateChange(): void {
    this.editing = false;
    this.showShiftForm = false;
    this.selectedShifts = [];
    this.loadDays();
  }

  loadDays(): void {
    this.days = this.service.getDays().slice();
  }

  isShiftSelected(index: number): boolean {
    return this.selectedShifts.includes(index);
  }

  toggleShiftSelected(index: number, isChecked: boolean): void {
    const idx = this.selectedShifts.indexOf(index);
    if (isChecked && idx === -1) {
      this.selectedShifts.push(index);
    } else if (!isChecked && idx >= 0) {
      this.selectedShifts.splice(idx, 1);
    }
  }

  // 取勾选的班次；未勾选则取本日全部班次
  targetShifts(): Shift[] {
    const shifts = this.service.findEntry(this.days, this.selectedDate)?.shifts ?? [];
    if (this.selectedShifts.length === 0) {
      return shifts;
    }
    const picked: Shift[] = [];
    for (const i of this.selectedShifts) {
      if (i >= 0 && i < shifts.length) {
        picked.push(shifts[i]);
      }
    }
    return picked;
  }

  upsertEntry(entry: DayEntry): void {
    const days = this.days;
    let found = false;
    for (let i = 0; i < days.length; i++) {
      if (days[i].date === entry.date) {
        days[i] = entry;
        found = true;
        break;
      }
    }
    if (!found) {
      days.push(entry);
    }
    this.saveDays(days);
    this.loadDays();
  }

  // 当前表单选中的预设（未选返回 undefined）
  findAppliedPreset(): PresetShift | undefined {
    for (const preset of this.presets) {
      if (preset.id === this.appliedPresetId) {
        return preset;
      }
    }
    return undefined;
  }

  addShift(): void {
    // 收集表单里完整的段，一次加齐
    const shifts: Shift[] = [];
    for (const seg of this.newSegs) {
      if (seg.start.trim() === '' || seg.end.trim() === '') {
        continue;
      }
      if (Shift.minutesBetween(seg.start.trim()) === Shift.minutesBetween(seg.end.trim())) {
        continue;
      }
      const s = new Shift();
      s.start = seg.start.trim();
      s.end = seg.end.trim();
      s.startDayOffset = seg.startPrev ? -1 : 0;
      // 显式标注次日，或结束早于开始的跨天兜底
      s.endDayOffset = seg.endNext || Shift.minutesBetween(s.end) <= Shift.minutesBetween(s.start) ? 1 : 0;
      shifts.push(s);
    }
    if (shifts.length === 0) {
      return;
    }
    if (this.editShiftIndex >= 0) {
      // 编辑模式：替换该班次的时间，保留原名称/颜色/休息
      const entry = this.service.findEntry(this.days, this.selectedDate);
      if (entry !== undefined && this.editShiftIndex < entry.shifts.length) {
        const old = entry.shifts[this.editShiftIndex];
        shifts[0].name = old.name;
        shifts[0].color = old.color;
        shifts[0].breakMinutes = old.breakMinutes;
        entry.shifts[this.editShiftIndex] = shifts[0];
        this.upsertEntry(entry);
      }
      this.editShiftIndex = -1;
      this.showShiftForm = false;
      this.appliedPresetId = '';
      return;
    }
    const entry = this.service.findEntry(this.days, this.selectedDate);
    const e = entry !== undefined ? entry : (() => {
      const ne = new DayEntry();
      ne.date = this.selectedDate;
      return ne;
    })();
    // 应用了预设且只有一段时，把预设的名称/颜色/休息带到班次上
    const preset = shifts.length === 1 ? this.findAppliedPreset() : undefined;
    for (const s of shifts) {
      if (preset !== undefined) {
        s.name = preset.name;
        s.color = preset.color;
        s.breakMinutes = preset.breakMinutes;
      }
      e.shifts.push(s);
    }
    this.appliedPresetId = '';
    this.upsertEntry(e);
    this.showShiftForm = false;
  }

  resetSegs(): void {
    const seg = new SegStartEnd();
    this.newSegs = [seg];
    this.appliedPresetId = '';
  }

  // 点预设按钮：一键填入起止时间，并记住名称/颜色/休息
  applyPreset(preset: PresetShift): void {
    const seg = new SegStartEnd();
    seg.start = preset.start;
    seg.end = preset.end;
    this.newSegs = [seg];
    this.appliedPresetId = preset.id;
  }

  addNewSeg(): void {
    this.newSegs.push(new SegStartEnd());
    this.appliedPresetId = '';
  }

  removeNewSeg(index: number): void {
    if (this.newSegs.length <= 1) {
      this.newSegs = [new SegStartEnd()];
      this.appliedPresetId = '';
      return;
    }
    this.newSegs.splice(index, 1);
    this.appliedPresetId = '';
  }

  // 昨天的日期键
  prevDateKey(): string {
    const parts = this.selectedDate.split('-');
    const d = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]) - 1);
    return dateKey(d.getFullYear(), d.getMonth() + 1, d.getDate());
  }

  // 昨日跨天班次落到当日的尾巴（只读展示，时长计入当日）
  borrowedTails(): BorrowedTail[] {
    const prev = this.service.findEntry(this.days, this.prevDateKey());
    if (prev === undefined) {
      return [];
    }
    const prevDay = this.service.str($r('app.string.shift_prev_day'));
    const result: BorrowedTail[] = [];
    for (const s of prev.shifts) {
      const tail = shiftMinutesOnOffsetDay(s, 1);
      if (tail <= 0) {
        continue;
      }
      const item = new BorrowedTail();
      item.name = s.name;
      item.color = s.color;
      item.timeText = `${prevDay} ${s.start} - ${s.end}`;
      item.hoursText = minutesToHoursText(tail);
      result.push(item);
    }
    return result;
  }

  // 班次时间段文案：结束跨到次日时带「次日」前缀，开始属昨日时带「昨日」前缀
  shiftTimeText(s: Shift): string {
    const prev = this.service.str($r('app.string.shift_prev_day'));
    const next = this.service.str($r('app.string.shift_next_day'));
    const startText = s.startDayOffset < 0 ? `${prev} ${s.start}` : s.start;
    const endText = shiftCrossesDay(s) ? `${next} ${s.end}` : s.end;
    return `${startText} - ${endText}`;
  }

  // 预设按钮两列网格的高度（chip 高 56 + rowsGap 6，末行无 gap）
  presetGridHeight(): number {
    if (this.presets.length === 0) {
      return 0;
    }
    const rows = Math.ceil(this.presets.length / 2);
    return rows * 56 + (rows - 1) * 6;
  }

  removeShift(index: number): void {
    const entry = this.service.findEntry(this.days, this.selectedDate);
    if (entry === undefined) {
      return;
    }
    entry.shifts.splice(index, 1);
    if (entry.shifts.length === 0) {
      // 删光班次 = 删除该天的记录，不算休息；休息只能通过「标记休息」产生
      const days = this.days;
      const idx = days.indexOf(entry);
      if (idx >= 0) {
        days.splice(idx, 1);
      }
      this.saveDays(days);
      this.loadDays();
      return;
    }
    this.upsertEntry(entry);
  }

  markRest(): void {
    const entry = this.service.findEntry(this.days, this.selectedDate);
    if (entry !== undefined && entry.shifts.length === 0) {
      // 已是休息标记，再点取消
      const days = this.days;
      const idx = days.indexOf(entry);
      if (idx >= 0) {
        days.splice(idx, 1);
      }
      this.saveDays(days);
      this.loadDays();
      return;
    }
    if (entry !== undefined && entry.shifts.length > 0) {
      // 已有班次：先确认再覆盖，避免静默丢班次
      this.getUIContext().showAlertDialog({
        title: $r('app.string.mark_rest'),
        message: $r('app.string.mark_rest_confirm_msg', entry.shifts.length),
        autoCancel: true,
        buttons: [
          { value: $r('app.string.cancel'), fontColor: $r('sys.color.font_secondary'), action: () => {} },
          { value: $r('app.string.mark_rest'), fontColor: $r('sys.color.brand'), action: () => this.doMarkRest() }
        ]
      });
      return;
    }
    this.doMarkRest();
  }

  doMarkRest(): void {
    const entry = this.service.findEntry(this.days, this.selectedDate);
    const ne = new DayEntry();
    ne.date = this.selectedDate;
    ne.memo = entry !== undefined ? entry.memo : '';
    this.upsertEntry(ne);
  }

  // 发布系统闹钟提醒（先选提前量，可批量）
  addAlarmForShifts(shifts: Shift[]): void {
    if (shifts.length === 0) {
      return;
    }
    const ctx = AppStorage.get<common.UIAbilityContext>('context');
    if (ctx === undefined) {
      return;
    }
    const leads: number[] = [0, 30, 60, 120];
    const labels: Resource[] = [$r('app.string.alarm_lead_none'), $r('app.string.alarm_lead_30'),
      $r('app.string.alarm_lead_60'), $r('app.string.alarm_lead_120')];
    promptAction.showActionMenu({
      title: $r('app.string.alarm_lead_title'),
      buttons: [
        { text: labels[0], color: '#0A59F7' },
        { text: labels[1], color: '#0A59F7' },
        { text: labels[2], color: '#0A59F7' },
        { text: labels[3], color: '#0A59F7' }
      ]
    }).then((res: promptAction.ActionMenuSuccessResponse) => {
      if (res.index < 0 || res.index >= leads.length) {
        return;
      }
      let allOk = true;
      let last: Promise<void> = Promise.resolve();
      for (const s of shifts) {
        last = last.then(() => {
          return addShiftAlarm(ctx, this.selectedDate, s, leads[res.index]).then((ok: boolean) => {
            if (!ok) {
              allOk = false;
            }
          });
        });
      }
      last.then(() => {
        promptAction.showToast({ message: allOk ? $r('app.string.added_ok') : $r('app.string.add_failed') });
      });
    });
  }

  // 写入系统日历（可批量）
  addCalendarForShifts(shifts: Shift[]): void {
    if (shifts.length === 0) {
      return;
    }
    const ctx = AppStorage.get<common.UIAbilityContext>('context');
    if (ctx === undefined) {
      return;
    }
    let allOk = true;
    let last: Promise<void> = Promise.resolve();
    for (const s of shifts) {
      last = last.then(() => {
        return addShiftToCalendar(ctx, this.selectedDate, s).then((ok: boolean) => {
          if (!ok) {
            allOk = false;
          }
        });
      });
    }
    last.then(() => {
      promptAction.showToast({ message: allOk ? $r('app.string.added_ok') : $r('app.string.add_failed') });
    });
  }

  onDataChanged(): void {
    this.loadDays();
    this.refreshStats();
    this.renderTick++;
  }

  onRulesChanged(): void {
    this.rules = this.service.getRules();
    this.refreshStats();
    this.renderTick++;
  }

  refreshStats(): void {
    const now = new Date();
    this.stats = this.service.computeStats(this.service.getDays(),
      now.getFullYear(), now.getMonth() + 1, this.rules);
  }

  // 保存并通知各页面刷新
  saveDays(days: DayEntry[]): void {
    this.service.saveDays(days);
    AppStorage.setOrCreate('scheduleDataVersion', Date.now());
  }

  dateFromPicker(d: Date): string {
    return dateKey(d.getFullYear(), d.getMonth() + 1, d.getDate());
  }

  addOneDay(date: string): string {
    const dt = new Date(date + 'T00:00:00');
    dt.setDate(dt.getDate() + 1);
    return this.dateFromPicker(dt);
  }

  pickDate(selected: Date, onAccept: (date: string) => void): void {
    this.getUIContext().showDatePickerDialog({
      start: new Date(2000, 0, 1),
      end: new Date(2100, 11, 31),
      selected: selected,
      onDateAccept: (value: Date) => {
        onAccept(this.dateFromPicker(value));
      }
    });
  }

  pickRange(onAccept: (start: string, end: string) => void): void {
    const now = new Date();
    this.pickDate(new Date(now.getFullYear(), now.getMonth(), 1), (start: string) => {
      this.pickDate(new Date(start + 'T00:00:00'), (end: string) => {
        if (end < start) {
          return;
        }
        onAccept(start, end);
      });
    });
  }

  // 先说明工具用途与步骤，用户点「开始」后再进入流程
  showIntro(title: Resource, desc: Resource, onStart: () => void): void {
    this.getUIContext().showAlertDialog({
      title: title,
      message: desc,
      autoCancel: true,
      buttons: [
        { value: $r('app.string.cancel'), fontColor: $r('sys.color.font_secondary'), action: () => {} },
        { value: $r('app.string.start'), fontColor: $r('sys.color.brand'), action: onStart }
      ]
    });
  }

  syncMonth(): void {
    this.showIntro($r('app.string.sync_to_month'), $r('app.string.sync_desc'), () => {
      const now = new Date();
      // 第一步：选源月份
      this.getUIContext().showDatePickerDialog({
        start: new Date(2000, 0, 1),
        end: new Date(2100, 11, 31),
        selected: new Date(now.getFullYear(), now.getMonth(), 1),
        mode: DatePickerMode.YEAR_AND_MONTH,
        onDateAccept: (src: Date) => {
          // 第二步：选目标月份
          this.getUIContext().showDatePickerDialog({
            start: new Date(2000, 0, 1),
            end: new Date(2100, 11, 31),
            selected: new Date(src.getFullYear(), src.getMonth() + 1, 1),
            mode: DatePickerMode.YEAR_AND_MONTH,
            onDateAccept: (dst: Date) => {
              // 第三步：确认覆盖
              this.getUIContext().showAlertDialog({
                title: $r('app.string.sync_confirm_title'),
                message: $r('app.string.sync_confirm_msg'),
                autoCancel: true,
                buttons: [
                  { value: $r('app.string.cancel'), fontColor: $r('sys.color.font_secondary'), action: () => {} },
                  {
                    value: $r('app.string.btn_clear'),
                    fontColor: $r('sys.color.brand'),
                    action: () => {
                      const days = this.service.getDays();
                      const n = this.service.copyMonthTo(days,
                        src.getFullYear(), src.getMonth() + 1,
                        dst.getFullYear(), dst.getMonth() + 1);
                      this.saveDays(days);
                      promptAction.showToast({ message: $r('app.string.copied_sync', n) });
                    }
                  }
                ]
              });
            }
          });
        }
      });
    });
  }

  autoFillMonth(): void {
    this.getUIContext().showAlertDialog({
      title: $r('app.string.auto_confirm_title'),
      message: $r('app.string.auto_confirm_msg'),
      autoCancel: true,
      buttons: [
        { value: $r('app.string.cancel'), fontColor: $r('sys.color.font_secondary'), action: () => {} },
        {
          value: $r('app.string.btn_clear'),
          fontColor: $r('sys.color.brand'),
          action: () => {
            const now = new Date();
            const days = this.service.getDays();
            const n = this.service.autoFillMonth(days, now.getFullYear(), now.getMonth() + 1, this.rules, this.autoFillPresetId);
            this.saveDays(days);
            promptAction.showToast({ message: $r('app.string.auto_filled', n) });
          }
        }
      ]
    });
  }

  rangeAuto(): void {
    this.showIntro($r('app.string.range_auto'), $r('app.string.range_auto_desc'), () => {
      this.pickRange((start: string, end: string) => {
        const days = this.service.getDays();
        const n = this.service.autoFillRange(days, start, end, this.rules, this.autoFillPresetId);
        this.saveDays(days);
        promptAction.showToast({ message: $r('app.string.range_filled', n) });
      });
    });
  }

  rangeCopy(): void {
    this.showIntro($r('app.string.range_copy'), $r('app.string.range_copy_desc'), () => {
      this.pickDate(new Date(), (srcStart: string) => {
        this.pickDate(new Date(srcStart + 'T00:00:00'), (srcEnd: string) => {
          if (srcEnd < srcStart) {
            return;
          }
          this.pickDate(new Date(srcEnd + 'T00:00:00'), (dstStart: string) => {
            const days = this.service.getDays();
            const n = this.service.copyRangeTo(days, srcStart, srcEnd, dstStart);
            this.saveDays(days);
            promptAction.showToast({ message: $r('app.string.range_copied', n) });
          });
        });
      });
    });
  }

  copyDay(): void {
    this.showIntro($r('app.string.copy_day'), $r('app.string.copyday_desc'), () => {
      this.pickDate(new Date(), (src: string) => {
        this.pickDate(new Date(src + 'T00:00:00'), (dst: string) => {
          const days = this.service.getDays();
          if (this.service.copyDayTo(days, src, dst)) {
            this.saveDays(days);
            promptAction.showToast({ message: $r('app.string.copy_day_done') });
          } else {
            promptAction.showToast({ message: $r('app.string.copy_day_done') });
          }
        });
      });
    });
  }

  // 区间内所有班次（批量加闹钟/日历共用的遍历）
  shiftsInRange(start: string, end: string): DateShift[] {
    const days = this.service.getDays();
    const result: DateShift[] = [];
    let cur = start;
    while (cur <= end) {
      const entry = this.service.findEntry(days, cur);
      if (entry !== undefined) {
        for (const s of entry.shifts) {
          const ds = new DateShift();
          ds.date = cur;
          ds.shift = s;
          result.push(ds);
        }
      }
      cur = this.addOneDay(cur);
    }
    return result;
  }

  batchAlarm(start: string, end: string): void {
    const targets = this.shiftsInRange(start, end);
    if (targets.length === 0) {
      promptAction.showToast({ message: $r('app.string.no_shifts_in_range') });
      return;
    }
    const ctx = AppStorage.get<common.UIAbilityContext>('context');
    if (ctx === undefined) {
      return;
    }
    const leads: number[] = [0, 30, 60, 120];
    const labels: Resource[] = [$r('app.string.alarm_lead_none'), $r('app.string.alarm_lead_30'),
      $r('app.string.alarm_lead_60'), $r('app.string.alarm_lead_120')];
    promptAction.showActionMenu({
      title: $r('app.string.alarm_lead_title'),
      buttons: [
        { text: labels[0], color: '#0A59F7' },
        { text: labels[1], color: '#0A59F7' },
        { text: labels[2], color: '#0A59F7' },
        { text: labels[3], color: '#0A59F7' }
      ]
    }).then((res: promptAction.ActionMenuSuccessResponse) => {
      if (res.index < 0 || res.index >= leads.length) {
        return;
      }
      let ok = 0;
      let last: Promise<void> = Promise.resolve();
      for (const t of targets) {
        last = last.then(() => {
          return addShiftAlarm(ctx, t.date, t.shift, leads[res.index]).then((success: boolean) => {
            if (success) {
              ok++;
            }
          });
        });
      }
      last.then(() => {
        promptAction.showToast({ message: $r('app.string.batch_added', ok) });
      });
    });
  }

  batchCalendar(start: string, end: string): void {
    const targets = this.shiftsInRange(start, end);
    if (targets.length === 0) {
      promptAction.showToast({ message: $r('app.string.no_shifts_in_range') });
      return;
    }
    const ctx = AppStorage.get<common.UIAbilityContext>('context');
    if (ctx === undefined) {
      return;
    }
    let ok = 0;
    let last: Promise<void> = Promise.resolve();
    for (const t of targets) {
      last = last.then(() => {
        return addShiftToCalendar(ctx, t.date, t.shift).then((success: boolean) => {
          if (success) {
            ok++;
          }
        });
      });
    }
    last.then(() => {
      promptAction.showToast({ message: $r('app.string.batch_added', ok) });
    });
  }

  @Builder
  presetChip(preset: PresetShift) {
    Column() {
      Text(preset.name)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(preset.color)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Text(`${preset.start}-${preset.end} · ${minutesToHoursText(preset.netMinutes())}`)
        .fontSize(10)
        .fontColor($r('sys.color.font_secondary'))
        .margin({ top: 2 })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .height(56)
    .justifyContent(FlexAlign.Center)
    .padding({ left: 8, right: 8 })
    .borderRadius(8)
    .backgroundColor($r('sys.color.comp_background_tertiary'))
    .border({
      width: this.appliedPresetId === preset.id ? 1.5 : 0.5,
      color: this.appliedPresetId === preset.id ? preset.color : $r('sys.color.comp_divider')
    })
    .onClick(() => this.applyPreset(preset))
  }

  @Builder
  shiftForm() {
    Column() {
      Text($r('app.string.section_presets'))
        .fontSize(12)
        .fontColor($r('sys.color.font_tertiary'))
        .width('100%')
      if (this.presets.length === 0) {
        Text($r('app.string.presets_none_in_form'))
          .fontSize(11)
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')
          .margin({ top: 6 })
      } else {
        Grid() {
          ForEach(this.presets, (preset: PresetShift) => {
            GridItem() {
              this.presetChip(preset)
            }
          }, (preset: PresetShift) =>
            `${preset.id}-${preset.name}-${preset.start}-${preset.end}-${preset.breakMinutes}`)
        }
        .columnsTemplate('1fr 1fr')
        .columnsGap(6)
        .rowsGap(6)
        .height(this.presetGridHeight())
        .width('100%')
        .margin({ top: 6 })
      }

      // 逐段编辑班次
      ForEach(this.newSegs, (seg: SegStartEnd, i: number) => {
        Row() {
          Column() {
            TextInput({ text: seg.start, placeholder: '08:00' })
              .type(InputType.Normal)
              .width('100%')
              .onChange((v: string) => {
                seg.start = v;
              })
              .onBlur(() => {
                const n = normalizeTime(seg.start);
                if (n !== seg.start) {
                  seg.start = n;
                  this.newSegs.splice(i, 1, seg);
                }
              })
            // 开始跨天标注：属于昨日
            Text($r('app.string.shift_prev_day'))
              .fontSize(11)
              .padding({ left: 8, right: 8, top: 2, bottom: 2 })
              .borderRadius(6)
              .border({
                width: seg.startPrev ? 1 : 0.5,
                color: seg.startPrev ? $r('sys.color.brand') : $r('sys.color.comp_divider')
              })
              .fontColor(seg.startPrev ? $r('sys.color.brand') : $r('sys.color.font_tertiary'))
              .margin({ top: 2 })
              .onClick(() => {
                seg.startPrev = !seg.startPrev;
                this.newSegs.splice(i, 1, seg);
              })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          Text('→').margin({ left: 6, right: 6 })

          Column() {
            TextInput({ text: seg.end, placeholder: '12:00' })
              .type(InputType.Normal)
              .width('100%')
              .onChange((v: string) => {
                seg.end = v;
              })
              .onBlur(() => {
                const n = normalizeTime(seg.end);
                if (n !== seg.end) {
                  seg.end = n;
                  this.newSegs.splice(i, 1, seg);
                }
              })
            // 结束跨天标注：属于次日
            Text($r('app.string.shift_next_day'))
              .fontSize(11)
              .padding({ left: 8, right: 8, top: 2, bottom: 2 })
              .borderRadius(6)
              .border({
                width: seg.endNext ? 1 : 0.5,
                color: seg.endNext ? $r('sys.color.brand') : $r('sys.color.comp_divider')
              })
              .fontColor(seg.endNext ? $r('sys.color.brand') : $r('sys.color.font_tertiary'))
              .margin({ top: 2 })
              .onClick(() => {
                seg.endNext = !seg.endNext;
                this.newSegs.splice(i, 1, seg);
              })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          Text($r('app.string.delete'))
            .fontSize(13)
            .fontColor($r('sys.color.warning'))
            .margin({ left: 10 })
            .onClick(() => this.removeNewSeg(i))
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
        .margin({ top: 6 })
      }, (seg: SegStartEnd, i: number) => `${i}-${seg.start}-${seg.end}-${seg.startPrev}-${seg.endNext}`)
      Button($r('app.string.add_segment'))
        .width('100%')
        .buttonStyle(ButtonStyleMode.NORMAL)
        .fontSize(12)
        .margin({ top: 6 })
        .onClick(() => this.addNewSeg())

      Row() {
        Button($r('app.string.cancel'))
          .buttonStyle(ButtonStyleMode.NORMAL)
          .onClick(() => {
            this.editShiftIndex = -1;
            this.appliedPresetId = '';
            this.showShiftForm = false;
          })
        Button(this.editShiftIndex >= 0 ? $r('app.string.save') : $r('app.string.add_shift_btn'))
          .margin({ left: 12 })
          .onClick(() => this.addShift())
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .margin({ top: 10 })
    }
    .padding(12)
    .borderRadius(12)
    .backgroundColor($r('sys.color.background_primary'))
    .border({ width: 0.5, color: $r('sys.color.comp_divider') })
    .margin({ top: 8 })
  }

  // 排班编辑区：标记休息 + 开始排班 + 班次编辑/批量
  @Builder
  scheduleEdit() {
    Column() {
      Row() {
        Text($r('app.string.day_schedule', this.selectedDate))
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
        Blank()
        Button(this.service.isRestDay(this.service.findEntry(this.days, this.selectedDate)) ? $r('app.string.cancel_rest') : $r('app.string.mark_rest'))
          .buttonStyle(ButtonStyleMode.NORMAL)
          .fontSize(12)
          .onClick(() => this.markRest())
      }
      .width('100%')

      // 当天没日程：开始排班放在前面
      if (!this.editing && this.targetShifts().length === 0 && this.selectedShifts.length === 0) {
        Button($r('app.string.start_schedule'))
          .width('100%')
          .margin({ top: 8 })
          .onClick(() => {
            this.editing = true;
          })
      }

      // 已排班次（编辑模式下勾选后可批量加闹钟/日历）
      List() {
        ForEach(this.service.findEntry(this.days, this.selectedDate)?.shifts ?? [], (s: Shift, i: number) => {
          ListItem() {
            Row() {
              if (this.editing) {
                Checkbox()
                  .select(this.isShiftSelected(i))
                  .width(18)
                  .height(18)
                  .onChange((isChecked: boolean) => {
                    this.toggleShiftSelected(i, isChecked);
                  })
              }
              // 班次颜色条：使用预设颜色，未命名班次用默认蓝
              Text('')
                .width(4)
                .height(34)
                .borderRadius(2)
                .backgroundColor(s.color !== '' ? s.color : '#0A59F7')
                .margin({ left: this.editing ? 10 : 0, right: 10 })
              Column() {
                if (s.name !== '') {
                  Text(s.name)
                    .fontSize(13)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(s.color !== '' ? s.color : $r('sys.color.font_primary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                Text(this.shiftTimeText(s))
                  .fontSize(s.name !== '' ? 12 : 15)
                  .fontColor(s.name !== '' ? $r('sys.color.font_secondary') : $r('sys.color.font_primary'))
                if (s.breakMinutes > 0) {
                  Text($r('app.string.preset_break_info', s.breakMinutes))
                    .fontSize(10)
                    .fontColor($r('sys.color.font_tertiary'))
                    .margin({ top: 1 })
                }
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Text(minutesToHoursText(s.durationMinutes()))
                .fontSize(13)
                .fontColor('#0A59F7')
                .margin({ left: 8 })
              Blank()
              if (this.editing) {
                Text($r('app.string.edit'))
                  .fontSize(13)
                  .fontColor($r('sys.color.brand'))
                  .margin({ left: 12, right: 12 })
                  .onClick(() => {
                    // 手动编辑该班次时间（保留名称/颜色/休息）
                    this.editShiftIndex = i;
                    this.appliedPresetId = '';
                    const seg = new SegStartEnd();
                    seg.start = s.start;
                    seg.end = s.end;
                    seg.startPrev = s.startDayOffset < 0;
                    seg.endNext = shiftCrossesDay(s);
                    this.newSegs = [seg];
                    this.showShiftForm = true;
                  })
                Text($r('app.string.delete'))
                  .fontSize(13)
                  .fontColor($r('sys.color.warning'))
                  .onClick(() => this.removeShift(i))
              }
            }
            .width('100%')
            .padding(10)
            .borderRadius(8)
            .backgroundColor($r('sys.color.comp_background_tertiary'))
            .margin({ top: 8 })
          }
        }, (s: Shift, i: number) =>
          `${i}-${s.start}-${s.end}-${s.name}-${s.color}-${s.breakMinutes}`)
      }
      .width('100%')

      // 昨日跨天班次落到今天的尾巴（只读，时长计入当日）
      ForEach(this.borrowedTails(), (item: BorrowedTail) => {
        Row() {
          Text('')
            .width(4)
            .height(34)
            .borderRadius(2)
            .backgroundColor(item.color !== '' ? item.color : '#0A59F7')
            .margin({ left: this.editing ? 10 : 0, right: 10 })
          Column() {
            if (item.name !== '') {
              Text(item.name)
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor(item.color !== '' ? item.color : $r('sys.color.font_primary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            Text(item.timeText)
              .fontSize(item.name !== '' ? 12 : 15)
              .fontColor(item.name !== '' ? $r('sys.color.font_secondary') : $r('sys.color.font_primary'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Text(item.hoursText)
            .fontSize(13)
            .fontColor('#0A59F7')
        }
        .width('100%')
        .padding(10)
        .borderRadius(8)
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .margin({ top: 8 })
      }, (item: BorrowedTail) => `${item.timeText}-${item.name}`)

      if (this.editing) {
        if (this.showShiftForm) {
          this.shiftForm()
        } else {
          Button($r('app.string.add_shift'))
            .width('100%')
            .buttonStyle(ButtonStyleMode.NORMAL)
            .margin({ top: 8 })
            .onClick(() => {
              this.editShiftIndex = -1;
              this.resetSegs();
              this.showShiftForm = true;
            })
        }

        // 批量：勾选的班次（未勾选则本日全部）
        Row({ space: 8 }) {
          if (this.showAlarmFeature) {
            Button($r('app.string.add_alarm'))
              .buttonStyle(ButtonStyleMode.NORMAL)
              .fontSize(13)
              .layoutWeight(1)
              .onClick(() => this.addAlarmForShifts(this.targetShifts()))
          }
          Button($r('app.string.add_calendar'))
            .buttonStyle(ButtonStyleMode.NORMAL)
            .fontSize(13)
            .layoutWeight(1)
            .onClick(() => this.addCalendarForShifts(this.targetShifts()))
        }
        .width('100%')
        .margin({ top: 8 })

        Button($r('app.string.done_schedule'))
          .width('100%')
          .margin({ top: 8 })
          .onClick(() => {
            this.editing = false;
            this.selectedShifts = [];
            this.showShiftForm = false;
          })
      } else if (this.targetShifts().length > 0 || this.selectedShifts.length > 0) {
        // 有日程：开始排班放在后面
        Button($r('app.string.start_schedule'))
          .width('100%')
          .buttonStyle(ButtonStyleMode.NORMAL)
          .margin({ top: 8 })
          .onClick(() => {
            this.editing = true;
          })
      }
    }
    .padding(12)
    .borderRadius(12)
    .backgroundColor($r('sys.color.background_primary'))
    .border({ width: 0.5, color: $r('sys.color.comp_divider') })
  }

  @Builder
  toolButton(label: Resource, action: () => void) {
    Button(label)
      .buttonStyle(ButtonStyleMode.NORMAL)
      .fontSize(13)
      .width('100%')
      .margin({ top: 8 })
      .onClick(() => action())
  }

  @Builder
  sectionTitle(title: Resource) {
    Text(title)
      .fontSize(13)
      .fontColor($r('sys.color.font_tertiary'))
      .width('100%')
      .margin({ top: 16, bottom: 6 })
  }

  // 排班编辑与工具区（大屏双栏时放右侧，竖屏时在日历下方）
  @Builder
  scheduleTools() {
    this.scheduleEdit()

    this.sectionTitle($r('app.string.tools_section_overview'))
    Column() {
      Row() {
        Text($r('app.string.progress_done', minutesToHoursText(this.stats.workedMinutes), this.rules.monthlyTargetHours))
          .fontSize(13)
        Blank()
        Text($r('app.string.progress_need', minutesToHoursText(this.stats.remainingMinutes)))
          .fontSize(13)
          .fontColor($r('sys.color.brand'))
          .fontWeight(FontWeight.Medium)
      }
      .width('100%')

      Progress({ value: this.stats.workedMinutes, total: Math.max(this.stats.targetMinutes, 1), type: ProgressType.Linear })
        .width('100%')
        .margin({ top: 8 })

      if (this.stats.violations.length > 0) {
        Text($r('app.string.rule_reminders'))
          .fontSize(12)
          .fontColor($r('sys.color.warning'))
          .margin({ top: 10 })
        ForEach(this.stats.violations, (v: string) => {
          Text(v)
            .fontSize(12)
            .fontColor($r('sys.color.font_secondary'))
            .margin({ top: 2 })
        }, (v: string) => `${this.renderTick}-${v}`)
      }
    }
    .width('100%')
    .padding(12)
    .borderRadius(12)
    .backgroundColor($r('sys.color.background_primary'))
    .border({ width: 0.5, color: $r('sys.color.comp_divider') })

    // 自动排班：选择模板预设后一键填充
    this.sectionTitle($r('app.string.section_autofill'))
    Column() {
      Text($r('app.string.autofill_desc'))
        .fontSize(11)
        .fontColor($r('sys.color.font_tertiary'))
        .width('100%')
        .padding({ left: 12, right: 12, top: 10 })
      Flex({ wrap: FlexWrap.Wrap }) {
        Text($r('app.string.autofill_all'))
          .fontSize(12)
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .borderRadius(8)
          .backgroundColor(this.autoFillPresetId === '' ? $r('sys.color.brand') : $r('sys.color.comp_background_tertiary'))
          .fontColor(this.autoFillPresetId === '' ? '#FFFFFF' : $r('sys.color.font_primary'))
          .margin({ right: 6, bottom: 6 })
          .onClick(() => {
            this.autoFillPresetId = '';
          })
        ForEach(this.presets.filter((p: PresetShift) => p.autoFill), (preset: PresetShift) => {
          Text(preset.name)
            .fontSize(12)
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .borderRadius(8)
            .backgroundColor(this.autoFillPresetId === preset.id ? $r('sys.color.brand') : $r('sys.color.comp_background_tertiary'))
            .fontColor(this.autoFillPresetId === preset.id ? '#FFFFFF' : $r('sys.color.font_primary'))
            .margin({ right: 6, bottom: 6 })
            .onClick(() => {
              this.autoFillPresetId = preset.id;
            })
        }, (preset: PresetShift) => `${preset.id}-${this.autoFillPresetId}`)
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })

      this.toolButton($r('app.string.auto_fill'), (): void => this.autoFillMonth())
      this.toolButton($r('app.string.range_auto'), (): void => this.rangeAuto())
    }
    .width('100%')
    .padding(12)
    .borderRadius(12)
    .backgroundColor($r('sys.color.background_primary'))
    .border({ width: 0.5, color: $r('sys.color.comp_divider') })

    this.sectionTitle($r('app.string.tools_section_schedule'))
    Column() {
      this.toolButton($r('app.string.sync_to_month'), (): void => this.syncMonth())
      this.toolButton($r('app.string.copy_day'), (): void => this.copyDay())
      this.toolButton($r('app.string.range_copy'), (): void => this.rangeCopy())
    }
    .width('100%')
    .padding(12)
    .borderRadius(12)
    .backgroundColor($r('sys.color.background_primary'))
    .border({ width: 0.5, color: $r('sys.color.comp_divider') })

    this.sectionTitle($r('app.string.tools_section_remind'))
    Column() {
      if (this.showAlarmFeature) {
        this.toolButton($r('app.string.batch_alarm'), (): void => {
          this.showIntro($r('app.string.batch_alarm'), $r('app.string.batch_alarm_desc'), (): void => {
            this.pickRange((start: string, end: string) => this.batchAlarm(start, end));
          });
        })
      }
      this.toolButton($r('app.string.batch_calendar'), (): void => {
        this.showIntro($r('app.string.batch_calendar'), $r('app.string.batch_calendar_desc'), (): void => {
          this.pickRange((start: string, end: string) => this.batchCalendar(start, end));
        });
      })
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
        if (this.isWideLayout) {
          // 大屏双栏：日历在左，排班编辑与工具在右
          Row() {
            Column() {
              CalendarView()
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            Column() {
              this.scheduleTools()
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
        } else {
          CalendarView()
          this.scheduleTools()
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
    .backgroundColor($r('sys.color.background_secondary'))
  }
}
