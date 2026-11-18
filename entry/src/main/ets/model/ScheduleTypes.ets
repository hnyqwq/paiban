// 排班数据模型与规则类型定义

export class Shift {
  start: string = '09:00'; // HH:mm
  end: string = '17:00';   // HH:mm，end <= start 视为跨天
  name: string = '';        // 班次名称（来自预设排班，空 = 未命名）
  color: string = '';       // 班次颜色（来自预设排班，空 = 主题蓝）
  breakMinutes: number = 0; // 休息时长（分钟），计算工时时扣除
  breakDayOffset: number = 0; // 休息归属日相对开始日的偏移：-1 前一日，0 开始日，+1 次日（跨天班次可选）
  startDayOffset: number = 0; // 开始日偏移：-1 昨日，0 当日
  endDayOffset: number = 0;   // 结束日偏移：0 当日，1 次日

  static minutesBetween(hm: string): number {
    const parts = hm.split(':');
    const h = Number(parts[0]);
    const m = Number(parts[1]);
    if (Number.isNaN(h) || Number.isNaN(m)) {
      return 0;
    }
    return h * 60 + m;
  }

  // 起止跨度（分钟），跨天按 +24h 处理
  static spanMinutes(start: string, end: string): number {
    const s = Shift.minutesBetween(start);
    let e = Shift.minutesBetween(end);
    if (e <= s) {
      e += 24 * 60;
    }
    return Math.max(0, e - s);
  }

  // 班次时长（分钟），支持跨天；设置了休息时长则扣除，最低为 0
  durationMinutes(): number {
    const span = Shift.spanMinutes(this.start, this.end);
    return Math.max(0, span - Math.max(0, this.breakMinutes));
  }
}

// 预设排班：在「我的」里自定义的常用班次
export class PresetShift {
  id: string = '';
  name: string = '';
  color: string = '#0A59F7';
  start: string = '09:00';
  end: string = '17:00';
  breakMinutes: number = 0; // 休息时长（分钟）
  breakDayOffset: number = 0; // 休息归属日相对开始日：-1 昨日 0 开始日 +1 次日（跨天班次可选）
  autoFill: boolean = false; // 用于自动排班：自动填充时按此预设排班

  // 计入工时的分钟数 = 起止跨度 - 休息时长
  netMinutes(): number {
    const span = Shift.spanMinutes(this.start, this.end);
    return Math.max(0, span - Math.max(0, this.breakMinutes));
  }
}

// 预设排班可选的班次颜色（也可作为默认值）
export const PRESET_COLORS: string[] = [
  '#0A59F7', '#00A870', '#ED6F21', '#E84026',
  '#6B4EFF', '#00A6A6', '#D94B8A', '#6B7280'
];

// 代理提醒的自定义设置
export class AlarmSettings {
  ringDuration: number = 5;      // 响铃时长（秒）
  snoozeEnabled: boolean = true; // 是否支持贪睡（提醒带贪睡按钮）
  snoozeTimes: number = 2;       // 贪睡次数
  timeInterval: number = 5;      // 贪睡间隔（分钟）
  wantAgentEnabled: boolean = true;  // 点击提醒跳转回应用
}

// 已添加的代理提醒登记：设置变化时按此重建全部提醒
export class AlarmSpec {
  date: string = '';       // 班次日期 yyyy-MM-dd
  name: string = '';       // 班次名称
  start: string = '';      // 开始时间 HH:mm
  end: string = '';        // 结束时间 HH:mm
  leadMinutes: number = 0; // 提前提醒分钟数
  reminderId: number = -1; // 系统返回的提醒 ID（-1 = 未知）
}

// 班次相对其所属日期 0 点的绝对分钟区间；
// end<=start 且未显式标注次日时，按跨天（+24h）兜底，兼容老数据
export function shiftAbsRange(s: Shift): number[] {
  const start = s.startDayOffset * 1440 + Shift.minutesBetween(s.start);
  let end = s.endDayOffset * 1440 + Shift.minutesBetween(s.end);
  if (end <= start) {
    end += 24 * 60;
  }
  return [start, end];
}

// 班次是否跨到次日
export function shiftCrossesDay(s: Shift): boolean {
  return shiftAbsRange(s)[1] > 1440;
}

