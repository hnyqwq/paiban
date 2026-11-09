// 首页：月历 + 每日排班编辑 + 今日日程 + 备忘录
import { promptAction } from '@kit.ArkUI';
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
  @StorageLink('dataCleared') @Watch('onDataCleared') dataCleared: number = 0;

  onDataCleared(): void {
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

  // 同步当前查看月份的班次到选定月份
  syncMonth(): void {
    this.getUIContext().showDatePickerDialog({
      start: new Date(2000, 0, 1),
      end: new Date(2100, 11, 31),
      selected: new Date(this.viewYear, this.viewMonth, 1),
      mode: DatePickerMode.YEAR_AND_MONTH,
      onDateAccept: (value: Date) => {
        this.getUIContext().showAlertDialog({
          title: $r('app.string.sync_confirm_title'),
          message: $r('app.string.sync_confirm_msg'),
          autoCancel: true,
          buttons: [
            { value: $r('app.string.cancel'), fontColor: $r('sys.color.font_secondary'), action: () => {} },
            { value: $r('app.string.btn_clear'), fontColor: $r('sys.color.brand'), action: () => {
              const n = this.service.copyMonthTo(this.days, this.viewYear, this.viewMonth, value.getFullYear(), value.getMonth() + 1);
              this.saveDays();
              promptAction.showToast({ message: $r('app.string.copied_sync', n) });
            } }
          ]
        });
      }
    });
  }

  // 复制所选日期的班次到另一天
  copyDay(): void {
    this.getUIContext().showDatePickerDialog({
      start: new Date(2000, 0, 1),
      end: new Date(2100, 11, 31),
      selected: new Date(this.viewYear, this.viewMonth - 1, 1),
      onDateAccept: (value: Date) => {
        const target = dateKey(value.getFullYear(), value.getMonth() + 1, value.getDate());
        if (this.service.copyDayTo(this.days, this.selectedDate, target)) {
          this.saveDays();
          promptAction.showToast({ message: $r('app.string.copy_day_done') });
        } else {
          promptAction.showToast({ message: $r('app.string.copy_day_done') });
        }
      }
    });
  }

  // 按规则自动排满本月
  autoFill(): void {
    this.getUIContext().showAlertDialog({
      title: $r('app.string.auto_confirm_title'),
      message: $r('app.string.auto_confirm_msg'),
      autoCancel: true,
      buttons: [
        { value: $r('app.string.cancel'), fontColor: $r('sys.color.font_secondary'), action: () => {} },
        { value: $r('app.string.btn_clear'), fontColor: $r('sys.color.brand'), action: () => {
          const n = this.service.autoFillMonth(this.days, this.viewYear, this.viewMonth, this.rules);
          this.saveDays();
          promptAction.showToast({ message: $r('app.string.auto_filled', n) });
        } }
      ]
    });
  }

  @Builder
  actionRow() {
    Row({ space: 8 }) {
      Button($r('app.string.sync_to_month'))
        .buttonStyle(ButtonStyleMode.NORMAL)
        .fontSize(12)
        .layoutWeight(1)
        .onClick(() => this.syncMonth())
      Button($r('app.string.copy_day'))
        .buttonStyle(ButtonStyleMode.NORMAL)
        .fontSize(12)
        .layoutWeight(1)
        .onClick(() => this.copyDay())
      Button($r('app.string.auto_fill'))
        .buttonStyle(ButtonStyleMode.NORMAL)
        .fontSize(12)
        .layoutWeight(1)
        .onClick(() => this.autoFill())
    }
    .width('100%')
    .margin({ top: 8 })
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

  @Builder
  calendarCell(day: number) {
    Column() {
      Text(day > 0 ? `${day}` : '')
        .fontSize(15)
        .fontWeight(this.selectedDate === dateKey(this.viewYear, this.viewMonth, day) ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.selectedDate === dateKey(this.viewYear, this.viewMonth, day) ? $r('sys.color.brand') : undefined)
      if (day > 0) {
        Text(this.dayCellInfo(day))
          .fontSize(9)
          .fontColor(this.dayIsRest(day) ? $r('sys.color.warning') : $r('sys.color.brand'))
      } else {
        Text('').fontSize(9)
      }
    }
    .width('100%')
    .height(48)
    .justifyContent(FlexAlign.Center)
    .borderRadius(8)
    .backgroundColor(this.selectedDate === dateKey(this.viewYear, this.viewMonth, day) ? '#0A59F71A' : Color.Transparent)
    .onClick(() => {
      if (day > 0) {
        this.selectedDate = dateKey(this.viewYear, this.viewMonth, day);
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
        })
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

      // 已排班次
      List() {
        ForEach(this.service.findEntry(this.days, this.selectedDate)?.shifts ?? [], (s: Shift, i: number) => {
          ListItem() {
            Row() {
              Text(`${s.start} - ${s.end}`)
                .fontSize(15)
              Text(minutesToHoursText(s.durationMinutes()))
                .fontSize(13)
                .fontColor('#0A59F7')
                .margin({ left: 12 })
              Blank()
              Text($r('app.string.delete'))
                .fontSize(13)
                .fontColor($r('sys.color.warning'))
                .onClick(() => this.removeShift(i))
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
        this.actionRow()
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
