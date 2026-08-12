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
      background: AppPageBackground.account,
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Image.asset(
                        AppAssets.infoOutlineIcon,
                        width: 18,
                        height: 18,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                      ),
                      const SizedBox(width: 7),
                      const Text(
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
    return SizedBox(
      key: const Key('wifi-connection-illustration'),
      height: 270,
      child: Image.asset(
        AppAssets.pairingWifiSetupIllustration,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        excludeFromSemantics: true,
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
          key: const Key('wifi-notice-card'),
          decoration: const BoxDecoration(
            color: AppColors.surfaceTranslucent,
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
    return Image.asset(
      AppAssets.wifi24GhzIcon,
      width: 40,
      height: 40,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      semanticLabel: '2.4GHz Wi-Fi',
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
                  const _CredentialIcon(
                    assetPath: AppAssets.wifiNetworkIcon,
                    semanticLabel: 'Wi-Fi 名称',
                  ),
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
                  const _CredentialIcon(
                    assetPath: AppAssets.wifiPasswordIcon,
                    semanticLabel: 'Wi-Fi 密码',
                  ),
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
  const _CredentialIcon({required this.assetPath, required this.semanticLabel});

  final String assetPath;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      assetPath,
      width: 40,
      height: 40,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      semanticLabel: semanticLabel,
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
                            Image.asset(
                              AppAssets.wifiSignalIcon,
                              width: 27,
                              height: 27,
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.high,
                              semanticLabel: 'Wi-Fi 网络',
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
                              Image.asset(
                                AppAssets.checkmarkIcon,
                                key: const Key('wifi-selected-check'),
                                width: 28,
                                height: 28,
                                fit: BoxFit.contain,
                                filterQuality: FilterQuality.high,
                                semanticLabel: '已选择',
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
