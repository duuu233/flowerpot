import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../../../routes/app_routes.dart';
import '../../../tuya/tuya_models.dart';
import 'pairing_page.dart';

/// Second provisioning step: pick which planter to provision.
///
/// The rows are the access points a planter raises in AP mode, taken from the
/// last `scanWifi` result — there is no device-discovery API in the Tuya SDK
/// and the product has no BLE pairing, so a hotspot is the only device the
/// phone can actually observe. Picking one carries its SSID to the Wi-Fi step,
/// which tells the user exactly which hotspot to join before provisioning.
///
/// Recognition by SSID prefix is a guess, so the page never stops at it: the
/// remaining scanned networks are one tap away (and shown outright when
/// nothing was recognized), the same raw list the SDK debug console prints.
/// A planter whose hotspot is named outside the whitelist showed up there and
/// nowhere else, which left provisioning with no way forward.
class DeviceSelectionPage extends StatefulWidget {
  const DeviceSelectionPage({super.key, this.request});

  final PairingRequest? request;

  @override
  State<DeviceSelectionPage> createState() => _DeviceSelectionPageState();
}

class _DeviceSelectionPageState extends State<DeviceSelectionPage> {
  bool _scanning = false;
  ActionResult? _result;

  @override
  void initState() {
    super.initState();
    // Arriving from the search step the scan is already in state; arriving from
    // the failure screen it may not be.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (FlowerpotScope.of(context).wifiScan == null) _scan();
    });
  }

  Future<void> _scan() async {
    if (!mounted || _scanning) return;
    setState(() {
      _scanning = true;
      _result = null;
    });
    final result = await FlowerpotScope.of(context).probeWifi();
    if (!mounted) return;
    setState(() {
      _scanning = false;
      _result = result;
    });
  }

  /// Moves to the Wi-Fi credentials for the picked planter.
  ///
  /// Nothing is "connected" here: joining a hotspot is a system-level action
  /// the app cannot perform. The name is
  /// carried so the next page can name the hotspot to join in AP mode.
  void _connect(WifiNetwork device) {
    Navigator.pushNamed(
      context,
      AppRoutes.pairing,
      arguments: PairingArguments(
        deviceName: device.ssid,
        hotspotSsid: device.ssid,
        // Carries the credentials back when arriving from the failure page.
        request: widget.request,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scan = FlowerpotScope.of(context).wifiScan;
    final hotspots = scan?.deviceHotspots ?? const <WifiNetwork>[];
    final others = scan?.otherNetworks ?? const <WifiNetwork>[];
    // Nothing was recognized: the raw scan is all there is, so it is listed
    // straight away rather than behind a "show more" the user has to find.
    final devices = hotspots.isEmpty
        ? <WifiNetwork>[...hotspots, ...others]
        : hotspots;
    return AppPageScaffold(
      appBar: const AppPageHeader(title: '选择设备', leading: AppBackButton()),
      background: AppPageBackground.account,
      body: ResponsiveContent(
        padding: EdgeInsets.zero,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 650;
            // No answer yet: either a scan is running, or the one started after
            // the first frame has not reported back. Neither is "no device".
            final pending = _scanning || (_result == null && scan == null);
            return SingleChildScrollView(
              key: const Key('device-selection-scroll-view'),
              padding: EdgeInsets.fromLTRB(
                AppSpacing.pageMargin,
                compact ? 50 : 70,
                AppSpacing.pageMargin,
                24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _DeviceSelectionIllustration(compact: compact),
                  SizedBox(height: compact ? 8 : 14),
                  Text(
                    _title(devices, hotspots, pending),
                    key: const Key('device-selection-title'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 15,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (devices.isEmpty)
                    _EmptySelectionCard(
                      message: _emptyMessage(scan, pending),
                      scanning: pending,
                      onRescan: _scan,
                    )
                  else ...<Widget>[
                    if (hotspots.isEmpty) ...<Widget>[
                      const _ManualPickNotice(),
                      const SizedBox(height: 12),
                    ],
                    _DeviceListCard(
                      devices: devices,
                      recognized: hotspots.length,
                      onConnect: _connect,
                    ),
                    const SizedBox(height: 12),
                    _ScanFooter(scanning: _scanning, onRescan: _scan),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// Heading for the current list. "未发现配网中的设备" is reserved for an
  /// empty list: with rows on screen, even unrecognized ones, the user has
  /// something to pick.
  String _title(
    List<WifiNetwork> devices,
    List<WifiNetwork> hotspots,
    bool pending,
  ) {
    if (devices.isEmpty) {
      return pending ? '请选择需要连接的设备' : '未发现配网中的设备';
    }
    return hotspots.isEmpty ? '请从附近的网络中选择设备' : '请选择需要连接的设备';
  }

  /// Why the list is empty. A platform that cannot enumerate networks must not
  /// be reported as "no device here".
  String _emptyMessage(WifiScan? scan, bool pending) {
    if (pending) return '正在扫描附近设备...';
    final result = _result;
    if (result != null && !result.success) {
      return switch (result.code) {
        // 另一次扫描还在跑，不是「这里没有设备」。
        'wifi_scanning' => '正在扫描附近设备...',
        'wifi_disabled' => '手机 Wi-Fi 未开启，无法扫描附近设备。',
        'location_disabled' => 'Android 9–12 扫描 Wi-Fi 需要打开系统定位开关。',
        'permission_denied' => '扫描需要附近设备/定位权限，请在系统设置中允许后重试。',
        _ => result.message,
      };
    }
    if (scan == null || scan.networks.isEmpty) {
      return '当前系统不提供附近网络列表，无法列出设备热点。\n'
          '确认设备已进入配网状态后可直接继续填写 Wi-Fi。';
    }
    // Every network the scan saw was 5 GHz, which the planter's AP never is.
    return '扫描到 ${scan.networks.length} 个网络，其中没有 2.4G 网络。\n'
        '请长按设备按键让它进入配网状态后重新扫描。';
  }
}

/// Shown when no SSID matched the known planter prefixes and the rows below
/// are therefore the raw scan.
class _ManualPickNotice extends StatelessWidget {
  const _ManualPickNotice();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const Key('device-selection-manual-notice'),
      decoration: const BoxDecoration(
        color: AppColors.brandSurfaceAlt,
        borderRadius: AppRadius.card,
      ),
      child: const Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Text(
          '没有自动认出设备热点，下面是手机扫描到的全部 2.4G 网络。\n'
          '设备进入配网状态后会放出一个自己的热点（例如 SmartLife-8987），'
          '在列表里找到它并点「连接」。',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
            height: 1.6,
          ),
        ),
      ),
    );
  }
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

class _EmptySelectionCard extends StatelessWidget {
  const _EmptySelectionCard({
    required this.message,
    required this.scanning,
    required this.onRescan,
  });

  final String message;
  final bool scanning;
  final VoidCallback onRescan;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const Key('device-selection-empty'),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.card,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          children: <Widget>[
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13.5,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: 200,
              height: 42,
              child: FilledButton(
                key: const Key('device-selection-rescan'),
                onPressed: scanning ? null : onRescan,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.brandPrimary,
                  foregroundColor: AppColors.surface,
                  disabledBackgroundColor: AppColors.disabled,
                  shape: const StadiumBorder(),
                  textStyle: const TextStyle(fontSize: 16),
                ),
                child: scanning
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.surface,
                        ),
                      )
                    : const Text('重新扫描'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanFooter extends StatelessWidget {
  const _ScanFooter({required this.scanning, required this.onRescan});

  final bool scanning;
  final VoidCallback onRescan;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        TextButton(
          key: const Key('device-selection-rescan'),
          onPressed: scanning ? null : onRescan,
          child: Text(
            scanning ? '正在扫描...' : '没找到设备？重新扫描',
            style: const TextStyle(color: AppColors.brandPrimary, fontSize: 14),
          ),
        ),
      ],
    );
  }
}

class _DeviceListCard extends StatelessWidget {
  const _DeviceListCard({
    required this.devices,
    required this.recognized,
    required this.onConnect,
  });

  final List<WifiNetwork> devices;

  /// How many leading rows matched a known planter SSID prefix. The rest are
  /// ordinary scanned networks offered for a manual pick and are drawn
  /// differently, so "connect" on a router is a deliberate choice.
  final int recognized;
  final ValueChanged<WifiNetwork> onConnect;

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
                recognized: index < recognized,
                onConnect: () => onConnect(devices[index]),
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
    required this.recognized,
    required this.onConnect,
  });

  final WifiNetwork device;
  final int index;

  /// Whether the SSID matched a known planter prefix. Unrecognized rows are
  /// plain networks the user may pick anyway, and say so instead of wearing
  /// the planter icon.
  final bool recognized;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: Row(
        children: <Widget>[
          SizedBox.square(
            dimension: 42,
            child: recognized
                ? Image.asset(
                    AppAssets.devicePlanterIcon,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                    semanticLabel: 'YSplanter 设备',
                  )
                : const Icon(
                    Icons.wifi_outlined,
                    size: 26,
                    color: AppColors.textTertiary,
                  ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              device.ssid,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: recognized
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
                fontSize: 16,
                fontWeight: recognized ? FontWeight.w500 : FontWeight.w400,
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
              onPressed: onConnect,
              style: FilledButton.styleFrom(
                padding: EdgeInsets.zero,
                backgroundColor: AppColors.brandPrimary,
                foregroundColor: AppColors.surface,
                disabledBackgroundColor: AppColors.disabled,
                shape: const StadiumBorder(),
                textStyle: const TextStyle(fontSize: 14),
              ),
              child: const Text('连接'),
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
