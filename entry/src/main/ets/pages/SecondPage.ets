@Component
export struct SecondPage {
  build() {
    Column() {
      Text('发现')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}
