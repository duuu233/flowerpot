import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/l10n/app_l10n.dart';
import '../../../tuya/tuya_config.dart';

/// 休眠模式：开关（DP 151 `standby_switch`）+ 延迟时间（DP 152 `standby_delay`，
/// 1–180 分钟）。版式照 `docs/UI/v2/割草机/割草机-雨淋设置.png`：一张卡，上半是
/// 开关和一句说明，下半是「延迟时间」滚轮，页面底部一个「保存」。
///
/// 开关即时下发（和 LED、行为那几页一致，用户拨完就该看到结果）；滚轮不即时下发
/// ——滚动过程中每一格都发一条 DP 只会把指令堆在链路上，所以由「保存」一次写入。
class StandbySettingsPage extends StatefulWidget {
  const StandbySettingsPage({required this.deviceId, super.key});

  final String deviceId;

  @override
  State<StandbySettingsPage> createState() => _StandbySettingsPageState();
}

class _StandbySettingsPageState extends State<StandbySettingsPage> {
  /// 滚轮一格的高度，和选中态那条高亮带同高。
  static const double _itemExtent = 44;

  late final FixedExtentScrollController _hourController;
  late final FixedExtentScrollController _minuteController;

  /// 页面打开时读一次设备当前值；之后由滚轮驱动，保存后再回到设备值。
  int _hours = 0;
  int _minutes = 30;
  bool _loaded = false;
  bool _updatingSwitch = false;
  bool _saving = false;

  int get _totalMinutes => _hours * 60 + _minutes;

  @override
  void initState() {
    super.initState();
    _hourController = FixedExtentScrollController();
    _minuteController = FixedExtentScrollController();
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    super.dispose();
  }

