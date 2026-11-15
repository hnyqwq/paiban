// 本周排班卡片（2*4）：一周七天的班次名称与工时
let weekcardStorage = new LocalStorage();

class WeekDayData {
  label: string = '';
  dateText: string = '';
  hoursText: string = '';
  nameText: string = '';
  isToday: boolean = false;
  isRest: boolean = false;
}

class WeekData {
  rev: number = 0;
  title: string = '';
  rangeText: string = '';
  totalText: string = '';
  days: WeekDayData[] = [];
}

@Entry(weekcardStorage)
@Component
struct WeekCard {
  @LocalStorageProp('payload') payload: string = '';
  private cache: WeekData = new WeekData();
  private cacheKey: string = '';

  getData(): WeekData {
    if (this.cacheKey !== this.payload) {
      this.cacheKey = this.payload;
      if (this.payload === '') {
        this.cache = new WeekData();
      } else {
        try {
          this.cache = JSON.parse(this.payload) as WeekData;
        } catch (e) {
          this.cache = new WeekData();
        }
      }
    }
    return this.cache;
  }

  build() {
    FormLink({
      action: 'router',
      abilityName: 'EntryAbility',
      params: { 'from': 'week_card' }
    }) {
      Column() {
        Row() {
          Text(this.getData().title !== '' ? this.getData().title : $r('app.string.EntryAbility_label'))
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor('#F2F5F8')
          Text(this.getData().rangeText)
            .fontSize(9)
            .fontColor('#A7B0BC')
            .margin({ left: 6 })
          Blank()
          Text(this.getData().totalText)
            .fontSize(11)
            .fontColor('#6E9BFF')
        }
        .width('100%')

        Row() {
          ForEach(this.getData().days, (day: WeekDayData, index: number) => {
            Column() {
              Text(day.label)
                .fontSize(9)
                .fontColor('#79828F')
              Text(day.dateText)
                .fontSize(9)
                .fontColor('#A7B0BC')
                .margin({ top: 1 })
              if (day.nameText !== '') {
                Text(day.nameText)
                  .fontSize(9)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(day.isRest ? '#FF8A7A'
                    : (day.isToday ? '#6E9BFF' : '#F2F5F8'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .margin({ top: 4 })
              } else {
                Text(' ')
                  .fontSize(9)
                  .margin({ top: 4 })
              }
              if (day.hoursText !== '') {
                Text(day.hoursText)
                  .fontSize(10)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(day.isToday ? '#6E9BFF' : '#F2F5F8')
                  .margin({ top: 1 })
              } else {
                Text(' ')
                  .fontSize(10)
              }
            }
            .layoutWeight(1)
            .height(92)
            .justifyContent(FlexAlign.Center)
            .backgroundColor(day.isToday ? '#1B2838' : Color.Transparent)
            .borderRadius(8)
          }, (day: WeekDayData, index: number) => `${this.getData().rev}-${index}-${day.dateText}`)
        }
        .width('100%')
        .margin({ top: 4 })

        if (this.payload === '') {
          Text($r('app.string.form_fallback_hint'))
            .fontSize(10)
            .fontColor('#A7B0BC')
            .margin({ top: 6 })
        }
      }
      .width('100%')
      .height('100%')
      .padding(12)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Start)
      .backgroundColor('#0E1420')
      .borderRadius(16)
    }
    .width('100%')
    .height('100%')
  }
}
