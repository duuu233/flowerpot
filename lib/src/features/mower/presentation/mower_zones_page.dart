import 'package:flutter/material.dart';

import '../../devices/presentation/device_online_guard.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../mower_ui.dart';
import '../mower_device.dart';
import '../mower_dp.dart';
import 'widgets/mower_card.dart';
import 'widgets/mower_form.dart';

/// 区域设置（`割草机-区域设置.png`）→ **DP103 zone_config**（raw 25 字节 = 5 区 × 5 字节）。
///
/// ⚠️ 三条设备口径（V2.2 §5.2），页面必须自己守住：
/// 1. **全量替换**：每次下发覆盖全部 5 个区，所以保存时 5 个区一起发；
/// 2. **百分比 0 = 删除该区**（即使有效位是 1）；
/// 3. **Σ 有效区百分比 > 100 设备整包拒绝**（原配置保留）——这里保存前就拦下来，
///    否则用户看到"保存成功"而设备那边一个字节都没改。
class MowerZonesPage extends StatefulWidget {
  const MowerZonesPage({super.key});

  /// 占比滑条一格 = 5%（2026-10-08 用户：「占比每次滑动按 5 为最小单位来递增递减」）。
  /// 设备报上来的旧值不是 5 的倍数时照原值显示、不替用户改，拖一下才落到 5 的倍数上。
  static const int percentStep = 5;

  @override
  State<MowerZonesPage> createState() => _MowerZonesPageState();
}

class _MowerZonesPageState extends State<MowerZonesPage> {
  MowerDevice get _device => MowerDevice.instance;

  late List<MowerZoneConfig> _zones = List<MowerZoneConfig>.of(_device.zones);

