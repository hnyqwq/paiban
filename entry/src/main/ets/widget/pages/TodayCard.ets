// 今日排班卡片（2*2）：今天所有班次的名称、时间与净工时
let todaycardStorage = new LocalStorage();

class CardShiftData {
  name: string = '';
  time: string = '';
  hours: string = '';
  color: string = '#0A59F7';
}

class TodayData {
  rev: number = 0;
  badge: string = '';
  title: string = '';
  weekday: string = '';
  totalText: string = '';
  statusText: string = '';
  shifts: CardShiftData[] = [];
  extraCount: number = 0;
}

@Entry(todaycardStorage)
@Component
struct TodayCard {
  @LocalStorageProp('payload') payload: string = '';
  private cache: TodayData = new TodayData();
  private cacheKey: string = '';

  getData(): TodayData {
    if (this.cacheKey !== this.payload) {
      this.cacheKey = this.payload;
      if (this.payload === '') {
        this.cache = new TodayData();
      } else {
        try {
          this.cache = JSON.parse(this.payload) as TodayData;
        } catch (e) {
          this.cache = new TodayData();
        }
      }
    }
    return this.cache;
  }

  visibleShifts(): CardShiftData[] {
    const shifts = this.getData().shifts;
    return shifts === undefined ? [] : shifts.slice(0, 2);
  }

  build() {
    FormLink({
      action: 'router',
      abilityName: 'EntryAbility',
      params: { 'from': 'today_card' }
    }) {
      Column() {
        Row() {
          Text(this.getData().badge)
            .fontSize(10)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.card_accent'))
          Blank()
          Text(this.getData().weekday)
            .fontSize(10)
            .fontColor($r('app.color.card_text_secondary'))
        }
        .width('100%')

        Text(this.getData().title !== '' ? this.getData().title : $r('app.string.EntryAbility_label'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.card_text_primary'))
          .margin({ top: 2 })

        if (this.getData().totalText !== '') {
          Text(this.getData().totalText)
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.card_text_primary'))
        }

        if (this.payload === '') {
          Text($r('app.string.form_fallback_hint'))
            .fontSize(10)
            .fontColor($r('app.color.card_text_secondary'))
            .margin({ top: 4 })
        } else if (this.getData().statusText !== '') {
          Text(this.getData().statusText)
            .fontSize(12)
            .fontColor($r('app.color.card_text_secondary'))
            .margin({ top: 4 })
        } else {
          ForEach(this.visibleShifts(), (shift: CardShiftData, index: number) => {
            Row() {
              Text('')
                .width(3)
                .height(16)
                .borderRadius(2)
                .backgroundColor(shift.color)
                .margin({ right: 6 })
              Text(shift.name)
                .fontSize(11)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.card_text_primary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
              Text(shift.time)
                .fontSize(9)
                .fontColor($r('app.color.card_text_secondary'))
                .margin({ left: 4 })
              Text(shift.hours)
                .fontSize(10)
                .fontColor($r('app.color.card_accent'))
                .margin({ left: 4 })
            }
            .width('100%')
            .margin({ top: 3 })
          }, (shift: CardShiftData, index: number) => `${this.getData().rev}-${index}-${shift.name}-${shift.time}`)

          if (this.getData().extraCount > 0) {
            Text(`+${this.getData().extraCount}`)
              .fontSize(9)
              .fontColor($r('app.color.card_muted'))
              .margin({ top: 2 })
          }
        }
      }
      .width('100%')
      .height('100%')
      .padding(12)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Start)
      .backgroundColor($r('app.color.card_bg'))
      .borderRadius(16)
    }
    .width('100%')
    .height('100%')
  }
}
