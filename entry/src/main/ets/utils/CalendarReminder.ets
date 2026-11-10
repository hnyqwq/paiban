// 将班次写入系统日历 / 发布系统闹钟提醒
import calendarManager from '@ohos.calendarManager';
import reminderAgentManager from '@ohos.reminderAgentManager';
import { abilityAccessCtrl, Permissions, common } from '@kit.AbilityKit';
import { Shift } from '../model/ScheduleTypes';

class ShiftTimeRange {
  startMs: number = 0;
  endMs: number = 0;
}

// 按需申请权限，全部授权返回 true
async function ensurePermissions(context: common.UIAbilityContext, perms: Array<Permissions>): Promise<boolean> {
  try {
    const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
    const result = await atManager.requestPermissionsFromUser(context, perms);
    const authResults: number[] = result.authResults;
    for (const r of authResults) {
      if (r !== 0) {
        return false;
      }
    }
    return true;
  } catch (e) {
    return false;
  }
}

// 班次起止时间（跨天时结束时间加一天）
function shiftTimes(date: string, shift: Shift): ShiftTimeRange {
  const range = new ShiftTimeRange();
  const parts = date.split('-');
  const y = Number(parts[0]);
  const m = Number(parts[1]);
  const d = Number(parts[2]);
  const s = Shift.minutesBetween(shift.start);
  const e = Shift.minutesBetween(shift.end);
  const endDay = e <= s ? d + 1 : d;
  range.startMs = new Date(y, m - 1, d, Math.floor(s / 60), s % 60, 0).getTime();
  range.endMs = new Date(y, m - 1, endDay, Math.floor(e / 60), e % 60, 0).getTime();
  return range;
}

// 写入系统日历
export async function addShiftToCalendar(context: common.UIAbilityContext, date: string, shift: Shift): Promise<boolean> {
  const ok = await ensurePermissions(context,
    ['ohos.permission.READ_CALENDAR', 'ohos.permission.WRITE_CALENDAR']);
  if (!ok) {
    return false;
  }
  try {
    const range = shiftTimes(date, shift);
    const manager: calendarManager.CalendarManager = calendarManager.getCalendarManager(context);
    const calendars: calendarManager.Calendar[] = await manager.getAllCalendars();
    if (calendars.length === 0) {
      return false;
    }
    // 去重：任一日历中已存在同标题且同开始时间的事件则跳过；
    // 手动删除后查询不到，即可重新添加
    for (const cal of calendars) {
      const existing: calendarManager.Event[] = await cal.queryEventInstances(range.startMs, range.endMs);
      for (const ev of existing) {
        if (ev.title === '上班' && ev.startTime === range.startMs) {
          return true;
        }
      }
    }
    const cal = calendars[0];
    const event: calendarManager.Event = {
      type: calendarManager.EventType.NORMAL,
      title: '上班',
      description: `${shift.start} - ${shift.end}`,
      startTime: range.startMs,
      endTime: range.endMs
    };
    await cal.addEvent(event);
    return true;
  } catch (e) {
    return false;
  }
}

// 发布系统提醒（班次开始时间提前 leadMinutes 分钟响铃，日历型一次性提醒）
// PUBLISH_AGENT_REMINDER 为安装即授予的权限，无需也不能动态申请
export async function addShiftAlarm(context: common.UIAbilityContext, date: string, shift: Shift,
  leadMinutes: number): Promise<boolean> {
  try {
    const parts = date.split('-');
    const y = Number(parts[0]);
    const m = Number(parts[1]);
    const d = Number(parts[2]);
    const s0 = Shift.minutesBetween(shift.start) - leadMinutes;
    // 提前量可能把提醒时间推到前一天
    let minutes = s0;
    let remindDay = d;
    if (minutes < 0) {
      minutes += 24 * 60;
      remindDay = d - 1;
    }
    const dt = new Date(y, m - 1, remindDay, 0, 0, 0);
    const dateTime: reminderAgentManager.LocalDateTime = {
      year: dt.getFullYear(),
      month: dt.getMonth() + 1,
      day: dt.getDate(),
      hour: Math.floor(minutes / 60),
      minute: minutes % 60
    };
    const reminder: reminderAgentManager.ReminderRequestCalendar = {
      reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR,
      dateTime: dateTime,
      title: leadMinutes > 0 ? `上班提醒（提前${leadMinutes}分钟）` : '上班提醒',
      content: `${shift.start} - ${shift.end}`,
      expiredContent: '已过上班时间'
    };
    await reminderAgentManager.publishReminder(reminder);
    return true;
  } catch (e) {
    console.error('publishReminder failed:', JSON.stringify(e));
    return false;
  }
}
