// 日程页：月历 + 只读日程 + 备忘录 + 待办（排班编辑在「排班」页）
import {
  DayEntry, Shift, TodoItem,
  dateKey, minutesToHoursText, shiftCrossesDay, shiftMinutesOnOffsetDay
} from '../model/ScheduleTypes';
import { ScheduleService } from '../service/ScheduleService';
import { CalendarView } from '../view/CalendarView';

// 当日展示的班次条目：本日班次 + 昨日跨天班次的尾巴
class DayShiftItem {
  name: string = '';
  color: string = '';
  timeText: string = '';
  hoursText: string = '';
  breakText: string = '';
  borrowed: boolean = false;
}

@Component
export struct AgendaPage {
  scroller: Scroller = new Scroller();
  @StorageProp('isWideLayout') isWideLayout: boolean = false; // 大屏（≥lg 断点）双栏布局
  @StorageLink('calendarSelectedDate') @Watch('onSelectedDateChange') selectedDate: string = '';
  @State days: DayEntry[] = [];
  @State memoDraft: string = '';
  @State memoDate: string = ''; // memoDraft 当前所属的日期，避免切换日期时写错天
  @State newTodo: string = '';
  @StorageLink('scheduleDataVersion') @Watch('onDataChanged') scheduleDataVersion: number = 0;
  private service: ScheduleService = ScheduleService.getInstance();
  private memoTimer: number = -1; // 备忘录输入防抖保存定时器
  private leaving: boolean = false; // 页面即将销毁时不再刷新状态

  onDataChanged(): void {
    if (!this.leaving) {
      this.refresh();
    }
  }

  aboutToAppear(): void {
    this.leaving = false;
    if (this.selectedDate === '') {
      const now = new Date();
      this.selectedDate = dateKey(now.getFullYear(), now.getMonth() + 1, now.getDate());
    }
    this.refresh();
  }

  aboutToDisappear(): void {
    // 离开页面时把还没保存的草稿写回所属日期；此刻不再刷新 UI 状态
    this.leaving = true;
    this.saveMemoNow();
  }

  // 切换日期：先把当前草稿存回上一天，再载入新一天的备忘录
  onSelectedDateChange(): void {
    this.saveMemoNow();
    this.refresh();
  }

