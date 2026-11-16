// 桌面服务卡片数据：FormExtensionAbility 与 App 共用，只读本地 preferences
// 卡片页面通过 @LocalStorageProp('payload') 收到 JSON 字符串后解析渲染
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { formBindingData, formProvider, formInfo } from '@kit.FormKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { DayEntry, Shift, dateKey, daysInMonth, minutesToHoursText, shiftAbsRange, shiftCrossesDay, unionMinutes } from '../model/ScheduleTypes';

const STORE_NAME = 'schedule_store';
const KEY_DAYS = 'schedule_days_v1';
const KEY_WEEK_START = 'calendar_week_start_v1';
const DEFAULT_COLOR = '#0A59F7';

export const FORM_TODAY = 'today_card';
export const FORM_WEEK = 'week_card';
export const FORM_MONTH = 'month_card';

class CardShift {
  name: string = '';
  time: string = '';
  hours: string = '';
  color: string = DEFAULT_COLOR;
}

class TodayPayload {
  rev: number = 0;
  badge: string = '';
  title: string = '';
  weekday: string = '';
  totalText: string = '';
  statusText: string = '';
  shifts: CardShift[] = [];
  extraCount: number = 0;
}

class WeekDayPayload {
  label: string = '';
  dateText: string = '';
  hoursText: string = '';
  nameText: string = '';
  isToday: boolean = false;
  isRest: boolean = false;
}

class WeekPayload {
  rev: number = 0;
  title: string = '';
  rangeText: string = '';
  totalText: string = '';
  days: WeekDayPayload[] = [];
}

class MonthCellPayload {
  dayText: string = '';
  hoursText: string = '';
  nameText: string = '';
  isToday: boolean = false;
  isRest: boolean = false;
}

class MonthPayload {
  rev: number = 0;
  title: string = '';
  weekLabels: string[] = [];
  rows: MonthCellPayload[][] = [];
  summaryText: string = '';
  totalText: string = '';
}

// 按资源名取文案：卡片扩展进程不依赖 $r，直接用 resourceManager
function readText(context: common.Context, name: string): string {
  try {
    return context.resourceManager.getStringByNameSync(name);
  } catch (e) {
    return '';
  }
}

function readText1(context: common.Context, name: string, a: string | number): string {
  try {
    return context.resourceManager.getStringByNameSync(name, a);
  } catch (e) {
    return '';
  }
}

function readText2(context: common.Context, name: string, a: string | number, b: string | number): string {
  try {
    return context.resourceManager.getStringByNameSync(name, a, b);
  } catch (e) {
    return '';
  }
}

function readPrefs(context: common.Context): preferences.Preferences | null {
  try {
    return preferences.getPreferencesSync(context, { name: STORE_NAME });
  } catch (e) {
    return null;
  }
}

function readDays(context: common.Context): DayEntry[] {
  const prefs = readPrefs(context);
  if (prefs === null) {
    return [];
  }
  try {
    const json = prefs.getSync(KEY_DAYS, '') as string;
    if (json === '') {
      return [];
    }
    const raw = JSON.parse(json) as DayEntry[];
    return Array.isArray(raw) ? raw : [];
  } catch (e) {
    return [];
  }
}

function readWeekStart(context: common.Context): number {
  const prefs = readPrefs(context);
  if (prefs === null) {
    return 0;
  }
  const value = prefs.getSync(KEY_WEEK_START, 0) as number;
  return value === 1 ? 1 : 0;
}

function findEntry(days: DayEntry[], date: string): DayEntry | undefined {
  for (const day of days) {
    if (day.date === date) {
      return day;
    }
  }
  return undefined;
}

function shiftMinutes(shift: Shift): number {
  const span = Shift.spanMinutes(shift.start, shift.end);
  const rest = typeof shift.breakMinutes === 'number' ? shift.breakMinutes : 0;
  return Math.max(0, span - Math.max(0, rest));
}

// 昨天的日期键
function prevDateKey(date: string): string {
  const parts = date.split('-');
  const d = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]) - 1);
  return dateKey(d.getFullYear(), d.getMonth() + 1, d.getDate());
}

