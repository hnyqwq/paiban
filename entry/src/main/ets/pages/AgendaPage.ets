// 日程页：月历 + 排班编辑 + 备忘录 + 待办
import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { addShiftToCalendar, addShiftAlarm } from '../utils/CalendarReminder';
import {
  DayEntry, Shift, ShiftRules, TodoItem,
  dateKey, minutesToHoursText
} from '../model/ScheduleTypes';
import { ScheduleService } from '../service/ScheduleService';
import { CalendarView } from '../view/CalendarView';

@Component
export struct AgendaPage {
  scroller: Scroller = new Scroller();
  @StorageLink('calendarSelectedDate') @Watch('onSelectedDateChange') selectedDate: string = '';
  @State days: DayEntry[] = [];
  @State rules: ShiftRules = new ShiftRules();
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

  // CalendarView 切换日期后重置编辑态
  onSelectedDateChange(): void {
    this.selectedShifts = [];
    this.editing = false;
    this.showShiftForm = false;
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
    if (this.selectedDate === '') {
      const now = new Date();
      this.selectedDate = dateKey(now.getFullYear(), now.getMonth() + 1, now.getDate());
    }
    this.rules = this.service.getRules();
    this.refresh();
  }

  refresh(): void {
    // 必须复制新数组：service 返回的是缓存引用，赋同一引用不会触发 UI 刷新
    this.days = this.service.getDays().slice();
    const entry = this.service.findEntry(this.days, this.selectedDate);
    this.memoDraft = entry !== undefined ? entry.memo : '';
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
  }

  build() {
    Scroll(this.scroller) {
      Column() {
        CalendarView()
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
