// 第五页：我的 —— 代理提醒/数据/外观/关于（排班规则与预设排班在「排班设置」页）
import { pasteboard, BusinessError } from '@kit.BasicServicesKit';
import { promptAction, SegmentButtonV2Items, CapsuleSegmentButtonV2 } from '@kit.ArkUI';
import { common, bundleManager } from '@kit.AbilityKit';
import fs from '@ohos.file.fs';
import picker from '@ohos.file.picker';
import { updateManager } from '@kit.AppGalleryKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AlarmSettings } from '../model/ScheduleTypes';
import { ScheduleService } from '../service/ScheduleService';
import { resyncAlarms } from '../utils/CalendarReminder';

function segString(res: Resource): string {
  try {
    const context = AppStorage.get<common.UIAbilityContext>('context');
    if (context === undefined) {
      return '';
    }
    return context.resourceManager.getStringSync(res);
  } catch (e) {
    return '';
  }
}

// 外观选择：胶囊型分段按钮（@ComponentV2）
@ComponentV2
struct AppearanceSegment {
  @Param selected: number = 0;
  @Event onSelect: (index: number) => void = (_index: number) => {};
  private items: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: segString($r('app.string.follow_system')) },
    { text: segString($r('app.string.light_mode')) },
    { text: segString($r('app.string.dark_mode')) },
  ]);

  build() {
    Row() {
      CapsuleSegmentButtonV2({
        items: this.items,
        selectedIndex: this.selected,
        onItemClicked: (index: number) => {
          this.onSelect(index);
        }
      })
    }
    .width('100%')
  }
}

@Component
export struct MinePage {
  scroller: Scroller = new Scroller();
  @State appearanceMode: number = 0; // 0 跟随系统 1 浅色 2 深色
  @StorageProp('isWideLayout') isWideLayout: boolean = false; // 大屏（≥lg 断点）双栏布局
  @State weekStart: number = 0; // 0 周日开始 1 周一开始
  @State alarm: AlarmSettings = new AlarmSettings();
  @State bundleName: string = '';
  @State versionName: string = '';
  private service: ScheduleService = ScheduleService.getInstance();
  @State showImportEditor: boolean = false;
  @State importText: string = '';

  // 确认导入：解析并写入，成功后广播刷新
  confirmImport(): void {
    const trimmed = this.importText.trim();
    if (trimmed === '') {
      promptAction.showToast({ message: $r('app.string.import_empty') });
      return;
    }
    if (this.service.importDays(trimmed)) {
      promptAction.showToast({ message: $r('app.string.import_success') });
      this.showImportEditor = false;
      this.importText = '';
    } else {
      promptAction.showToast({ message: $r('app.string.import_failed_len', trimmed.length) });
    }
  }

  aboutToAppear(): void {
    this.appearanceMode = this.service.getAppearanceMode();
    this.weekStart = this.service.getWeekStart();
    this.alarm = this.service.getAlarmSettings();
    this.loadBundleInfo();
  }

  // 通过 bundleManager 实时读取包名与版本号
  loadBundleInfo(): void {
    try {
      const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      this.bundleName = info.name;
      this.versionName = `${info.versionName} (${info.versionCode})`;
    } catch (e) {
      hilog.error(0x0000, 'testTag', 'Failed to load bundle info. Cause: %{public}s', JSON.stringify(e));
    }
  }

  // 保存代理提醒自定义设置，并同步到全部已添加的提醒
  saveAlarmSettings(): void {
    this.service.saveAlarmSettings(this.alarm);
    const ctx = AppStorage.get<common.UIAbilityContext>('context');
    if (ctx === undefined) {
      promptAction.showToast({ message: $r('app.string.alarm_saved') });
      return;
    }
    resyncAlarms(ctx).then(() => {
      promptAction.showToast({ message: $r('app.string.alarm_saved') });
    });
  }

  // 选择自定义铃声：拷贝到应用沙箱后存 URI
  pickCustomRing(): void {
    const ctx = AppStorage.get<common.UIAbilityContext>('context');
    if (ctx === undefined) {
      return;
    }
    const audioPicker = new picker.AudioViewPicker();
    const opt = new picker.AudioSelectOptions();
    opt.maxSelectNumber = 1;
    audioPicker.select(opt).then((uris: Array<string>) => {
      if (uris.length === 0) {
        return;
      }
      const srcUri = uris[0];
      const src = fs.openSync(srcUri, fs.OpenMode.READ_ONLY);
      const suffix = srcUri.substring(srcUri.lastIndexOf('.')).length < 8 ? srcUri.substring(srcUri.lastIndexOf('.')) : '';
      const destPath = `${ctx.filesDir}/custom_ring_${Date.now()}${suffix}`;
      fs.copyFile(src.fd, destPath).then(() => {
        fs.closeSync(src.fd);
        this.alarm.customRingUri = `file://${destPath}`;
        this.alarm.customRingName = decodeURIComponent(srcUri.substring(srcUri.lastIndexOf('/') + 1));
        this.saveAlarmSettings();
      }).catch((err: BusinessError) => {
        fs.closeSync(src.fd);
        promptAction.showToast({ message: `${$r('app.string.card_add_failed')} (${err.code})` });
      });
    }).catch((_err: BusinessError) => {
      // 用户取消选择，不处理
    });
  }

