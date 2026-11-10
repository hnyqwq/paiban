// 工具页：排班与提醒的批量操作集中在此
import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import {
  DayEntry, Shift, ShiftRules, MonthStats,
  dateKey, daysInMonth, minutesToHoursText
} from '../model/ScheduleTypes';
import { ScheduleService } from '../service/ScheduleService';
import { addShiftToCalendar, addShiftAlarm } from '../utils/CalendarReminder';
import { CalendarView } from '../view/CalendarView';

class DateShift {
  date: string = '';
  shift: Shift = new Shift();
}

@Component
export struct ToolsPage {
  scroller: Scroller = new Scroller();
  @State selDate: string = '';
  @State rules: ShiftRules = new ShiftRules();
  @State stats: MonthStats = new MonthStats();
  @StorageLink('scheduleDataVersion') @Watch('onDataChanged') scheduleDataVersion: number = 0;
  @StorageLink('rulesChanged') @Watch('onRulesChanged') rulesChanged: number = 0;
  private service: ScheduleService = ScheduleService.getInstance();

  aboutToAppear(): void {
    const now = new Date();
    this.selDate = dateKey(now.getFullYear(), now.getMonth() + 1, now.getDate());
    this.rules = this.service.getRules();
    this.refreshStats();
  }

  onDataChanged(): void {
    this.refreshStats();
  }

  onRulesChanged(): void {
    this.rules = this.service.getRules();
    this.refreshStats();
  }

  refreshStats(): void {
    const now = new Date();
    this.stats = this.service.computeStats(this.service.getDays(),
      now.getFullYear(), now.getMonth() + 1, this.rules);
  }

  // 保存并通知各页面刷新
  saveDays(days: DayEntry[]): void {
    this.service.saveDays(days);
    AppStorage.setOrCreate('scheduleDataVersion', Date.now());
  }

  dateFromPicker(d: Date): string {
    return dateKey(d.getFullYear(), d.getMonth() + 1, d.getDate());
  }

  addOneDay(date: string): string {
    const dt = new Date(date + 'T00:00:00');
    dt.setDate(dt.getDate() + 1);
    return this.dateFromPicker(dt);
  }

  pickDate(selected: Date, onAccept: (date: string) => void): void {
    this.getUIContext().showDatePickerDialog({
      start: new Date(2000, 0, 1),
      end: new Date(2100, 11, 31),
      selected: selected,
      onDateAccept: (value: Date) => {
        onAccept(this.dateFromPicker(value));
      }
    });
  }

  pickRange(onAccept: (start: string, end: string) => void): void {
    const now = new Date();
    this.pickDate(new Date(now.getFullYear(), now.getMonth(), 1), (start: string) => {
      this.pickDate(new Date(start + 'T00:00:00'), (end: string) => {
        if (end < start) {
          return;
        }
        onAccept(start, end);
      });
    });
  }

  syncMonth(): void {
    const now = new Date();
    this.getUIContext().showDatePickerDialog({
      start: new Date(2000, 0, 1),
      end: new Date(2100, 11, 31),
      selected: new Date(now.getFullYear(), now.getMonth() + 1, 1),
      mode: DatePickerMode.YEAR_AND_MONTH,
      onDateAccept: (value: Date) => {
        this.getUIContext().showAlertDialog({
          title: $r('app.string.sync_confirm_title'),
          message: $r('app.string.sync_confirm_msg'),
          autoCancel: true,
          buttons: [
            { value: $r('app.string.cancel'), fontColor: $r('sys.color.font_secondary'), action: () => {} },
            {
              value: $r('app.string.btn_clear'),
              fontColor: $r('sys.color.brand'),
              action: () => {
                const days = this.service.getDays();
                const n = this.service.copyMonthTo(days, now.getFullYear(), now.getMonth() + 1,
                  value.getFullYear(), value.getMonth() + 1);
                this.saveDays(days);
                promptAction.showToast({ message: $r('app.string.copied_sync', n) });
              }
            }
          ]
        });
      }
    });
  }

