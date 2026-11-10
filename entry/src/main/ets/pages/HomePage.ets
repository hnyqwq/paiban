// 首页：月历 + 每日排班编辑 + 今日日程 + 备忘录
import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { addShiftToCalendar, addShiftAlarm } from '../utils/CalendarReminder';
import {
  DayEntry, Shift, ShiftRules, MonthStats, TodoItem,
  dateKey, daysInMonth, minutesToHoursText
} from '../model/ScheduleTypes';
import { ScheduleService } from '../service/ScheduleService';

const WEEK_LABELS: string[] = ['日', '一', '二', '三', '四', '五', '六'];

@Component
export struct HomePage {
  scroller: Scroller = new Scroller();
  @State viewYear: number = 2025;
  @State viewMonth: number = 1;
  @State selectedDate: string = '';
  @State days: DayEntry[] = [];
  @State rules: ShiftRules = new ShiftRules();
  @State monthStats: MonthStats = new MonthStats();
  // 新增班次表单
  @State showShiftForm: boolean = false;
  @State newStart: string = '09:00';
  @State newEnd: string = '17:00';
  @State memoDraft: string = '';
  @State newTodo: string = '';
  @State selectedShifts: number[] = []; // 本日勾选的班次下标
  @State editing: boolean = false;      // 开始排班后才显示编辑/工具按钮
  @StorageLink('scheduleDataVersion') @Watch('onDataChanged') scheduleDataVersion: number = 0;
  @StorageLink('rulesChanged') @Watch('onRulesChanged') rulesChanged: number = 0;

  onDataChanged(): void {
    this.selectedShifts = [];
    this.refresh();
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

  onRulesChanged(): void {
    this.rules = this.service.getRules();
    this.refresh();
  }

  private service: ScheduleService = ScheduleService.getInstance();

  aboutToAppear(): void {
    const now = new Date();
    this.viewYear = now.getFullYear();
    this.viewMonth = now.getMonth() + 1;
    this.selectedDate = dateKey(now.getFullYear(), now.getMonth() + 1, now.getDate());
    this.rules = this.service.getRules();
    this.refresh();
  }

  refresh(): void {
    // 必须复制新数组：service 返回的是缓存引用，赋同一引用不会触发 UI 刷新
    this.days = this.service.getDays().slice();
    this.monthStats = this.service.computeStats(this.days, this.viewYear, this.viewMonth, this.rules);
    const entry = this.service.findEntry(this.days, this.selectedDate);
    this.memoDraft = entry !== undefined ? entry.memo : '';
  }

  changeMonth(delta: number): void {
    let m = this.viewMonth + delta;
    let y = this.viewYear;
    if (m < 1) {
      m = 12;
      y--;
    } else if (m > 12) {
      m = 1;
      y++;
    }
    this.viewYear = y;
    this.viewMonth = m;
    this.refresh();
  }

  // 点击标题弹出年月选择器（官方 YEAR_AND_MONTH 模式，仅年、月两列）
  showMonthPicker(): void {
    this.getUIContext().showDatePickerDialog({
      start: new Date(2000, 0, 1),
      end: new Date(2100, 11, 31),
      selected: new Date(this.viewYear, this.viewMonth - 1, 1),
      mode: DatePickerMode.YEAR_AND_MONTH,
      onDateAccept: (value: Date) => {
        this.viewYear = value.getFullYear();
        this.viewMonth = value.getMonth() + 1;
        this.refresh();
      }
    });
  }

  saveDays(): void {
    this.service.saveDays(this.days);
    this.refresh();
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
    this.saveDays();
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
      this.saveDays();
      return;
    }
    this.upsertEntry(entry);
  }

  saveMemo(): void {
    const entry = this.service.findEntry(this.days, this.selectedDate);
    if (entry === undefined) {
      if (this.memoDraft.trim() === '') {
        return;
      }
      const ne = new DayEntry();
      ne.date = this.selectedDate;
      ne.memo = this.memoDraft;
      this.upsertEntry(ne);
      return;
    }
    entry.memo = this.memoDraft;
    this.upsertEntry(entry);
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

  addTodo(): void {
    if (this.newTodo.trim() === '') {
      return;
    }
    const entry = this.service.findEntry(this.days, this.selectedDate);
    const e = entry !== undefined ? entry : (() => {
      const ne = new DayEntry();
      ne.date = this.selectedDate;
      return ne;
    })();
    const t = new TodoItem();
    t.text = this.newTodo.trim();
    t.done = false;
    e.todos.push(t);
    this.newTodo = '';
    this.upsertEntry(e);
  }

  toggleTodo(index: number): void {
    const entry = this.service.findEntry(this.days, this.selectedDate);
    if (entry === undefined || index >= entry.todos.length) {
      return;
    }
    entry.todos[index].done = !entry.todos[index].done;
    this.upsertEntry(entry);
  }

  removeTodo(index: number): void {
    const entry = this.service.findEntry(this.days, this.selectedDate);
    if (entry === undefined || index >= entry.todos.length) {
      return;
    }
    entry.todos.splice(index, 1);
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
      this.saveDays();
      return;
    }
    const ne = new DayEntry();
    ne.date = this.selectedDate;
    ne.memo = entry !== undefined ? entry.memo : '';
    this.upsertEntry(ne);
  }

