// 共用月历组件：首页与工具页使用；选中日期实心蓝底白字
import { DayEntry, dateKey, daysInMonth, minutesToHoursText } from '../model/ScheduleTypes';
import { ScheduleService } from '../service/ScheduleService';

const WEEK_LABELS: string[] = ['日', '一', '二', '三', '四', '五', '六'];

// 月历格子：day = 0 表示月首空白占位格（不含相邻月日期）
// 每个格子都带唯一 key：空白格若共用 key，ForEach 只会保留第一个，
// 导致「周一开始」时 11 月 1 日这类周日日期整体左移、落到错误的星期列下
class CalendarCell {
  key: string = '';
  day: number = 0;
  name: string = '';        // 当天预设班次名称（预计算，避免渲染时重复查 entry）
  nameColor: string = '';   // 名称颜色（空 = 用默认次要文字色）
}

@Component
export struct CalendarView {
  // 选中日期与查看的年月用 AppStorage 共享：日程页与排班页的日历联动
  @StorageLink('calendarSelectedDate') selectedDate: string = '';
  @StorageLink('calendarViewYear') viewYear: number = 0;
  @StorageLink('calendarViewMonth') viewMonth: number = 0;
  @StorageLink('weekStart') @Watch('onWeekStartChange') weekStart: number = 0; // 0 周日开始 1 周一开始
  @StorageLink('scheduleDataVersion') @Watch('onDataChanged') scheduleDataVersion: number = 0;
  @State viewDays: DayEntry[] = [];  // 可观察的日数据，格子渲染只依赖它
  @State renderTick: number = 0;     // 数据变化时自增，强制格子重建
  private service: ScheduleService = ScheduleService.getInstance();

