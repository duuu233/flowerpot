import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';

/// 首页「今日养护」：把四条状态建议轮流播出来。
///
/// 一条状态一句话（需水 → 光照 → 温度 → 湿度，与上面四张卡片同序同源），每
/// [interval] 换一条：**旧的一句整体往上滚出、新的一句从下面滚进来**（文字滚动轮播，
/// 2026-09-14 产品：不要渐变效果）。只有一条时不轮播，也不起定时器。
class HomeCareBanner extends StatefulWidget {
  const HomeCareBanner({
    required this.messages,
    this.title = '今日养护',
    this.interval = const Duration(seconds: 8),
    this.notice,
    super.key,
  });

  /// 盆里没有植物时整行换成的提示（惊叹号 + 一句话），此时不显示标题、也不轮播。
  static const String plantMissingNotice = '未检测到植物，请将植物种入花盆。';

  /// 轮播内容，顺序由 `HomeDashboardModel.careMessages` 决定。
  final List<String> messages;

  /// 左边那几个字，跟着界面语言走。
  final String title;

  /// 切换间隔：**这一条停留多久才换下一条**，和切换那一下的动画时长
  /// （[_HomeCareBannerState._transition]）是两回事。
  ///
  /// 2026-09-12 从 5 秒放到 8 秒（产品：「轮播间隙时间可以再长一点」）。减去 900ms
  /// 的切换动画，每条实际静止约 7.1 秒，够把两行读完。
  final Duration interval;

  /// 有值时整行只画这一句（前面是惊叹号图标），养护建议和标题都不显示。
  final String? notice;

  @override
  State<HomeCareBanner> createState() => _HomeCareBannerState();
}

class _HomeCareBannerState extends State<HomeCareBanner> {
  /// 文字区固定两行高。轮播的四句长短不一（2026-09-16 那版文案里「水好像有点多。」
  /// 和「空气里的水分有点少。」就差着几个字，以后换稿还会更长），不固定住的话每切
  /// 一条卡片就会抽一下。
  static const double _messageHeight = 36;

  /// 图标和它右边那一截（有植物时是「今日养护」，没植物时是提示语）之间的间距。
  ///
  /// 2026-09-12 从 `AppSpacing.lg`（16）收到 8（产品：「今日养护要和左边的图标离得
  /// 近点」）。**两支都用它**——这两支是同一张卡的两个状态，只改一边的话，设备切换
  /// 有无植物时图标后面的文字会横向跳一下。
  static const double _iconGap = AppSpacing.sm;

  /// 一条换下一条的**动画时长**，不是轮播间隔（那是 [HomeCareBanner.interval]，
  /// 2026-09-12 起 8 秒换一条）。产品先后提了两次，指的是不同的东西，别弄混：
  ///
  /// - 「滚动速率慢一点」→ 改的是这里：旧的一句滚出、新的一句滚进，这个位移过程走多久。
  ///   420ms 显得"刷"一下就过去了，放到 900ms 读起来从容。
  /// - 「轮播间隙时间再长一点」→ 改的是 [HomeCareBanner.interval]，5 秒 → 8 秒。
  static const Duration _transition = Duration(milliseconds: 900);

  int _index = 0;
  Timer? _timer;

  /// 当前这一句的 key。滚动动画靠它分辨「进来的」和「出去的」（见 build 里的
  /// `transitionBuilder`）。
  Key _messageKey = const ValueKey<String>('');

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
          // 上下 4 + 两行区 36 = 44，稿子 156:4427 / 156:4304 的养护条高（原上下 10，条高 56，
          // 下面的快捷列表和帮助卡整体低 12）。两支同高的口径不变。
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
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
              // 间距和下面那一支保持一致（见 [_iconGap]），否则设备切换有无植物时，
              // 图标后面的文字会横向跳一下。
              const SizedBox(width: _iconGap),
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
    _messageKey = ValueKey<String>('$_index:$message');
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: AppSurfaceCard(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
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
            const SizedBox(width: _iconGap),
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
                // **文字滚动轮播**（2026-09-14 产品：「改为文字滚动轮播的效果，不要这种渐变的效果」）：
                // 旧的一句整体往上滚出这一格、新的一句从格子下沿滚进来，全程不透明度不变。
                // 滚动距离是整格高度（Offset 1.0），格子外的部分由 [ClipRect] 裁掉。
                //
                // 原来是 `FadeTransition` 叠一小段 `SlideTransition`（0.35 格）：新旧两句在
                // 同一位置半透明地重叠一下，产品看到的就是「渐变」。
                child: ClipRect(
                  child: AnimatedSwitcher(
                    duration: _transition,
                    // 时长拉长之后曲线也要换：`easeOutCubic` 尾巴收得太快，
                    // 900ms 下会显得"前面猛冲、最后一截停住"。`easeInOut` 两头都缓，
                    // 整段匀一些，才是"慢"而不是"拖"。
                    switchInCurve: Curves.easeInOut,
                    switchOutCurve: Curves.easeInOut,
                    layoutBuilder: (current, previous) => Stack(
                      alignment: Alignment.centerLeft,
                      children: <Widget>[...previous, ?current],
                    ),
                    transitionBuilder: (child, animation) {
                      // AnimatedSwitcher 对进出两句用同一个 builder：进来的那句动画 0→1，
                      // 出去的那句是反着播 1→0。按 key 分开，进来的从下面（+1）滚到 0，
                      // 出去的从 0 滚到上面（-1）。
                      final entering = child.key == _messageKey;
                      final offset = Tween<Offset>(
                        begin: Offset(0, entering ? 1 : -1),
                        end: Offset.zero,
                      ).animate(animation);
                      return SlideTransition(position: offset, child: child);
                    },
                    child: Align(
                      // 语言切换后同一个下标也要重播，所以键里带上文案本身。
                      key: _messageKey,
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
            ),
          ],
        ),
      ),
    );
  }
}
