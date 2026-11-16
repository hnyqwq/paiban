// 将班次写入系统日历 / 发布系统闹钟提醒
import calendarManager from '@ohos.calendarManager';
import reminderAgentManager from '@ohos.reminderAgentManager';
import notificationManager from '@ohos.notificationManager';
import { abilityAccessCtrl, bundleManager, Permissions, common } from '@kit.AbilityKit';
import { Shift, shiftCrossesDay } from '../model/ScheduleTypes';
import { ScheduleService } from '../service/ScheduleService';

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
    // 事件标题资源化（zh「上班」/ en「Work」），去重比对也用同一标题
    let eventTitle = 'Work';
    try {
      eventTitle = context.resourceManager.getStringByNameSync('calendar_event_title');
    } catch (e) {
      // 取不到文案就用默认
    }
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
        if (ev.title === eventTitle && ev.startTime === range.startMs) {
          return true;
        }
      }
    }
    const cal = calendars[0];
    const namePrefix = shift.name !== '' ? `${shift.name} ` : '';
    let endText = shift.end;
    if (shiftCrossesDay(shift)) {
      try {
        endText = `${context.resourceManager.getStringByNameSync('shift_next_day')} ${shift.end}`;
      } catch (e) {
        // 取不到文案就用原样
      }
    }
    const event: calendarManager.Event = {
      type: calendarManager.EventType.NORMAL,
      title: eventTitle,
      description: `${namePrefix}${shift.start} - ${endText}`,
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
    // 文档要求：publishReminder 前必须先获得通知授权（未启用时返回 1700001）
    const enabled = await notificationManager.isNotificationEnabled();
    if (!enabled) {
      await notificationManager.requestEnableNotification(context);
    }
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
    // 文案按应用当前语言取（标题/过期/贪睡）
    const text = (name: string, a?: number): string => {
      try {
        if (a === undefined) {
          return context.resourceManager.getStringByNameSync(name);
        }
        return context.resourceManager.getStringByNameSync(name, a);
      } catch (e) {
        return '';
      }
    };
    const settings = ScheduleService.getInstance().getAlarmSettings();
    // 提醒按钮：关闭必带，开启贪睡时追加贪睡按钮（actionButton 为固定三元组，最多 3 个）
    const closeButton: reminderAgentManager.ActionButton = {
      title: text('alarm_btn_close'),
      type: reminderAgentManager.ActionButtonType.ACTION_BUTTON_TYPE_CLOSE
    };
    const snoozeButton: reminderAgentManager.ActionButton = {
      title: text('alarm_btn_snooze'),
      type: reminderAgentManager.ActionButtonType.ACTION_BUTTON_TYPE_SNOOZE
    };
    const title = leadMinutes > 0 ? text('alarm_title_lead', leadMinutes) : text('alarm_title');
    // 点击提醒跳转回应用（参数 page=schedule）
    let wantAgent: reminderAgentManager.WantAgent | undefined = undefined;
    if (settings.wantAgentEnabled) {
      const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      wantAgent = {
        pkgName: info.name,
        abilityName: 'EntryAbility',
        parameters: { page: 'schedule' }
      };
    }
    // 班次结束时间戳：开启自动删除时，班次结束后提醒自动移除
    const endMin = Shift.minutesBetween(shift.end);
    const shiftEndMs = new Date(y, m - 1, d).getTime() +
      (endMin + (shiftCrossesDay(shift) ? 24 * 60 : 0)) * 60 * 1000;
    const reminder: reminderAgentManager.ReminderRequestCalendar = {
      reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR,
      dateTime: dateTime,
      title: title,
      content: `${shift.start} - ${shift.end}`,
      expiredContent: text('alarm_expired'),
      snoozeContent: text('alarm_snooze_content'),
      ringDuration: settings.ringDuration,
      snoozeTimes: settings.snoozeEnabled ? settings.snoozeTimes : 0,
      timeInterval: settings.timeInterval * 60, // 分钟 → 秒
      wantAgent: wantAgent,
      groupId: 'schedule_alarms',
      // 通知 ID 按日期 + 班次起始时间生成，避免同班次重复通知叠加
      notificationId: (y % 100) * 100000000 + m * 1000000 + d * 10000 + Math.floor(Shift.minutesBetween(shift.start) % 10000),
      tapDismissed: settings.tapDismissed,
      autoDeletedTime: settings.autoDeleteEnabled ? shiftEndMs : 0,
      customRingUri: settings.customRingUri !== '' ? settings.customRingUri : undefined,
      snoozeSlotType: notificationManager.SlotType.CONTENT_INFORMATION,
      slotType: notificationManager.SlotType.CONTENT_INFORMATION
    };
    if (settings.snoozeEnabled) {
      reminder.actionButton = [closeButton, snoozeButton];
    } else {
      reminder.actionButton = [closeButton];
    }
    await reminderAgentManager.publishReminder(reminder);
    return true;
  } catch (e) {
    console.error('publishReminder failed:', JSON.stringify(e));
    return false;
  }
}
