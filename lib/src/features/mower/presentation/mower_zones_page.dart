import 'package:flutter/material.dart';

import '../../../design_system/design_system.dart';
import '../mower_demo.dart';
import 'widgets/mower_card.dart';
import 'widgets/mower_form.dart';

/// 区域设置（`割草机-区域设置.png`）：五个区域各一条占比滑块和一个距离框。
///
/// 静态页：滑块拖得动（拖了就能看到百分比和条一起变），但不写设备；距离框是只读的
/// 展示，稿子没给输入态。
class MowerZonesPage extends StatefulWidget {
  const MowerZonesPage({super.key});

  @override
  State<MowerZonesPage> createState() => _MowerZonesPageState();
}

class _MowerZonesPageState extends State<MowerZonesPage> {
  late final List<int> _percents = MowerDemoZones.zones
      .map((zone) => zone.percent)
      .toList(growable: false);

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      appBar: const AppPageHeader(title: '区域设置', leading: AppBackButton()),
      body: SingleChildScrollView(
        key: const Key('mower-zones-scroll-view'),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            MowerCard(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Row(
                    children: <Widget>[
                      Expanded(child: _ColumnHeader(text: '区域占比')),
                      SizedBox(
                        width: 96,
                        child: _ColumnHeader(
                          text: '距离',
                          align: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                  for (var i = 0; i < MowerDemoZones.zones.length; i++)
                    _ZoneRow(
                      zone: MowerDemoZones.zones[i],
                      percent: _percents[i],
                      last: i == MowerDemoZones.zones.length - 1,
                      onChanged: (value) =>
                          setState(() => _percents[i] = value),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const MowerNoteList(notes: MowerDemoZones.notes),
            const SizedBox(height: 22),
            MowerSaveButton(
              buttonKey: const Key('mower-zones-save'),
              onPressed: () => showAppMessage(
                context,
                '静态页面：区域不会真的下发',
                tone: AppMessageTone.info,
              ),
            ),
          ],
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
    required this.percent,
    required this.last,
    required this.onChanged,
  });

  final MowerZone zone;
  final int percent;
  final bool last;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
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
                          zone.name,
                          style: const TextStyle(
                            color: MowerColors.ink,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          '$percent%',
                          key: Key('mower-zone-percent-${zone.name}'),
                          style: const TextStyle(
                            color: MowerColors.brand,
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
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 9,
                        ),
                        trackShape: const RoundedRectSliderTrackShape(),
                      ),
                      child: Slider(
                        key: Key('mower-zone-slider-${zone.name}'),
                        value: percent.toDouble(),
                        max: 100,
                        onChanged: (value) => onChanged(value.round()),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _DistanceBox(meters: zone.meters),
            ],
          ),
        ),
        if (!last) const MowerRowDivider(indent: 0),
      ],
    );
  }
}

/// 距离框：稿子上是个只读的圆角框，不是输入框。
class _DistanceBox extends StatelessWidget {
  const _DistanceBox({required this.meters});

  final int meters;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .6),
        border: Border.all(color: MowerColors.brand.withValues(alpha: .35)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$meters 米',
        style: const TextStyle(color: MowerColors.ink, fontSize: 16),
      ),
    );
  }
}
