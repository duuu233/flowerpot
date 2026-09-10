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
  /// 无法判断该改什么。2026-09-10 起 [message] 是**不带来源前缀的原文**（产品要求
  /// toast 直接给内容），所以认得的失败码由这一页自己补在括号里。
  final String? code;
  final String? message;

  String get _subtitle {
    const generic = '设备未能成功连接到当前Wi-Fi网络';
    // 失败码**无论认不认得都要显示**。
    //
    // 改之前只在认得的那一支里带上 `（$code）`，认不得时整个把 code 丢了、只剩涂鸦
    // 的原文。2026-09-10 测试报回来的就是这种：「……，out of time」——看不到任何码，
    // 于是没法判断失败在哪一步。而认不得恰恰是最需要这个码的情形。
    final tag = code?.trim() ?? '';
    final suffix = tag.isEmpty ? '' : '（$tag）';
    final hint = hintFor(code) ?? _hintForMessage(message);
    if (hint != null) return '$generic\n$hint$suffix';
    final detail = message?.trim() ?? '';
    if (detail.isEmpty) {
      return tag.isEmpty ? generic : '$generic\n失败码 $tag';
    }
    return '$generic\n$detail$suffix';
  }

  /// 码认不出来时，退一步看涂鸦给的那句原文。
  ///
  /// `out of time` 是涂鸦 activator 的超时原文，不分新旧流程都可能出现，而它在新流程
  /// 里的含义很具体：**没有收到设备的任何结构化回复**（收到了就会是 207xxx）——
  /// 也就是整条通道没建起来，不是密码错或连不上路由器。
  static String? _hintForMessage(String? message) {
    final text = message?.toLowerCase() ?? '';
    if (text.isEmpty) return null;
    // 只认涂鸦那句**没翻译的英文原文**。我们自己的中文文案（「配网超时」之类）本来
    // 就读得懂，不该被换掉——换掉反而把原始信息弄没了。
    if (text.contains('out of time') || text.contains('timeout')) {
      return '等待设备回应超时，整条配网通道没有建立起来：请给设备重新上电，'
          '确认手机靠近设备、且手机连的是 2.4GHz Wi-Fi，然后重试';
    }
    return null;
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
    // 「热点配网新流程」的失败码，抄自涂鸦官方文档（存档见
    // docs/reference/tuya-ap-mode-android.md 的「错误码」表）。这些码之前一个都没
    // 映射，失败时页面只剩一句笼统的「设备未能成功连接到当前Wi-Fi网络」，看不出
    // 到底是密码错、找不到路由器，还是固件不支持这套流程。
    '207201' => '没能和设备建立通道：确认设备已开机、靠近手机，并且没有被别的手机占着配网',
    '207206' => '设备返回了无法识别的状态：多半是设备已退出配网状态，请给设备重新上电后重试；也可能正被另一台手机占着配网',
    '207207' => '设备不支持读取 Wi-Fi 列表（不影响配网，直接用手机当前连着的网络即可）',
    '207209' => '设备收到的配网信息有误，请重新输入 Wi-Fi 名称和密码',
    '207210' => '设备找不到这个路由器：确认 Wi-Fi 名称没打错，并且设备在路由器覆盖范围内',
    '207211' => 'Wi-Fi 密码错误，请重新输入',
    '207212' => '设备连不上路由器：确认所选网络是 2.4GHz，且路由器没有开启设备数量或黑白名单限制',
    '207213' => '路由器没给设备分配到 IP（DHCP 失败），请重启路由器后重试',
    '207214' || '207216' || '207218' => '设备激活失败，请稍后重试；持续失败请联系客服',
    '207215' => '设备连上了路由器但没能连上云端：确认这个网络可以正常上网',
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
                      // 插图上下的留白是这一页唯一能让的地方：失败原因一多，
                      // 副标题就涨到三四行，再按原来的 70 + 235 + 24 排，底部那颗
                      // 「返回搜索设备」会被挤出首屏、只露出上半截。
                      SizedBox(height: compact ? 16 : 36),
                      Center(child: _FailureRadar(size: compact ? 160 : 200)),
                      SizedBox(height: compact ? 10 : 16),
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
                      SizedBox(height: compact ? 14 : 18),
                      const _FailureTipCard(),
                      // 内容不足一屏时把按钮推到底部；够高时 24 就是普通间距。
                      // `IntrinsicHeight` 是 SingleChildScrollView 里用 Expanded
                      // 的标准写法：没有它，Column 拿到的高度约束是无界的，Expanded
                      // 会直接抛「non-zero flex but unbounded height」。
                      SizedBox(height: compact ? 14 : 20),
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
  const _FailureRadar({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      AppAssets.pairingFailureIllustration,
      width: size,
      height: size,
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