// 班次落在某天的时长（分钟）：dayOffset 0 = 班次所属日，-1 = 昨日
// 休息时长按 breakDayOffset 指定的日子扣除（0 = 开始日，-1 = 前一日，+1 = 次日），跨天尾部不重复扣除
export function shiftMinutesOnOffsetDay(s: Shift, dayOffset: number): number {
  const range = shiftAbsRange(s);
  const dayStart = dayOffset * 1440;
  const from = Math.max(range[0], dayStart);
  const to = Math.min(range[1], dayStart + 1440);
  let minutes = Math.max(0, to - from);
  if (dayOffset === s.startDayOffset + s.breakDayOffset) {
    minutes = Math.max(0, minutes - Math.max(0, s.breakMinutes));
  }
  return minutes;
}

// 一天班次的净工时（分钟）：取班次落在该天的工时段（跨度扣除休息，休息按班次末尾计），
// 合并去重（重叠/相邻时段只计一次）后求和，避免重叠班次被重复计时
export function unionWorkedMinutes(shifts: Shift[], dayOffset: number = 0): number {
  const dayStart = dayOffset * 1440;
  const intervals: number[][] = [];
  for (const s of shifts) {
    const range = shiftAbsRange(s);
    const from = Math.max(range[0], dayStart);
    const to = Math.min(range[1], dayStart + 1440);
    if (to > from) {
      intervals.push([from - dayStart, to - dayStart]);
    }
  }
  return unionMinutes(intervals);
}

// 区间并集总长（分钟），intervals 为相对同一起点的 [start, end)
export function unionMinutes(intervals: number[][]): number {
  intervals.sort((a: number[], b: number[]) => a[0] - b[0]);
  let total = 0;
  let curStart = 0;
  let curEnd = 0;
  for (const it of intervals) {
    if (it[0] > curEnd) {
      total += curEnd - curStart;
      curStart = it[0];
      curEnd = it[1];
    } else if (it[1] > curEnd) {
      curEnd = it[1];
    }
  }
  total += curEnd - curStart;
  return total;
}

export class TodoItem {
  text: string = '';
  done: boolean = false;
}

export class DayEntry {
  date: string = '';       // yyyy-MM-dd
  shifts: Shift[] = [];    // 空 shifts 且 memo 非空 = 休息日/纯备忘
  memo: string = '';
  todos: TodoItem[] = [];  // 当日待办
}

export class ShiftRules {
  monthlyTargetHours: number = 144;     // 每月目标工时
  minWorkHoursPerDay: number = 6;       // 每个上班日最少工时（未排且未标记休息的非休息日也按此校验）
  dailyRestMinutes: number = 60;        // 同一天两个班次之间最少间隔
  restDaysPerMonth: number = 4;         // 每月最少休息天数
  restHoursPerMonth: number = 40;       // 每月最少休息时长（非工作日按整天 8h 计）
  maxConsecutiveWorkDays: number = 6;   // 最长连续上班天数
  restWeekdays: number[] = [];          // 固定每周休息日（0=周日…6=周六）
  maxContinuousWorkMinutes: number = 360; // 一天内单段最长连续工作时长，0 = 不限制（默认 6 小时）
  mandatoryRestMinutes: number = 60;    // 超过单段上限后需强制休息的时长
  skipHolidays: boolean = false;        // 自动排班时跳过法定节假日
}

