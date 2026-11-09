// 排班本地存储与统计计算服务（纯本地，无网络）
import { preferences } from '@kit.ArkData';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import {
  DayEntry, Shift, ShiftRules, MonthStats, TodoItem,
  dateKey, daysInMonth, minutesToHoursText, pad2
} from '../model/ScheduleTypes';

const KEY_DAYS = 'schedule_days_v1';
const KEY_RULES = 'shift_rules_v1';
const KEY_APPEARANCE = 'appearance_mode_v1'; // 0 跟随系统 1 浅色 2 深色
const FULL_REST_DAY_MINUTES = 8 * 60;        // 休息日按整天 8h 估算休息时长

export class ScheduleService {
  private static instance: ScheduleService | null = null;
  private prefs: preferences.Preferences | null = null;
  private appCtx: common.ApplicationContext | null = null;
  private uiCtx: common.UIAbilityContext | null = null;
  private cacheDays: DayEntry[] | null = null;

  static getInstance(): ScheduleService {
    if (ScheduleService.instance === null) {
      ScheduleService.instance = new ScheduleService();
    }
    return ScheduleService.instance;
  }

  init(context: common.UIAbilityContext): void {
    try {
      this.prefs = preferences.getPreferencesSync(context, { name: 'schedule_store' });
      this.appCtx = context.getApplicationContext();
      this.uiCtx = context;
      const appearance = this.getAppearanceMode();
      this.applyAppearance(appearance);
    } catch (e) {
      console.error('ScheduleService init failed:', JSON.stringify(e));
    }
  }

  // 按系统语言取参数化文案：必须按 id+参数格式化，$r 携带的参数在 getStringSync(Resource) 下不会替换
  str(res: Resource, a?: number | string, b?: number | string, c?: number | string, d?: number | string): string {
    if (this.uiCtx === null) {
      return '';
    }
    try {
      if (a === undefined) {
        return this.uiCtx.resourceManager.getStringSync(res.id);
      }
      if (b === undefined) {
        return this.uiCtx.resourceManager.getStringSync(res.id, a);
      }
      if (c === undefined) {
        return this.uiCtx.resourceManager.getStringSync(res.id, a, b);
      }
      if (d === undefined) {
        return this.uiCtx.resourceManager.getStringSync(res.id, a, b, c);
      }
      return this.uiCtx.resourceManager.getStringSync(res.id, a, b, c, d);
    } catch (e) {
      return '';
    }
  }

  applyAppearance(mode: number): void {
    if (this.appCtx === null) {
      return;
    }
    try {
      if (mode === 1) {
        this.appCtx.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
      } else if (mode === 2) {
        this.appCtx.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
      } else {
        this.appCtx.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
      }
    } catch (e) {
      console.error('applyAppearance failed:', JSON.stringify(e));
    }
  }

  getAppearanceMode(): number {
    if (this.prefs === null) {
      return 0;
    }
    return this.prefs.getSync(KEY_APPEARANCE, 0) as number;
  }

  setAppearanceMode(mode: number): void {
    if (this.prefs === null) {
      return;
    }
    this.prefs.putSync(KEY_APPEARANCE, mode);
    this.prefs.flush();
    this.applyAppearance(mode);
  }

  getRules(): ShiftRules {
    if (this.prefs === null) {
      return new ShiftRules();
    }
    const json = this.prefs.getSync(KEY_RULES, '') as string;
    if (json === '') {
      return new ShiftRules();
    }
    return this.parseRules(json);
  }

  saveRules(rules: ShiftRules): void {
    if (this.prefs === null) {
      return;
    }
    this.prefs.putSync(KEY_RULES, JSON.stringify(rules));
    this.prefs.flush();
  }

  getDays(): DayEntry[] {
    if (this.cacheDays !== null) {
      return this.cacheDays;
    }
    if (this.prefs === null) {
      return [];
    }
    const json = this.prefs.getSync(KEY_DAYS, '') as string;
    if (json === '') {
      this.cacheDays = [];
      return this.cacheDays;
    }
    try {
      const raw = JSON.parse(json) as DayEntry[];
      const result: DayEntry[] = [];
      for (const d of raw) {
        const entry = new DayEntry();
        entry.date = d.date;
        entry.memo = d.memo ?? '';
        entry.shifts = [];
        if (d.shifts) {
          for (const s of d.shifts) {
            const sh = new Shift();
            sh.start = s.start;
            sh.end = s.end;
            entry.shifts.push(sh);
          }
        }
        entry.todos = [];
        if (d.todos) {
          for (const t of d.todos) {
            const td = new TodoItem();
            td.text = t.text;
            td.done = t.done;
            entry.todos.push(td);
          }
        }
        result.push(entry);
      }
      this.cacheDays = result;
      return result;
    } catch (e) {
      console.error('parse days failed:', JSON.stringify(e));
      this.cacheDays = [];
      return this.cacheDays;
    }
  }

