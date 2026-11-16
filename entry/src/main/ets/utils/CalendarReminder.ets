// 将班次写入系统日历 / 发布系统闹钟提醒
import calendarManager from '@ohos.calendarManager';
import reminderAgentManager from '@ohos.reminderAgentManager';
import notificationManager from '@ohos.notificationManager';
import { abilityAccessCtrl, bundleManager, Permissions, common } from '@kit.AbilityKit';
import { AlarmSpec, DayEntry, Shift, shiftCrossesDay } from '../model/ScheduleTypes';
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

// 发布提醒的核心实现，返回系统提醒 ID（失败返回 -1）
async function publishShiftAlarm(context: common.UIAbilityContext, date: string, shift: Shift,
  leadMinutes: number): Promise<number> {
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
      snoozeSlotType: notificationManager.SlotType.CONTENT_INFORMATION,
      slotType: notificationManager.SlotType.CONTENT_INFORMATION
    };
    if (settings.snoozeEnabled) {
      reminder.actionButton = [closeButton, snoozeButton];
    } else {
      reminder.actionButton = [closeButton];
    }
    return await reminderAgentManager.publishReminder(reminder);
  } catch (e) {
    console.error('publishReminder failed:', JSON.stringify(e));
    return -1;
  }
}

// 发布系统提醒（班次开始时间提前 leadMinutes 分钟响铃，日历型一次性提醒）并登记到注册表
// PUBLISH_AGENT_REMINDER 为安装即授予的权限，无需也不能动态申请
export async function addShiftAlarm(context: common.UIAbilityContext, date: string, shift: Shift,
  leadMinutes: number): Promise<boolean> {
  const id = await publishShiftAlarm(context, date, shift, leadMinutes);
  if (id < 0) {
    return false;
  }
  const spec = new AlarmSpec();
  spec.date = date;
  spec.name = shift.name;
  spec.start = shift.start;
  spec.end = shift.end;
  spec.leadMinutes = leadMinutes;
  spec.reminderId = id;
  ScheduleService.getInstance().addAlarmSpec(spec);
  return true;
}

// 设置变化时同步全部已添加提醒：取消现有的，按登记表用新设置重建
// 本 SDK 的 ReminderRequest 类型未暴露 id，运行时系统返回的对象带有已发布提醒的 id
export interface ReminWithId extends reminderAgentManager.ReminderRequest {
  id?: number;
}

// 取消本应用全部有效提醒
async function cancelAllReminders(): Promise<void> {
  const valid = await reminderAgentManager.getValidReminders();
  for (const r of valid) {
    const withId = r as ReminWithId;
    if (withId.id !== undefined) {
      await reminderAgentManager.cancelReminder(withId.id);
    }
  }
}

// 设置变化时同步全部已添加提醒：取消现有的，按登记表用新设置重建
export async function resyncAlarms(context: common.UIAbilityContext): Promise<void> {
  try {
    const registry = ScheduleService.getInstance().getAlarmRegistry();
    await cancelAllReminders();
    for (const spec of registry) {
      const shift = new Shift();
      shift.name = spec.name;
      shift.start = spec.start;
      shift.end = spec.end;
      await addShiftAlarm(context, spec.date, shift, spec.leadMinutes);
    }
  } catch (e) {
    console.error('resyncAlarms failed:', JSON.stringify(e));
  }
}

// 日程变化后同步：登记的日期已无班次/时间改变时，取消旧提醒并按当前日程重建
export async function syncAlarmsWithSchedule(context: common.UIAbilityContext): Promise<void> {
  try {
    const service = ScheduleService.getInstance();
    const specs = service.getAlarmRegistry();
    if (specs.length === 0) {
      return;
    }
    const days = service.getDays();
    // 检查登记的提醒是否与当前日程一致（日期仍有该时间的班次）
    let changed = false;
    for (const spec of specs) {
      const entry = days.find((d: DayEntry) => d.date === spec.date);
      const stillThere = entry !== undefined && entry.shifts.length > 0 &&
        entry.shifts.some((s: Shift) => s.start === spec.start && s.end === spec.end);
      if (!stillThere) {
        changed = true;
        break;
      }
    }
    if (!changed) {
      return;
    }
    // 全量重建：按日期沿用首次登记的提前量，只为仍有班次的日期重建
    const leadByDate = new Map<string, number>();
    for (const spec of specs) {
      if (!leadByDate.has(spec.date)) {
        leadByDate.set(spec.date, spec.leadMinutes);
      }
    }
    await cancelAllReminders();
    const next: AlarmSpec[] = [];
    for (const date of leadByDate.keys()) {
      const lead = leadByDate.get(date) as number;
      const entry = days.find((d: DayEntry) => d.date === date);
      if (entry === undefined || entry.shifts.length === 0) {
        continue; // 班次已删除，不再重建
      }
      for (const s of entry.shifts) {
        const id = await publishShiftAlarm(context, date, s, lead);
        if (id >= 0) {
          const spec = new AlarmSpec();
          spec.date = date;
          spec.name = s.name;
          spec.start = s.start;
          spec.end = s.end;
          spec.leadMinutes = lead;
          spec.reminderId = id;
          next.push(spec);
        }
      }
    }
    service.saveAlarmRegistry(next);
  } catch (e) {
    console.error('syncAlarmsWithSchedule failed:', JSON.stringify(e));
  }
}

// 叉叉删除：取消提醒并从登记表移除
export async function removeReminderById(reminderId: number): Promise<void> {
  try {
    if (reminderId >= 0) {
      await reminderAgentManager.cancelReminder(reminderId);
    }
    ScheduleService.getInstance().removeAlarmSpecById(reminderId);
  } catch (e) {
    console.error('removeReminderById failed:', JSON.stringify(e));
  }
}