// 某一天的实际在岗时长：当日班次该日部分 + 昨日跨天班次的尾巴，并集去重
function dayMinutesOnDate(days: DayEntry[], date: string): number {
  const intervals: number[][] = [];
  const own = findEntry(days, date);
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
  const prev = findEntry(days, prevDateKey(date));
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

function isRestEntry(entry: DayEntry | undefined): boolean {
  return entry !== undefined && (entry.shifts === undefined || entry.shifts.length === 0);
}

function firstName(entry: DayEntry, context: common.Context): string {
  if (entry.shifts !== undefined) {
    for (const shift of entry.shifts) {
      if (shift.name !== undefined && shift.name !== '') {
        return shift.name;
      }
    }
  }
  return readText(context, 'form_unnamed_shift');
}

export class FormCardData {
  private static refreshTimer: number = -1;
  private static refreshContext: common.Context | null = null;

  // 根据卡片名称构建对应数据（JSON 字符串）
  static build(context: common.Context, formName: string): string {
    if (formName === FORM_WEEK) {
      return FormCardData.buildWeek(context);
    }
    if (formName === FORM_MONTH) {
      return FormCardData.buildMonth(context);
    }
    return FormCardData.buildToday(context);
  }

  // App 内数据变化后调用：合并短时间内的多次变更，再统一刷新桌面卡片
  static requestRefresh(context: common.Context): void {
    FormCardData.refreshContext = context;
    if (FormCardData.refreshTimer >= 0) {
      clearTimeout(FormCardData.refreshTimer);
    }
    FormCardData.refreshTimer = setTimeout(() => {
      FormCardData.refreshTimer = -1;
      const ctx = FormCardData.refreshContext;
      if (ctx !== null) {
        FormCardData.refreshAll(ctx);
      }
    }, 800);
  }

  private static refreshAll(context: common.Context): void {
    try {
      formProvider.getPublishedRunningFormInfos().then((infos: formInfo.RunningFormInfo[]) => {
        for (const info of infos) {
          const payload = FormCardData.build(context, info.formName);
          if (payload === '') {
            continue;
          }
          const data: Record<string, string> = { 'payload': payload };
          formProvider.updateForm(info.formId, formBindingData.createFormBindingData(data))
            .catch((err: BusinessError) => {
              console.error('update card failed: ' + JSON.stringify(err));
            });
        }
      }).catch((err: BusinessError) => {
        console.error('get running forms failed: ' + JSON.stringify(err));
      });
    } catch (e) {
      console.error('refresh cards failed: ' + JSON.stringify(e));
    }
  }

  private static buildToday(context: common.Context): string {
    const days = readDays(context);
    const now = new Date();
    const todayKey = dateKey(now.getFullYear(), now.getMonth() + 1, now.getDate());
    const entry = findEntry(days, todayKey);
    const payload = new TodayPayload();
    payload.badge = readText(context, 'today_label');
    payload.title = readText2(context, 'form_month_day', now.getMonth() + 1, now.getDate());
    payload.weekday = readText(context, `form_weekday_${now.getDay()}`);
    const minutes = dayMinutesOnDate(days, todayKey);
    payload.totalText = minutesToHoursText(minutes);
    payload.rev = Date.now();
    if (entry !== undefined && entry.shifts !== undefined) {
      for (const shift of entry.shifts) {
        const item = new CardShift();
        item.name = shift.name !== undefined && shift.name !== ''
          ? shift.name : readText(context, 'form_unnamed_shift');
        item.time = `${shift.start}-${shiftCrossesDay(shift) ? readText(context, 'shift_next_day') + '-' : ''}${shift.end}`;
        item.hours = minutesToHoursText(shiftMinutes(shift));
        item.color = shift.color !== undefined && shift.color !== '' ? shift.color : DEFAULT_COLOR;
        payload.shifts.push(item);
      }
    }
    if (payload.shifts.length === 0) {
      payload.statusText = isRestEntry(entry)
        ? readText(context, 'form_rest_day')
        : readText(context, 'form_no_shift');
    }
    payload.extraCount = Math.max(0, payload.shifts.length - 2);
    return JSON.stringify(payload);
  }

  private static buildWeek(context: common.Context): string {
    const days = readDays(context);
    const weekStart = readWeekStart(context);
    const payload = new WeekPayload();
    payload.title = readText(context, 'form_week_title');
    const now = new Date();
    const todayKey = dateKey(now.getFullYear(), now.getMonth() + 1, now.getDate());
    const offset = (now.getDay() - weekStart + 7) % 7;
    const startDate = new Date(now.getFullYear(), now.getMonth(), now.getDate() - offset);
    const endDate = new Date(startDate.getFullYear(), startDate.getMonth(), startDate.getDate() + 6);
    payload.rangeText = `${startDate.getMonth() + 1}/${startDate.getDate()} - ${endDate.getMonth() + 1}/${endDate.getDate()}`;
    let totalMinutes = 0;
    for (let i = 0; i < 7; i++) {
      const date = new Date(startDate.getFullYear(), startDate.getMonth(), startDate.getDate() + i);
      const key = dateKey(date.getFullYear(), date.getMonth() + 1, date.getDate());
      const entry = findEntry(days, key);
      const minutes = dayMinutesOnDate(days, key);
      totalMinutes += minutes;
      const day = new WeekDayPayload();
      day.label = readText(context, `wd_${(weekStart + i) % 7}`);
      day.dateText = `${date.getMonth() + 1}/${date.getDate()}`;
      day.hoursText = minutes > 0 ? minutesToHoursText(minutes) : '';
      day.isToday = key === todayKey;
      day.isRest = isRestEntry(entry);
      if (entry !== undefined && entry.shifts !== undefined && entry.shifts.length > 0) {
        day.nameText = firstName(entry, context);
      } else if (day.isRest) {
        day.nameText = readText(context, 'rest_marker');
      }
      payload.days.push(day);
    }
    payload.totalText = minutesToHoursText(totalMinutes);
    payload.rev = Date.now();
    return JSON.stringify(payload);
  }

  private static buildMonth(context: common.Context): string {
    const days = readDays(context);
    const weekStart = readWeekStart(context);
    const now = new Date();
    const year = now.getFullYear();
    const month = now.getMonth() + 1;
    const todayKey = dateKey(year, month, now.getDate());
    const payload = new MonthPayload();
    payload.title = readText2(context, 'month_title', year, month);
    for (let i = 0; i < 7; i++) {
      payload.weekLabels.push(readText(context, `wd_${(weekStart + i) % 7}`));
    }

    const first = new Date(year, month - 1, 1);
    const blanks = (first.getDay() - weekStart + 7) % 7;
    const totalDays = daysInMonth(year, month);
    let row: MonthCellPayload[] = [];
    let totalMinutes = 0;
    let workDays = 0;
    let restDays = 0;

    for (let i = 0; i < blanks; i++) {
      row.push(new MonthCellPayload());
      if (row.length === 7) {
        payload.rows.push(row);
        row = [];
      }
    }

    for (let d = 1; d <= totalDays; d++) {
      const key = dateKey(year, month, d);
      const entry = findEntry(days, key);
      const minutes = dayMinutesOnDate(days, key);
      const cell = new MonthCellPayload();
      cell.dayText = `${d}`;
      cell.isToday = key === todayKey;
      cell.isRest = isRestEntry(entry);
      if (minutes > 0) {
        workDays++;
        totalMinutes += minutes;
        cell.hoursText = minutesToHoursText(minutes);
      }
      if (cell.isRest) {
        restDays++;
        cell.nameText = readText(context, 'rest_marker');
      } else if (entry !== undefined && entry.shifts !== undefined && entry.shifts.length > 0) {
        cell.nameText = firstName(entry, context);
      }
      row.push(cell);
      if (row.length === 7) {
        payload.rows.push(row);
        row = [];
      }
    }

    if (row.length > 0) {
      while (row.length < 7) {
        row.push(new MonthCellPayload());
      }
      payload.rows.push(row);
    }

    payload.summaryText = readText2(context, 'form_month_summary', workDays, restDays);
    payload.totalText = minutesToHoursText(totalMinutes);
    payload.rev = Date.now();
    return JSON.stringify(payload);
  }
}