  aboutToAppear(): void {
    this.viewDays = this.service.getDays().slice();
    if (this.viewYear === 0 || this.viewMonth === 0) {
      const now = new Date();
      this.viewYear = now.getFullYear();
      this.viewMonth = now.getMonth() + 1;
    }
    if (this.selectedDate === '') {
      const now = new Date();
      this.selectedDate = dateKey(now.getFullYear(), now.getMonth() + 1, now.getDate());
    }
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
    this.viewDays = this.service.getDays().slice();
    this.renderTick++;
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
  calendarCells(): CalendarCell[] {
    const first = new Date(this.viewYear, this.viewMonth - 1, 1);
    const blanks = (first.getDay() - this.weekStart + 7) % 7;
    const cells: CalendarCell[] = [];
    for (let i = 0; i < blanks; i++) {
      const cell = new CalendarCell();
      cell.key = `${this.weekStart}-${this.viewYear}-${this.viewMonth}-blank-${i}`;
      cell.day = 0;
      cells.push(cell);
    }
    const total = daysInMonth(this.viewYear, this.viewMonth);
    for (let d = 1; d <= total; d++) {
      const cell = new CalendarCell();
      cell.key = `${this.weekStart}-${this.viewYear}-${this.viewMonth}-${this.renderTick}-${this.cellKey(d)}`;
      cell.day = d;
      // 一次性预计算当天的班次名称与颜色：渲染热路径上每个格子只做一次 findEntry
      cell.name = this.dayShiftNames(d);
      const color = this.dayShiftNameColor(d);
      cell.nameColor = typeof color === 'string' ? color : '';
      cells.push(cell);
    }
    return cells;
  }

  // 按实际行数算高度，避免固定 6 行多出空白；空白数须与 calendarCells 一致（含周起始日）
  gridHeight(): number {
    const total = daysInMonth(this.viewYear, this.viewMonth);
    const blanks = (new Date(this.viewYear, this.viewMonth - 1, 1).getDay() - this.weekStart + 7) % 7;
    const rows = Math.ceil((blanks + total) / 7);
    return rows * 56 + (rows - 1) * 2;
  }

  // 格子渲染键：包含当日排班状态，删班次/改班次后立即重绘（如变休息）
  cellKey(day: number): string {
    const entry = this.service.findEntry(this.viewDays, dateKey(this.viewYear, this.viewMonth, day));
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
    const entry = this.service.findEntry(this.viewDays, dateKey(this.viewYear, this.viewMonth, day));
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
    return this.service.isRestDay(this.service.findEntry(this.viewDays, dateKey(this.viewYear, this.viewMonth, day)));
  }

  // 当天预设班次名称：多个名称去重后压缩成「名称 +N」；没有名称（手动添加的班次）返回空串
  dayShiftNames(day: number): string {
    const entry = this.service.findEntry(this.viewDays, dateKey(this.viewYear, this.viewMonth, day));
    if (entry === undefined || entry.shifts.length === 0) {
      return '';
    }
    const names: string[] = [];
    for (const s of entry.shifts) {
      if (s.name !== '' && !names.includes(s.name)) {
        names.push(s.name);
      }
    }
    if (names.length === 0) {
      return '';
    }
    return names.length === 1 ? names[0] : `${names[0]} +${names.length - 1}`;
  }

  // 名称颜色跟随第一个班次的预设颜色，未设置颜色时用次要文字色
  dayShiftNameColor(day: number): ResourceColor {
    const entry = this.service.findEntry(this.viewDays, dateKey(this.viewYear, this.viewMonth, day));
    if (entry !== undefined && entry.shifts.length > 0 && entry.shifts[0].color !== '') {
      return entry.shifts[0].color;
    }
    return $r('sys.color.font_secondary');
  }

  // 今天的工时文本（无班次返回空串）
  todayHoursText(day: number): string {
    const dm = this.service.dayMinutes(this.service.findEntry(this.viewDays, dateKey(this.viewYear, this.viewMonth, day)));
    return dm > 0 ? minutesToHoursText(dm) : '';
  }

  isSelected(day: number): boolean {
    return this.selectedDate === dateKey(this.viewYear, this.viewMonth, day);
  }

  @Builder
  calendarCell(cell: CalendarCell) {
    Column() {
      Text(cell.day > 0 ? `${cell.day}` : '')
        .fontSize(15)
        .fontWeight(this.isSelected(cell.day) ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.cellTextPrimary(cell.day))
      if (cell.day > 0) {
        if (this.isTodayCell(cell.day)) {
          Row() {
            // 蓝底（选中）时用白字，否则用品牌蓝
            Text($r('app.string.today_label'))
              .fontSize(10)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.isSelected(cell.day) ? Color.White : $r('sys.color.brand'))
            if (this.dayIsRest(cell.day)) {
              Text('  ')
                .fontSize(10)
              Text($r('app.string.rest_marker'))
                .fontSize(10)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.isSelected(cell.day) ? Color.White : $r('sys.color.warning'))
            } else if (this.todayHoursText(cell.day) !== '') {
              Text('  ')
                .fontSize(10)
              Text(this.todayHoursText(cell.day))
                .fontSize(10)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.isSelected(cell.day) ? Color.White : $r('sys.color.brand'))
            }
          }
        } else {
          Text(this.dayCellInfo(cell.day))
            .fontSize(10)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.dayIsRest(cell.day) && !this.isSelected(cell.day)
              ? $r('sys.color.warning')
              : (this.isSelected(cell.day) ? Color.White : $r('sys.color.brand')))
        }
      } else {
        Text('').fontSize(10)
      }
      // 预设班次名称：让日历直接看得到「早班 / 白班」等，而不只是工时（值已在 calendarCells 预计算）
      if (cell.name !== '') {
        Text(cell.name)
          .fontSize(9)
          .fontColor(this.isSelected(cell.day) ? Color.White
            : (cell.nameColor !== '' ? cell.nameColor : $r('sys.color.font_secondary')))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ top: 1 })
      }
    }
    .width('100%')
    .height(56)
    .justifyContent(FlexAlign.Center)
    .borderRadius(8)
    .backgroundColor(this.cellBackground(cell.day))
    .onClick(() => {
      if (cell.day > 0) {
        this.selectedDate = dateKey(this.viewYear, this.viewMonth, cell.day);
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

      // 星期表头：space 与下方 Grid 的 columnsGap 一致，七列宽度逐像素对齐
      Row({ space: 2 }) {
        ForEach(this.weekdayLabels(), (w: string) => {
          Text(w)
            .fontSize(12)
            .fontColor($r('sys.color.font_tertiary'))
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
        }, (w: string) => `${this.weekStart}-${w}`)
      }
      .width('100%')
      .margin({ top: 8 })

      Grid() {
        ForEach(this.calendarCells(), (cell: CalendarCell) => {
          GridItem() {
            this.calendarCell(cell)
          }
        }, (cell: CalendarCell) => cell.key)
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