  // 格子渲染键：包含当日排班状态，删班次/改班次后立即重绘（如变休息）
  cellKey(day: number): string {
    const entry = this.service.findEntry(this.days, dateKey(this.viewYear, this.viewMonth, day));
    if (entry === undefined) {
      return `${day}-x`;
    }
    return `${day}-${entry.shifts.length}-${this.service.dayMinutes(entry)}`;
  }

  // 月历格子：前置空白 + 日期
  calendarCells(): number[] {
    const first = new Date(this.viewYear, this.viewMonth - 1, 1);
    const blanks = first.getDay(); // 0=周日
    const cells: number[] = [];
    for (let i = 0; i < blanks; i++) {
      cells.push(0);
    }
    const total = daysInMonth(this.viewYear, this.viewMonth);
    for (let d = 1; d <= total; d++) {
      cells.push(d);
    }
    return cells;
  }

  dayCellInfo(day: number): Resource | string {
    const entry = this.service.findEntry(this.days, dateKey(this.viewYear, this.viewMonth, day));
    if (entry === undefined) {
      return '';
    }
    const dm = this.service.dayMinutes(entry);
    if (dm > 0) {
      return minutesToHoursText(dm);
    }
    return $r('app.string.rest_marker');
  }

  dayIsRest(day: number): boolean {
    return this.service.isRestDay(this.service.findEntry(this.days, dateKey(this.viewYear, this.viewMonth, day)));
  }

  // 今天的工时文本（无班次返回空串）
  todayHoursText(day: number): string {
    const dm = this.service.dayMinutes(this.service.findEntry(this.days, dateKey(this.viewYear, this.viewMonth, day)));
    return dm > 0 ? minutesToHoursText(dm) : '';
  }

  // 选中日期实心蓝底，今天不加背景（用「今日」文字标记）
  cellBackground(day: number): ResourceColor {
    const key = dateKey(this.viewYear, this.viewMonth, day);
    if (this.selectedDate === key) {
      return '#0A59F7';
    }
    return Color.Transparent;
  }

  isTodayCell(day: number): boolean {
    const now = new Date();
    return dateKey(this.viewYear, this.viewMonth, day) === dateKey(now.getFullYear(), now.getMonth() + 1, now.getDate());
  }

  cellTextPrimary(day: number): ResourceColor {
    return this.selectedDate === dateKey(this.viewYear, this.viewMonth, day) ? Color.White : $r('sys.color.font_primary');
  }

