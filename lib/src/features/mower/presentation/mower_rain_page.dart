import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../mower_ui.dart';
import '../mower_device.dart';
import '../mower_dp.dart';
import 'widgets/mower_card.dart';
import 'widgets/mower_form.dart';

/// 雨淋设置（`割草机-雨淋设置.png`）→ 三条 DP：
///
/// | 控件 | DP |
/// | --- | --- |
/// | 开启 | DP104 rain_detect_enable（雨淋检测总开关） |
/// | 延迟时间 | DP102 rain_delay_switch（雨滴延时开关，V2.2 新增） |
/// | 时 / 分滚轮 | DP105 rain_delay（**0-120 分钟**） |
///
/// ⚠️ **稿子上画的是「03 时」，而 DP105 的上限是 120 分钟（2 小时）**。
/// 这里把小时滚轮收到 0-2，并在保存时按 0-120 钳位（钳了会在联调日志里记一行）——
/// 画得出来但发不下去的值不该让用户选。产品若要支持 3 小时，得先让设备端放宽 DP105。
class MowerRainPage extends StatefulWidget {
  const MowerRainPage({super.key});

  @override
  State<MowerRainPage> createState() => _MowerRainPageState();
}

class _MowerRainPageState extends State<MowerRainPage> {
  static const double _itemExtent = 56;

  /// DP105 的上限（分钟）。
  static const int _maxDelay = 120;

  MowerDevice get _device => MowerDevice.instance;

  late bool _enabled = _device.rainDetectEnable;
  late bool _delayEnabled = _device.rainDelaySwitch;
  late int _hours = _device.rainDelayMinutes ~/ 60;
  late int _minutes = _device.rainDelayMinutes % 60;

  late final FixedExtentScrollController _hourController =
      FixedExtentScrollController(initialItem: _hours);
  late final FixedExtentScrollController _minuteController =
      FixedExtentScrollController(initialItem: _minutes);

  int get _totalMinutes => _hours * 60 + _minutes;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      FlowerpotScope.of(context)
        ..logPageEntry('割草机-雨淋设置')
        ..logMowerInteraction(
          '读取 ← 割草机-雨淋设置 '
          'DP${MowerDp.rainDetectEnable}=$_enabled，'
          'DP${MowerDp.rainDelaySwitch}=$_delayEnabled，'
          'DP${MowerDp.rainDelay}=${_device.rainDelayMinutes} 分钟',
        );
    });
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    super.dispose();
  }

  /// 2 小时那一档只能配 0 分：再往上就越过 DP105 的 120 分钟上限了。
  void _clampToRange() {
    if (_totalMinutes <= _maxDelay) return;
    _hours = _maxDelay ~/ 60;
    _minutes = _maxDelay % 60;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_hourController.hasClients && _hourController.selectedItem != _hours) {
        _hourController.jumpToItem(_hours);
      }
      if (_minuteController.hasClients &&
          _minuteController.selectedItem != _minutes) {
        _minuteController.jumpToItem(_minutes);
      }
    });
  }

  void _save() {
    final state = FlowerpotScope.of(context);
    _device.setRain(
      state,
      detectEnable: _enabled,
      delaySwitch: _delayEnabled,
      delayMinutes: _totalMinutes,
    );
    showAppMessage(
      context,
      '已下发 DP${MowerDp.rainDetectEnable} / DP${MowerDp.rainDelaySwitch} / DP${MowerDp.rainDelay}',
    );
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
                      subtitle: '雨淋结束后延迟恢复割草（DP${MowerDp.rainDetectEnable}）',
                      value: _enabled,
                      switchKey: const Key('mower-rain-switch'),
                      onChanged: (value) => setState(() => _enabled = value),
                    ),
                    const MowerRowDivider(indent: 20),
                    MowerSwitchRow(
                      title: '延迟时间',
                      subtitle: '雨滴延时开关（DP${MowerDp.rainDelaySwitch}）',
                      value: _delayEnabled,
                      switchKey: const Key('mower-rain-delay-switch'),
                      onChanged: (value) =>
                          setState(() => _delayEnabled = value),
                    ),
                    IgnorePointer(
                      ignoring: !_delayEnabled,
                      child: Opacity(
                        opacity: _delayEnabled ? 1 : .4,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                          child: SizedBox(
                            height: _itemExtent * 3,
                            child: Stack(
                              children: <Widget>[
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
                                        // 0 / 1 / 2 —— DP105 上限 120 分钟
                                        count: _maxDelay ~/ 60 + 1,
                                        selected: _hours,
                                        itemExtent: _itemExtent,
                                        unit: '时',
                                        onSelected: (value) => setState(() {
                                          _hours = value;
                                          _clampToRange();
                                        }),
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
                                        onSelected: (value) => setState(() {
                                          _minutes = value;
                                          _clampToRange();
                                        }),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                      child: Text(
                        '延迟 $_totalMinutes 分钟（DP${MowerDp.rainDelay} 取值 0-$_maxDelay）',
                        key: const Key('mower-rain-summary'),
                        style: const TextStyle(
                          color: MowerColors.inkSecondary,
                          fontSize: 12,
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
              onPressed: _save,
            ),
          ),
        ],
      ),
    );
  }
}
