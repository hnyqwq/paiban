// 排班数据模型与规则类型定义

export class Shift {
  start: string = '09:00'; // HH:mm
  end: string = '17:00';   // HH:mm，end <= start 视为跨天
  name: string = '';        // 班次名称（来自预设排班，空 = 未命名）
  color: string = '';       // 班次颜色（来自预设排班，空 = 主题蓝）
  breakMinutes: number = 0; // 休息时长（分钟），计算工时时扣除

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
