// 排班本地存储与统计计算服务（纯本地，无网络）
import { preferences } from '@kit.ArkData';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import {
  DayEntry, Shift, ShiftRules, MonthStats, TodoItem, PresetShift, PRESET_COLORS,
  AlarmSettings, AlarmSpec, dateKey, daysInMonth, isStatutoryHoliday, minutesToHoursText, pad2, shiftAbsRange, unionMinutes, unionWorkedMinutes
} from '../model/ScheduleTypes';
import { FormCardData } from '../form/FormCardData';

const KEY_DAYS = 'schedule_days_v1';
const KEY_RULES = 'shift_rules_v1';
const KEY_APPEARANCE = 'appearance_mode_v1'; // 0 跟随系统 1 浅色 2 深色
const KEY_WEEK_START = 'calendar_week_start_v1'; // 0 周日开始 1 周一开始
const KEY_PRESETS = 'preset_shifts_v1'; // 预设排班（名称/颜色/起止/休息）
const KEY_ALARM_SETTINGS = 'alarm_settings_v1'; // 代理提醒自定义设置
const KEY_ALARM_REGISTRY = 'alarm_registry_v1'; // 已添加的代理提醒登记（设置变化时重建）
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
      // 启动时同步刷新桌面卡片，避免上次异常退出留下旧数据
      this.notifyCards();
      // 一次性迁移：老的固定班次模板 → 「用于自动排班」的预设
      this.migrateTemplateToPreset();
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

  // 日历周起始日：0 周日开始（默认）1 周一开始
  getWeekStart(): number {
    if (this.prefs === null) {
      return 0;
    }
    return this.prefs.getSync(KEY_WEEK_START, 0) as number;
  }

  setWeekStart(mode: number): void {
    if (this.prefs === null) {
      return;
    }
    this.prefs.putSync(KEY_WEEK_START, mode);
    this.prefs.flush();
    AppStorage.setOrCreate('weekStart', mode);
    this.notifyCards();
  }

  // 数据变化后通知桌面卡片刷新（内部做 800ms 合并）
  private notifyCards(): void {
    if (this.uiCtx !== null) {
      FormCardData.requestRefresh(this.uiCtx);
    }
  }

  // ===== 预设排班 =====

  // 默认预设：早/白/晚/夜四个常用班次，首次使用时展示，可自由增删改
  private defaultPresets(): PresetShift[] {
    const list: PresetShift[] = [];
    this.pushDefaultPreset(list, 'default_early', this.str($r('app.string.preset_default_early')), '早班',
      PRESET_COLORS[0], '06:00', '14:00');
    this.pushDefaultPreset(list, 'default_day', this.str($r('app.string.preset_default_day')), '白班',
      PRESET_COLORS[1], '09:00', '17:00');
    this.pushDefaultPreset(list, 'default_evening', this.str($r('app.string.preset_default_evening')), '晚班',
      PRESET_COLORS[2], '14:00', '22:00');
    this.pushDefaultPreset(list, 'default_night', this.str($r('app.string.preset_default_night')), '夜班',
      PRESET_COLORS[4], '22:00', '06:00');
    return list;
  }

  private pushDefaultPreset(list: PresetShift[], id: string, localizedName: string, fallbackName: string,
    color: string, start: string, end: string): void {
    const preset = new PresetShift();
    preset.id = id;
    preset.name = localizedName !== '' ? localizedName : fallbackName;
    preset.color = color;
    preset.start = start;
    preset.end = end;
    preset.breakMinutes = 0;
    list.push(preset);
  }

  getPresets(): PresetShift[] {
    if (this.prefs === null) {
      return this.defaultPresets();
    }
    const json = this.prefs.getSync(KEY_PRESETS, '') as string;
    if (json === '') {
      return this.defaultPresets();
    }
    const list = this.parsePresets(json);
    // 用户把预设全部删光时保留空列表（json 为 "[]"），不要自动恢复默认值
    if (list.length === 0 && json.trim() !== '[]') {
      return this.defaultPresets();
    }
    return list;
  }

  savePresets(presets: PresetShift[]): void {
    if (this.prefs === null) {
      return;
    }
    this.prefs.putSync(KEY_PRESETS, JSON.stringify(presets));
    this.prefs.flush();
    // 通知排班页的预设按钮刷新
    AppStorage.setOrCreate('presetsChanged', Date.now());
  }

  private parsePresets(json: string): PresetShift[] {
    try {
      const raw = JSON.parse(json) as PresetShift[];
      if (!Array.isArray(raw)) {
        return [];
      }
      const result: PresetShift[] = [];
      for (const r of raw) {
        if (r === undefined || r === null || typeof r.name !== 'string' || r.name === '') {
          continue;
        }
        const preset = new PresetShift();
        preset.id = typeof r.id === 'string' && r.id !== '' ? r.id : `p_${result.length}_${Date.now()}`;
        preset.name = r.name;
        preset.color = typeof r.color === 'string' && r.color !== '' ? r.color : PRESET_COLORS[0];
        preset.start = typeof r.start === 'string' && r.start !== '' ? r.start : '09:00';
        preset.end = typeof r.end === 'string' && r.end !== '' ? r.end : '17:00';
        preset.breakMinutes = typeof r.breakMinutes === 'number' && r.breakMinutes > 0
          ? Math.floor(r.breakMinutes) : 0;
        preset.autoFill = r.autoFill === true;
        result.push(preset);
      }
      return result;
    } catch (e) {
      return [];
    }
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

  // 代理提醒自定义设置
  getAlarmSettings(): AlarmSettings {
    const settings = new AlarmSettings();
    if (this.prefs === null) {
      return settings;
    }
    try {
      const json = this.prefs.getSync(KEY_ALARM_SETTINGS, '') as string;
      if (json === '') {
        return settings;
      }
      const raw = JSON.parse(json) as AlarmSettings;
      settings.ringDuration = typeof raw.ringDuration === 'number' && raw.ringDuration > 0 ? Math.floor(raw.ringDuration) : settings.ringDuration;
      settings.snoozeEnabled = raw.snoozeEnabled === true;
      settings.snoozeTimes = typeof raw.snoozeTimes === 'number' && raw.snoozeTimes > 0 ? Math.floor(raw.snoozeTimes) : settings.snoozeTimes;
      settings.timeInterval = typeof raw.timeInterval === 'number' && raw.timeInterval > 0 ? Math.floor(raw.timeInterval) : settings.timeInterval;
      settings.wantAgentEnabled = raw.wantAgentEnabled !== false;
      settings.tapDismissed = raw.tapDismissed === true;
      settings.autoDeleteEnabled = raw.autoDeleteEnabled === true;
      settings.customRingUri = typeof raw.customRingUri === 'string' ? raw.customRingUri : '';
      settings.customRingName = typeof raw.customRingName === 'string' ? raw.customRingName : '';
    } catch (e) {
      // 解析失败返回默认值
    }
    return settings;
  }

  saveAlarmSettings(settings: AlarmSettings): void {
    if (this.prefs === null) {
      return;
    }
    this.prefs.putSync(KEY_ALARM_SETTINGS, JSON.stringify(settings));
    this.prefs.flush();
  }

  // 已添加代理提醒的登记表：设置变化时按此重建全部提醒
  getAlarmRegistry(): AlarmSpec[] {
    if (this.prefs === null) {
      return [];
    }
    try {
      const json = this.prefs.getSync(KEY_ALARM_REGISTRY, '') as string;
      if (json === '') {
        return [];
      }
      const raw = JSON.parse(json) as AlarmSpec[];
      return raw.filter((s: AlarmSpec) => s.date !== '' && s.start !== '' && s.end !== '');
    } catch (e) {
      return [];
    }
  }

  saveAlarmRegistry(list: AlarmSpec[]): void {
    if (this.prefs === null) {
      return;
    }
    this.prefs.putSync(KEY_ALARM_REGISTRY, JSON.stringify(list));
    this.prefs.flush();
  }

  // 登记一条提醒（按日期+开始时间去重，重复添加不重复登记）
  addAlarmSpec(spec: AlarmSpec): void {
    const list = this.getAlarmRegistry().filter((s: AlarmSpec) =>
      !(s.date === spec.date && s.start === spec.start));
    list.push(spec);
    this.saveAlarmRegistry(list);
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
            sh.name = s.name ?? '';
            sh.color = s.color ?? '';
            sh.breakMinutes = s.breakMinutes ?? 0;
            sh.startDayOffset = s.startDayOffset ?? 0;
            sh.endDayOffset = s.endDayOffset ?? 0;
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
            sh.name = s.name ?? '';
            sh.color = s.color ?? '';
            sh.breakMinutes = s.breakMinutes ?? 0;
            sh.startDayOffset = s.startDayOffset ?? 0;
            sh.endDayOffset = s.endDayOffset ?? 0;
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
    this.notifyCards();
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
    this.notifyCards();
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
    this.notifyCards();
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
      rules.restWeekdays = Array.isArray(raw.restWeekdays) ? raw.restWeekdays as number[] : rules.restWeekdays;
      const rawBool = JSON.parse(json) as Record<string, boolean>;
      rules.skipHolidays = rawBool.skipHolidays === true;
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
    // 重叠班次按并集计，避免重复计时
    return unionWorkedMinutes(entry.shifts, 0);
  }

  // 某一天的实际在岗时长（分钟）：当日班次落在该日的部分 + 昨日跨天班次的次日尾巴，
  // 合并去重后求和
  dayMinutesOnDate(days: DayEntry[], date: string): number {
    const intervals: number[][] = [];
    const own = this.findEntry(days, date);
    if (own !== undefined) {
      for (const s of own.shifts) {
        const range = shiftAbsRange(s);
        const from = Math.max(range[0], 0);
        const to = Math.min(range[1], 1440);
        if (to > from) {
          intervals.push([from, to]);
        }
      }
    }
    const prev = this.findEntry(days, this.addDays(date, -1));
    if (prev !== undefined) {
      for (const s of prev.shifts) {
        const range = shiftAbsRange(s);
        const from = Math.max(range[0] - 1440, 0);
        const to = Math.min(range[1] - 1440, 1440);
        if (to > from) {
          intervals.push([from, to]);
        }
      }
    }
    return unionMinutes(intervals);
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

    // 同一天班次间隔：按绝对时间排序后相邻工时段的间隔（后一班次开始早于前一班次结束视为跨天）
    const ranges = entry.shifts.map((s: Shift) => shiftAbsRange(s))
      .sort((a: number[], b: number[]) => a[0] - b[0]);
    for (let i = 1; i < ranges.length; i++) {
      const gap = ranges[i][0] - ranges[i - 1][1];
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

    // 每日最少工时：已排班日查当日实际在岗工时；未排班且未标记休息的非休息日（仅统计到今天）也视为违规
    if (rules.minWorkHoursPerDay > 0) {
      if (entry.shifts.length > 0) {
        const dm = this.dayMinutesOnDate(days, date);
        if (dm < rules.minWorkHoursPerDay * 60) {
          result.push(this.str($r('app.string.warn_min_daily'), day, minutesToHoursText(dm), rules.minWorkHoursPerDay));
        }
      } else {
        const today = new Date();
        const isCurrentMonth = today.getFullYear() === year && today.getMonth() + 1 === month;
        if (!isCurrentMonth || day <= today.getDate()) {
          const markedRest = entry !== undefined; // 有 entry 无班次 = 手动标记休息
          // 昨日跨天班次的尾巴已覆盖当日工时时不再告警
          const tailMinutes = this.dayMinutesOnDate(days, date);
          if (!markedRest && tailMinutes < rules.minWorkHoursPerDay * 60) {
            result.push(this.str($r('app.string.warn_workday_min'), day, rules.minWorkHoursPerDay));
          }
        }
      }
    }

    // 连续上班天数（包含当天，向后不查，向前数）；0 = 不限制
    const streak = this.consecutiveWorkDaysEnding(days, date);
    if (rules.maxConsecutiveWorkDays > 0 && entry.shifts.length > 0 && streak > rules.maxConsecutiveWorkDays) {
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

  // 休息天数：当天没有任何排班工时（含未记录天与手动标记的休息日）
  countRestDays(days: DayEntry[], year: number, month: number): number {
    let count = 0;
    const total = daysInMonth(year, month);
    for (let d = 1; d <= total; d++) {
      if (this.dayMinutesOnDate(days, dateKey(year, month, d)) === 0) {
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
      const dm = this.dayMinutesOnDate(days, dateKey(year, month, d));
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
        ns.name = s.name;
        ns.color = s.color;
        ns.breakMinutes = s.breakMinutes;
        ns.startDayOffset = s.startDayOffset;
        ns.endDayOffset = s.endDayOffset;
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
      ns.name = s.name;
      ns.color = s.color;
      ns.breakMinutes = s.breakMinutes;
      ns.startDayOffset = s.startDayOffset;
      ns.endDayOffset = s.endDayOffset;
      shifts.push(ns);
    }
    dst.shifts = shifts;
    return true;
  }

  // 按规则自动排满本月未排的日期，直到目标工时；返回自动排的天数
  autoFillMonth(days: DayEntry[], year: number, month: number, rules: ShiftRules, presetId: string = ''): number {
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
      if (rules.skipHolidays && isStatutoryHoliday(year, month, d)) {
        sinceRest = 0; // 法定节假日自动跳过，视为休息
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
      worked += this.dayMinutesOnDate(days, dateKey(year, month, d));
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
      this.fillShiftsForDay(ne, perDay, rules, presetId);
      worked += perDay;
      filled++;
    }
    return filled;
  }

  // 给某天填充班次：勾选了「用于自动排班」的预设则按预设排（可多选，按开始时间排序全部排上，
  // 名称/颜色/休息时长随预设带到班次上）；指定 presetId 时只用该预设；
  // 无可用预设时按时长填充，总时长超过单段上限时自动拆成多段，段间留强制休息间隔
  private fillShiftsForDay(ne: DayEntry, duration: number, rules: ShiftRules, presetId: string = ''): void {
    const presets = this.getPresets().filter((p: PresetShift) => p.autoFill && (presetId === '' || p.id === presetId));
    if (presets.length > 0) {
      presets.sort((a: PresetShift, b: PresetShift) =>
        Shift.minutesBetween(a.start) - Shift.minutesBetween(b.start));
      for (const p of presets) {
        const s = new Shift();
        s.start = p.start;
        s.end = p.end;
        s.name = p.name;
        s.color = p.color;
        s.breakMinutes = p.breakMinutes;
        ne.shifts.push(s);
      }
      return;
    }
    const cap = rules.maxContinuousWorkMinutes > 0
      ? Math.min(duration, rules.maxContinuousWorkMinutes)
      : duration;
    const restGap = rules.maxContinuousWorkMinutes > 0 ? Math.max(rules.mandatoryRestMinutes, 0) : 0;
    // 计算所需跨度；9:00 开始放不下就提前开始，确保当天内完成，不产生凌晨时段
    const segCount = cap > 0 ? Math.ceil(duration / cap) : 1;
    const span = duration + Math.max(0, segCount - 1) * restGap;
    let cursor = 9 * 60;
    if (cursor + span > 1440) {
      cursor = Math.max(0, 1440 - span); // 最早提前到 0:00，最晚 24:00 结束
    }
    let remaining = duration;
    while (remaining > 0) {
      const dur = Math.min(cap, remaining);
      const startMin = cursor % 1440;
      let endMin = cursor + dur;
      if (endMin > 1440) {
        endMin = 1440; // 任何段都不超过当天 24:00
      }
      const s = new Shift();
      s.start = `${pad2(Math.floor(startMin / 60))}:${pad2(startMin % 60)}`;
      s.end = `${pad2(Math.floor(endMin / 60))}:${pad2(endMin % 60)}`;
      ne.shifts.push(s);
      remaining -= dur;
      cursor = cursor + dur + restGap;
      if (cursor >= 1440) {
        break; // 当天已排满，剩余时长放弃
      }
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
      // 拒绝超 23 点的时间（如 27:00）
      const sh = Number(start.split(':')[0]);
      const eh = Number(end.split(':')[0]);
      if (Number.isNaN(sh) || Number.isNaN(eh) || sh > 23 || eh > 23) {
        return [];
      }
      result.push([start, end]);
    }
    return result;
  }

  // 老数据一次性迁移：把固定班次模板转换成一个「用于自动排班」的预设
  // 多段模板取首段开始/末段结束，中间空档折算为休息时长，工时语义不变
  private migrateTemplateToPreset(): void {
    if (this.prefs === null) {
      return;
    }
    const migrated = this.prefs.getSync('template_migrated_v1', false) as boolean;
    if (migrated) {
      return;
    }
    const rulesJson = this.prefs.getSync(KEY_RULES, '') as string;
    let template = '';
    if (rulesJson !== '') {
      try {
        const raw = JSON.parse(rulesJson) as Record<string, string>;
        template = typeof raw['shiftTemplate'] === 'string' ? raw['shiftTemplate'] : '';
      } catch (e) {
        template = '';
      }
    }
    const segs = this.parseShiftTemplate(template);
    if (segs.length > 0) {
      const first = segs[0];
      const last = segs[segs.length - 1];
      let breakMinutes = 0;
      if (segs.length > 1) {
        breakMinutes = Math.max(0, Shift.minutesBetween(last[0]) - Shift.minutesBetween(first[1]));
      }
      const preset = new PresetShift();
      preset.id = `p_template_${Date.now()}`;
      preset.name = this.str($r('app.string.preset_migrated'));
      preset.color = PRESET_COLORS[6];
      preset.start = first[0];
      preset.end = last[1];
      preset.breakMinutes = breakMinutes;
      preset.autoFill = true;
      const presets = this.getPresets();
      presets.push(preset);
      this.prefs.putSync(KEY_PRESETS, JSON.stringify(presets));
      // 重写规则存储，去掉已废弃的 shiftTemplate 字段
      this.saveRules(this.getRules());
    }
    this.prefs.putSync('template_migrated_v1', true);
    this.prefs.flush();
  }

  // 按日期区间（如 7 天）自动排班：跳过已有班次/手动休息/固定休息日，遵守连续上限；
  // 剩余目标工时按区间内可排天数均摊，天数不够排时单日自动往上加；返回排的天数
  autoFillRange(days: DayEntry[], start: string, end: string, rules: ShiftRules, presetId: string = ''): number {
    const dailyMin = (rules.minWorkHoursPerDay > 0 ? rules.minWorkHoursPerDay : 8) * 60;
    const target = rules.monthlyTargetHours * 60;
    // 区间内已有班次工时
    let worked = 0;
    let probe = start;
    while (probe <= end) {
      worked += this.dayMinutesOnDate(days, probe);
      probe = this.addDays(probe, 1);
    }
    const remain = Math.max(0, target - worked);
    // 第一遍：确定实际要排的天（跳过固定休息日/手动休息/连续上限强制休息），
    // 均摊分母只用真实可排天数，避免最少工时被当成实际上限
    const fillDays: string[] = [];
    let sinceRest = this.consecutiveWorkDaysEnding(days, this.addDays(start, -1));
    let cur = start;
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
      if (entry !== undefined) {
        sinceRest = 0; // 手动标记的休息日，保留
        cur = this.addDays(cur, 1);
        continue;
      }
      if (rules.maxConsecutiveWorkDays > 0 && sinceRest >= rules.maxConsecutiveWorkDays) {
        sinceRest = 0; // 达到连续上限，当天强制休息
        cur = this.addDays(cur, 1);
        continue;
      }
      fillDays.push(cur);
      sinceRest++;
      cur = this.addDays(cur, 1);
    }
    if (remain === 0 || fillDays.length === 0) {
      return 0;
    }
    // 每日最少工时是下限：天数不够排时单日自动往上加，尽快凑够目标
    const perDay = Math.min(Math.max(dailyMin, Math.ceil(remain / fillDays.length)), 16 * 60);
    let filled = 0;
    for (const day of fillDays) {
      if (worked >= target) {
        break; // 目标工时已够
      }
      const ne = (() => {
        const e = this.findEntry(days, day);
        if (e !== undefined) {
          return e;
        }
        const created = new DayEntry();
        created.date = day;
        days.push(created);
        return created;
      })();
      this.fillShiftsForDay(ne, perDay, rules, presetId);
      worked += perDay;
      filled++;
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