  saveDays(days: DayEntry[]): void {
    this.cacheDays = days;
    if (this.prefs === null) {
      return;
    }
    this.prefs.putSync(KEY_DAYS, JSON.stringify(days));
    this.prefs.flush();
  }

  clearAll(): void {
    this.cacheDays = [];
    if (this.prefs === null) {
      return;
    }
    this.prefs.deleteSync(KEY_DAYS);
    this.prefs.flush();
  }

  private parseRules(json: string): ShiftRules {
    const rules = new ShiftRules();
    try {
      const raw = JSON.parse(json) as Record<string, number>;
      rules.monthlyTargetHours = raw.monthlyTargetHours ?? rules.monthlyTargetHours;
      rules.minWorkHoursPerDay = raw.minWorkHoursPerDay ?? rules.minWorkHoursPerDay;
      rules.dailyRestMinutes = raw.dailyRestMinutes ?? rules.dailyRestMinutes;
      rules.restDaysPerMonth = raw.restDaysPerMonth ?? rules.restDaysPerMonth;
      rules.restHoursPerMonth = raw.restHoursPerMonth ?? rules.restHoursPerMonth;
      rules.maxConsecutiveWorkDays = raw.maxConsecutiveWorkDays ?? rules.maxConsecutiveWorkDays;
      rules.maxContinuousWorkMinutes = raw.maxContinuousWorkMinutes ?? rules.maxContinuousWorkMinutes;
      rules.mandatoryRestMinutes = raw.mandatoryRestMinutes ?? rules.mandatoryRestMinutes;
      return rules;
    } catch (e) {
      return rules;
    }
  }

  // ===== 统计计算 =====

  findEntry(days: DayEntry[], date: string): DayEntry | undefined {
    for (const d of days) {
      if (d.date === date) {
        return d;
      }
    }
    return undefined;
  }

  dayMinutes(entry: DayEntry | undefined): number {
    if (entry === undefined) {
      return 0;
    }
    let total = 0;
    for (const s of entry.shifts) {
      total += s.durationMinutes();
    }
    return total;
  }

  isRestDay(entry: DayEntry | undefined): boolean {
    return entry !== undefined && entry.shifts.length === 0;
  }

  // 连续上班天数：end 排班的那天是否工作
  private isWorkDay(days: DayEntry[], date: string): boolean {
    const entry = this.findEntry(days, date);
    return entry !== undefined && entry.shifts.length > 0;
  }

  private addDays(dateStr: string, delta: number): string {
    const d = new Date(dateStr + 'T00:00:00');
    d.setDate(d.getDate() + delta);
    const y = d.getFullYear();
    const m = d.getMonth() + 1;
    const day = d.getDate();
    return dateKey(y, m, day);
  }

  // 以 end 为终点，向前数连续上班天数
  consecutiveWorkDaysEnding(days: DayEntry[], end: string): number {
    let count = 0;
    let cur = end;
    while (this.isWorkDay(days, cur)) {
      count++;
      cur = this.addDays(cur, -1);
      if (count > 62) {
        break; // 防御上限
      }
    }
    return count;
  }