// 法定节假日表（离线静态数据，按国务院历年公告整理；建议每年校准）
// key: 年份；value: 当年所有节假日日期（MM-dd，跨月节假日按实际日期逐条列出）
const HOLIDAY_TABLE: Map<number, string[]> = new Map([
  [2026, ['01-01', '01-02', '01-03', '02-16', '02-17', '02-18', '02-19', '02-20', '02-21', '02-22',
    '04-04', '04-05', '04-06', '05-01', '05-02', '05-03', '06-19', '06-20', '06-21',
    '09-25', '09-26', '09-27', '10-01', '10-02', '10-03', '10-04', '10-05', '10-06', '10-07']],
  [2027, ['01-01', '01-02', '01-03', '02-05', '02-06', '02-07', '02-08', '02-09', '02-10', '02-11', '02-12', '02-13',
    '04-03', '04-04', '04-05', '05-01', '05-02', '05-03', '05-04', '05-05', '06-09',
    '09-15', '10-01', '10-02', '10-03', '10-04', '10-05', '10-06', '10-07']],
  [2028, ['01-01', '01-02', '01-03', '01-25', '01-26', '01-27', '01-28', '01-29', '01-30', '01-31',
    '04-03', '04-04', '04-05', '05-01', '05-02', '05-03', '05-28', '05-29', '05-30',
    '10-01', '10-02', '10-03', '10-04', '10-05', '10-06', '10-07']],
  [2029, ['01-01', '01-02', '01-03', '02-12', '02-13', '02-14', '02-15', '02-16', '02-17', '02-18',
    '04-04', '04-05', '04-06', '05-01', '05-02', '05-03', '06-16', '06-17', '06-18',
    '09-21', '09-22', '09-23', '10-01', '10-02', '10-03', '10-04', '10-05', '10-06', '10-07']],
  [2030, ['01-01', '01-02', '01-03', '02-02', '02-03', '02-04', '02-05', '02-06', '02-07', '02-08',
    '04-04', '04-05', '04-06', '05-01', '05-02', '05-03', '06-05', '06-06', '06-07',
    '09-11', '09-12', '09-13', '10-01', '10-02', '10-03', '10-04', '10-05', '10-06', '10-07']]
]);

// 判断某天是否为法定节假日（不含调休补班日）
export function isStatutoryHoliday(year: number, month: number, day: number): boolean {
  const list = HOLIDAY_TABLE.get(year);
  if (list === undefined) {
    return false;
  }
  const md = `${pad2(month)}-${pad2(day)}`;
  return list.includes(md);
}

// 调休补班日表（官方公布的周末上班日）：这些天虽是周末但应视为工作日
const WORKDAY_SWAPS: Map<number, string[]> = new Map([
  [2027, ['01-31', '02-14', '05-08', '09-26', '10-09']]
]);

// 判断某天是否为调休补班日
export function isSwapWorkday(year: number, month: number, day: number): boolean {
  const list = WORKDAY_SWAPS.get(year);
  if (list === undefined) {
    return false;
  }
  const md = `${pad2(month)}-${pad2(day)}`;
  return list.includes(md);
}

// 一个月的统计结果
export class MonthStats {
  year: number = 0;
  month: number = 0;            // 1-12
  workedMinutes: number = 0;    // 已排总工时（分钟）
  targetMinutes: number = 0;
  remainingMinutes: number = 0; // 还需排的分钟数
  workDays: number = 0;
  restDays: number = 0;
  restDaysTarget: number = 0;
  restMinutes: number = 0;      // 已休时长（按整天 8h 估算）
  restMinutesTarget: number = 0;
  maxConsecutive: number = 0;
  currentConsecutive: number = 0;
  dailyMinutes: number[] = [];  // 每天工时（分钟），按月内日期下标从 1 开始（0 空置）
  violations: string[] = [];    // 规则命中提示
}

export function hmToMinutes(hm: string): number {
  return Shift.minutesBetween(hm);
}

export function minutesToHoursText(minutes: number): string {
  const h = Math.floor(minutes / 60);
  const m = minutes % 60;
  if (m === 0) {
    return `${h}h`;
  }
  return `${h}h${m}m`;
}

export function pad2(n: number): string {
  return n < 10 ? `0${n}` : `${n}`;
}

// 时间输入自动规范化：13→13:00，02→02:00，930→09:30，20.30/2030→20:30
// 无数字（如空串）保持原样返回
export function normalizeTime(raw: string): string {
  const digits = raw.replace(/[^0-9]/g, '');
  if (digits.length === 0) {
    return raw;
  }
  let h = 0;
  let m = 0;
  if (digits.length <= 2) {
    h = Number(digits);
  } else if (digits.length === 3) {
    h = Number(digits.slice(0, 1));
    m = Number(digits.slice(1));
  } else {
    h = Number(digits.slice(0, digits.length - 2));
    m = Number(digits.slice(-2));
  }
  if (Number.isNaN(h) || Number.isNaN(m)) {
    return raw;
  }
  if (h > 23) {
    h = 23;
  }
  if (m > 59) {
    m = 59;
  }
  return `${pad2(h)}:${pad2(m)}`;
}

export function dateKey(year: number, month: number, day: number): string {
  return `${year}-${pad2(month)}-${pad2(day)}`;
}

export function daysInMonth(year: number, month: number): number {
  return new Date(year, month, 0).getDate();
}
