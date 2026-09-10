import 'package:flutter/material.dart';

import '../../../design_system/design_system.dart';
import '../../../routes/app_routes.dart';
import '../../../tuya/tuya_models.dart';
import 'pairing_page.dart';

class PairingFailurePage extends StatelessWidget {
  const PairingFailurePage({super.key, this.request, this.code, this.message});

  final PairingRequest? request;

  /// 涂鸦返回的原始失败原因。
  ///
  /// 正式包也照常显示：那句产品文案分不出超时、密码错和设备已被绑定，只看它
  /// 无法判断该改什么。[message] 已经由 `FlowerpotState` 打上来源标签（形如
  /// `涂鸦-<code> 原文`），所以这里不再重复拼 [code]。
  final String? code;
  final String? message;

  String get _subtitle {
    const generic = '设备未能成功连接到当前Wi-Fi网络';
    final hint = hintFor(code);
    if (hint != null) return '$generic\n$hint（$code）';
    final detail = message?.trim() ?? '';
    if (detail.isEmpty) return generic;
    return '$generic\n$detail';
  }

  /// 认得的失败码换成一句能照着做的话；原始码仍附在括号里，联调时对照日志用。
  ///
  /// 认不得的照常显示 [message]：那里面带着来源标签、原始报错和各步耗时，真机
  /// 上排查只能靠它。
  static String? hintFor(String? code) => switch (code) {
    'hotspot_join_cancelled' ||
    'hotspot_join_failed' ||
    'hotspot_join_timeout' => '手机没有连上设备热点：确认设备已开机并靠近手机，并在系统弹框中点「连接」',
    'hotspot_bind_failed' => '手机连上了设备热点但流量没能切过去，请关闭再打开 Wi-Fi 后重试',
    'hotspot_ssid_required' => '还不知道要连哪台设备，请回到「搜索设备」页从列表里选中设备后再配网',
    'pair_cancelled' => '配网已中止',
    'pair_timeout' => '长时间没有收到结果，请给设备断电重启后重试',
    '1006' => '设备没有在两分钟内连上路由器：多半是 Wi-Fi 密码有误，或所选网络不是 2.4GHz',
    _ => null,
  };

  void _retry(BuildContext context) {
    // The Wi-Fi page no longer pre-fills placeholder credentials, so a retry
    // has to carry the previous attempt back or the form arrives blank.
    //
    // 产品页只有 AP 一种方式，所以这里不再做「改用另一种模式」的回落——EZ 仍在
    // 桥接层可用，但不对最终用户暴露。
    Navigator.pushReplacementNamed(
      context,
      AppRoutes.pairing,
      arguments: PairingArguments(request: request),
    );
  }

  /// 回到搜索页重新找设备。
  ///
  /// 2026-09-10 之前这里回的是「选择设备」页；那一页已经删掉——扫到的设备现在
  /// 直接列在搜索页上，不再单独占一页。
  void _returnToDevices(BuildContext context) {
    Navigator.pushReplacementNamed(
      context,
      AppRoutes.deviceSearch,
      arguments: request,
    );
  }

  @override
  Widget build(BuildContext context) {
    // 版式从「Stack + 写死的 Positioned 偏移」改成正常的纵向流。
    //
    // 原来标题在 top:315、副标题 top:362、小提示卡 top:400 —— 副标题只有 38px 的空档，
    // 而它是 14px/1.5 的两行（42px），失败码带上提示语时必然顶进小提示卡里，看起来就是
    // 两段文字重叠。同一段 `SizedBox(height: max(690, 屏高))` 还把内容硬撑到 690，
    // 于是矮屏上凭空多出一条滚动条。现在让每段自己占高度，短屏才滚。
    return AppPageScaffold(
      appBar: const AppPageHeader(title: '连接设备', leading: AppBackButton()),
      background: AppPageBackground.account,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final horizontalPadding = constraints.maxWidth < 360 ? 12.0 : 20.0;
          final compact = constraints.maxHeight < 690;
          return SingleChildScrollView(
            key: const Key('pairing-failure-scroll-view'),
            child: ConstrainedBox(
              // 撑满一屏，好让两个按钮沉到底部；内容比一屏高时照常滚。
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: ResponsiveContent(
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      SizedBox(height: compact ? 28 : 70),
                      const Center(child: _FailureRadar()),
                      SizedBox(height: compact ? 12 : 24),
                      const Text(
                        '配网失败，请重试',
                        key: Key('pairing-failure-title'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _subtitle,
                        key: const Key('pairing-failure-subtitle'),
                        textAlign: TextAlign.center,
                        // 行数不再写死 2：失败码带上提示语时本来就是三四行，
                        // 截断反而把唯一能照着做的那句话吃掉了。
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 20),
                      const _FailureTipCard(),
                      // 内容不足一屏时把按钮推到底部；够高时 24 就是普通间距。
                      // `IntrinsicHeight` 是 SingleChildScrollView 里用 Expanded
                      // 的标准写法：没有它，Column 拿到的高度约束是无界的，Expanded
                      // 会直接抛「non-zero flex but unbounded height」。
                      const SizedBox(height: 24),
                      const Expanded(child: SizedBox.shrink()),
                      SizedBox(
                        height: 50,
                        child: FilledButton(
                          key: const Key('retry-pairing-button'),
                          onPressed: () => _retry(context),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.brandPrimary,
                            foregroundColor: AppColors.surface,
                            shape: const StadiumBorder(),
                            textStyle: const TextStyle(fontSize: 19),
                          ),
                          child: const Text('重新配网'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 50,
                        child: OutlinedButton(
                          key: const Key('return-device-selection-button'),
                          onPressed: () => _returnToDevices(context),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.brandPrimary,
                            side: const BorderSide(
                              color: AppColors.brandPrimary,
                            ),
                            shape: const StadiumBorder(),
                            textStyle: const TextStyle(fontSize: 19),
                          ),
                          child: const Text('返回搜索设备'),
                        ),
                      ),
                      SizedBox(height: compact ? 16 : 24),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FailureRadar extends StatelessWidget {
  const _FailureRadar();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      AppAssets.pairingFailureIllustration,
      width: 235,
      height: 235,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      excludeFromSemantics: true,
    );
  }
}

class _FailureTipCard extends StatelessWidget {
  const _FailureTipCard();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.brandSurfaceAlt,
        borderRadius: AppRadius.card,
      ),
      child: const Padding(
        padding: EdgeInsets.fromLTRB(18, 14, 14, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _QuestionBubble(),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '小提示',
                    style: TextStyle(
                      color: AppColors.brandPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '1. 请靠近路由器，确保信号强度良好\n'
                    '2. 请检查Wi-Fi密码是否正确\n'
                    '3. 请检查设备是否已接通电源\n'
                    '4. 请检查设备是否连接2.4GHzWi-Fi网络',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12.5,
                      height: 1.75,
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

class _QuestionBubble extends StatelessWidget {
  const _QuestionBubble();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      AppAssets.helpChatIcon,
      width: 34,
      height: 34,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      semanticLabel: '提示',
    );
  }
}