  // 排班某天的班次后，检查当天与当月规则，返回提示列表（空数组 = 无违规）
  checkViolations(days: DayEntry[], date: string, rules: ShiftRules): string[] {
    const result: string[] = [];
    const entry = this.findEntry(days, date);
    if (entry === undefined) {
      return result;
    }
    const parts = date.split('-');
    const year = Number(parts[0]);
    const month = Number(parts[1]);
    const day = Number(parts[2]);

    // 同一天班次间隔
    for (let i = 1; i < entry.shifts.length; i++) {
      const prevEnd = Shift.minutesBetween(entry.shifts[i - 1].end);
      const curStart = Shift.minutesBetween(entry.shifts[i].start) + (entry.shifts[i].start <= entry.shifts[i - 1].end ? 24 * 60 : 0);
      const gap = curStart - prevEnd;
      if (gap < rules.dailyRestMinutes) {
        result.push(this.str($r('app.string.warn_gap'), day, gap, rules.dailyRestMinutes));
      }
    }

    // 单段最长连续工作时长（0 = 不限制）
    if (rules.maxContinuousWorkMinutes > 0) {
      for (const s of entry.shifts) {
        const dur = s.durationMinutes();
        if (dur > rules.maxContinuousWorkMinutes) {
          result.push(this.str($r('app.string.warn_continuous'), day,
            minutesToHoursText(dur), rules.maxContinuousWorkMinutes, rules.mandatoryRestMinutes));
        }
      }
    }

    // 每日最少工时（仅上班日）
    if (entry.shifts.length > 0 && rules.minWorkHoursPerDay > 0) {
      const dm = this.dayMinutes(entry);
      if (dm < rules.minWorkHoursPerDay * 60) {
        result.push(this.str($r('app.string.warn_min_daily'), day, minutesToHoursText(dm), rules.minWorkHoursPerDay));
      }
    }

    // 连续上班天数（包含当天，向后不查，向前数）
    const streak = this.consecutiveWorkDaysEnding(days, date);
    if (entry.shifts.length > 0 && streak > rules.maxConsecutiveWorkDays) {
      result.push(this.str($r('app.string.warn_streak'), day, streak, rules.maxConsecutiveWorkDays));
    }

    // 当月休息天数
    if (rules.restDaysPerMonth > 0) {
      const restDays = this.countRestDays(days, year, month);
      const total = daysInMonth(year, month);
      const today = new Date();
      const isCurrentMonth = today.getFullYear() === year && today.getMonth() + 1 === month;
      const elapsed = isCurrentMonth ? today.getDate() : total;
      const expectedRest = Math.floor(elapsed / total * rules.restDaysPerMonth);
      if (restDays < expectedRest) {
        result.push(this.str($r('app.string.warn_rest_progress'), restDays, expectedRest, rules.restDaysPerMonth));
      }
    }
    return result;
  }

  countRestDays(days: DayEntry[], year: number, month: number): number {
    let count = 0;
    const total = daysInMonth(year, month);
    for (let d = 1; d <= total; d++) {
      if (this.isRestDay(this.findEntry(days, dateKey(year, month, d)))) {
        count++;
      }
    }
    return count;
  }

  // 当前是否处于连续上班中（以今天为终点）
  currentStreak(days: DayEntry[]): number {
    const now = new Date();
    const today = dateKey(now.getFullYear(), now.getMonth() + 1, now.getDate());
    if (this.isWorkDay(days, today)) {
      return this.consecutiveWorkDaysEnding(days, today);
    }
    return this.consecutiveWorkDaysEnding(days, this.addDays(today, -1));
  }

  computeStats(days: DayEntry[], year: number, month: number, rules: ShiftRules): MonthStats {
    const stats = new MonthStats();
    stats.year = year;
    stats.month = month;
    stats.targetMinutes = rules.monthlyTargetHours * 60;
    stats.restDaysTarget = rules.restDaysPerMonth;
    stats.restMinutesTarget = rules.restHoursPerMonth * 60;
    const total = daysInMonth(year, month);
    stats.dailyMinutes = new Array(total + 1).fill(0);

    for (let d = 1; d <= total; d++) {
      const entry = this.findEntry(days, dateKey(year, month, d));
      const dm = this.dayMinutes(entry);
      stats.dailyMinutes[d] = dm;
      if (dm > 0) {
        stats.workDays++;
        stats.workedMinutes += dm;
      } else if (this.isRestDay(entry)) {
        stats.restDays++;
        stats.restMinutes += FULL_REST_DAY_MINUTES;
      }
    }
    stats.remainingMinutes = Math.max(0, stats.targetMinutes - stats.workedMinutes);

    // 连续上班：月内最长
    let cur = 0;
    let maxStreak = 0;
    for (let d = 1; d <= total; d++) {
      if (stats.dailyMinutes[d] > 0) {
        cur++;
        if (cur > maxStreak) {
          maxStreak = cur;
        }
      } else {
        cur = 0;
      }
    }
    stats.maxConsecutive = maxStreak;
    stats.currentConsecutive = this.currentStreak(days);

    // 规则命中（扫描整月每天）
    const violations: string[] = [];
    for (let d = 1; d <= total; d++) {
      const list = this.checkViolations(days, dateKey(year, month, d), rules);
      for (const v of list) {
        violations.push(v);
      }
    }
    stats.violations = violations;
    return stats;
  }

