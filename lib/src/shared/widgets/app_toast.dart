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
                // 限高之后长文案（例如开发构建里贴出来的接口原始响应）只会被
                // 裁掉尾巴，不会撑破气泡。
                constraints: BoxConstraints(
                  maxWidth: 300,
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 13,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(icon, size: 19, color: accent),
                        const SizedBox(width: 9),
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
