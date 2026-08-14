import 'package:flutter/material.dart';

import '../../../design_system/design_system.dart';
import '../../../routes/app_routes.dart';
import '../../../tuya/tuya_models.dart';
import 'pairing_page.dart';

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

  /// Connects to the picked planter, then collects the Wi-Fi credentials.
  /// Provisioning itself runs on the Wi-Fi page.
  Future<void> _connect(int index) async {
    if (_connectingIndex != null) return;
    setState(() => _connectingIndex = index);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    setState(() => _connectingIndex = null);
    await Navigator.pushNamed(
      context,
      AppRoutes.pairing,
      arguments: PairingArguments(
        deviceName: _devices[index].name,
        // Carries the credentials back when arriving from the failure page.
        request: widget.request,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      appBar: const AppPageHeader(title: '选择设备', leading: AppBackButton()),
      background: AppPageBackground.account,
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
      child: Image.asset(
        AppAssets.pairingDeviceSelectionIllustration,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        excludeFromSemantics: true,
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
          SizedBox.square(
            dimension: 42,
            child: Image.asset(
              AppAssets.devicePlanterIcon,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              semanticLabel: 'YSplanter 设备',
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