  // 把 from 年月的全部班次复制到 to 年月（按同日对齐，覆盖目标已有班次），返回同步天数
  copyMonthTo(days: DayEntry[], fromYear: number, fromMonth: number, toYear: number, toMonth: number): number {
    const srcTotal = daysInMonth(fromYear, fromMonth);
    const dstTotal = daysInMonth(toYear, toMonth);
    let count = 0;
    for (let d = 1; d <= Math.min(srcTotal, dstTotal); d++) {
      const src = this.findEntry(days, dateKey(fromYear, fromMonth, d));
      if (src === undefined || src.shifts.length === 0) {
        continue;
      }
      const key = dateKey(toYear, toMonth, d);
      let dst = this.findEntry(days, key);
      if (dst === undefined) {
        dst = new DayEntry();
        dst.date = key;
        days.push(dst);
      }
      const shifts: Shift[] = [];
      for (const s of src.shifts) {
        const ns = new Shift();
        ns.start = s.start;
        ns.end = s.end;
        shifts.push(ns);
      }
      dst.shifts = shifts;
      count++;
    }
    return count;
  }

  // 把某一天的班次复制到另一天，返回是否复制
  copyDayTo(days: DayEntry[], fromDate: string, toDate: string): boolean {
    const src = this.findEntry(days, fromDate);
    if (src === undefined || src.shifts.length === 0) {
      return false;
    }
    let dst = this.findEntry(days, toDate);
    if (dst === undefined) {
      dst = new DayEntry();
      dst.date = toDate;
      days.push(dst);
    }
    const shifts: Shift[] = [];
    for (const s of src.shifts) {
      const ns = new Shift();
      ns.start = s.start;
      ns.end = s.end;
      shifts.push(ns);
    }
    dst.shifts = shifts;
    return true;
  }

  // 按规则自动排满本月未排的日期，直到目标工时；返回自动排的天数
  autoFillMonth(days: DayEntry[], year: number, month: number, rules: ShiftRules): number {
    const total = daysInMonth(year, month);
    let worked = 0;
    for (let d = 1; d <= total; d++) {
      worked += this.dayMinutes(this.findEntry(days, dateKey(year, month, d)));
    }
    const target = rules.monthlyTargetHours * 60;
    const dailyMin = (rules.minWorkHoursPerDay > 0 ? rules.minWorkHoursPerDay : 8) * 60;
    let sinceRest = 0;
    let filled = 0;
    for (let d = 1; d <= total; d++) {
      const key = dateKey(year, month, d);
      const entry = this.findEntry(days, key);
      if (entry !== undefined && entry.shifts.length > 0) {
        sinceRest++; // 已排班，按上班日计
        continue;
      }
      if (worked >= target) {
        break; // 目标工时已够
      }
      if (entry !== undefined && entry.shifts.length === 0) {
        sinceRest = 0; // 手动标记的休息日，保留
        continue;
      }
      if (sinceRest >= rules.maxConsecutiveWorkDays) {
        sinceRest = 0; // 达到连续上限，当天强制休息（留空）
        continue;
      }
      const remain = target - worked;
      // 单段时长同时受每日最少工时与单段连续上限约束
      let dur = Math.min(dailyMin, remain);
      if (rules.maxContinuousWorkMinutes > 0) {
        dur = Math.min(dur, rules.maxContinuousWorkMinutes);
      }
      const startMin = 9 * 60;
      const endMin = startMin + dur;
      const ne = entry !== undefined ? entry : (() => {
        const e = new DayEntry();
        e.date = key;
        days.push(e);
        return e;
      })();
      const s = new Shift();
      s.start = `${pad2(Math.floor(startMin / 60))}:${pad2(startMin % 60)}`;
      s.end = `${pad2(Math.floor(endMin / 60))}:${pad2(endMin % 60)}`;
      ne.shifts.push(s);
      worked += dur;
      sinceRest++;
      filled++;
    }
    return filled;
  }
}
