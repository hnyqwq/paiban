// 日程页：只读展示今天的班次时间安排
import {
  DayEntry, Shift, dateKey, minutesToHoursText
} from '../model/ScheduleTypes';
import { ScheduleService } from '../service/ScheduleService';

@Component
export struct AgendaPage {
  scroller: Scroller = new Scroller();
  @StorageLink('scheduleDataVersion') @Watch('onDataChanged') scheduleDataVersion: number = 0;
  private service: ScheduleService = ScheduleService.getInstance();

  onDataChanged(): void {
    // scheduleDataVersion 变化触发整树刷新
  }

  todayStr(): string {
    const now = new Date();
    return dateKey(now.getFullYear(), now.getMonth() + 1, now.getDate());
  }

  todayShifts(): Shift[] {
    const days: DayEntry[] = this.service.getDays();
    const entry = this.service.findEntry(days, this.todayStr());
    return entry !== undefined ? entry.shifts : [];
  }

  todayRest(): boolean {
    const days: DayEntry[] = this.service.getDays();
    return this.service.isRestDay(this.service.findEntry(days, this.todayStr()));
  }

  @Builder
  shiftRow(s: Shift) {
    Row() {
      Text(`${s.start} - ${s.end}`)
        .fontSize(16)
      Text(minutesToHoursText(s.durationMinutes()))
        .fontSize(14)
        .fontColor($r('sys.color.brand'))
        .margin({ left: 12 })
      Blank()
    }
    .width('100%')
    .padding(14)
    .borderRadius(10)
    .backgroundColor($r('sys.color.comp_background_tertiary'))
    .margin({ top: 8 })
  }

  build() {
    Scroll(this.scroller) {
      Column() {
        Column() {
          Text($r('app.string.day_schedule', this.todayStr()))
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .width('100%')

          if (this.todayShifts().length > 0) {
            List({ space: 4 }) {
              ForEach(this.todayShifts(), (s: Shift, i: number) => {
                ListItem() {
                  this.shiftRow(s)
                }
              }, (s: Shift, i: number) => `${i}-${s.start}-${s.end}`)
            }
            .width('100%')
            .margin({ top: 8 })
          } else if (this.todayRest()) {
            Text($r('app.string.rest_marker'))
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('sys.color.warning'))
              .margin({ top: 16 })
            Text($r('app.string.today_label'))
              .fontSize(12)
              .fontColor($r('sys.color.font_tertiary'))
              .margin({ top: 4 })
          } else {
            Text($r('app.string.agenda_empty'))
              .fontSize(14)
              .fontColor($r('sys.color.font_tertiary'))
              .margin({ top: 16 })
          }
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
