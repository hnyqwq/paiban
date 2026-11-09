// 排班数据模型与规则类型定义

export class Shift {
  start: string = '09:00'; // HH:mm
  end: string = '17:00';   // HH:mm，end <= start 视为跨天

  static minutesBetween(hm: string): number {
    const parts = hm.split(':');
    const h = Number(parts[0]);
    const m = Number(parts[1]);
    if (Number.isNaN(h) || Number.isNaN(m)) {
      return 0;
    }
    return h * 60 + m;
  }

  // 班次时长（分钟），支持跨天
  durationMinutes(): number {
    const s = Shift.minutesBetween(this.start);
    let e = Shift.minutesBetween(this.end);
    if (e <= s) {
      e += 24 * 60;
    }
    return e - s;
  }
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
  minWorkHoursPerDay: number = 6;       // 每个上班日最少工时
  dailyRestMinutes: number = 60;        // 同一天两个班次之间最少间隔
  restDaysPerMonth: number = 4;         // 每月最少休息天数
  restHoursPerMonth: number = 40;       // 每月最少休息时长（非工作日按整天 8h 计）
  maxConsecutiveWorkDays: number = 6;   // 最长连续上班天数
  maxContinuousWorkMinutes: number = 0; // 一天内单段最长连续工作时长，0 = 不限制
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

export function dateKey(year: number, month: number, day: number): string {
  return `${year}-${pad2(month)}-${pad2(day)}`;
}

export function daysInMonth(year: number, month: number): number {
  return new Date(year, month, 0).getDate();
}