  refresh(): void {
    if (this.leaving) {
      return;
    }
    // 必须复制新数组：service 返回的是缓存引用，赋同一引用不会触发 UI 刷新
    this.days = this.service.getDays().slice();
    // 自动保存的防抖窗口内不覆盖用户正在输入的内容
    if (this.memoTimer >= 0) {
      return;
    }
    const entry = this.service.findEntry(this.days, this.selectedDate);
    this.memoDraft = entry !== undefined ? entry.memo : '';
    this.memoDate = this.selectedDate;
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

  cancelMemoTimer(): void {
    if (this.memoTimer >= 0) {
      clearTimeout(this.memoTimer);
      this.memoTimer = -1;
    }
  }

  // 立即保存：只写到 memoDate 对应的一天，切换日期/失焦时不会串到别的日期
  saveMemoNow(): void {
    this.cancelMemoTimer();
    this.saveMemoTo(this.memoDate, this.memoDraft);
  }

  saveMemoTo(date: string, text: string): void {
    if (date === '') {
      return;
    }
    const entry = this.service.findEntry(this.days, date);
    if (entry === undefined) {
      if (text.trim() === '') {
        return;
      }
      const ne = new DayEntry();
      ne.date = date;
      ne.memo = text;
      this.upsertEntry(ne);
      return;
    }
    if (entry.memo === text) {
      return;
    }
    entry.memo = text;
    this.upsertEntry(entry);
  }

  // 输入停顿 500ms 自动保存，保证每天独立保存、切页/切日期不丢
  scheduleMemoSave(): void {
    this.cancelMemoTimer();
    this.memoTimer = setTimeout(() => {
      this.memoTimer = -1;
      this.saveMemoTo(this.memoDate, this.memoDraft);
    }, 500);
  }

  saveMemo(): void {
    this.saveMemoNow();
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

  // 昨天的日期键
  prevDateKey(): string {
    const parts = this.selectedDate.split('-');
    const d = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]) - 1);
    return dateKey(d.getFullYear(), d.getMonth() + 1, d.getDate());
  }

  // 当日展示的班次条目：本日班次（结束跨天带「次日」）+ 昨日跨天班次的尾巴（计入当日时长）
  dayShiftItems(): DayShiftItem[] {
    const nextDay = this.service.str($r('app.string.shift_next_day'));
    const prevDay = this.service.str($r('app.string.shift_prev_day'));
    const items: DayShiftItem[] = [];
    const own = this.service.findEntry(this.days, this.selectedDate);
    if (own !== undefined) {
      for (const s of own.shifts) {
        const item = new DayShiftItem();
        item.name = s.name;
        item.color = s.color;
        const endText = shiftCrossesDay(s) ? `${nextDay} ${s.end}` : s.end;
        item.timeText = `${s.start} - ${endText}`;
        item.hoursText = minutesToHoursText(shiftMinutesOnOffsetDay(s, 0));
        if (s.breakMinutes > 0) {
          item.breakText = this.service.str($r('app.string.preset_break_info'), s.breakMinutes);
        }
        items.push(item);
      }
    }
    const prev = this.service.findEntry(this.days, this.prevDateKey());
    if (prev !== undefined) {
      for (const s of prev.shifts) {
        const tail = shiftMinutesOnOffsetDay(s, 1);
        if (tail <= 0) {
          continue; // 未跨到今天
        }
        const item = new DayShiftItem();
        item.name = s.name;
        item.color = s.color;
        item.timeText = `${prevDay} ${s.start} - ${s.end}`;
        item.hoursText = minutesToHoursText(tail);
        if (s.breakMinutes > 0) {
          item.breakText = this.service.str($r('app.string.preset_break_info'), s.breakMinutes);
        }
        item.borrowed = true;
        items.push(item);
      }
    }
    return items;
  }

  @Builder
  dayDetail() {
    Column() {
      Text($r('app.string.day_schedule', this.selectedDate))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .margin({ bottom: 8 })

      // 只读展示当天班次（本日班次 + 昨日跨天班次的尾巴，名称/颜色/休息来自预设排班）
      List() {
        ForEach(this.dayShiftItems(), (item: DayShiftItem, i: number) => {
          ListItem() {
            Row() {
              Text('')
                .width(4)
                .height(34)
                .borderRadius(2)
                .backgroundColor(item.color !== '' ? item.color : '#0A59F7')
                .margin({ right: 10 })
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
                if (item.breakText !== '') {
                  Text(item.breakText)
                    .fontSize(10)
                    .fontColor($r('sys.color.font_tertiary'))
                    .margin({ top: 1 })
                }
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Text(item.hoursText)
                .fontSize(13)
                .fontColor('#0A59F7')
                .margin({ left: 8 })
            }
            .width('100%')
            .padding(10)
            .borderRadius(8)
            .backgroundColor($r('sys.color.comp_background_tertiary'))
            .margin({ top: 8 })
          }
        }, (item: DayShiftItem, i: number) =>
          `${i}-${item.timeText}-${item.name}-${item.color}-${item.borrowed}`)
      }
      .width('100%')

      // 休息日只读提示
      if ((this.service.findEntry(this.days, this.selectedDate)?.shifts.length ?? 0) === 0
        && this.service.isRestDay(this.service.findEntry(this.days, this.selectedDate))) {
        Text($r('app.string.rest_marker'))
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.warning'))
          .margin({ top: 12 })
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
          this.scheduleMemoSave();
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
        if (this.isWideLayout) {
          // 大屏双栏：日历在左，当日详情（班次/备忘/待办）在右
          Row() {
            Column() {
              CalendarView()
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            Column() {
              this.dayDetail()
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
        } else {
          CalendarView()
          this.dayDetail()
        }
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
