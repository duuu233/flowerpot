import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../../../routes/app_routes.dart';
import '../../../tuya/tuya_models.dart';

class PairingPage extends StatefulWidget {
  const PairingPage({super.key});

  @override
  State<PairingPage> createState() => _PairingPageState();
}

class _PairingPageState extends State<PairingPage> {
  final ssidController = TextEditingController(text: 'Home_2.4G');
  final passwordController = TextEditingController(text: '12345678');

  @override
  void dispose() {
    ssidController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> _switchWifi() async {
    final value = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .42),
      builder: (_) => _WifiSelectionSheet(current: ssidController.text),
    );
    if (value != null && value.isNotEmpty && mounted) {
      setState(() => ssidController.text = value);
    }
  }

  Future<void> _pair() async {
    if (ssidController.text.trim().isEmpty || passwordController.text.isEmpty) {
      showAppMessage(context, '请输入 Wi-Fi 名称与密码', tone: AppMessageTone.error);
      return;
    }

    await Navigator.pushNamed(
      context,
      AppRoutes.deviceSearch,
      arguments: PairingRequest(
        ssid: ssidController.text.trim(),
        password: passwordController.text,
        mode: 'ap',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = FlowerpotScope.of(context);
    return AppPageScaffold(
      appBar: const AppPageHeader(title: '连接Wi-Fi', leading: AppBackButton()),
      background: AppPageBackground.standard,
      body: Stack(
        children: <Widget>[
          SingleChildScrollView(
            key: const Key('pairing-scroll-view'),
            padding: const EdgeInsets.only(bottom: 92),
            child: ResponsiveContent(
              maxWidth: 375,
              padding: const EdgeInsets.fromLTRB(20, 88, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const _WifiConnectionIllustration(),
                  const SizedBox(height: 27),
                  const Text(
                    '请将设备连接到2.4GHz Wi-Fi网络',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 15,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const _WifiNoticeCard(),
                  const SizedBox(height: 12),
                  _WifiCredentialsCard(
                    ssidController: ssidController,
                    passwordController: passwordController,
                    onSwitchWifi: _switchWifi,
                  ),
                  const SizedBox(height: 38),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Icon(
                        Icons.info_outline_rounded,
                        color: AppColors.brandPrimary,
                        size: 18,
                      ),
                      SizedBox(width: 7),
                      Text(
                        '连接过程中请保持设备靠近路由器',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 8,
            child: FilledButton(
              key: const Key('start-pairing-button'),
              onPressed: state.busy ? null : _pair,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                backgroundColor: AppColors.brandPrimary,
                foregroundColor: AppColors.surface,
                elevation: 2,
                shadowColor: AppColors.brandPrimary.withValues(alpha: .35),
                shape: const StadiumBorder(),
                textStyle: AppTypography.pageTitle.copyWith(
                  color: AppColors.surface,
                ),
              ),
              child: state.busy
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(
                        color: AppColors.surface,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('开始配网'),
            ),
          ),
        ],
      ),
    );
  }
}

class _WifiConnectionIllustration extends StatelessWidget {
  const _WifiConnectionIllustration();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 250,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          _SignalCircle(size: 230, opacity: .20),
          _SignalCircle(size: 184, opacity: .25),
          _SignalCircle(size: 140, opacity: .34),
          Positioned(left: 5, top: 34, child: _DecorationDot(size: 10)),
          Positioned(right: 25, top: 60, child: _DecorationDot(size: 10)),
          Positioned(left: 18, bottom: 5, child: _DecorationDot(size: 15)),
          Positioned(right: 31, bottom: 17, child: _DecorationDot(size: 9)),
          Positioned(left: 58, top: 136, child: _PlanterWifiHub()),
          Positioned(right: 42, top: 137, child: _RouterHub()),
          Positioned(left: 124, right: 117, top: 166, child: _DottedLink()),
          Positioned(top: 151, child: _ConnectionLock()),
        ],
      ),
    );
  }
}

class _SignalCircle extends StatelessWidget {
  const _SignalCircle({required this.size, required this.opacity});

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

class _DecorationDot extends StatelessWidget {
  const _DecorationDot({required this.size});

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

class _PlanterWifiHub extends StatelessWidget {
  const _PlanterWifiHub();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 70,
      height: 65,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: <Widget>[
          const Positioned(
            top: 0,
            child: Icon(
              Icons.wifi_rounded,
              color: AppColors.brandPrimary,
              size: 48,
            ),
          ),
          Container(
            width: 62,
            height: 29,
            decoration: const BoxDecoration(
              color: AppColors.brandPrimary,
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                _WhiteDot(),
                SizedBox(width: 8),
                _WhiteDot(),
                SizedBox(width: 8),
                _WhiteDot(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RouterHub extends StatelessWidget {
  const _RouterHub();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 82,
      height: 62,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: <Widget>[
          const Positioned(left: 8, top: 0, child: _Antenna()),
          const Positioned(right: 8, top: 0, child: _Antenna()),
          Container(
            width: 82,
            height: 27,
            decoration: const BoxDecoration(
              color: AppColors.brandPrimary,
              borderRadius: BorderRadius.all(Radius.circular(9)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                SizedBox(
                  width: 13,
                  height: 3,
                  child: ColoredBox(color: AppColors.surface),
                ),
                SizedBox(width: 8),
                _WhiteDot(size: 4),
                SizedBox(width: 6),
                _WhiteDot(size: 4),
                SizedBox(width: 6),
                _WhiteDot(size: 4),
                SizedBox(width: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Antenna extends StatelessWidget {
  const _Antenna();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.brandPrimary,
        borderRadius: AppRadius.full,
      ),
      child: SizedBox(width: 5, height: 41),
    );
  }
}

class _WhiteDot extends StatelessWidget {
  const _WhiteDot({this.size = 7});

  final double size;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        shape: BoxShape.circle,
      ),
      child: SizedBox.square(dimension: size),
    );
  }
}

class _DottedLink extends StatelessWidget {
  const _DottedLink();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List<Widget>.generate(
        10,
        (_) => const DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.brandPrimary,
            shape: BoxShape.circle,
          ),
          child: SizedBox.square(dimension: 3),
        ),
      ),
    );
  }
}

class _ConnectionLock extends StatelessWidget {
  const _ConnectionLock();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.brandSurface,
        shape: BoxShape.circle,
      ),
      child: SizedBox.square(
        dimension: 31,
        child: Icon(Icons.lock_rounded, color: AppColors.brandDark, size: 18),
      ),
    );
  }
}

class _WifiNoticeCard extends StatelessWidget {
  const _WifiNoticeCard();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 300;
        return DecoratedBox(
          decoration: const BoxDecoration(
            color: AppColors.brandSurfaceAlt,
            borderRadius: AppRadius.card,
          ),
          child: SizedBox(
            height: compact ? 84 : 72,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: <Widget>[
                  _WifiBandIcon(),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '仅支持2.4GHz Wi-Fi网络',
                          style: TextStyle(
                            color: AppColors.brandPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          '请确保设备连接的是稳定的2.4GHz网络',
                          style: TextStyle(
                            color: AppColors.brandPrimary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WifiBandIcon extends StatelessWidget {
  const _WifiBandIcon();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        shape: BoxShape.circle,
      ),
      child: SizedBox.square(
        dimension: 40,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            Positioned(
              top: 7,
              child: Icon(
                Icons.wifi_rounded,
                color: AppColors.brandPrimary,
                size: 25,
              ),
            ),
            Positioned(
              bottom: 4,
              child: Text(
                '2.4G',
                style: TextStyle(
                  color: AppColors.brandPrimary,
                  fontSize: 8,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WifiCredentialsCard extends StatelessWidget {
  const _WifiCredentialsCard({
    required this.ssidController,
    required this.passwordController,
    required this.onSwitchWifi,
  });

  final TextEditingController ssidController;
  final TextEditingController passwordController;
  final VoidCallback onSwitchWifi;

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
            SizedBox(
              height: 72,
              child: Row(
                children: <Widget>[
                  const _CredentialIcon(icon: Icons.wifi_rounded),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text(
                          'Wi-Fi名称',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                        SizedBox(
                          height: 24,
                          child: TextField(
                            key: const Key('pairing-ssid-field'),
                            controller: ssidController,
                            readOnly: true,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 15,
                            ),
                            decoration: const InputDecoration.collapsed(
                              hintText: '请选择 Wi-Fi',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    key: const Key('switch-wifi-button'),
                    onPressed: onSwitchWifi,
                    child: const Text('切换'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.divider),
            SizedBox(
              height: 72,
              child: Row(
                children: <Widget>[
                  const _CredentialIcon(icon: Icons.lock_outline_rounded),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text(
                          'Wi-Fi密码',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                        SizedBox(
                          height: 24,
                          child: TextField(
                            key: const Key('pairing-password-field'),
                            controller: passwordController,
                            obscureText: true,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 15,
                              letterSpacing: 3,
                            ),
                            decoration: const InputDecoration.collapsed(
                              hintText: '请输入密码',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CredentialIcon extends StatelessWidget {
  const _CredentialIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.brandSurface,
        borderRadius: AppRadius.card,
      ),
      child: SizedBox.square(
        dimension: 40,
        child: Icon(icon, color: AppColors.brandPrimary, size: 24),
      ),
    );
  }
}

class _WifiSelectionSheet extends StatefulWidget {
  const _WifiSelectionSheet({required this.current});

  final String current;

  @override
  State<_WifiSelectionSheet> createState() => _WifiSelectionSheetState();
}

class _WifiSelectionSheetState extends State<_WifiSelectionSheet> {
  late String selected = widget.current;

  List<String> get networks => <String>[
    widget.current,
    if (widget.current != 'Home_2.4G') 'Home_2.4G',
    if (widget.current != 'TP-LINK_2.4G') 'TP-LINK_2.4G',
    if (widget.current != 'Xiaomi_2.4G') 'Xiaomi_2.4G',
  ];

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: 360,
        child: SafeArea(
          top: false,
          child: Column(
            children: <Widget>[
              const SizedBox(height: 10),
              Container(
                width: 48,
                height: 4,
                decoration: const BoxDecoration(
                  color: AppColors.disabled,
                  borderRadius: AppRadius.full,
                ),
              ),
              SizedBox(
                height: 56,
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          key: const Key('wifi-selection-cancel'),
                          onPressed: () => Navigator.pop(context),
                          child: const Text(
                            '取消',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const Text(
                      '选择Wi-Fi',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          key: const Key('wifi-selection-confirm'),
                          onPressed: () => Navigator.pop(context, selected),
                          child: const Text(
                            '确认',
                            style: TextStyle(
                              color: AppColors.brandPrimary,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Text(
                '仅显示可用的2.4GHzWi-Fi网络',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 36),
                  itemCount: networks.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, color: AppColors.divider),
                  itemBuilder: (context, index) {
                    final network = networks[index];
                    final active = selected == network;
                    return InkWell(
                      key: Key('wifi-option-$network'),
                      onTap: () => setState(() => selected = network),
                      child: SizedBox(
                        height: 64,
                        child: Row(
                          children: <Widget>[
                            const Icon(
                              Icons.wifi_rounded,
                              color: AppColors.brandPrimary,
                              size: 27,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Text(
                                network,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 17,
                                ),
                              ),
                            ),
                            if (active)
                              const Icon(
                                Icons.check_rounded,
                                key: Key('wifi-selected-check'),
                                color: AppColors.brandPrimary,
                                size: 28,
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
