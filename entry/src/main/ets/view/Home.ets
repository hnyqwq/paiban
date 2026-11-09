import { HomePage } from '../pages/HomePage';
import { SecondPage } from '../pages/SecondPage';
import { MinePage } from '../pages/MinePage';

@Component
export struct Home {
  @StorageLink('currentTabIndex') firstLevelIndex: number = 0;
  @StorageProp('bottomRectHeight') bottomRectHeight: number = 0;

  private tabNames: string[] = ['首页', '发现', '我的'];

  getTabSymbol(index: number): Resource {
    switch (index) {
      case 0:
        return $r('sys.symbol.house');
      case 1:
        return $r('sys.symbol.square_grid_2x2');
      case 2:
        return $r('sys.symbol.person');
      default:
        return $r('sys.symbol.house');
    }
  }

  @Builder
  tabBuilder(name: string, index: number) {
    Column() {
      SymbolGlyph(this.getTabSymbol(index))
        .fontSize(24)
        .fontColor([index === this.firstLevelIndex ? $r('sys.color.brand') : $r('sys.color.icon_secondary')])
      Text(name)
        .fontSize(10)
        .fontWeight(500)
        .fontColor(index === this.firstLevelIndex ? '#0A59F7' : '#999999')
        .margin({ top: 4 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  build() {
    Tabs({
      barPosition: BarPosition.End,
      index: this.firstLevelIndex
    }) {
      TabContent() {
        HomePage()
      }
      .tabBar(this.tabBuilder(this.tabNames[0], 0))

      TabContent() {
        SecondPage()
      }
      .tabBar(this.tabBuilder(this.tabNames[1], 1))

      TabContent() {
        MinePage()
      }
      .tabBar(this.tabBuilder(this.tabNames[2], 2))
    }
    .barPosition(BarPosition.End)
    .vertical(false)
    .onChange((index: number) => {
      this.firstLevelIndex = index;
      AppStorage.setOrCreate('currentTabIndex', index);
    })
    .scrollable(false)
    .height('100%')
    .width('100%')
    .padding({ bottom: px2vp(this.bottomRectHeight) })
  }
}
