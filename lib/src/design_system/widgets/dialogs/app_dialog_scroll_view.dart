import 'package:flutter/material.dart';

/// Owns a separate controller for each modal, including nested wheel pickers.
class AppDialogScrollbar extends StatefulWidget {
  const AppDialogScrollbar({required this.builder, super.key});

  final Widget Function(ScrollController controller) builder;

  @override
  State<AppDialogScrollbar> createState() => _AppDialogScrollbarState();
}

class _AppDialogScrollbarState extends State<AppDialogScrollbar> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScrollConfiguration(
    behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
    child: Scrollbar(
      controller: _controller,
      thumbVisibility: true,
      trackVisibility: true,
      interactive: true,
      thickness: 4,
      radius: const Radius.circular(4),
      notificationPredicate: (notification) => notification.depth == 0,
      child: widget.builder(_controller),
    ),
  );
}

/// Shrinks to short content; overflowing content keeps a visible scroll thumb.
/// Place in Flexible/Expanded and keep modal actions outside this viewport.
class AppDialogScrollView extends StatelessWidget {
  const AppDialogScrollView({
    required this.child,
    super.key,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => AppDialogScrollbar(
    builder: (controller) => SingleChildScrollView(
      controller: controller,
      primary: false,
      padding: padding,
      child: child,
    ),
  );
}