  // 清除自定义铃声，恢复系统默认
  clearCustomRing(): void {
    this.alarm.customRingUri = '';
    this.alarm.customRingName = '';
    this.saveAlarmSettings();
  }

  // 打开隐私协议（系统浏览器）
  openPrivacy(): void {
    const ctx = AppStorage.get<common.UIAbilityContext>('context');
    if (ctx === undefined) {
      return;
    }
    ctx.openLink('https://agreement-drcn.hispace.dbankcloud.cn/index.html?lang=zh&agreementId=2085312685611734272');
  }

  exportData(): void {
    const json = JSON.stringify(this.service.getDays());
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, json);
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      promptAction.showToast({ message: $r('app.string.exported') });
    }).catch((_err: Error) => {
      promptAction.showToast({ message: $r('app.string.export_failed') });
    });
  }

  // 检查更新（照搬 hny：AppGallery updateManager）
  checkUpdate(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    updateManager.checkAppUpdate(context).then((checkResult: updateManager.CheckUpdateResult) => {
      if (checkResult.updateAvailable) {
        updateManager.showUpdateDialog(context).catch((_error: BusinessError) => {
          promptAction.showToast({ message: $r('app.string.update_dialog_failed') });
        });
      } else {
        promptAction.showToast({ message: $r('app.string.already_latest') });
      }
    }).catch((_error: BusinessError) => {
      promptAction.showToast({ message: $r('app.string.check_update_failed') });
    });
  }

  clearData(): void {
    promptAction.showDialog({
      title: $r('app.string.clear_confirm_title'),
      message: $r('app.string.clear_confirm_msg'),
      buttons: [
        { text: $r('app.string.cancel'), color: $r('sys.color.font_secondary') },
        { text: $r('app.string.btn_clear'), color: $r('sys.color.warning') }
      ]
    }).then((res) => {
      if (res.index === 1) {
        this.service.clearAll();
        promptAction.showToast({ message: $r('app.string.cleared') });
      }
    });
  }

  @Builder
  sectionTitle(title: Resource | string) {
    Text(title)
      .fontSize(13)
      .fontColor($r('sys.color.font_tertiary'))
      .width('100%')
      .margin({ top: 16, bottom: 6 })
  }

  // 代理提醒自定义卡片：响铃时长、贪睡开关/次数/间隔
  @Builder
  alarmCard() {
    Column() {
      Row() {
        Text($r('app.string.alarm_ring_duration'))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
        TextInput({ text: `${this.alarm.ringDuration}` })
          .type(InputType.Number)
          .width(120)
          .onChange((v: string) => {
            const n = Number(v);
            this.alarm.ringDuration = Number.isNaN(n) || n <= 0 ? 5 : Math.floor(n);
          })
      }
      .width('100%')
      .margin({ top: 4 })

      Row() {
        Text($r('app.string.alarm_snooze'))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.alarm.snoozeEnabled })
          .onChange((isOn: boolean) => {
            this.alarm.snoozeEnabled = isOn;
          })
      }
      .width('100%')
      .margin({ top: 12 })

      if (this.alarm.snoozeEnabled) {
        Text($r('app.string.alarm_snooze_times'))
          .fontSize(13)
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')
          .margin({ top: 10 })
        TextInput({ text: `${this.alarm.snoozeTimes}` })
          .type(InputType.Number)
          .width('100%')
          .onChange((v: string) => {
            const n = Number(v);
            this.alarm.snoozeTimes = Number.isNaN(n) || n <= 0 ? 2 : Math.floor(n);
          })

        Text($r('app.string.alarm_snooze_interval'))
          .fontSize(13)
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')
          .margin({ top: 10 })
        TextInput({ text: `${this.alarm.timeInterval}` })
          .type(InputType.Number)
          .width('100%')
          .onChange((v: string) => {
            const n = Number(v);
            this.alarm.timeInterval = Number.isNaN(n) || n <= 0 ? 5 : Math.floor(n);
          })
      }

      Row() {
        Text($r('app.string.alarm_want_agent'))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
        Text(this.alarm.wantAgentEnabled ? $r('app.string.rule_enabled') : $r('app.string.rule_disabled'))
          .fontSize(12)
          .fontColor($r('sys.color.font_tertiary'))
          .margin({ right: 8 })
        Toggle({ type: ToggleType.Switch, isOn: this.alarm.wantAgentEnabled })
          .onChange((isOn: boolean) => {
            this.alarm.wantAgentEnabled = isOn;
          })
      }
      .width('100%')
      .margin({ top: 12 })

      Row() {
        Text($r('app.string.alarm_tap_dismissed'))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
        Text(this.alarm.tapDismissed ? $r('app.string.rule_enabled') : $r('app.string.rule_disabled'))
          .fontSize(12)
          .fontColor($r('sys.color.font_tertiary'))
          .margin({ right: 8 })
        Toggle({ type: ToggleType.Switch, isOn: this.alarm.tapDismissed })
          .onChange((isOn: boolean) => {
            this.alarm.tapDismissed = isOn;
          })
      }
      .width('100%')
      .margin({ top: 12 })

      Row() {
        Text($r('app.string.alarm_auto_delete'))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
        Text(this.alarm.autoDeleteEnabled ? $r('app.string.rule_enabled') : $r('app.string.rule_disabled'))
          .fontSize(12)
          .fontColor($r('sys.color.font_tertiary'))
          .margin({ right: 8 })
        Toggle({ type: ToggleType.Switch, isOn: this.alarm.autoDeleteEnabled })
          .onChange((isOn: boolean) => {
            this.alarm.autoDeleteEnabled = isOn;
          })
      }
      .width('100%')
      .margin({ top: 12 })

      Row() {
        Text($r('app.string.alarm_custom_ring'))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
        if (this.alarm.customRingUri !== '') {
          Text(this.alarm.customRingName)
            .fontSize(12)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: '40%' })
          Button($r('app.string.alarm_ring_clear'))
            .buttonStyle(ButtonStyleMode.NORMAL)
            .fontSize(12)
            .margin({ left: 8 })
            .onClick(() => this.clearCustomRing())
        } else {
          Button($r('app.string.alarm_ring_pick'))
            .buttonStyle(ButtonStyleMode.NORMAL)
            .fontSize(12)
            .onClick(() => this.pickCustomRing())
        }
      }
      .width('100%')
      .margin({ top: 12 })

      Button($r('app.string.save_rules'))
        .width('100%')
        .buttonStyle(ButtonStyleMode.NORMAL)
        .margin({ top: 14 })
        .onClick(() => this.saveAlarmSettings())
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 4, bottom: 12 })
  }

  // 代理提醒区（大屏双栏时放左侧，竖屏在页面顶部）
  @Builder
  alarmSection() {
    this.sectionTitle($r('app.string.section_alarm'))
    Column() {
      this.alarmCard()
    }
    .width('100%')
    .borderRadius(12)
    .backgroundColor($r('sys.color.background_primary'))
    .border({ width: 0.5, color: $r('sys.color.comp_divider') })
  }

  // 数据/外观/关于区（大屏双栏时放右侧）
  @Builder
  otherSections() {
    this.sectionTitle($r('app.string.section_data'))
        Column() {
          Row({ space: 8 }) {
            Button($r('app.string.export_data'))
              .buttonStyle(ButtonStyleMode.NORMAL)
              .fontSize(13)
              .layoutWeight(1)
              .margin({ top: 12, bottom: 4, left: 12 })
              .onClick(() => this.exportData())
            Button($r('app.string.import_data'))
              .buttonStyle(ButtonStyleMode.NORMAL)
              .fontSize(13)
              .layoutWeight(1)
              .margin({ top: 12, bottom: 4, right: 12 })
              .onClick(() => {
                this.importText = '';
                this.showImportEditor = true;
              })
          }
          .width('100%')
          if (this.showImportEditor) {
            // 导入在主窗口内联执行：安全控件 PasteButton 在子窗口（CustomDialog）中拿不到临时授权
            Column() {
              Row() {
                PasteButton()
                  .fontSize(13)
                  .onClick((event: ClickEvent, result: PasteButtonOnClickResult) => {
                    if (result !== PasteButtonOnClickResult.SUCCESS) {
                      return;
                    }
                    try {
                      const text = pasteboard.getSystemPasteboard().getDataSync().getPrimaryText();
                      if (text !== '') {
                        this.importText = text;
                      } else {
                        promptAction.showToast({ message: $r('app.string.clipboard_empty') });
                      }
                    } catch (e) {
                      promptAction.showToast({ message: $r('app.string.clipboard_empty') });
                    }
                  })
              }
              .width('100%')
              .justifyContent(FlexAlign.Start)

              TextArea({ text: this.importText, placeholder: $r('app.string.import_hint') })
                .width('100%')
                .height(140)
                .margin({ top: 8 })
                .onChange((v: string) => {
                  this.importText = v;
                })
              Row() {
                Button($r('app.string.cancel'))
                  .buttonStyle(ButtonStyleMode.NORMAL)
                  .layoutWeight(1)
                  .onClick(() => {
                    this.showImportEditor = false;
                    this.importText = '';
                  })
                Button($r('app.string.import_data'))
                  .layoutWeight(1)
                  .margin({ left: 12 })
                  .onClick(() => this.confirmImport())
              }
              .width('100%')
              .margin({ top: 12 })
            }
            .width('calc(100% - 24vp)')
            .margin({ left: 12, right: 12, top: 8 })
          }
          Button($r('app.string.clear_data'))
            .width('calc(100% - 24vp)')
            .buttonStyle(ButtonStyleMode.NORMAL)
            .fontColor($r('sys.color.warning'))
            .margin({ top: 8, bottom: 12, left: 12, right: 12 })
            .onClick(() => this.clearData())
        }
        .width('100%')
        .borderRadius(12)
        .backgroundColor($r('sys.color.background_primary'))
        .border({ width: 0.5, color: $r('sys.color.comp_divider') })

        this.sectionTitle($r('app.string.section_appearance'))
        Column() {
          AppearanceSegment({
            selected: this.appearanceMode,
            onSelect: (index: number) => {
              this.appearanceMode = index;
              this.service.setAppearanceMode(index);
            }
          })
            .width('calc(100% - 24vp)')
            .margin({ left: 12, right: 12, top: 12, bottom: 12 })

          Row() {
            Text($r('app.string.week_start_title'))
              .fontSize(14)
              .layoutWeight(1)
            Button($r('app.string.week_start_sun'))
              .buttonStyle(this.weekStart === 0 ? ButtonStyleMode.EMPHASIZED : ButtonStyleMode.NORMAL)
              .fontSize(12)
              .onClick(() => {
                this.weekStart = 0;
                this.service.setWeekStart(0);
              })
            Button($r('app.string.week_start_mon'))
              .buttonStyle(this.weekStart === 1 ? ButtonStyleMode.EMPHASIZED : ButtonStyleMode.NORMAL)
              .fontSize(12)
              .margin({ left: 8 })
              .onClick(() => {
                this.weekStart = 1;
                this.service.setWeekStart(1);
              })
          }
          .width('calc(100% - 24vp)')
          .margin({ left: 12, right: 12, bottom: 12 })
        }
        .width('100%')
        .borderRadius(12)
        .backgroundColor($r('sys.color.background_primary'))
        .border({ width: 0.5, color: $r('sys.color.comp_divider') })

        this.sectionTitle($r('app.string.section_about'))
        Column() {
          Row() {
            Text($r('app.string.EntryAbility_label'))
              .fontSize(15)
            Blank()
            Text(this.bundleName)
              .fontSize(15)
              .fontColor($r('sys.color.font_secondary'))
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 12, bottom: 4 })
          Row() {
            Text($r('app.string.version_label'))
              .fontSize(15)
            Blank()
            Text(this.versionName)
              .fontSize(15)
              .fontColor($r('sys.color.font_secondary'))
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 4, bottom: 4 })
          Row() {
            Text($r('app.string.check_update'))
              .fontSize(15)
            Blank()
            Text('›')
              .fontSize(16)
              .fontColor($r('sys.color.font_tertiary'))
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 4, bottom: 12 })
          .onClick(() => this.checkUpdate())
        }
        .width('100%')
        .borderRadius(12)
        .backgroundColor($r('sys.color.background_primary'))
        .border({ width: 0.5, color: $r('sys.color.comp_divider') })

        // 隐私协议
        Row() {
          Text($r('app.string.privacy_policy'))
            .fontSize(15)
            .fontColor($r('sys.color.brand'))
          Blank()
          Text('›')
            .fontSize(16)
            .fontColor($r('sys.color.font_tertiary'))
        }
        .width('100%')
        .padding(12)
        .borderRadius(12)
        .backgroundColor($r('sys.color.background_primary'))
        .border({ width: 0.5, color: $r('sys.color.comp_divider') })
        .margin({ top: 12 })
        .onClick(() => this.openPrivacy())
  }

  build() {
    Scroll(this.scroller) {
      Column() {
        if (this.isWideLayout) {
          // 大屏双栏：代理提醒在左，数据/外观/关于/隐私在右
          Row({ space: 8 }) {
            Column() {
              this.alarmSection()
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            Column() {
              this.otherSections()
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
        } else {
          this.alarmSection()
          this.otherSections()
        }

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