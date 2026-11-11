// 共用月历组件：首页与工具页使用；选中日期实心蓝底白字
import { dateKey, daysInMonth, minutesToHoursText } from '../model/ScheduleTypes';
import { ScheduleService } from '../service/ScheduleService';

const WEEK_LABELS: string[] = ['日', '一', '二', '三', '四', '五', '六'];

@Component
export struct CalendarView {
  @Link selectedDate: string;
  @StorageLink('weekStart') @Watch('onWeekStartChange') weekStart: number = 0; // 0 周日开始 1 周一开始
  @StorageLink('scheduleDataVersion') @Watch('onDataChanged') scheduleDataVersion: number = 0;
  @State viewYear: number = 2026;
  @State viewMonth: number = 1;
  private service: ScheduleService = ScheduleService.getInstance();

  aboutToAppear(): void {
    const now = new Date();
    this.viewYear = now.getFullYear();
    this.viewMonth = now.getMonth() + 1;
    this.weekStart = this.service.getWeekStart();
  }

  onWeekStartChange(): void {
    // 周起始日变化，表头与空白由状态自动重算
  }

  // 表头按周起始日旋转
  weekdayLabels(): string[] {
    return WEEK_LABELS.slice(this.weekStart).concat(WEEK_LABELS.slice(0, this.weekStart));
  }

  onDataChanged(): void {
    // 数据变化由 scheduleDataVersion 触发整树刷新，这里无需额外处理
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
  }

  showMonthPicker(): void {
    this.getUIContext().showDatePickerDialog({
      start: new Date(2000, 0, 1),
      end: new Date(2100, 11, 31),
      selected: new Date(this.viewYear, this.viewMonth - 1, 1),
      mode: DatePickerMode.YEAR_AND_MONTH,
      onDateAccept: (value: Date) => {
        this.viewYear = value.getFullYear();
        this.viewMonth = value.getMonth() + 1;
      }
    });
  }

  // 月历格子：前置空白 + 日期（空白按周起始日对齐）
  calendarCells(): number[] {
    const first = new Date(this.viewYear, this.viewMonth - 1, 1);
    const blanks = (first.getDay() - this.weekStart + 7) % 7;
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

  // 按实际行数算高度，避免固定 6 行多出空白
  gridHeight(): number {
    const total = daysInMonth(this.viewYear, this.viewMonth);
    const blanks = new Date(this.viewYear, this.viewMonth - 1, 1).getDay();
    const rows = Math.ceil((blanks + total) / 7);
    return rows * 48 + (rows - 1) * 2;
  }

  // 格子渲染键：包含当日排班状态，删班次/改班次后立即重绘（如变休息）
  cellKey(day: number): string {
    const entry = this.service.findEntry(this.service.getDays(), dateKey(this.viewYear, this.viewMonth, day));
    if (entry === undefined) {
      return `${day}-x`;
    }
    return `${day}-${entry.shifts.length}-${this.service.dayMinutes(entry)}`;
  }

  // 选中日期实心蓝底，今天不加背景（用「今日」文字标记）
  cellBackground(day: number): ResourceColor {
    const key = dateKey(this.viewYear, this.viewMonth, day);
    if (this.selectedDate === key) {
      return '#0A59F7';
    }
    return Color.Transparent;
  }

  cellTextPrimary(day: number): ResourceColor {
    return this.selectedDate === dateKey(this.viewYear, this.viewMonth, day) ? Color.White : $r('sys.color.font_primary');
  }

  isTodayCell(day: number): boolean {
    const now = new Date();
    return dateKey(this.viewYear, this.viewMonth, day) === dateKey(now.getFullYear(), now.getMonth() + 1, now.getDate());
  }

  dayCellInfo(day: number): Resource | string {
    const entry = this.service.findEntry(this.service.getDays(), dateKey(this.viewYear, this.viewMonth, day));
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
    return this.service.isRestDay(this.service.findEntry(this.service.getDays(), dateKey(this.viewYear, this.viewMonth, day)));
  }

  // 今天的工时文本（无班次返回空串）
  todayHoursText(day: number): string {
    const dm = this.service.dayMinutes(this.service.findEntry(this.service.getDays(), dateKey(this.viewYear, this.viewMonth, day)));
    return dm > 0 ? minutesToHoursText(dm) : '';
  }

  isSelected(day: number): boolean {
    return this.selectedDate === dateKey(this.viewYear, this.viewMonth, day);
  }

  @Builder
  calendarCell(day: number) {
    Column() {
      Text(day > 0 ? `${day}` : '')
        .fontSize(15)
        .fontWeight(this.isSelected(day) ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.cellTextPrimary(day))
      if (day > 0) {
        if (this.isTodayCell(day)) {
          Row() {
            // 蓝底（选中）时用白字，否则用品牌蓝
            Text($r('app.string.today_label'))
              .fontSize(10)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.isSelected(day) ? Color.White : $r('sys.color.brand'))
            if (this.dayIsRest(day)) {
              Text('  ')
                .fontSize(10)
              Text($r('app.string.rest_marker'))
                .fontSize(10)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.isSelected(day) ? Color.White : $r('sys.color.warning'))
            } else if (this.todayHoursText(day) !== '') {
              Text('  ')
                .fontSize(10)
              Text(this.todayHoursText(day))
                .fontSize(10)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.isSelected(day) ? Color.White : $r('sys.color.brand'))
            }
          }
        } else {
          Text(this.dayCellInfo(day))
            .fontSize(10)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.dayIsRest(day) && !this.isSelected(day)
              ? $r('sys.color.warning')
              : (this.isSelected(day) ? Color.White : $r('sys.color.brand')))
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
      }
    })
  }

  build() {
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

      // 星期表头：七个字均匀分布，对齐下方七列格子
      Row() {
        ForEach(this.weekdayLabels(), (w: string) => {
          Text(w)
            .fontSize(12)
            .fontColor($r('sys.color.font_tertiary'))
            .layoutWeight(1)
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
      .height(this.gridHeight())
      .margin({ top: 4 })
    }
    .padding(12)
    .borderRadius(12)
    .backgroundColor(Color.Transparent)
  }
}
