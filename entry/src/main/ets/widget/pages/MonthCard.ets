// 本月排班卡片（4*4）：整月日历，每天显示工时与预设班次名称
let monthcardStorage = new LocalStorage();

class MonthCellData {
  dayText: string = '';
  hoursText: string = '';
  nameText: string = '';
  isToday: boolean = false;
  isRest: boolean = false;
}

class MonthData {
  rev: number = 0;
  title: string = '';
  weekLabels: string[] = [];
  rows: MonthCellData[][] = [];
  summaryText: string = '';
  totalText: string = '';
}

@Entry(monthcardStorage)
@Component
struct MonthCard {
  @LocalStorageProp('payload') payload: string = '';
  private cache: MonthData = new MonthData();
  private cacheKey: string = '';

  getData(): MonthData {
    if (this.cacheKey !== this.payload) {
      this.cacheKey = this.payload;
      if (this.payload === '') {
        this.cache = new MonthData();
      } else {
        try {
          this.cache = JSON.parse(this.payload) as MonthData;
        } catch (e) {
          this.cache = new MonthData();
        }
      }
    }
    return this.cache;
  }

  build() {
    FormLink({
      action: 'router',
      abilityName: 'EntryAbility',
      params: { 'from': 'month_card' }
    }) {
      Column() {
        Row() {
          Text(this.getData().title !== '' ? this.getData().title : $r('app.string.EntryAbility_label'))
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor('#F2F5F8')
          Blank()
          Text(this.getData().totalText)
            .fontSize(11)
            .fontColor('#6E9BFF')
        }
        .width('100%')

        Text(this.getData().summaryText)
          .fontSize(9)
          .fontColor('#79828F')
          .width('100%')
          .margin({ top: 1 })

        if (this.payload === '') {
          Text($r('app.string.form_fallback_hint'))
            .fontSize(10)
            .fontColor('#A7B0BC')
            .margin({ top: 6 })
        }

        Row() {
          ForEach(this.getData().weekLabels, (label: string, index: number) => {
            Text(label)
              .fontSize(9)
              .fontColor('#79828F')
              .textAlign(TextAlign.Center)
              .layoutWeight(1)
          }, (label: string, index: number) => `${this.getData().rev}-${index}-${label}`)
        }
        .width('100%')
        .margin({ top: 5 })

        ForEach(this.getData().rows, (row: MonthCellData[], rowIndex: number) => {
          Row() {
            ForEach(row, (cell: MonthCellData, cellIndex: number) => {
              Column() {
                if (cell.dayText !== '') {
                  Text(cell.dayText)
                    .fontSize(9)
                    .fontWeight(cell.isToday ? FontWeight.Bold : FontWeight.Normal)
                    .fontColor(cell.isToday ? '#6E9BFF' : '#F2F5F8')
                  Text(cell.hoursText)
                    .fontSize(7)
                    .fontColor('#6E9BFF')
                    .maxLines(1)
                  Text(cell.nameText)
                    .fontSize(7)
                    .fontColor(cell.isRest ? '#FF8A7A' : '#A7B0BC')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')
                    .textAlign(TextAlign.Center)
                }
              }
              .layoutWeight(1)
              .height(34)
              .justifyContent(FlexAlign.Center)
              .backgroundColor(cell.isToday ? '#1B2838' : Color.Transparent)
              .borderRadius(4)
            }, (cell: MonthCellData, cellIndex: number) => `${this.getData().rev}-${rowIndex}-${cellIndex}`)
          }
          .width('100%')
          .height(34)
        }, (row: MonthCellData[], rowIndex: number) => `${this.getData().rev}-${rowIndex}`)
      }
      .width('100%')
      .height('100%')
      .padding(12)
      .alignItems(HorizontalAlign.Start)
      .backgroundColor('#0E1420')
      .borderRadius(16)
    }
    .width('100%')
    .height('100%')
  }
}
