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
    // 通知各页面重读规则
    AppStorage.setOrCreate('rulesChanged', Date.now());
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

  // 解析导出/存储的 JSON 为 DayEntry 数组，格式非法返回 null
  parseDaysJson(json: string): DayEntry[] | null {
    let text = json.trim();
    if (text === '') {
      return null;
    }
    // 容错：剪贴板可能带入说明文字或代码块围栏，只取首个 [ 到最后一个 ] 之间的内容
    const first = text.indexOf('[');
    const last = text.lastIndexOf(']');
    if (first === -1 || last === -1 || last <= first) {
      return null;
    }
    if (first > 0 || last < text.length - 1) {
      text = text.substring(first, last + 1);
    }
    try {
      const raw = JSON.parse(text) as DayEntry[];
      if (!Array.isArray(raw)) {
        return null;
      }
      const result: DayEntry[] = [];
      for (const d of raw) {
        if (d.date === undefined || d.date === null) {
          continue;
        }
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
      return result;
    } catch (e) {
      return null;
    }
  }

  // 导入：解析导出的 JSON 并整体替换本地数据
  importDays(json: string): boolean {
    if (this.prefs === null) {
      return false;
    }
    const days = this.parseDaysJson(json);
    if (days === null) {
      return false;
    }
    this.cacheDays = days;
    this.prefs.putSync(KEY_DAYS, JSON.stringify(days));
    this.prefs.flush();
    // 通知各页面重载数据
    AppStorage.setOrCreate('scheduleDataVersion', Date.now());
    return true;
  }

  saveDays(days: DayEntry[]): void {
    this.cacheDays = days;
    if (this.prefs === null) {
      return;
    }
    this.prefs.putSync(KEY_DAYS, JSON.stringify(days));
    this.prefs.flush();
    // 通知各页面重载数据
    AppStorage.setOrCreate('scheduleDataVersion', Date.now());
  }

  clearAll(): void {
    this.cacheDays = [];
    if (this.prefs === null) {
      return;
    }
    this.prefs.deleteSync(KEY_DAYS);
    this.prefs.flush();
    // 通知各页面重载数据
    AppStorage.setOrCreate('scheduleDataVersion', Date.now());
  }

  private parseRules(json: string): ShiftRules {
    const rules = new ShiftRules();
    try {
      const raw = JSON.parse(json) as Record<string, number>;
      rules.monthlyTargetHours = raw.monthlyTargetHours ?? rules.monthlyTargetHours;
      rules.minWorkHoursPerDay = raw.minWorkHoursPerDay ?? rules.minWorkHoursPerDay;
      rules.workdayMinHours = raw.workdayMinHours ?? rules.workdayMinHours;
      rules.dailyRestMinutes = raw.dailyRestMinutes ?? rules.dailyRestMinutes;
      rules.restDaysPerMonth = raw.restDaysPerMonth ?? rules.restDaysPerMonth;
      rules.restHoursPerMonth = raw.restHoursPerMonth ?? rules.restHoursPerMonth;
      rules.maxConsecutiveWorkDays = raw.maxConsecutiveWorkDays ?? rules.maxConsecutiveWorkDays;
      rules.maxContinuousWorkMinutes = raw.maxContinuousWorkMinutes ?? rules.maxContinuousWorkMinutes;
      rules.mandatoryRestMinutes = raw.mandatoryRestMinutes ?? rules.mandatoryRestMinutes;
      rules.restWeekdays = Array.isArray(raw.restWeekdays) ? raw.restWeekdays as number[] : rules.restWeekdays;
      rules.shiftTemplate = typeof raw.shiftTemplate === 'string' ? raw.shiftTemplate : rules.shiftTemplate;
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

    // 固定每周休息日：当天不应排班
    if (rules.restWeekdays.length > 0 && entry.shifts.length > 0) {
      const wd = new Date(year, month - 1, day).getDay();
      if (rules.restWeekdays.includes(wd)) {
        result.push(this.str($r('app.string.warn_rest_weekday'), day));
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

    // 除休息日外每日最少工时：未排班且未标记休息的天（仅统计到今天）视为违规
    if (rules.workdayMinHours > 0 && entry.shifts.length === 0) {
      const today = new Date();
      const isCurrentMonth = today.getFullYear() === year && today.getMonth() + 1 === month;
      if (!isCurrentMonth || day <= today.getDate()) {
        const markedRest = entry !== undefined; // 有 entry 无班次 = 手动标记休息
        if (!markedRest) {
          result.push(this.str($r('app.string.warn_workday_min'), day, rules.workdayMinHours));
        }
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
    const dailyMin = (rules.minWorkHoursPerDay > 0 ? rules.minWorkHoursPerDay : 8) * 60;
    const target = rules.monthlyTargetHours * 60;
    // 连续计数接上月末，避免跨月超过连续上限
    const prevLast = new Date(year, month - 1, 0);
    let sinceRest = this.consecutiveWorkDaysEnding(days,
      dateKey(prevLast.getFullYear(), prevLast.getMonth() + 1, prevLast.getDate()));

    // 第一遍：确定每天状态，收集可排日期（固定休息日/手动休息/已达连续上限的天跳过）
    const openDays: string[] = [];
    for (let d = 1; d <= total; d++) {
      const key = dateKey(year, month, d);
      const entry = this.findEntry(days, key);
      if (entry !== undefined && entry.shifts.length > 0) {
        sinceRest++; // 已排班，按上班日计
        continue;
      }
      const wd = new Date(year, month - 1, d).getDay();
      if (rules.restWeekdays.includes(wd)) {
        sinceRest = 0; // 固定每周休息日
        continue;
      }
      if (entry !== undefined) {
        sinceRest = 0; // 手动标记的休息日，保留
        continue;
      }
      if (sinceRest >= rules.maxConsecutiveWorkDays) {
        sinceRest = 0; // 达到连续上限，当天强制休息（留空）
        continue;
      }
      openDays.push(key);
      sinceRest++;
    }

    // 已排总工时与剩余目标
    let worked = 0;
    for (let d = 1; d <= total; d++) {
      worked += this.dayMinutes(this.findEntry(days, dateKey(year, month, d)));
    }
    const remain = Math.max(0, target - worked);
    if (remain === 0 || openDays.length === 0) {
      return 0;
    }

    // 每日最少工时是下限：天数不够排时，单日自动往上加，尽快凑够目标
    const perDay = Math.min(Math.max(dailyMin, Math.ceil(remain / openDays.length)), 16 * 60);
    let filled = 0;
    for (const key of openDays) {
      if (worked >= target) {
        break;
      }
      const dur = Math.min(perDay, target - worked);
      const ne = (() => {
        const e = this.findEntry(days, key);
        if (e !== undefined) {
          return e;
        }
        const created = new DayEntry();
        created.date = key;
        days.push(created);
        return created;
      })();
      this.fillShiftsForDay(ne, dur, rules);
      worked += dur;
      filled++;
    }
    return filled;
  }

  // 给某天填充班次：配置了固定班次模板则按模板排（可多段），
  // 否则总时长超过单段上限时自动拆成多段，段间留强制休息间隔
  private fillShiftsForDay(ne: DayEntry, duration: number, rules: ShiftRules): void {
    const template = this.parseShiftTemplate(rules.shiftTemplate);
    if (template.length > 0) {
      for (const seg of template) {
        const s = new Shift();
        s.start = seg[0];
        s.end = seg[1];
        ne.shifts.push(s);
      }
      return;
    }
    const cap = rules.maxContinuousWorkMinutes > 0
      ? Math.min(duration, rules.maxContinuousWorkMinutes)
      : duration;
    const restGap = rules.maxContinuousWorkMinutes > 0 ? Math.max(rules.mandatoryRestMinutes, 0) : 0;
    let remaining = duration;
    let startMin = 9 * 60;
    while (remaining > 0) {
      const dur = Math.min(cap, remaining);
      const endMin = startMin + dur;
      const s = new Shift();
      s.start = `${pad2(Math.floor(startMin / 60))}:${pad2(startMin % 60)}`;
      s.end = `${pad2(Math.floor(endMin / 60))}:${pad2(endMin % 60)}`;
      ne.shifts.push(s);
      remaining -= dur;
      startMin = endMin + restGap;
    }
  }

  // 解析班次模板 "08:00-12:00,14:00-18:00" → [["08:00","12:00"],["14:00","18:00"]]，非法返回空
  private parseShiftTemplate(template: string): string[][] {
    const result: string[][] = [];
    const text = template.trim();
    if (text === '') {
      return result;
    }
    for (const part of text.split(',')) {
      const seg = part.trim().split('-');
      if (seg.length !== 2) {
        return []; // 任一段非法则整条模板不生效
      }
      const start = seg[0].trim();
      const end = seg[1].trim();
      if (!/^\d{1,2}:\d{2}$/.test(start) || !/^\d{1,2}:\d{2}$/.test(end)) {
        return [];
      }
      result.push([start, end]);
    }
    return result;
  }

  // 按日期区间（如 7 天）自动排班：跳过已有班次/手动休息/固定休息日，遵守连续上限；
  // 剩余目标工时按区间内可排天数均摊，天数不够排时单日自动往上加；返回排的天数
  autoFillRange(days: DayEntry[], start: string, end: string, rules: ShiftRules): number {
    const dailyMin = (rules.minWorkHoursPerDay > 0 ? rules.minWorkHoursPerDay : 8) * 60;
    const target = rules.monthlyTargetHours * 60;
    // 区间内已有班次工时 + 剩余目标
    let worked = 0;
    let schedulableLeft = 0;
    let probe = start;
    while (probe <= end) {
      const e = this.findEntry(days, probe);
      const wd = new Date(probe + 'T00:00:00').getDay();
      if (e !== undefined && e.shifts.length > 0) {
        worked += this.dayMinutes(e);
      } else if (!rules.restWeekdays.includes(wd)) {
        schedulableLeft++; // 未排且非固定休息日，可参与分摊
      }
      probe = this.addDays(probe, 1);
    }
    let remain = Math.max(0, target - worked);
    // 连续计数延续区间开始之前的状态
    let sinceRest = this.consecutiveWorkDaysEnding(days, this.addDays(start, -1));
    let filled = 0;
    let cur = start;
    // yyyy-MM-dd 字典序即日期序
    while (cur <= end) {
      const entry = this.findEntry(days, cur);
      if (entry !== undefined && entry.shifts.length > 0) {
        sinceRest++;
        cur = this.addDays(cur, 1);
        continue;
      }
      const wd = new Date(cur + 'T00:00:00').getDay();
      if (rules.restWeekdays.includes(wd)) {
        sinceRest = 0;
        cur = this.addDays(cur, 1);
        continue;
      }
      if (entry !== undefined && entry.shifts.length === 0) {
        sinceRest = 0; // 手动标记的休息日，保留
        cur = this.addDays(cur, 1);
        continue;
      }
      if (sinceRest >= rules.maxConsecutiveWorkDays) {
        sinceRest = 0; // 达到连续上限，当天强制休息
        cur = this.addDays(cur, 1);
        continue;
      }
      // 每日最少工时是下限：区间天数不够排时，单日自动往上加，尽快凑够目标
      let dur = dailyMin;
      if (schedulableLeft > 0 && remain / schedulableLeft > dailyMin) {
        dur = Math.min(Math.ceil(remain / schedulableLeft), 16 * 60);
      }
      const ne = entry !== undefined ? entry : (() => {
        const e = new DayEntry();
        e.date = cur;
        days.push(e);
        return e;
      })();
      this.fillShiftsForDay(ne, dur, rules);
      worked += dur;
      remain = Math.max(0, remain - dur);
      schedulableLeft--;
      sinceRest++;
      filled++;
      cur = this.addDays(cur, 1);
    }
    return filled;
  }

  // 把一段日期区间（srcStart..srcEnd）的班次逐日复制到 dstStart 开始的等长区间，返回复制天数
  copyRangeTo(days: DayEntry[], srcStart: string, srcEnd: string, dstStart: string): number {
    let count = 0;
    let src = srcStart;
    let dst = dstStart;
    while (src <= srcEnd) {
      if (this.copyDayTo(days, src, dst)) {
        count++;
      }
      src = this.addDays(src, 1);
      dst = this.addDays(dst, 1);
    }
    return count;
  }
}
