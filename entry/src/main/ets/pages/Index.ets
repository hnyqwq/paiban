// 主框架：HdsNavigation + HdsTabs 悬浮底栏（照搬 hny）
import { HomePage } from './HomePage';
import { SecondPage } from './SecondPage';
import { MinePage } from './MinePage';
import {
  HdsNavigation,
  HdsNavigationTitleMode,
  HdsTabs,
  HdsTabsController,
  hdsMaterial,
  ScrollEffectType,
} from '@kit.UIDesignKit';
import { LengthMetrics, SymbolGlyphModifier } from '@kit.ArkUI';

@Entry
@Component
struct Index {
  @State currentTab: number = 0;
  @State tabMaterialType: number = hdsMaterial.MaterialType.ADAPTIVE;
  @State tabMaterialLevel: number = hdsMaterial.MaterialLevel.SMOOTH;
  @State symbolHome: SymbolGlyphModifier = new SymbolGlyphModifier($r('sys.symbol.house'));
  @State symbolTools: SymbolGlyphModifier = new SymbolGlyphModifier($r('sys.symbol.square_grid_2x2'));
  @State symbolMine: SymbolGlyphModifier = new SymbolGlyphModifier($r('sys.symbol.person'));
  private tabsController: HdsTabsController = new HdsTabsController();

  private getMainTitle(): Resource {
    if (this.currentTab === 0) {
      return $r('app.string.tab_home');
    }
    if (this.currentTab === 1) {
      return $r('app.string.tab_discover');
    }
    return $r('app.string.tab_mine');
  }

  aboutToAppear(): void {
    // 检测系统材质能力，选择悬浮栏材质（照搬 hny）
    try {
      const materialTypes: Array<hdsMaterial.MaterialType> = hdsMaterial.getSystemMaterialTypes();
      const hasImmersive: boolean =
        materialTypes.some((t: hdsMaterial.MaterialType) => t === hdsMaterial.MaterialType.IMMERSIVE);
      if (materialTypes.length === 0) {
        this.tabMaterialLevel = hdsMaterial.MaterialLevel.SMOOTH;
        this.tabMaterialType = hdsMaterial.MaterialType.ADAPTIVE;
      } else if (!hasImmersive) {
        this.tabMaterialLevel = hdsMaterial.MaterialLevel.GENTLE;
        this.tabMaterialType = hdsMaterial.MaterialType.ADAPTIVE;
      } else {
        this.tabMaterialLevel = hdsMaterial.MaterialLevel.EXQUISITE;
        this.tabMaterialType = hdsMaterial.MaterialType.IMMERSIVE;
      }
    } catch (err) {
      console.error('getSystemMaterialTypes failed');
    }
  }

  build() {
    HdsNavigation() {
      HdsTabs({ controller: this.tabsController }) {
        TabContent() {
          HomePage()
        }
        .tabBar(new BottomTabBarStyle({ normal: this.symbolHome }, $r('app.string.tab_home')))

        TabContent() {
          SecondPage()
        }
        .tabBar(new BottomTabBarStyle({ normal: this.symbolTools }, $r('app.string.tab_discover')))

        TabContent() {
          MinePage()
        }
        .tabBar(new BottomTabBarStyle({ normal: this.symbolMine }, $r('app.string.tab_mine')))
      }
      .barPosition(BarPosition.End)
      .vertical(false)
      .barOverlap(true)
      .scrollable(false)
      .barFloatingStyle({
        barBottomMargin: 28,
        systemMaterialEffect: {
          materialType: this.tabMaterialType,
          materialLevel: this.tabMaterialLevel,
        },
      })
      .onChange((index: number) => {
        this.currentTab = index;
      })
    }
    .titleBar({
      content: {
        title: {
          mainTitle: this.getMainTitle()
        }
      },
      style: {
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: ScrollEffectType.GRADIENT_BLUR,
          blurEffectiveStartOffset: LengthMetrics.vp(0),
          blurEffectiveEndOffset: LengthMetrics.vp(56),
        },
        originalStyle: {
          backgroundStyle: {
            backgroundColor: '#00ffffff'
          }
        },
        scrollEffectStyle: {
          backgroundStyle: {
            backgroundColor: '#00ffffff'
          }
        }
      }
    })
    .mode(NavigationMode.Stack)
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideBackButton(true)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
  }
}
