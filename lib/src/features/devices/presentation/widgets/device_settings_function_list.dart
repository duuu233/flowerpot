import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../models/device_settings_page_model.dart';

class DeviceSettingsFunctionList extends StatelessWidget {
  const DeviceSettingsFunctionList({
    required this.items,
    required this.onItemTap,
    super.key,
  });

  final List<DeviceSettingsMenuItem> items;
  final ValueChanged<DeviceSettingsMenuKind> onItemTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Container(width: 4, height: 18, color: AppColors.brandPrimary),
            const SizedBox(width: AppSpacing.sm),
            Text(
              '功能设置',
              style: AppTypography.pageTitle.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        // 行高抬到 58 并补下划线，与「账号与安全」那张卡（忘记密码所在的列表）
        // 一致；分隔线左右缩进对齐这里的 20px 内容边距。
        AppSettingsList(
          borderRadius: AppRadius.large,
          dividerIndent: 20,
          dividerEndIndent: 20,
          children: <Widget>[
            for (final item in items)
              AppSettingsTile(
                title: item.label,
                value: item.value,
                minTileHeight: 58,
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                leading: _LeadingIcon(kind: item.kind, label: item.label),
                // 字重用常规 w400，不用 sectionTitle 的 w500（2026-09-15 产品：「LED设置」的
                // LED 看着加粗，要和其它行一致）。App 没有打包字体：Android 上中文落到
                // 系统思源黑体，只有常规 / 粗体两档，w500 画出来就是常规；英文落到
                // Roboto，它有 Medium，w500 真画成中粗——同一个样式，只有「LED」显粗。
                titleStyle: AppTypography.sectionTitle.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                ),
                // 默认的 trailing 只有取值和箭头，红点行得自己拼一遍。
                trailing: item.badge ? _BadgedTrailing(value: item.value) : null,
                onTap: () => onItemTap(item.kind),
              ),
          ],
        ),
      ],
    );
  }
}

/// 行尾：小红点 + 原本的取值和箭头。
class _BadgedTrailing extends StatelessWidget {
  const _BadgedTrailing({this.value});

  final String? value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const AppNoticeDot(semanticLabel: '有新固件'),
        const SizedBox(width: AppSpacing.xs),
        if (value != null) ...<Widget>[
          Text(value!, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(width: AppSpacing.xs),
        ],
        const AppTrailingChevron(),
      ],
    );
  }
}

/// 行首的小图标。
///
/// 老的七项都有切图；LED 设置和纪念日是 v2 才加的，Figma 还没给图，用同尺寸的
/// Material 图标顶上——留个空位或者借用别人的切图都会让这两行看起来像画错了。
class _LeadingIcon extends StatelessWidget {
  const _LeadingIcon({required this.kind, required this.label});

  final DeviceSettingsMenuKind kind;
  final String label;

  @override
  Widget build(BuildContext context) {
    if (kind == DeviceSettingsMenuKind.battery) {
      return Semantics(
        label: label,
        child: const SizedBox.square(
          key: Key('settings-battery-icon'),
          dimension: 25,
          child: CustomPaint(painter: _BatteryLinePainter()),
        ),
      );
    }
    final asset = _assetFor(kind);
    if (asset == null) {
      return Icon(
        _iconFor(kind),
        size: 24,
        color: AppColors.brandDark,
        semanticLabel: label,
      );
    }
    return Image.asset(
      asset,
      width: 25,
      height: 25,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      semanticLabel: label,
    );
  }

  static String? _assetFor(DeviceSettingsMenuKind kind) => switch (kind) {
    DeviceSettingsMenuKind.plant => AppAssets.settingsPlantIcon,
    DeviceSettingsMenuKind.display => AppAssets.settingsDisplayIcon,
    DeviceSettingsMenuKind.hearing => AppAssets.settingsHearingIcon,
    DeviceSettingsMenuKind.touch => AppAssets.settingsTouchIcon,
    DeviceSettingsMenuKind.vibration => AppAssets.settingsVibrationIcon,
    DeviceSettingsMenuKind.behavior => AppAssets.settingsBehaviorIcon,
    DeviceSettingsMenuKind.other => AppAssets.settingsOtherIcon,
    DeviceSettingsMenuKind.led ||
    DeviceSettingsMenuKind.memorial ||
    DeviceSettingsMenuKind.battery ||
    DeviceSettingsMenuKind.plantDetection => null,
  };

  static IconData _iconFor(DeviceSettingsMenuKind kind) => switch (kind) {
    DeviceSettingsMenuKind.memorial => Icons.event_note_outlined,
    DeviceSettingsMenuKind.plantDetection => Icons.eco_outlined,
    _ => Icons.lightbulb_outline,
  };
}

/// 「电池状态」那一行的图标（2026-09-15 挪进设置页）。
///
/// 这一列的切图是品牌青 `#70AFB5`、无底色的描边图标（40 px 图里线宽约 2.5，画在 25 上
/// 约 1.6），Figma 没给电池这一枚；Material 的电池图标是实心的，和旁边几枚对不上，
/// 所以按同样的颜色和线宽自己画：圆角电池外框 + 正极 + 闪电。坐标按 24 格设计，随尺寸缩放。
class _BatteryLinePainter extends CustomPainter {
  const _BatteryLinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.shortestSide / 24;
    final paint = Paint()
      ..color = AppColors.brandPrimary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 * unit
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawRRect(
      RRect.fromLTRBR(
        2 * unit,
        6.5 * unit,
        19.5 * unit,
        17.5 * unit,
        Radius.circular(2.4 * unit),
      ),
      paint,
    );
    canvas.drawLine(
      Offset(22 * unit, 10.2 * unit),
      Offset(22 * unit, 13.8 * unit),
      paint,
    );
    final bolt = Path()
      ..moveTo(12.2 * unit, 8.8 * unit)
      ..lineTo(9.2 * unit, 12.3 * unit)
      ..lineTo(12.3 * unit, 12.3 * unit)
      ..lineTo(9.4 * unit, 15.2 * unit);
    canvas.drawPath(bolt, paint);
  }

  @override
  bool shouldRepaint(covariant _BatteryLinePainter oldDelegate) => false;
}
