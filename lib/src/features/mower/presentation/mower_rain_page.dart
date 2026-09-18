import 'package:flutter/material.dart';

import '../../../design_system/design_system.dart';
import '../mower_demo.dart';
import 'widgets/mower_card.dart';
import 'widgets/mower_form.dart';

/// 雨淋设置（`割草机-雨淋设置.png`）：两个开关加一组「时 / 分」滚轮。
///
/// 静态页：开关和滚轮都只改这一页的状态，「保存」不下发。滚轮参数和花盆那边的
/// 休眠延迟弹窗一致（平的、不要 iOS 圆筒感），两处手感一样。
class MowerRainPage extends StatefulWidget {
  const MowerRainPage({super.key});

  @override
  State<MowerRainPage> createState() => _MowerRainPageState();
}

class _MowerRainPageState extends State<MowerRainPage> {
  static const double _itemExtent = 56;

  bool _enabled = true;
  bool _delayEnabled = true;
  int _hours = 3;
  int _minutes = 0;

  late final FixedExtentScrollController _hourController =
      FixedExtentScrollController(initialItem: _hours);
  late final FixedExtentScrollController _minuteController =
      FixedExtentScrollController(initialItem: _minutes);

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      appBar: const AppPageHeader(title: '雨淋设置', leading: AppBackButton()),
      body: Column(
        children: <Widget>[
          Expanded(
            child: SingleChildScrollView(
              key: const Key('mower-rain-scroll-view'),
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              child: MowerCard(
                child: Column(
                  children: <Widget>[
                    MowerSwitchRow(
                      title: '开启',
                      subtitle: '雨淋结束后延迟恢复割草',
                      value: _enabled,
                      switchKey: const Key('mower-rain-switch'),
                      onChanged: (value) => setState(() => _enabled = value),
                    ),
                    const MowerRowDivider(indent: 20),
                    MowerSwitchRow(
                      title: '延迟时间',
                      value: _delayEnabled,
                      switchKey: const Key('mower-rain-delay-switch'),
                      onChanged: (value) =>
                          setState(() => _delayEnabled = value),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      child: SizedBox(
                        height: _itemExtent * 3,
                        child: Stack(
                          children: <Widget>[
                            // 选中那一格的高亮带：滚轮只管数字，居中那格由它衬底。
                            Center(
                              child: Container(
                                height: _itemExtent + 8,
                                decoration: const BoxDecoration(
                                  color: MowerColors.chipFill,
                                  border: Border.symmetric(
                                    horizontal: BorderSide(
                                      color: MowerColors.divider,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: MowerWheel(
                                    wheelKey: const Key('mower-rain-hour'),
                                    controller: _hourController,
                                    count: 24,
                                    selected: _hours,
                                    itemExtent: _itemExtent,
                                    unit: '时',
                                    onSelected: (value) =>
                                        setState(() => _hours = value),
                                  ),
                                ),
                                Expanded(
                                  child: MowerWheel(
                                    wheelKey: const Key('mower-rain-minute'),
                                    controller: _minuteController,
                                    count: 60,
                                    selected: _minutes,
                                    itemExtent: _itemExtent,
                                    unit: '分',
                                    onSelected: (value) =>
                                        setState(() => _minutes = value),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: MowerSaveButton(
              buttonKey: const Key('mower-rain-save'),
              onPressed: () => showAppMessage(
                context,
                '静态页面：延迟 $_hours 时 $_minutes 分不会真的下发',
                tone: AppMessageTone.info,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