  autoFillMonth(): void {
    this.getUIContext().showAlertDialog({
      title: $r('app.string.auto_confirm_title'),
      message: $r('app.string.auto_confirm_msg'),
      autoCancel: true,
      buttons: [
        { value: $r('app.string.cancel'), fontColor: $r('sys.color.font_secondary'), action: () => {} },
        {
          value: $r('app.string.btn_clear'),
          fontColor: $r('sys.color.brand'),
          action: () => {
            const now = new Date();
            const days = this.service.getDays();
            const n = this.service.autoFillMonth(days, now.getFullYear(), now.getMonth() + 1, this.rules);
            this.saveDays(days);
            promptAction.showToast({ message: $r('app.string.auto_filled', n) });
          }
        }
      ]
    });
  }

  rangeAuto(): void {
    this.pickRange((start: string, end: string) => {
      const days = this.service.getDays();
      const n = this.service.autoFillRange(days, start, end, this.rules);
      this.saveDays(days);
      promptAction.showToast({ message: $r('app.string.range_filled', n) });
    });
  }

  rangeCopy(): void {
    this.pickDate(new Date(), (srcStart: string) => {
      this.pickDate(new Date(srcStart + 'T00:00:00'), (srcEnd: string) => {
        if (srcEnd < srcStart) {
          return;
        }
        this.pickDate(new Date(srcEnd + 'T00:00:00'), (dstStart: string) => {
          const days = this.service.getDays();
          const n = this.service.copyRangeTo(days, srcStart, srcEnd, dstStart);
          this.saveDays(days);
          promptAction.showToast({ message: $r('app.string.range_copied', n) });
        });
      });
    });
  }

  copyDay(): void {
    this.pickDate(new Date(), (src: string) => {
      this.pickDate(new Date(src + 'T00:00:00'), (dst: string) => {
        const days = this.service.getDays();
        if (this.service.copyDayTo(days, src, dst)) {
          this.saveDays(days);
          promptAction.showToast({ message: $r('app.string.copy_day_done') });
        } else {
          promptAction.showToast({ message: $r('app.string.copy_day_done') });
        }
      });
    });
  }

  // 区间内所有班次（批量加闹钟/日历共用的遍历）
  shiftsInRange(start: string, end: string): DateShift[] {
    const days = this.service.getDays();
    const result: DateShift[] = [];
    let cur = start;
    while (cur <= end) {
      const entry = this.service.findEntry(days, cur);
      if (entry !== undefined) {
        for (const s of entry.shifts) {
          const ds = new DateShift();
          ds.date = cur;
          ds.shift = s;
          result.push(ds);
        }
      }
      cur = this.addOneDay(cur);
    }
    return result;
  }

  batchAlarm(start: string, end: string): void {
    const targets = this.shiftsInRange(start, end);
    if (targets.length === 0) {
      promptAction.showToast({ message: $r('app.string.no_shifts_in_range') });
      return;
    }
    const ctx = AppStorage.get<common.UIAbilityContext>('context');
    if (ctx === undefined) {
      return;
    }
    const leads: number[] = [0, 30, 60, 120];
    const labels: Resource[] = [$r('app.string.alarm_lead_none'), $r('app.string.alarm_lead_30'),
      $r('app.string.alarm_lead_60'), $r('app.string.alarm_lead_120')];
    promptAction.showActionMenu({
      title: $r('app.string.alarm_lead_title'),
      buttons: [
        { text: labels[0], color: '#0A59F7' },
        { text: labels[1], color: '#0A59F7' },
        { text: labels[2], color: '#0A59F7' },
        { text: labels[3], color: '#0A59F7' }
      ]
    }).then((res: promptAction.ActionMenuSuccessResponse) => {
      if (res.index < 0 || res.index >= leads.length) {
        return;
      }
      let ok = 0;
      let last: Promise<void> = Promise.resolve();
      for (const t of targets) {
        last = last.then(() => {
          return addShiftAlarm(ctx, t.date, t.shift, leads[res.index]).then((success: boolean) => {
            if (success) {
              ok++;
            }
          });
        });
      }
      last.then(() => {
        promptAction.showToast({ message: $r('app.string.batch_added', ok) });
      });
    });
  }

