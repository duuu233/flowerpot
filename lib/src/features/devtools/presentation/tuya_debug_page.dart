import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../../../routes/app_routes.dart';
import '../../../state.dart';
import '../../../tuya/tuya_config.dart';
import '../../../tuya/tuya_models.dart';

/// Console for bringing the native Tuya bridge up on a real device.
///
/// The product login form is deliberately strict: it gates on the agreement
/// checkbox, only offers domestic phone login and shows a human message when a
/// call fails. SDK integration needs the opposite — register and login called
/// directly, plus the raw failure code (`sdk_unavailable`,
/// `credentials_missing`, `security_component_mismatch` or the SDK's own code)
/// for every call, so a platform configuration problem can be told apart from a
/// rejected account before the pairing flow is even reached.
class TuyaDebugPage extends StatefulWidget {
  const TuyaDebugPage({super.key});

  @override
  State<TuyaDebugPage> createState() => _TuyaDebugPageState();
}

class _TuyaDebugPageState extends State<TuyaDebugPage> {
  static const int _logLimit = 50;

  final accountController = TextEditingController();
  final passwordController = TextEditingController();
  final codeController = TextEditingController();
  final ssidController = TextEditingController();
  final wifiPasswordController = TextEditingController();

  final List<_CallLog> log = <_CallLog>[];
  LoginRegion region = LoginRegion.domestic;

  @override
  void dispose() {
    accountController.dispose();
    passwordController.dispose();
    codeController.dispose();
    ssidController.dispose();
    wifiPasswordController.dispose();
    super.dispose();
  }

  String get _countryCode => region == LoginRegion.domestic ? '86' : '1';

  /// [usesAccount] is false for calls that take no account (initialization,
  /// session, device list, logout), so the log does not imply one was sent.
  Future<void> _run(
    String label,
    Future<ActionResult> Function() call, {
    bool usesAccount = true,
  }) async {
    final result = await call();
    if (!mounted) return;
    setState(() {
      log.insert(
        0,
        _CallLog(
          time: DateTime.now(),
          label: label,
          success: result.success,
          code: result.code,
          message: result.message,
          target: usesAccount
              ? '$_countryCode/${_maskAccount(accountController.text)}'
              : '',
        ),
      );
      if (log.length > _logLimit) log.removeRange(_logLimit, log.length);
    });
    showAppMessage(
      context,
      result.message,
      tone: result.success ? AppMessageTone.success : AppMessageTone.error,
    );
  }

  Future<void> _copyLog() async {
    if (log.isEmpty) return;
    await Clipboard.setData(
      ClipboardData(text: log.map((entry) => entry.line).join('\n')),
    );
    if (!mounted) return;
    showAppMessage(context, '调用日志已复制', tone: AppMessageTone.info);
  }

  /// Accounts are masked so a pasted log stays diagnostic without carrying a
  /// full phone number or mailbox.
  static String _maskAccount(String value) {
    final account = value.trim();
    if (account.isEmpty) return '未填写';
    final at = account.indexOf('@');
    if (at > 0) return '${account.substring(0, 1)}***${account.substring(at)}';
    if (account.length < 7) return '***';
    return '${account.substring(0, 3)}****'
        '${account.substring(account.length - 2)}';
  }