  void _loadOnce(int delayMinutes) {
    if (_loaded) return;
    _loaded = true;
    _hours = delayMinutes ~/ 60;
    _minutes = delayMinutes % 60;
    // 控制器要等第一帧之后才有 attach 的滚轮可跳。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_hourController.hasClients) _hourController.jumpToItem(_hours);
      if (_minuteController.hasClients) _minuteController.jumpToItem(_minutes);
    });
  }

  /// 把两个滚轮的取值收进 [TuyaConfig.standbyDelayMin]–[TuyaConfig.standbyDelayMax]。
  ///
  /// 3 时 30 分是 210 分钟，设备只认到 180；0 时 0 分是 0，也不合法。越界时把越界的
  /// 那一根滚轮拨回去，用户看到的就是「拨不过去」，而不是保存时才被告知。
  void _clampToRange() {
    final total = _totalMinutes;
    if (total > TuyaConfig.standbyDelayMax) {
      _hours = TuyaConfig.standbyDelayMax ~/ 60;
      _minutes = TuyaConfig.standbyDelayMax % 60;
    } else if (total < TuyaConfig.standbyDelayMin) {
      _hours = TuyaConfig.standbyDelayMin ~/ 60;
      _minutes = TuyaConfig.standbyDelayMin % 60;
    } else {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_hourController.hasClients &&
          _hourController.selectedItem != _hours) {
        _hourController.animateToItem(
          _hours,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
      if (_minuteController.hasClients &&
          _minuteController.selectedItem != _minutes) {
        _minuteController.animateToItem(
          _minutes,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _setEnabled(bool value) async {
    if (_updatingSwitch) return;
    setState(() => _updatingSwitch = true);
    final result = await FlowerpotScope.of(
      context,
    ).updateSetting(widget.deviceId, 'standby', value);
    if (!mounted) return;
    setState(() => _updatingSwitch = false);
    if (!result.success) {
      showAppMessage(context, result.message, tone: AppMessageTone.error);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final l10n = AppL10n.of(context);
    final minutes = _totalMinutes;
    if (minutes < TuyaConfig.standbyDelayMin ||
        minutes > TuyaConfig.standbyDelayMax) {
      showAppMessage(
        context,
        l10n.standbyDelayRange(
          TuyaConfig.standbyDelayMin,
          TuyaConfig.standbyDelayMax,
        ),
        tone: AppMessageTone.error,
      );
      return;
    }
    setState(() => _saving = true);
    final result = await FlowerpotScope.of(
      context,
    ).updateSetting(widget.deviceId, 'standbyDelay', minutes);
    if (!mounted) return;
    setState(() => _saving = false);
    showAppMessage(
      context,
      result.message,
      tone: result.success ? AppMessageTone.success : AppMessageTone.error,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final device = FlowerpotScope.of(context).deviceById(widget.deviceId);
    if (device == null) {
      return AppPageScaffold(
        appBar: AppPageHeader(
          title: l10n.standby,
          leading: const AppBackButton(),
        ),
        body: AppErrorView(
          title: l10n.deviceNotFound,
          message: l10n.deviceNotFoundMessage,
        ),
      );
    }
    final settings = device.settings;
    _loadOnce(settings.standbyDelayMinutes);
    return AppPageScaffold(
      appBar: AppPageHeader(title: l10n.standby, leading: const AppBackButton()),
      background: AppPageBackground.standard,
      body: Column(
        children: <Widget>[
          Expanded(
            child: SingleChildScrollView(
              key: const Key('standby-settings-scroll-view'),
              child: ResponsiveContent(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.pageMargin,
                  37,
                  AppSpacing.pageMargin,
                  24,
                ),
                child: AppSurfaceCard(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  l10n.standbyEnable,
                                  style: AppTypography.sectionTitle.copyWith(
                                    fontSize: 17,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  l10n.standbyDescription,
                                  style: AppTypography.smallBody,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Switch(
                            key: const Key('standby-switch'),
                            value: settings.standbyEnabled,
                            onChanged: _updatingSwitch ? null : _setEnabled,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      const Divider(height: 1, color: AppColors.divider),
                      const SizedBox(height: 18),
                      Text(
                        l10n.standbyDelay,
                        style: AppTypography.sectionTitle.copyWith(
                          fontSize: 17,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: _itemExtent * 3,
                        child: Stack(
                          children: <Widget>[
                            // 选中态的高亮带：滚轮本身只负责数字，居中那一格由它衬底。
                            Center(
                              child: Container(
                                height: _itemExtent,
                                decoration: BoxDecoration(
                                  color: AppColors.canvas,
                                  borderRadius: AppRadius.small,
                                ),
                              ),
                            ),
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: _DelayWheel(
                                    wheelKey: const Key('standby-hour-wheel'),
                                    controller: _hourController,
                                    itemExtent: _itemExtent,
                                    count: TuyaConfig.standbyDelayMax ~/ 60 + 1,
                                    selected: _hours,
                                    unit: l10n.hourUnit,
                                    onSelected: (value) {
                                      setState(() {
                                        _hours = value;
                                        _clampToRange();
                                      });
                                    },
                                  ),
                                ),
                                Expanded(
                                  child: _DelayWheel(
                                    wheelKey: const Key('standby-minute-wheel'),
                                    controller: _minuteController,
                                    itemExtent: _itemExtent,
                                    count: 60,
                                    selected: _minutes,
                                    unit: l10n.minuteUnit,
                                    onSelected: (value) {
                                      setState(() {
                                        _minutes = value;
                                        _clampToRange();
                                      });
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: ResponsiveContent(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.pageMargin,
                0,
                AppSpacing.pageMargin,
                24,
              ),
              child: AppPrimaryButton(
                key: const Key('standby-save-button'),
                label: l10n.save,
                loading: _saving,
                onPressed: _saving ? null : _save,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 一根滚轮：数字居中，单位跟在选中那一格右边。
class _DelayWheel extends StatelessWidget {
  const _DelayWheel({
    required this.wheelKey,
    required this.controller,
    required this.itemExtent,
    required this.count,
    required this.selected,
    required this.unit,
    required this.onSelected,
  });

  final Key wheelKey;
  final FixedExtentScrollController controller;
  final double itemExtent;
  final int count;
  final int selected;
  final String unit;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return ListWheelScrollView.useDelegate(
      key: wheelKey,
      controller: controller,
      itemExtent: itemExtent,
      physics: const FixedExtentScrollPhysics(),
      // 透视压到最小：这一版设计里滚轮是平的，不要 iOS 那种圆筒感。
      perspective: 0.001,
      diameterRatio: 20,
      onSelectedItemChanged: onSelected,
      childDelegate: ListWheelChildBuilderDelegate(
        childCount: count,
        builder: (context, index) {
          final active = index == selected;
          return Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: <Widget>[
                Text(
                  index.toString().padLeft(2, '0'),
                  style: TextStyle(
                    color: active
                        ? AppColors.textPrimary
                        : AppColors.textTertiary,
                    fontSize: active ? 26 : 22,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                if (active) ...<Widget>[
                  const SizedBox(width: 6),
                  Text(
                    unit,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 15,
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
