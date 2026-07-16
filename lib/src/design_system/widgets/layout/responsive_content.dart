import 'package:flutter/widgets.dart';

import '../../tokens/app_breakpoints.dart';
import '../../tokens/app_spacing.dart';

class ResponsiveContent extends StatelessWidget {
  const ResponsiveContent({
    required this.child,
    super.key,
    this.padding = AppSpacing.pagePadding,
    this.maxWidth,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width =
            maxWidth ?? AppBreakpoints.contentMaxWidth(constraints.maxWidth);
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: width),
            child: Padding(padding: padding, child: child),
          ),
        );
      },
    );
  }
}
