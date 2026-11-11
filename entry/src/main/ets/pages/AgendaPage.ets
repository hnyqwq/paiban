// 日程页：月历 + 只读日程 + 备忘录 + 待办（排班编辑在「排班」页）
import {
  DayEntry, Shift, TodoItem,
  dateKey, minutesToHoursText
} from '../model/ScheduleTypes';
import { ScheduleService } from '../service/ScheduleService';
import { CalendarView } from '../view/CalendarView';

@Component
export struct AgendaPage {
  scroller: Scroller = new Scroller();
  @StorageLink('calendarSelectedDate') selectedDate: string = '';
  @State days: DayEntry[] = [];
  @State memoDraft: string = '';
  @State newTodo: string = '';
  @StorageLink('scheduleDataVersion') @Watch('onDataChanged') scheduleDataVersion: number = 0;
  private service: ScheduleService = ScheduleService.getInstance();

  onDataChanged(): void {
    this.refresh();
  }

  aboutToAppear(): void {
    if (this.selectedDate === '') {
      const now = new Date();
      this.selectedDate = dateKey(now.getFullYear(), now.getMonth() + 1, now.getDate());
    }
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

  @Builder
  dayDetail() {
    Column() {
      Text($r('app.string.day_schedule', this.selectedDate))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .margin({ bottom: 8 })

      // 只读展示当天班次
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
