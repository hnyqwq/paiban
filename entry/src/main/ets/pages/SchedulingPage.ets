// 排班页：月历 + 本月概览 + 排班/提醒批量工具
import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import {
  DayEntry, Shift, ShiftRules, MonthStats,
  dateKey, daysInMonth, minutesToHoursText
} from '../model/ScheduleTypes';
import { ScheduleService } from '../service/ScheduleService';
import { addShiftToCalendar, addShiftAlarm } from '../utils/CalendarReminder';
import { CalendarView } from '../view/CalendarView';

class DateShift {
  date: string = '';
  shift: Shift = new Shift();
}

@Component
export struct SchedulingPage {
  scroller: Scroller = new Scroller();
  @StorageLink('calendarSelectedDate') @Watch('onSelectedDateChange') selectedDate: string = '';
  @State days: DayEntry[] = [];
  @State rules: ShiftRules = new ShiftRules();
  @State stats: MonthStats = new MonthStats();
  // 新增班次表单与编辑态
  @State showShiftForm: boolean = false;
  @State newStart: string = '09:00';
  @State newEnd: string = '17:00';
  @State selectedShifts: number[] = []; // 本日勾选的班次下标
  @State editing: boolean = false;      // 开始排班后才显示编辑按钮
  @StorageLink('scheduleDataVersion') @Watch('onDataChanged') scheduleDataVersion: number = 0;
  @StorageLink('rulesChanged') @Watch('onRulesChanged') rulesChanged: number = 0;
  private service: ScheduleService = ScheduleService.getInstance();

  aboutToAppear(): void {
    this.loadDays();
    this.rules = this.service.getRules();
    this.refreshStats();
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

  addShift(): void {
    if (Shift.minutesBetween(this.newEnd) === Shift.minutesBetween(this.newStart)) {
      return;
    }
    const entry = this.service.findEntry(this.days, this.selectedDate);
    const e = entry !== undefined ? entry : (() => {
      const ne = new DayEntry();
      ne.date = this.selectedDate;
      return ne;
    })();
    const s = new Shift();
    s.start = this.newStart;
    s.end = this.newEnd;
    e.shifts.push(s);
    this.upsertEntry(e);
    this.showShiftForm = false;
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
  }

  onRulesChanged(): void {
    this.rules = this.service.getRules();
    this.refreshStats();
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
            const n = this.service.autoFillMonth(days, now.getFullYear(), now.getMonth() + 1, this.rules);
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
        const n = this.service.autoFillRange(days, start, end, this.rules);
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
  shiftForm() {
    Column() {
      Text($r('app.string.tpl_title'))
        .fontSize(12)
        .fontColor($r('sys.color.font_tertiary'))
        .width('100%')
      Row({ space: 6 }) {
        Button($r('app.string.tpl_early'))
          .buttonStyle(ButtonStyleMode.NORMAL)
          .fontSize(11)
          .layoutWeight(1)
          .onClick(() => {
            this.newStart = '06:00';
            this.newEnd = '14:00';
          })
        Button($r('app.string.tpl_day'))
          .buttonStyle(ButtonStyleMode.NORMAL)
          .fontSize(11)
          .layoutWeight(1)
          .onClick(() => {
            this.newStart = '09:00';
            this.newEnd = '17:00';
          })
      }
      .width('100%')
      .margin({ top: 4 })
      Row({ space: 6 }) {
        Button($r('app.string.tpl_evening'))
          .buttonStyle(ButtonStyleMode.NORMAL)
          .fontSize(11)
          .layoutWeight(1)
          .onClick(() => {
            this.newStart = '14:00';
            this.newEnd = '22:00';
          })
        Button($r('app.string.tpl_night'))
          .buttonStyle(ButtonStyleMode.NORMAL)
          .fontSize(11)
          .layoutWeight(1)
          .onClick(() => {
            this.newStart = '22:00';
            this.newEnd = '06:00';
          })
      }
      .width('100%')
      .margin({ top: 6 })

      Row() {
        TextInput({ text: this.newStart, placeholder: '09:00' })
          .type(InputType.Normal)
          .width('45%')
          .onChange((v: string) => {
            this.newStart = v;
          })
        Text('→').margin({ left: 8, right: 8 })
        TextInput({ text: this.newEnd, placeholder: '17:00' })
          .type(InputType.Normal)
          .width('45%')
          .onChange((v: string) => {
            this.newEnd = v;
          })
      }
      .width('100%')

      Row() {
        Button($r('app.string.cancel'))
          .buttonStyle(ButtonStyleMode.NORMAL)
          .onClick(() => {
            this.showShiftForm = false;
          })
        Button($r('app.string.add_shift_btn'))
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
              Text(`${s.start} - ${s.end}`)
                .fontSize(15)
                .margin({ left: this.editing ? 10 : 0 })
              Text(minutesToHoursText(s.durationMinutes()))
                .fontSize(13)
                .fontColor('#0A59F7')
                .margin({ left: 12 })
              Blank()
              if (this.editing) {
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
        }, (s: Shift, i: number) => `${i}-${s.start}-${s.end}`)
      }
      .width('100%')

      if (this.editing) {
        if (this.showShiftForm) {
          this.shiftForm()
        } else {
          Button($r('app.string.add_shift'))
            .width('100%')
            .buttonStyle(ButtonStyleMode.NORMAL)
            .margin({ top: 8 })
            .onClick(() => {
              this.showShiftForm = true;
            })
        }

        // 批量：勾选的班次（未勾选则本日全部）
        Row({ space: 8 }) {
          Button($r('app.string.add_alarm'))
            .buttonStyle(ButtonStyleMode.NORMAL)
            .fontSize(13)
            .layoutWeight(1)
            .onClick(() => this.addAlarmForShifts(this.targetShifts()))
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

  build() {
    Scroll(this.scroller) {
      Column() {
        CalendarView()
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
            }, (v: string) => v)
          }
        }
        .width('100%')
        .padding(12)
        .borderRadius(12)
        .backgroundColor($r('sys.color.background_primary'))
        .border({ width: 0.5, color: $r('sys.color.comp_divider') })

        this.sectionTitle($r('app.string.tools_section_schedule'))
        Column() {
          this.toolButton($r('app.string.auto_fill'), (): void => this.autoFillMonth())
          this.toolButton($r('app.string.range_auto'), (): void => this.rangeAuto())
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
          this.toolButton($r('app.string.batch_alarm'), (): void => {
            this.showIntro($r('app.string.batch_alarm'), $r('app.string.batch_alarm_desc'), (): void => {
              this.pickRange((start: string, end: string) => this.batchAlarm(start, end));
            });
          })
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
