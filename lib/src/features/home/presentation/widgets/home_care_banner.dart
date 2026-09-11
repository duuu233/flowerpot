import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';

/// 首页「今日养护」：把四条状态建议轮流播出来。
///
/// 一条状态一句话（需水 → 光照 → 温度 → 湿度，与上面四张卡片同序同源），每
/// [interval] 换一条：旧的一句往下淡出、新的一句从下面淡入。只有一条时不轮播，
/// 也不起定时器。
class HomeCareBanner extends StatefulWidget {
  const HomeCareBanner({
    required this.messages,
    this.title = '今日养护',
    this.interval = const Duration(seconds: 5),
    this.notice,
    super.key,
  });

  /// 盆里没有植物时整行换成的提示（惊叹号 + 一句话），此时不显示标题、也不轮播。
  static const String plantMissingNotice = '未检测到植物，请将植物种入花盆。';

  /// 轮播内容，顺序由 `HomeDashboardModel.careMessages` 决定。
  final List<String> messages;

  /// 左边那几个字，跟着界面语言走。
  final String title;

  /// 切换间隔。
  final Duration interval;

  /// 有值时整行只画这一句（前面是惊叹号图标），养护建议和标题都不显示。
  final String? notice;

  @override
  State<HomeCareBanner> createState() => _HomeCareBannerState();
}

class _HomeCareBannerState extends State<HomeCareBanner> {
  /// 文字区固定两行高。建议长短不一（「继续保持。」和「水仓快见底了，根系快吸
  /// 不到水了，该加水啦。」差一倍），不固定住的话每切一条卡片就会抽一下。
  static const double _messageHeight = 36;

  static const Duration _transition = Duration(milliseconds: 420);

  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _restartTimer();
  }

  @override
  void didUpdateWidget(HomeCareBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.messages.length != oldWidget.messages.length ||
        widget.interval != oldWidget.interval) {
      // 条数变了（例如换了设备）先把下标收回有效范围，再按新的间隔重新计时。
      _index = widget.messages.isEmpty ? 0 : _index % widget.messages.length;
      _restartTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _restartTimer() {
    _timer?.cancel();
    if (widget.messages.length < 2) return;
    _timer = Timer.periodic(widget.interval, (_) {
      if (!mounted) return;
      setState(() => _index = (_index + 1) % widget.messages.length);
    });
  }

  @override
  Widget build(BuildContext context) {
    final notice = widget.notice;
    if (notice != null) {
      return ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: AppSurfaceCard(
          key: const Key('home-care-notice'),
          // ⚠️ **内边距要和下面那一支一模一样**（2026-09-11）：这两支是同一张卡的两个
          // 状态，差 2px 也会在切换时看出来。
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          color: AppColors.surfaceTranslucent,
          borderRadius: AppRadius.large,
          side: const BorderSide(color: AppColors.surface),
          child: Row(
            children: <Widget>[
              const Icon(
                Icons.error_outline_rounded,
                size: 18,
                color: AppColors.warning,
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                // **同样固定两行高**（[_messageHeight]）。
                //
                // 改之前这一支让文字自己撑高：「未检测到植物」只有一行，而有植物时的
                // 养护建议区是固定两行，于是用户按固件按钮切换有无植物时，整张卡的高度
                // 变一次、下面的内容跟着跳一次（2026-09-11 产品反馈）。两支同高就不跳。
                child: SizedBox(
                  height: _messageHeight,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      notice,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.compactBody.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final messages = widget.messages;
    final message = messages.isEmpty ? '' : messages[_index % messages.length];
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: AppSurfaceCard(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        color: AppColors.surfaceTranslucent,
        borderRadius: AppRadius.large,
        side: const BorderSide(color: AppColors.surface),
        child: Row(
          children: <Widget>[
            Image.asset(
              AppAssets.selectPlantIcon,
              width: 18,
              height: 18,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              semanticLabel: widget.title,
            ),
            const SizedBox(width: AppSpacing.lg),
            Text(
              widget.title,
              style: AppTypography.compactBody.copyWith(
                color: AppColors.brandPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: SizedBox(
                height: _messageHeight,
                child: AnimatedSwitcher(
                  duration: _transition,
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, .35),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: Align(
                    // 语言切换后同一个下标也要重播，所以键里带上文案本身。
                    key: ValueKey<String>('$_index:$message'),
                    alignment: Alignment.centerLeft,
                    child: Text(
                      message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.compactBody.copyWith(
                        color: AppColors.textPrimary,
                        height: 1.35,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