  @Builder
  calendarCell(day: number) {
    Column() {
      Text(day > 0 ? `${day}` : '')
        .fontSize(15)
        .fontWeight(this.selectedDate === dateKey(this.viewYear, this.viewMonth, day) ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.cellTextPrimary(day))
      if (day > 0) {
        if (this.isTodayCell(day)) {
          Row() {
            // 蓝底（选中）时用白字，否则用品牌蓝
            Text($r('app.string.today_label'))
              .fontSize(10)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.selectedDate === dateKey(this.viewYear, this.viewMonth, day) ? Color.White : $r('sys.color.brand'))
            if (this.dayIsRest(day)) {
              Text('  ')
                .fontSize(10)
              Text($r('app.string.rest_marker'))
                .fontSize(10)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.selectedDate === dateKey(this.viewYear, this.viewMonth, day) ? Color.White : $r('sys.color.warning'))
            } else if (this.todayHoursText(day) !== '') {
              Text('  ')
                .fontSize(10)
              Text(this.todayHoursText(day))
                .fontSize(10)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.selectedDate === dateKey(this.viewYear, this.viewMonth, day) ? Color.White : $r('sys.color.brand'))
            }
          }
        } else {
          Text(this.dayCellInfo(day))
            .fontSize(10)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.dayIsRest(day) ? $r('sys.color.warning') : $r('sys.color.brand'))
        }
      } else {
        Text('').fontSize(10)
      }
    }
    .width('100%')
    .height(48)
    .justifyContent(FlexAlign.Center)
    .borderRadius(8)
    .backgroundColor(this.cellBackground(day))
    .onClick(() => {
      if (day > 0) {
        this.selectedDate = dateKey(this.viewYear, this.viewMonth, day);
        this.selectedShifts = [];
        this.editing = false;
        this.showShiftForm = false;
        this.refresh();
      }
    })
  }

  @Builder
  calendar() {
    Column() {
      Row() {
        Text($r('app.string.month_title', this.viewYear, this.viewMonth))
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .onClick(() => this.showMonthPicker())
        Blank()
        Text('‹')
          .fontSize(24)
          .padding({ left: 16, right: 16 })
          .onClick(() => this.changeMonth(-1))
        Text('›')
          .fontSize(24)
          .padding({ left: 16, right: 16 })
          .onClick(() => this.changeMonth(1))
      }
      .width('100%')

      Row() {
        ForEach(WEEK_LABELS, (w: string) => {
          Text(w)
            .fontSize(12)
            .fontColor('#999999')
            .width('100%')
            .textAlign(TextAlign.Center)
        })
      }
      .width('100%')
      .margin({ top: 8 })

      Grid() {
        ForEach(this.calendarCells(), (d: number) => {
          GridItem() {
            this.calendarCell(d)
          }
        }, (d: number) => this.cellKey(d))
      }
      .columnsTemplate('1fr 1fr 1fr 1fr 1fr 1fr 1fr')
      .columnsGap(2)
      .rowsGap(2)
      .height(48 * 6 + 12)
      .margin({ top: 4 })
    }
    .padding(12)
    .borderRadius(12)
    .backgroundColor($r('sys.color.background_primary'))
    .border({ width: 0.5, color: $r('sys.color.comp_divider') })
  }

  @Builder
  progressLine() {
    Row() {
      Text($r('app.string.progress_done', minutesToHoursText(this.monthStats.workedMinutes), this.rules.monthlyTargetHours))
        .fontSize(13)
      Blank()
      Text($r('app.string.progress_need', minutesToHoursText(this.monthStats.remainingMinutes)))
        .fontSize(13)
        .fontColor('#0A59F7')
        .fontWeight(FontWeight.Medium)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10 })

    Progress({ value: this.monthStats.workedMinutes, total: Math.max(this.monthStats.targetMinutes, 1), type: ProgressType.Linear })
      .width('100%')
      .margin({ top: 6 })
      .padding({ left: 12, right: 12 })
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

  @Builder
  dayDetail() {
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

      // 备忘录
      Text($r('app.string.memo'))
        .fontSize(13)
        .fontColor($r('sys.color.font_tertiary'))
        .margin({ top: 12 })
      TextArea({ text: this.memoDraft, placeholder: $r('app.string.memo_hint') })
        .width('100%')
        .height(72)
        .margin({ top: 4 })
        .onChange((v: string) => {
          this.memoDraft = v;
        })
        .onBlur(() => {
          this.saveMemo();
        })

      // 待办
      Text($r('app.string.todo'))
        .fontSize(13)
        .fontColor($r('sys.color.font_tertiary'))
        .margin({ top: 12 })
      List() {
        ForEach(this.service.findEntry(this.days, this.selectedDate)?.todos ?? [], (t: TodoItem, i: number) => {
          ListItem() {
            Row() {
              Checkbox()
                .select(t.done)
                .width(18)
                .height(18)
                .onChange((isChecked: boolean) => {
                  this.toggleTodo(i);
                })
              Text(t.text)
                .fontSize(14)
                .margin({ left: 10 })
                .layoutWeight(1)
                .decoration({ type: t.done ? TextDecorationType.LineThrough : TextDecorationType.None })
                .fontColor(t.done ? $r('sys.color.font_tertiary') : $r('sys.color.font_primary'))
              Text($r('app.string.delete'))
                .fontSize(13)
                .fontColor($r('sys.color.warning'))
                .onClick(() => this.removeTodo(i))
            }
            .width('100%')
            .padding(8)
            .borderRadius(8)
            .backgroundColor($r('sys.color.comp_background_tertiary'))
            .margin({ top: 6 })
          }
        }, (t: TodoItem, i: number) => `${i}-${t.text}-${t.done}`)
      }
      .width('100%')

      Row() {
        TextInput({ text: this.newTodo, placeholder: $r('app.string.todo_hint') })
          .layoutWeight(1)
          .height(40)
          .onChange((v: string) => {
            this.newTodo = v;
          })
        Button($r('app.string.add'))
          .buttonStyle(ButtonStyleMode.NORMAL)
          .height(40)
          .margin({ left: 8 })
          .onClick(() => this.addTodo())
      }
      .width('100%')
      .margin({ top: 6 })
    }
    .padding(12)
    .borderRadius(12)
    .backgroundColor($r('sys.color.background_primary'))
    .border({ width: 0.5, color: $r('sys.color.comp_divider') })
    .margin({ top: 8 })
  }

  @Builder
  violationBanner() {
    if (this.monthStats.violations.length > 0) {
      Column() {
        Text($r('app.string.rule_reminders'))
          .fontSize(12)
          .fontColor($r('sys.color.warning'))
          .margin({ bottom: 4 })
        ForEach(this.monthStats.violations.slice(0, 3), (v: string) => {
          Text(v)
            .fontSize(12)
            .fontColor($r('sys.color.font_secondary'))
            .margin({ top: 2 })
        }, (v: string) => v)
      }
      .width('100%')
      .padding(12)
      .borderRadius(8)
      .backgroundColor($r('sys.color.comp_background_tertiary'))
      .border({ width: 0.5, color: $r('sys.color.comp_divider') })
      .margin({ top: 8 })
    }
  }

  build() {
    Scroll(this.scroller) {
      Column() {
        this.calendar()
        this.progressLine()
        this.violationBanner()
        this.dayDetail()
        Text('') // 底部留白，避开悬浮 Tab 栏
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
