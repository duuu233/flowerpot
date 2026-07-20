import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../../../routes/app_routes.dart';
import '../../../tuya/tuya_models.dart';

class DeviceSelectionPage extends StatefulWidget {
  const DeviceSelectionPage({super.key, this.request});

  final PairingRequest? request;

  @override
  State<DeviceSelectionPage> createState() => _DeviceSelectionPageState();
}

class _DeviceSelectionPageState extends State<DeviceSelectionPage> {
  static const _devices = <_NearbyDevice>[
    _NearbyDevice(name: 'YSplanter-01', signalBars: 4),
    _NearbyDevice(name: 'YSplanter-02', signalBars: 2),
    _NearbyDevice(name: 'YSplanter-03', signalBars: 1),
  ];

  int? _connectingIndex;

  Future<void> _connect(int index) async {
    if (_connectingIndex != null) return;
    if (widget.request == null) {
      await Navigator.pushNamed(context, AppRoutes.pairing);
      return;
    }

    setState(() => _connectingIndex = index);
    final state = FlowerpotScope.of(context);
    final result = await state.pairDevice(widget.request!);
    if (!mounted) return;
    if (!result.success) {
      setState(() => _connectingIndex = null);
      Navigator.pushReplacementNamed(
        context,
        AppRoutes.pairingFailure,
        arguments: widget.request,
      );
      return;
    }
    Navigator.pushReplacementNamed(
      context,
      AppRoutes.pairingSuccess,
      arguments: state.selectedDevice!.id,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      appBar: const AppPageHeader(title: '选择设备', leading: AppBackButton()),
      background: AppPageBackground.standard,
      body: ResponsiveContent(
        maxWidth: 375,
        padding: EdgeInsets.zero,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 650;
            return SingleChildScrollView(
              key: const Key('device-selection-scroll-view'),
              padding: EdgeInsets.fromLTRB(20, compact ? 50 : 70, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _DeviceSelectionIllustration(compact: compact),
                  SizedBox(height: compact ? 8 : 14),
                  const Text(
                    '请选择需要连接的设备',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 15,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _DeviceListCard(
                    devices: _devices,
                    connectingIndex: _connectingIndex,
                    onConnect: _connect,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _NearbyDevice {
  const _NearbyDevice({required this.name, required this.signalBars});

  final String name;
  final int signalBars;
}

class _DeviceSelectionIllustration extends StatelessWidget {
  const _DeviceSelectionIllustration({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: compact ? 205 : 285,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          _SignalDisc(size: compact ? 194 : 260, opacity: .25),
          _SignalDisc(size: compact ? 142 : 190, opacity: .34),
          _SignalDisc(size: compact ? 92 : 126, opacity: .46),
          const Positioned(left: 66, top: 15, child: _SoftDot(size: 8)),
          const Positioned(right: 53, top: 74, child: _SoftDot(size: 8)),
          const Positioned(left: 88, bottom: 15, child: _SoftDot(size: 9)),
          const Positioned(right: 95, bottom: 0, child: _SoftDot(size: 10)),
          Positioned(
            left: compact ? 6 : 22,
            child: const Opacity(
              opacity: .34,
              child: _WifiDeviceHub(scale: .62),
            ),
          ),
          const _WifiDeviceHub(),
          Positioned(
            right: compact ? 6 : 22,
            child: const Opacity(
              opacity: .34,
              child: _WifiDeviceHub(scale: .62),
            ),
          ),
        ],
      ),
    );
  }
}

class _SignalDisc extends StatelessWidget {
  const _SignalDisc({required this.size, required this.opacity});

  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.brandSurface.withValues(alpha: opacity),
        shape: BoxShape.circle,
      ),
      child: SizedBox.square(dimension: size),
    );
  }
}

class _SoftDot extends StatelessWidget {
  const _SoftDot({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.brandSoft.withValues(alpha: .35),
        shape: BoxShape.circle,
      ),
      child: SizedBox.square(dimension: size),
    );
  }
}

class _WifiDeviceHub extends StatelessWidget {
  const _WifiDeviceHub({this.scale = 1});

  final double scale;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 92 * scale,
      height: 91 * scale,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: <Widget>[
          Positioned(
            top: 0,
            child: Icon(
              Icons.wifi_rounded,
              color: AppColors.brandPrimary,
              size: 64 * scale,
            ),
          ),
          Container(
            width: 84 * scale,
            height: 38 * scale,
            decoration: BoxDecoration(
              color: AppColors.brandPrimary,
              borderRadius: BorderRadius.all(Radius.circular(16 * scale)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List<Widget>.generate(
                3,
                (index) => Padding(
                  padding: EdgeInsets.symmetric(horizontal: 5 * scale),
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      color: AppColors.surface,
                      shape: BoxShape.circle,
                    ),
                    child: SizedBox.square(dimension: 8 * scale),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceListCard extends StatelessWidget {
  const _DeviceListCard({
    required this.devices,
    required this.connectingIndex,
    required this.onConnect,
  });

  final List<_NearbyDevice> devices;
  final int? connectingIndex;
  final ValueChanged<int> onConnect;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.card,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: <Widget>[
            for (var index = 0; index < devices.length; index++) ...<Widget>[
              _DeviceRow(
                device: devices[index],
                index: index,
                loading: connectingIndex == index,
                disabled: connectingIndex != null && connectingIndex != index,
                onConnect: () => onConnect(index),
              ),
              if (index != devices.length - 1)
                const Divider(height: 1, color: AppColors.divider),
            ],
          ],
        ),
      ),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.device,
    required this.index,
    required this.loading,
    required this.disabled,
    required this.onConnect,
  });

  final _NearbyDevice device;
  final int index;
  final bool loading;
  final bool disabled;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: Row(
        children: <Widget>[
          const DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.brandSurface,
              borderRadius: AppRadius.card,
            ),
            child: SizedBox.square(
              dimension: 42,
              child: CustomPaint(painter: _PlantDevicePainter()),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              device.name,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          _SignalBars(activeBars: device.signalBars),
          const SizedBox(width: 18),
          SizedBox(
            width: 62,
            height: 32,
            child: FilledButton(
              key: Key('connect-device-$index'),
              onPressed: disabled ? null : onConnect,
              style: FilledButton.styleFrom(
                padding: EdgeInsets.zero,
                backgroundColor: AppColors.brandPrimary,
                foregroundColor: AppColors.surface,
                disabledBackgroundColor: AppColors.disabled,
                shape: const StadiumBorder(),
                textStyle: const TextStyle(fontSize: 14),
              ),
              child: loading
                  ? const SizedBox.square(
                      dimension: 15,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.surface,
                      ),
                    )
                  : const Text('连接'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SignalBars extends StatelessWidget {
  const _SignalBars({required this.activeBars});

  final int activeBars;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24,
      height: 22,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List<Widget>.generate(4, (index) {
          return DecoratedBox(
            decoration: BoxDecoration(
              color: index < activeBars
                  ? AppColors.brandPrimary
                  : AppColors.disabled,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(1.5),
              ),
            ),
            child: SizedBox(width: 4, height: 7 + index * 4),
          );
        }),
      ),
    );
  }
}

class _PlantDevicePainter extends CustomPainter {
  const _PlantDevicePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = AppColors.brandPrimary;
    canvas.save();
    canvas.translate(size.width * .49, size.height * .38);
    canvas.rotate(-math.pi / 4);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 10, height: 18),
      paint,
    );
    canvas.restore();
    canvas.save();
    canvas.translate(size.width * .62, size.height * .31);
    canvas.rotate(math.pi / 4);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 10, height: 18),
      paint,
    );
    canvas.restore();
    canvas.drawRect(
      Rect.fromLTWH(size.width * .48, size.height * .33, 2.5, 11),
      paint,
    );
    canvas.drawRect(
      Rect.fromLTWH(size.width * .28, size.height * .51, size.width * .44, 4),
      paint,
    );
    final pot = Path()
      ..moveTo(size.width * .33, size.height * .61)
      ..lineTo(size.width * .67, size.height * .61)
      ..lineTo(size.width * .62, size.height * .82)
      ..lineTo(size.width * .38, size.height * .82)
      ..close();
    canvas.drawPath(pot, paint);
  }

  @override
  bool shouldRepaint(_PlantDevicePainter oldDelegate) => false;
}