  @override
  Widget build(BuildContext context) {
    final state = FlowerpotScope.of(context);
    final busy = state.busy;
    final buildSwitch = TuyaConfig.enabled
        ? 'TUYA_ENABLED=true'
        : '未开启（默认 Mock）';
    return AppPageScaffold(
      appBar: const AppPageHeader(title: '涂鸦 SDK 联调'),
      body: SingleChildScrollView(
        child: ResponsiveContent(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.lg,
            AppSpacing.xl,
            AppSpacing.xxxl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (state.usingMockBackend) _MockBackendNotice(state: state),
              AppSection(
                title: '运行环境',
                child: AppSurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _StatusRow(label: '编译开关', value: buildSwitch),
                      _StatusRow(
                        label: '当前仓库',
                        value: state.usingMockBackend
                            ? (state.demoMode ? 'Mock（体验模式切换）' : 'Mock 后端')
                            : '原生桥接',
                      ),
                      _StatusRow(
                        label: '初始化',
                        value: state.sdkReady ? '已就绪' : '未就绪',
                      ),
                      const _StatusRow(
                        label: '方法通道',
                        value: TuyaConfig.channelName,
                      ),
                      const _StatusRow(
                        label: '默认家庭',
                        value: TuyaConfig.defaultHomeName,
                      ),
                      _StatusRow(
                        label: '当前会话',
                        value: state.user == null
                            ? '未登录'
                            : '${state.user!.nickname} · '
                                  '${_maskAccount(state.user!.account)} · '
                                  'uid ${state.user!.id}',
                      ),
                      _StatusRow(
                        label: '设备数量',
                        value: '${state.devices.length}',
                        last: state.devices.isEmpty,
                      ),
                      // 配网成功后设备是否真的进了账号，只有这份列表能说明。
                      // 之前「解绑当前设备」报没有设备 ID，就是因为列表其实是空
                      // 的——配网返回成功不等于设备已经在列表里。
                      for (final (index, device)
                          in state.devices.indexed) ...<Widget>[
                        _StatusRow(
                          label: '设备 ${index + 1}',
                          value:
                              '${device.name}\n${device.id}'
                              '${device.online ? '' : '（离线）'}',
                          last: index == state.devices.length - 1,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              AppSection(
                title: '账号参数',
                child: AppSurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      SegmentedButton<LoginRegion>(
                        segments: const <ButtonSegment<LoginRegion>>[
                          ButtonSegment<LoginRegion>(
                            value: LoginRegion.domestic,
                            label: Text('手机号 +86'),
                          ),
                          ButtonSegment<LoginRegion>(
                            value: LoginRegion.overseas,
                            label: Text('邮箱 +1'),
                          ),
                        ],
                        selected: <LoginRegion>{region},
                        showSelectedIcon: false,
                        onSelectionChanged: (value) =>
                            setState(() => region = value.first),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      AppTextField(
                        key: const Key('tuya-debug-account'),
                        controller: accountController,
                        label: '账号',
                        hintText: region == LoginRegion.domestic
                            ? '11 位手机号'
                            : '邮箱地址',
                        helperText: '国家码 $_countryCode，'
                            '${region == LoginRegion.domestic ? '走手机号接口' : '走邮箱接口'}',
                        keyboardType: region == LoginRegion.domestic
                            ? TextInputType.phone
                            : TextInputType.emailAddress,
                        prefixIcon: Icon(
                          region == LoginRegion.domestic
                              ? Icons.smartphone_outlined
                              : Icons.alternate_email,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      AppPasswordField(
                        key: const Key('tuya-debug-password'),
                        controller: passwordController,
                        label: '密码',
                        hintText: '注册与密码登录使用，至少 8 位',
                      ),
                      const SizedBox(height: AppSpacing.md),
                      AppTextField(
                        key: const Key('tuya-debug-code'),
                        controller: codeController,
                        label: '验证码',
                        hintText: '注册与验证码登录使用',
                        keyboardType: TextInputType.number,
                        prefixIcon: const Icon(Icons.pin_outlined),
                      ),
                    ],
                  ),
                ),
              ),
              AppSection(
                title: '注册',
                child: AppSurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(
                        '注册验证码类型为 1。注册成功后 SDK 直接持有会话，无需再登录。',
                        style: AppTypography.smallBody.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _ActionRow(
                        children: <Widget>[
                          _action(
                            key: const Key('tuya-debug-send-register-code'),
                            label: '发送注册验证码',
                            busy: busy,
                            onPressed: () => _run(
                              '发送注册验证码',
                              () => state.sendCode(
                                account: accountController.text,
                                region: region,
                                type: 1,
                              ),
                            ),
                          ),
                          _action(
                            key: const Key('tuya-debug-register'),
                            label: '注册并登录',
                            busy: busy,
                            primary: true,
                            onPressed: () => _run(
                              '注册并登录',
                              () => state.register(
                                account: accountController.text,
                                password: passwordController.text,
                                code: codeController.text,
                                region: region,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              AppSection(
                title: '登录',
                child: AppSurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(
                        '登录验证码类型为 2。桥接按账号类型分发到手机验证码、'
                        '手机密码或邮箱登录接口。',
                        style: AppTypography.smallBody.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _ActionRow(
                        children: <Widget>[
                          _action(
                            key: const Key('tuya-debug-send-login-code'),
                            label: '发送登录验证码',
                            busy: busy,
                            onPressed: () => _run(
                              '发送登录验证码',
                              () => state.sendCode(
                                account: accountController.text,
                                region: region,
                                type: 2,
                              ),
                            ),
                          ),
                          _action(
                            key: const Key('tuya-debug-login-code'),
                            label: '验证码登录',
                            busy: busy,
                            onPressed: () => _run(
                              '验证码登录',
                              () => state.login(
                                account: accountController.text,
                                credential: codeController.text,
                                region: region,
                                verificationCode: true,
                              ),
                            ),
                          ),
                          _action(
                            key: const Key('tuya-debug-login-password'),
                            label: '密码登录',
                            busy: busy,
                            primary: true,
                            onPressed: () => _run(
                              '密码登录',
                              () => state.login(
                                account: accountController.text,
                                credential: passwordController.text,
                                region: region,
                                verificationCode: false,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              AppSection(
                title: '会话与设备',
                child: AppSurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(
                        '“拉取设备列表”会先查询家庭，没有家庭时自动创建，'
                        '是配网前必须先跑通的一步。',
                        style: AppTypography.smallBody.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _ActionRow(
                        children: <Widget>[
                          _action(
                            key: const Key('tuya-debug-probe-sdk'),
                            label: '初始化自检',
                            busy: busy,
                            onPressed: () => _run(
                              '初始化自检',
                              () => state.probeSdk(),
                              usesAccount: false,
                            ),
                          ),
                          _action(
                            key: const Key('tuya-debug-probe-session'),
                            label: '查询会话',
                            busy: busy,
                            onPressed: () => _run(
                              '查询会话',
                              () => state.probeSession(),
                              usesAccount: false,
                            ),
                          ),
                          _action(
                            key: const Key('tuya-debug-probe-devices'),
                            label: '拉取设备列表',
                            busy: busy,
                            onPressed: () => _run(
                              '拉取设备列表',
                              () => state.probeDevices(),
                              usesAccount: false,
                            ),
                          ),
                          _action(
                            key: const Key('tuya-debug-unbind'),
                            label: '解绑当前设备',
                            busy: busy,
                            onPressed: () => _run(
                              '解绑当前设备',
                              () {
                                // 配好的设备会一直绑在账号上，不解绑就回不到配网
                                // 状态，再配只会等满 120 秒报 1006。反复联调必须
                                // 有这个入口，否则每次都要退到产品页去解绑。
                                final device = state.selectedDevice;
                                if (device == null) {
                                  return Future<ActionResult>.value(
                                    const ActionResult(
                                      false,
                                      'APP-no_device 设备列表为空。配网返回成功不代表'
                                      '设备已进列表，先点「拉取设备列表」确认。',
                                      code: 'no_device',
                                    ),
                                  );
                                }
                                return state.removeDevice(
                                  device.id,
                                  resetFactory: true,
                                );
                              },
                              usesAccount: false,
                            ),
                          ),
                          _action(
                            key: const Key('tuya-debug-logout'),
                            label: '退出登录',
                            busy: busy,
                            onPressed: () => _run(
                              '退出登录',
                              () => state.logout(),
                              usesAccount: false,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      // Filled buttons use an 18px face with 2px letter
                      // spacing and never wrap, so the label has to stay short
                      // enough for a 360dp viewport.
                      AppPrimaryButton(
                        key: const Key('tuya-debug-enter-app'),
                        label: '进入 App 配网',
                        onPressed: state.authenticated
                            ? () => Navigator.pushNamedAndRemoveUntil(
                                context,
                                AppRoutes.shell,
                                (_) => false,
                              )
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
              AppSection(
                title: '配网',
                child: AppSurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(
                        'AP 配网（超时 120 秒）。失败只写进下面的日志并带原始错误码，'
                        '不跳配网失败页，方便连续重试。\n\n'
                        '「开始配网」一步做完三件事：取配网令牌 → 连设备热点 → 下发凭据。'
                        '令牌只能在还有外网时取，连上热点后就取不到了，所以必须串在一起，'
                        '不用手动分步。\n\n'
                        '① 设备长按到指示灯慢闪，Wi-Fi 列表里能看到 SmartLife-… 热点\n'
                        '② 手机先连在目标 2.4G 路由器上（要有网）\n'
                        '③ 填路由器的名称和密码——不是设备热点的\n'
                        '④ 点「开始配网」，系统会弹框问是否连接设备热点，点确认\n\n'
                        '设备若已被别的 App 绑定，必须先在那边解绑，否则它不会回到配网状态。',
                        style: AppTypography.smallBody.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      AppTextField(
                        key: const Key('tuya-debug-ssid'),
                        controller: ssidController,
                        label: 'Wi-Fi 名称',
                        hintText: '设备要连的 2.4G 网络',
                        prefixIcon: const Icon(Icons.wifi_outlined),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      AppPasswordField(
                        key: const Key('tuya-debug-wifi-password'),
                        controller: wifiPasswordController,
                        label: 'Wi-Fi 密码',
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _ActionRow(
                        children: <Widget>[
                          _action(
                            key: const Key('tuya-debug-activator-modes'),
                            label: '查询配网模式',
                            busy: busy,
                            onPressed: () => _run(
                              '查询配网模式',
                              () => state.probeActivatorModes(),
                              usesAccount: false,
                            ),
                          ),
                          _action(
                            key: const Key('tuya-debug-scan-wifi'),
                            label: '扫描附近 Wi-Fi',
                            busy: busy,
                            onPressed: () => _run(
                              '扫描 Wi-Fi',
                              () => state.probeWifi(),
                              usesAccount: false,
                            ),
                          ),
                        ],
                      ),
                      if (state.wifiScan case final WifiScan scan) ...<Widget>[
                        const SizedBox(height: AppSpacing.sm),
                        _WifiScanResult(
                          scan: scan,
                          onPick: (ssid) =>
                              setState(() => ssidController.text = ssid),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      _action(
                        key: const Key('tuya-debug-pair'),
                        label: '开始配网',
                        busy: busy,
                        primary: true,
                        onPressed: () => _run(
                          '配网 AP',
                          () => state.pairViaHotspot(
                            ssid: ssidController.text.trim(),
                            password: wifiPasswordController.text,
                          ),
                          usesAccount: false,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              AppSection(
                padding: EdgeInsets.zero,
                title: '调用日志',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    IconButton(
                      key: const Key('tuya-debug-copy-log'),
                      tooltip: '复制日志',
                      onPressed: log.isEmpty ? null : _copyLog,
                      icon: const Icon(Icons.copy_all_outlined, size: 20),
                    ),
                    IconButton(
                      key: const Key('tuya-debug-clear-log'),
                      tooltip: '清空日志',
                      onPressed: log.isEmpty
                          ? null
                          : () => setState(log.clear),
                      icon: const Icon(Icons.delete_outline, size: 20),
                    ),
                  ],
                ),
                child: AppSurfaceCard(
                  child: log.isEmpty
                      ? Text(
                          '还没有调用记录。每次调用都会记录时间、结果、错误码和脱敏账号。',
                          style: AppTypography.smallBody.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            for (final entry in log) _CallLogRow(entry: entry),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _action({
    required Key key,
    required String label,
    required bool busy,
    required VoidCallback onPressed,
    bool primary = false,
  }) {
    if (primary) {
      return AppPrimaryButton(
        key: key,
        label: label,
        expand: false,
        onPressed: busy ? null : onPressed,
      );
    }
    return AppOutlinedButton(
      key: key,
      label: label,
      expand: false,
      onPressed: busy ? null : onPressed,
    );
  }
}

class _MockBackendNotice extends StatelessWidget {
  const _MockBackendNotice({required this.state});

  final FlowerpotState state;

  @override
  Widget build(BuildContext context) {
    final demo = state.demoMode;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: AppSurfaceCard(
        key: const Key('tuya-debug-mock-notice'),
        color: AppColors.warningSurface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(
                  Icons.warning_amber_rounded,
                  color: AppColors.warning,
                  size: 20,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    demo ? '体验模式已把仓库换成 Mock' : '当前调用不会到达涂鸦 SDK',
                    style: AppTypography.bodyEmphasis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              demo
                  ? '体验模式在运行时替换了仓库，本页的调用只会命中 Mock。重启 App 后再进入本页才能验证真实链路。'
                  : '本页调用由 Mock 后端应答，只能验证页面动线。真实链路需要按下面命令重新启动，并准备好安全组件、密钥与 ARM 运行环境。',
              style: AppTypography.smallBody.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            if (!demo) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              const _CommandText(
                'flutter run --dart-define=TUYA_ENABLED=true',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CommandText extends StatelessWidget {
  const _CommandText(this.command);

  final String command;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.small,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: SelectableText(
          command,
          style: AppTypography.smallBody.copyWith(
            color: AppColors.textPrimary,
            fontFamily: 'monospace',
            fontFamilyFallback: const <String>['Courier New'],
          ),
        ),
      ),
    );
  }
}

/// Nearby networks from the last scan. Tapping one fills the SSID field, so a
/// bench test cannot mistype the network the device has to join.
class _WifiScanResult extends StatelessWidget {
  const _WifiScanResult({required this.scan, required this.onPick});

  final WifiScan scan;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final current = scan.current;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (current != null)
          Text(
            '手机当前连接：$current'
            '${switch (scan.currentIs24g) {
              true => '（2.4G）',
              false => '（5G，设备只能连 2.4G）',
              null => '',
            }}',
            style: AppTypography.smallBody.copyWith(
              color: scan.currentIs24g == false
                  ? AppColors.danger
                  : AppColors.textSecondary,
            ),
          ),
        if (scan.networks.isEmpty)
          Text(
            '没有扫到任何网络。检查手机 Wi-Fi 与系统定位是否开启。',
            style: AppTypography.smallBody.copyWith(
              color: AppColors.textSecondary,
            ),
          )
        else
          for (final network in scan.networks.take(12))
            InkWell(
              onTap: () => onPick(network.ssid),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        network.ssid,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.compactBody.copyWith(
                          color: network.looksLikeDeviceHotspot
                              ? AppColors.brandPrimary
                              : AppColors.textPrimary,
                          fontWeight: network.looksLikeDeviceHotspot
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                    Text(
                      '${network.is24g ? '2.4G' : '5G'} · ${network.level}dBm',
                      style: AppTypography.smallBody.copyWith(
                        color: network.is24g
                            ? AppColors.textSecondary
                            : AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.label,
    required this.value,
    this.last = false,
  });

  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: AppTypography.smallBody.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTypography.smallBody.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: children,
    );
  }
}

class _CallLogRow extends StatelessWidget {
  const _CallLogRow({required this.entry});

  final _CallLog entry;

  @override
  Widget build(BuildContext context) {
    final color = entry.success ? AppColors.success : AppColors.danger;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                entry.success
                    ? Icons.check_circle_outline
                    : Icons.error_outline,
                size: 16,
                color: color,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  '${entry.stamp} ${entry.label}',
                  style: AppTypography.compactBody.copyWith(color: color),
                ),
              ),
              if (entry.target.isNotEmpty)
                Text(
                  entry.target,
                  style: AppTypography.smallBody.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 20, top: AppSpacing.xxs),
            child: Text(
              entry.code == null
                  ? entry.message
                  : '[${entry.code}] ${entry.message}',
              style: AppTypography.smallBody.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CallLog {
  const _CallLog({
    required this.time,
    required this.label,
    required this.success,
    required this.message,
    required this.target,
    this.code,
  });

  final DateTime time;
  final String label;
  final bool success;
  final String message;

  /// Country code plus masked account the call was made with, empty for calls
  /// that take no account.
  final String target;
  final String? code;

  String get stamp =>
      '${_pad(time.hour)}:${_pad(time.minute)}:${_pad(time.second)}';

  String get line {
    final status = success ? 'OK ' : 'ERR';
    final codeText = code == null ? '' : ' [$code]';
    final targetText = target.isEmpty ? '' : ' · $target';
    return '$stamp $status $label$codeText · $message$targetText';
  }

  static String _pad(int value) => value.toString().padLeft(2, '0');
}