  int get _total => _zones.fold(
    0,
    (sum, zone) => sum + (zone.percent > 0 ? zone.percent : 0),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      FlowerpotScope.of(context)
        ..logPageEntry('割草机-区域设置')
        ..logMowerInteraction(
          '读取 ← 割草机-区域设置 DP${MowerDp.zoneConfig} zone_config '
          '= ${MowerZoneCodec.toHexZones(MowerZoneCodec.encode(_zones))}',
        );
    });
  }

  void _setPercent(int index, int percent) {
    setState(() {
      _zones[index] = MowerZoneConfig(
        index: _zones[index].index,
        percent: percent,
        meters: _zones[index].meters,
      );
    });
  }

  Future<void> _editMeters(int index) async {
    final zone = _zones[index];
    final value = await showAppInputDialog(
      context,
      title: '区域 ${zone.index} 出发点距离',
      message:
          '单位米，最大 ${MowerZoneCodec.maxMeters}（DP${MowerDp.zoneConfig} 第 3-4 字节）',
      initialValue: '${zone.meters}',
      keyboardType: TextInputType.number,
    );
    if (value == null || !mounted) return;
    final meters = int.tryParse(value.trim());
    if (meters == null) return;
    setState(() {
      _zones[index] = MowerZoneConfig(
        index: zone.index,
        percent: zone.percent,
        meters: meters.clamp(0, MowerZoneCodec.maxMeters),
      );
    });
  }

  void _save() {
    final id = _device.deviceId;
    if (id == null || !ensureDeviceOnline(context, id)) return;
    final state = FlowerpotScope.of(context);
    // 先拦 Σ>100：设备是**整包拒绝**，发下去等于什么都没做，还让用户以为成了。
    if (_total > MowerZoneCodec.maxTotalPercent) {
      state.logMowerInteraction(
        '下发被拦 ✗ 割草机 DP${MowerDp.zoneConfig}：Σ 百分比 $_total% > 100%，设备会整包拒绝',
      );
      showAppMessage(
        context,
        '区域占比合计 $_total%，不能大于 100%',
        tone: AppMessageTone.error,
      );
      return;
    }
    _device.setZones(state, _zones);
    showAppMessage(context, '已下发 DP${MowerDp.zoneConfig}（区域配置）');
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      appBar: const AppPageHeader(title: '区域设置', leading: AppBackButton()),
      body: DeviceOnlineBody(
        deviceId: MowerDevice.instance.deviceId,
        child: SingleChildScrollView(
          key: const Key('mower-zones-scroll-view'),
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              MowerCard(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const Row(
                      children: <Widget>[
                        Expanded(child: _ColumnHeader(text: '区域占比')),
                        SizedBox(
                          width: 91,
                          child: _ColumnHeader(
                            text: '距离',
                            align: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                    for (var i = 0; i < _zones.length; i++)
                      _ZoneRow(
                        zone: _zones[i],
                        last: i == _zones.length - 1,
                        onChanged: (value) => _setPercent(i, value),
                        onEditMeters: () => _editMeters(i),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              MowerNoteList(
                notes: <String>[
                  '1. 区域设置总和不能大于 100%（当前 $_total%）',
                  '2. 距离最大可设置 ${MowerZoneCodec.maxMeters} 米',
                  '3. 百分比为 0 表示删除该区域（DP${MowerDp.zoneConfig} 口径）',
                ],
              ),
              const SizedBox(height: 33),
              MowerSaveButton(
                buttonKey: const Key('mower-zones-save'),
                onPressed: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ColumnHeader extends StatelessWidget {
  const _ColumnHeader({required this.text, this.align = TextAlign.left});

  final String text;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: align,
      style: const TextStyle(color: MowerColors.inkTertiary, fontSize: 14),
    );
  }
}

class _ZoneRow extends StatelessWidget {
  const _ZoneRow({
    required this.zone,
    required this.last,
    required this.onChanged,
    required this.onEditMeters,
  });

  final MowerZoneConfig zone;
  final bool last;
  final ValueChanged<int> onChanged;
  final VoidCallback onEditMeters;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Padding(
          // 稿子 561:3090 一行 72 高。
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Text(
                          '区域 ${zone.index}',
                          style: const TextStyle(
                            color: MowerColors.ink,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          '${zone.percent}%',
                          key: Key('mower-zone-percent-${zone.index}'),
                          style: TextStyle(
                            color: zone.percent == 0
                                ? MowerColors.inkTertiary
                                : MowerColors.brand,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 4,
                        activeTrackColor: MowerColors.brand,
                        inactiveTrackColor: MowerColors.brand.withValues(
                          alpha: .16,
                        ),
                        thumbColor: MowerColors.brand,
                        overlayColor: MowerColors.brand.withValues(alpha: .12),
                        // 稿子滑块直径 14；按压光圈收到 14，滑条本身只占 28 高
                        // （默认 48 的触控留白把一行撑到 95，稿子 72）。
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 7,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 14,
                        ),
                        trackShape: const RoundedRectSliderTrackShape(),
                        // 分档后 Material 默认在每一格画个点，稿子上的滑条是光的。
                        tickMarkShape: SliderTickMarkShape.noTickMark,
                      ),
                      child: SizedBox(
                        height: 28,
                        child: Slider(
                          key: Key('mower-zone-slider-${zone.index}'),
                          value: zone.percent.toDouble(),
                          max: 100,
                          divisions: 100 ~/ MowerZonesPage.percentStep,
                          onChanged: (value) => onChanged(
                            (value / MowerZonesPage.percentStep).round() *
                                MowerZonesPage.percentStep,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                key: Key('mower-zone-meters-${zone.index}'),
                onTap: onEditMeters,
                child: Container(
                  width: 91,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .6),
                    border: Border.all(
                      color: MowerColors.brand.withValues(alpha: .35),
                    ),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Text(
                    '${zone.meters} 米',
                    style: const TextStyle(
                      color: MowerColors.ink,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (!last) const MowerRowDivider(indent: 0),
      ],
    );
  }
}
