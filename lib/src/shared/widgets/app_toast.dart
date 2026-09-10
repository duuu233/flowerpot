import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

enum AppToastTone { success, error, info }

/// A single, centered app-wide toast backed by the root overlay.
class AppToast {
  AppToast._();

  static OverlayEntry? _current;
  static int _sequence = 0;

  static void show(
    BuildContext context,
    String message, {
    AppToastTone tone = AppToastTone.success,
    Duration duration = const Duration(seconds: 2),
  }) {
    final text = message.trim();
    if (text.isEmpty) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    dismiss();
    final sequence = ++_sequence;
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _ToastEntry(
        message: text,
        tone: tone,
        duration: effectiveDuration(text, duration),
        onExpired: () {
          if (sequence == _sequence && identical(_current, entry)) dismiss();
        },
      ),
    );
    _current = entry;
    overlay.insert(entry);
    SemanticsService.sendAnnouncement(
      View.of(context),
      text,
      Directionality.of(context),
    ).ignore();
  }

  @visibleForTesting
  static Duration effectiveDuration(String message, Duration duration) {
    final readingTime = 300 + message.length * 30;
    final wanted = readingTime > duration.inMilliseconds
        ? readingTime
        : duration.inMilliseconds;
    return Duration(milliseconds: wanted.clamp(2000, 10000));
  }

  static void warn(BuildContext context, String message) {
    show(
      context,
      message,
      tone: AppToastTone.error,
      duration: const Duration(seconds: 3),
    );
  }

  static void dismiss() {
    final entry = _current;
    if (entry?.mounted ?? false) entry!.remove();
    _current = null;
    _sequence++;
  }
}

class _ToastEntry extends StatefulWidget {
  const _ToastEntry({
    required this.message,
    required this.tone,
    required this.duration,
    required this.onExpired,
  });

  final String message;
  final AppToastTone tone;
  final Duration duration;
  final VoidCallback onExpired;

  @override
  State<_ToastEntry> createState() => _ToastEntryState();
}

class _ToastEntryState extends State<_ToastEntry> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.duration, widget.onExpired);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _ToastBubble(message: widget.message, tone: widget.tone);
  }
}

class _ToastBubble extends StatelessWidget {
  const _ToastBubble({required this.message, required this.tone});

  final String message;
  final AppToastTone tone;

  @override
  Widget build(BuildContext context) {
    final (icon, accent) = switch (tone) {
      AppToastTone.success => (
        Icons.check_circle_rounded,
        const Color(0xFFA7D7B8),
      ),
      AppToastTone.error => (Icons.error_rounded, const Color(0xFFFFB4AB)),
      AppToastTone.info => (Icons.info_rounded, const Color(0xFFB8D8F2)),
    };
    return IgnorePointer(
      child: SafeArea(
        child: Center(
          child: Material(
            type: MaterialType.transparency,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: 1),
              duration: const Duration(milliseconds: 160),
              builder: (_, value, child) => Opacity(
                opacity: value,
                child: Transform.scale(
                  scale: 0.96 + value * 0.04,
                  child: child,
                ),
              ),
              child: ConstrainedBox(
                // 宽度跟着屏幕走，不再写死 300。
                //
                // 写死 300 时气泡里留给文字的只有 `300 - 18×2 - 图标 19 - 间距 9
                // = 236`，而「请先阅读并同意用户协议与隐私政策」这种 16 个汉字的
                // 短句在 14px 下就要 224 —— 只差 12px，用户把系统字号调大一档就
                // 折行了。现在按屏宽减一个 16 的边距算（375 的屏上是 343，留给
                // 文字 284），同样这句话有 60px 富余，字号放大到 1.2 倍仍是一行。
                //
                // ⚠️ 「一定不折行」做不到：toast 也要显示接口返回的长报错。这里
                // 做的是把常见的短提示留足余量，长文案照旧折行 + 限高裁尾。
                constraints: BoxConstraints(
                  maxWidth: (MediaQuery.sizeOf(context).width - 32).clamp(
                    260.0,
                    380.0,
                  ),
                  minWidth: 96,
                  maxHeight: MediaQuery.sizeOf(context).height * 0.6,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFF17201B).withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const <BoxShadow>[
                      BoxShadow(
                        color: Color(0x26000000),
                        blurRadius: 18,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Padding(
                    // 左右内边距由 18 收到 16、图标与文字的间距由 9 收到 8：
                    // 这 6px 全部让给文字，短提示更不容易折行。
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 13,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(icon, size: 19, color: accent),
                        const SizedBox(width: 8),
                        Flexible(
                          child: SingleChildScrollView(
                            child: Text(
                              message,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                height: 1.45,
                                fontWeight: FontWeight.w500,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