  batchCalendar(start: string, end: string): void {
    const targets = this.shiftsInRange(start, end);
    if (targets.length === 0) {
      promptAction.showToast({ message: $r('app.string.no_shifts_in_range') });
      return;
    }
    const ctx = AppStorage.get<common.UIAbilityContext>('context');
    if (ctx === undefined) {
      return;
    }
    let ok = 0;
    let last: Promise<void> = Promise.resolve();
    for (const t of targets) {
      last = last.then(() => {
        return addShiftToCalendar(ctx, t.date, t.shift).then((success: boolean) => {
          if (success) {
            ok++;
          }
        });
      });
    }
    last.then(() => {
      promptAction.showToast({ message: $r('app.string.batch_added', ok) });
    });
  }

  @Builder
  toolButton(label: Resource, action: () => void) {
    Button(label)
      .buttonStyle(ButtonStyleMode.NORMAL)
      .fontSize(13)
      .width('100%')
      .margin({ top: 8 })
      .onClick(() => action())
  }

  @Builder
  sectionTitle(title: Resource) {
    Text(title)
      .fontSize(13)
      .fontColor($r('sys.color.font_tertiary'))
      .width('100%')
      .margin({ top: 16, bottom: 6 })
  }

  build() {
    Scroll(this.scroller) {
      Column() {
        CalendarView({ selectedDate: $selDate })

        this.sectionTitle($r('app.string.tools_section_overview'))
        Column() {
          Row() {
            Text($r('app.string.progress_done', minutesToHoursText(this.stats.workedMinutes), this.rules.monthlyTargetHours))
              .fontSize(13)
            Blank()
            Text($r('app.string.progress_need', minutesToHoursText(this.stats.remainingMinutes)))
              .fontSize(13)
              .fontColor($r('sys.color.brand'))
              .fontWeight(FontWeight.Medium)
          }
          .width('100%')

          Progress({ value: this.stats.workedMinutes, total: Math.max(this.stats.targetMinutes, 1), type: ProgressType.Linear })
            .width('100%')
            .margin({ top: 8 })

          if (this.stats.violations.length > 0) {
            Text($r('app.string.rule_reminders'))
              .fontSize(12)
              .fontColor($r('sys.color.warning'))
              .margin({ top: 10 })
            ForEach(this.stats.violations, (v: string) => {
              Text(v)
                .fontSize(12)
                .fontColor($r('sys.color.font_secondary'))
                .margin({ top: 2 })
            }, (v: string) => v)
          }
        }
        .width('100%')
        .padding(12)
        .borderRadius(12)
        .backgroundColor($r('sys.color.background_primary'))
        .border({ width: 0.5, color: $r('sys.color.comp_divider') })

        this.sectionTitle($r('app.string.tools_section_schedule'))
        Column() {
          this.toolButton($r('app.string.sync_to_month'), (): void => this.syncMonth())
          this.toolButton($r('app.string.range_copy'), (): void => this.rangeCopy())
          this.toolButton($r('app.string.copy_day'), (): void => this.copyDay())
          this.toolButton($r('app.string.range_auto'), (): void => this.rangeAuto())
          this.toolButton($r('app.string.auto_fill'), (): void => this.autoFillMonth())
        }
        .width('100%')
        .padding(12)
        .borderRadius(12)
        .backgroundColor($r('sys.color.background_primary'))
        .border({ width: 0.5, color: $r('sys.color.comp_divider') })

        this.sectionTitle($r('app.string.tools_section_remind'))
        Column() {
          this.toolButton($r('app.string.batch_alarm'), (): void => {
            this.pickRange((start: string, end: string) => this.batchAlarm(start, end));
          })
          this.toolButton($r('app.string.batch_calendar'), (): void => {
            this.pickRange((start: string, end: string) => this.batchCalendar(start, end));
          })
        }
        .width('100%')
        .padding(12)
        .borderRadius(12)
        .backgroundColor($r('sys.color.background_primary'))
        .border({ width: 0.5, color: $r('sys.color.comp_divider') })

        Text('')
          .height(100)
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 110 })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .align(Alignment.Top)
    .backgroundColor($r('sys.color.background_secondary'))
  }
}
