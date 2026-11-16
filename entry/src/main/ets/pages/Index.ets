// 主框架：HdsNavigation + HdsTabs 悬浮底栏（照搬 hny）
import { AgendaPage } from './AgendaPage';
import { SchedulingPage } from './SchedulingPage';
import { SecondPage } from './SecondPage';
import { SettingsPage } from './SettingsPage';
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
import { openCardManager } from '../utils/AddCardButton';

@Entry
@Component
struct Index {
  @State currentTab: number = 0;
  @State tabMaterialType: number = hdsMaterial.MaterialType.ADAPTIVE;
  @State tabMaterialLevel: number = hdsMaterial.MaterialLevel.SMOOTH;
  @State symbolHome: SymbolGlyphModifier = new SymbolGlyphModifier($r('sys.symbol.calendar'));
  @State symbolStats: SymbolGlyphModifier = new SymbolGlyphModifier($r('sys.symbol.hourglass'));
  @State symbolTools: SymbolGlyphModifier = new SymbolGlyphModifier($r('sys.symbol.square_grid_2x2'));
  @State symbolMine: SymbolGlyphModifier = new SymbolGlyphModifier($r('sys.symbol.person'));
  @State symbolSettings: SymbolGlyphModifier = new SymbolGlyphModifier($r('sys.symbol.gearshape'));
  private tabsController: HdsTabsController = new HdsTabsController();
  // 各页滚动器，绑定顶栏滚动磨砂效果（照搬 hny）
  private scrollerHome: Scroller = new Scroller();
  private scrollerTools: Scroller = new Scroller();
  private scrollerStats: Scroller = new Scroller();
  private scrollerSettings: Scroller = new Scroller();
  private scrollerMine: Scroller = new Scroller();

  private getCurScroll(): Scroller {
    if (this.currentTab === 1) {
      return this.scrollerTools;
    }
    if (this.currentTab === 2) {
      return this.scrollerStats;
    }
    if (this.currentTab === 3) {
      return this.scrollerSettings;
    }
    return this.scrollerMine;
  }

  private getMainTitle(): Resource {
    if (this.currentTab === 0) {
      return $r('app.string.tab_home');
    }
    if (this.currentTab === 1) {
      return $r('app.string.tab_tools');
    }
    if (this.currentTab === 2) {
      return $r('app.string.tab_discover');
    }
    if (this.currentTab === 3) {
      return $r('app.string.tab_settings');
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
          AgendaPage({ scroller: this.scrollerHome })
        }
        .tabBar(new BottomTabBarStyle({ normal: this.symbolHome }, $r('app.string.tab_home')))

        TabContent() {
          SchedulingPage({ scroller: this.scrollerTools })
        }
        .tabBar(new BottomTabBarStyle({ normal: this.symbolTools }, $r('app.string.tab_tools')))

        TabContent() {
          SecondPage({ scroller: this.scrollerStats })
        }
        .tabBar(new BottomTabBarStyle({ normal: this.symbolStats }, $r('app.string.tab_discover')))

        TabContent() {
          SettingsPage({ scroller: this.scrollerSettings })
        }
        .tabBar(new BottomTabBarStyle({ normal: this.symbolSettings }, $r('app.string.tab_settings')))

        TabContent() {
          MinePage({ scroller: this.scrollerMine })
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
        // 广播当前 Tab：供各页在切回时刷新（如日程页重读提醒列表）
        AppStorage.setOrCreate('currentTab', index);
      })
    }
    .titleBar({
      content: {
        title: {
          mainTitle: this.getMainTitle()
        },
        menu: {
          value: [{
            content: {
              icon: new SymbolGlyphModifier($r('sys.symbol.plus_square_on_square'))
                .fontColor([$r('sys.color.font_primary')]),
              action: () => {
                openCardManager();
              }
            }
          }]
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
    .bindToScrollable([this.getCurScroll()])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
  }
}
