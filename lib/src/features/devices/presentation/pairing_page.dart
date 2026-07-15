import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../app/flowerpot_app.dart';
import '../../../routes/app_routes.dart';
import '../../../shared/shared.dart';
import '../../../tuya/tuya_models.dart';

class PairingPage extends StatefulWidget {
  const PairingPage({super.key});

  @override
  State<PairingPage> createState() => _PairingPageState();
}

class _PairingPageState extends State<PairingPage> {
  final ssid = TextEditingController();
  final password = TextEditingController();
  int step = 0;
  String mode = 'ap';
  String? pairedDeviceId;

  @override
  void dispose() {
    ssid.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> _pair() async {
    if (ssid.text.trim().isEmpty || password.text.isEmpty) {
      showAppMessage(context, '请输入 Wi-Fi 名称与密码', success: false);
      return;
    }
    setState(() => step = 2);
    final result = await FlowerpotScope.of(context).pairDevice(
      PairingRequest(
        ssid: ssid.text.trim(),
        password: password.text,
        mode: mode,
      ),
    );
    if (!mounted) return;
    if (result.success) {
      pairedDeviceId = FlowerpotScope.of(context).selectedDevice?.id;
      setState(() => step = 3);
    } else {
      setState(() => step = 1);
      showAppMessage(context, result.message, success: false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('添加智能花盆')),
    body: AppBackground(
      child: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 32),
          children: <Widget>[
            _StepHeader(step: step),
            const SizedBox(height: 24),
            if (step == 0) _prepare(context),
            if (step == 1) _wifi(context),
            if (step == 2) _searching(context),
            if (step == 3) _success(context),
          ],
        ),
      ),
    ),
  );

  Widget _prepare(BuildContext context) => Column(
    children: <Widget>[
      GlassCard(
        color: AppColors.ink,
        child: Column(
          children: <Widget>[
            const PlantIllustration(size: 190),
            Text(
              '让设备进入配网模式',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 8),
            const Text(
              '长按花盆背面的配网键 5 秒，直到 Wi-Fi 指示灯快速闪烁。',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, height: 1.5),
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      const GlassCard(
        child: Row(
          children: <Widget>[
            Icon(Icons.info_outline_rounded, color: AppColors.sun),
            SizedBox(width: 12),
            Expanded(child: Text('设备只支持 2.4 GHz Wi-Fi，请确保手机已连接对应网络。')),
          ],
        ),
      ),
      const SizedBox(height: 24),
      FilledButton(
        onPressed: () => setState(() => step = 1),
        child: const Text('指示灯正在闪烁'),
      ),
    ],
  );

  Widget _wifi(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text('连接 Wi-Fi', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      const Text('密码只会交给涂鸦 SDK 用于本次设备配网。'),
      const SizedBox(height: 20),
      TextField(
        controller: ssid,
        decoration: const InputDecoration(
          labelText: 'Wi-Fi 名称',
          prefixIcon: Icon(Icons.wifi_rounded),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: password,
        obscureText: true,
        decoration: const InputDecoration(
          labelText: 'Wi-Fi 密码',
          prefixIcon: Icon(Icons.lock_outline_rounded),
        ),
      ),
      const SizedBox(height: 18),
      Text('配网方式', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 10),
      SegmentedButton<String>(
        segments: const <ButtonSegment<String>>[
          ButtonSegment(
            value: 'ap',
            icon: Icon(Icons.router_outlined),
            label: Text('热点模式'),
          ),
          ButtonSegment(
            value: 'ez',
            icon: Icon(Icons.bolt_rounded),
            label: Text('快连模式'),
          ),
        ],
        selected: <String>{mode},
        showSelectedIcon: false,
        onSelectionChanged: (value) => setState(() => mode = value.first),
      ),
      const SizedBox(height: 8),
      Text(
        mode == 'ap' ? '官方推荐：成功率更高，对路由器兼容性更好。' : '适合网络环境简单、路由器兼容性良好的场景。',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: 28),
      FilledButton(onPressed: _pair, child: const Text('开始配网')),
    ],
  );

  Widget _searching(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 40),
    child: Column(
      children: <Widget>[
        SizedBox.square(
          dimension: 184,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              const CircularProgressIndicator(
                strokeWidth: 3,
                color: AppColors.leaf,
              ),
              Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .7),
                  shape: BoxShape.circle,
                ),
                child: const PlantIllustration(size: 132),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        Text('正在发现花盆…', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text('正在获取配网 Token，并将设备加入“我的花园”'),
        const SizedBox(height: 18),
        const StatusPill(label: 'Token 有效期 10 分钟', icon: Icons.timer_outlined),
      ],
    ),
  );

  Widget _success(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 28),
    child: Column(
      children: <Widget>[
        Container(
          width: 92,
          height: 92,
          decoration: const BoxDecoration(
            color: AppColors.leaf,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_rounded, color: Colors.white, size: 52),
        ),
        const SizedBox(height: 24),
        Text('设备添加成功', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text('花盆已连接，现在可以为它选择植物。'),
        const SizedBox(height: 26),
        FilledButton(
          onPressed: () => Navigator.pushReplacementNamed(
            context,
            AppRoutes.plantPicker,
            arguments: pairedDeviceId,
          ),
          child: const Text('选择植物'),
        ),
        TextButton(
          onPressed: () => Navigator.pushNamedAndRemoveUntil(
            context,
            AppRoutes.shell,
            (_) => false,
          ),
          child: const Text('稍后设置'),
        ),
      ],
    ),
  );
}

class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) => Row(
    children: List<Widget>.generate(4, (index) {
      final active = index <= step;
      return Expanded(
        child: Container(
          height: 5,
          margin: EdgeInsets.only(right: index == 3 ? 0 : 7),
          decoration: BoxDecoration(
            color: active ? AppColors.leaf : const Color(0xFFD9E2DA),
            borderRadius: BorderRadius.circular(99),
          ),
        ),
      );
    }),
  );
}
