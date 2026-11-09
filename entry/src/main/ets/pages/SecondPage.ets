// 第二页：排班统计
import {
  MonthStats, ShiftRules, dateKey, minutesToHoursText
} from '../model/ScheduleTypes';
import { ScheduleService } from '../service/ScheduleService';

@Component
export struct SecondPage {  scroller: Scroller = new Scroller();
  @State viewYear: number = 2025;
  @State viewMonth: number = 1;
  @State stats: MonthStats = new MonthStats();
  @State rules: ShiftRules = new ShiftRules();
  @StorageLink('dataCleared') @Watch('onDataCleared') dataCleared: number = 0;

  onDataCleared(): void {
    this.refresh();
  }
  private service: ScheduleService = ScheduleService.getInstance();

  aboutToAppear(): void {
    const now = new Date();
    this.viewYear = now.getFullYear();
    this.viewMonth = now.getMonth() + 1;
    this.rules = this.service.getRules();
    this.refresh();
  }

  refresh(): void {
    this.stats = this.service.computeStats(this.service.getDays(), this.viewYear, this.viewMonth, this.rules);
  }

  changeMonth(delta: number): void {
    let m = this.viewMonth + delta;
    let y = this.viewYear;
    if (m < 1) {
      m = 12;
      y--;
    } else if (m > 12) {
      m = 1;
      y++;
    }
    this.viewYear = y;
    this.viewMonth = m;
    this.refresh();
  }

  // 点击标题弹出年月选择器（官方 YEAR_AND_MONTH 模式，仅年、月两列）
  showMonthPicker(): void {
    this.getUIContext().showDatePickerDialog({
      start: new Date(2000, 0, 1),
      end: new Date(2100, 11, 31),
      selected: new Date(this.viewYear, this.viewMonth - 1, 1),
      mode: DatePickerMode.YEAR_AND_MONTH,
      onDateAccept: (value: Date) => {
        this.viewYear = value.getFullYear();
        this.viewMonth = value.getMonth() + 1;
        this.refresh();
      }
    });
  }

  // 每日工时柱状图的最大值（小时）
  maxDailyHours(): number {
    let max = 0;
    for (const m of this.stats.dailyMinutes) {
      if (m > max) {
        max = m;
      }
    }
    return Math.max(Math.ceil(max / 60), 8);
  }

  @Builder
  statCard(title: Resource | string, value: Resource | string, sub: Resource | string) {
    Column() {
      Text(title)
        .fontSize(12)
        .fontColor($r('sys.color.font_secondary'))
      Text(value)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .margin({ top: 4 })
      Text(sub)
        .fontSize(11)
        .fontColor($r('sys.color.font_tertiary'))
        .margin({ top: 2 })
    }
    .layoutWeight(1)
    .padding(12)
    .borderRadius(12)
    .backgroundColor($r('sys.color.background_primary'))
    .border({ width: 0.5, color: $r('sys.color.comp_divider') })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  ringCard() {
    Column() {
      Stack() {
        Progress({ value: this.stats.workedMinutes, total: Math.max(this.stats.targetMinutes, 1), type: ProgressType.Ring })
          .width(120)
          .height(120)
          .style({ strokeWidth: 10 })
        Column() {
          Text(`${Math.round(this.stats.workedMinutes / 60)}h`)
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
          Text(`/ ${this.rules.monthlyTargetHours}h`)
            .fontSize(12)
            .fontColor($r('sys.color.font_tertiary'))
        }
      }
      Text(this.viewYear + ' / ' + this.viewMonth)
        .fontSize(13)
        .margin({ top: 8 })
    }
    .width('100%')
    .padding(16)
    .borderRadius(12)
    .backgroundColor($r('sys.color.background_primary'))
    .border({ width: 0.5, color: $r('sys.color.comp_divider') })
  }

  @Builder
  barChart() {
    Column() {
      Text($r('app.string.daily_chart'))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .width('100%')
      Row() {
        ForEach(this.stats.dailyMinutes.slice(1), (m: number, i: number) => {
          Column() {
            Blank()
            Column()
              .width('70%')
              .height(Math.max(m / 60 / this.maxDailyHours() * 80, m > 0 ? 3 : 1))
              .borderRadius(2)
              .backgroundColor(m > 0 ? $r('sys.color.brand') : $r('sys.color.font_tertiary'))
            Text(`${i + 1}`)
              .fontSize(8)
              .fontColor($r('sys.color.font_tertiary'))
              .margin({ top: 2 })
          }
          .layoutWeight(1)
          .height(100)
          .alignItems(HorizontalAlign.Center)
        }, (m: number, i: number) => `${i}-${m}`)
      }
      .width('100%')
      .margin({ top: 8 })
      .alignItems(VerticalAlign.Bottom)
    }
    .width('100%')
    .padding(12)
    .borderRadius(12)
    .backgroundColor($r('sys.color.background_primary'))
    .border({ width: 0.5, color: $r('sys.color.comp_divider') })
    .margin({ top: 8 })
  }

  @Builder
  violationList() {
    Column() {
      Text($r('app.string.rule_reminders'))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
      if (this.stats.violations.length === 0) {
        Text($r('app.string.no_violations'))
          .fontSize(12)
          .fontColor($r('sys.color.font_tertiary'))
          .margin({ top: 8 })
      } else {
        ForEach(this.stats.violations, (v: string) => {
          Text(v)
            .fontSize(12)
            .fontColor($r('sys.color.warning'))
            .margin({ top: 6 })
            .width('100%')
        }, (v: string) => v)
      }
    }
    .width('100%')
    .padding(12)
    .borderRadius(12)
    .backgroundColor($r('sys.color.background_primary'))
    .border({ width: 0.5, color: $r('sys.color.comp_divider') })
    .margin({ top: 8 })
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Scroll(this.scroller) {
      Column() {
        Row() {
          Text('‹')
            .fontSize(24)
            .padding({ left: 16, right: 16 })
            .onClick(() => this.changeMonth(-1))
          Blank()
          Text($r('app.string.stats_title', this.viewYear, this.viewMonth))
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .onClick(() => this.showMonthPicker())
          Blank()
          Text('›')
            .fontSize(24)
            .padding({ left: 16, right: 16 })
            .onClick(() => this.changeMonth(1))
        }
        .width('100%')

        this.ringCard()

        Row({ space: 8 }) {
          this.statCard($r('app.string.stat_scheduled'), minutesToHoursText(this.stats.workedMinutes),
            $r('app.string.progress_need', minutesToHoursText(this.stats.remainingMinutes)))
          this.statCard($r('app.string.stat_rest_days'), $r('app.string.stat_rest_days_val', this.stats.restDays),
            $r('app.string.stat_rest_days_sub', this.stats.restDaysTarget))
        }
        .width('100%')
        .margin({ top: 8 })

        Row({ space: 8 }) {
          this.statCard($r('app.string.stat_rest_hours'), minutesToHoursText(this.stats.restMinutes),
            $r('app.string.stat_rest_hours_sub', this.rules.restHoursPerMonth))
          this.statCard($r('app.string.stat_streak'), $r('app.string.stat_streak_val', this.stats.currentConsecutive),
            $r('app.string.stat_streak_sub', this.stats.maxConsecutive, this.rules.maxConsecutiveWorkDays))
        }
        .width('100%')
        .margin({ top: 8 })
        this.barChart()
        this.violationList()
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
