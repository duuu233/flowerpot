import 'dart:ui';

import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../design_system/tokens/app_assets.dart';
import 'app_toast.dart';

class AppBackground extends StatelessWidget {
  const AppBackground({required this.child, super.key, this.warm = false});

  final Widget child;
  final bool warm;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: warm
              ? const <Color>[Color(0xFFFFF8EB), Color(0xFFF3F7EF)]
              : const <Color>[
                  Color(0xFFEAF4EC),
                  Color(0xFFF7F4E9),
                  Color(0xFFF2F6EF),
                ],
          stops: const <double>[0, .56, 1],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          const Positioned(
            top: -90,
            right: -70,
            child: _Glow(size: 240, color: AppColors.lime),
          ),
          const Positioned(
            bottom: 100,
            left: -100,
            child: _Glow(size: 250, color: AppColors.water),
          ),
          child,
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => ImageFiltered(
    imageFilter: ImageFilter.blur(sigmaX: 38, sigmaY: 38),
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: .16),
      ),
    ),
  );
}

class GlassCard extends StatelessWidget {
  const GlassCard({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.all(18),
    this.onTap,
    this.color,
    this.borderRadius = 24,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(borderRadius),
      side: BorderSide(color: Colors.white.withValues(alpha: .85)),
    );
    final content = Padding(padding: padding, child: child);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x0C17332B),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: color ?? Colors.white.withValues(alpha: .78),
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: onTap == null ? content : InkWell(onTap: onTap, child: content),
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({
    required this.label,
    super.key,
    this.icon,
    this.color = AppColors.leaf,
  });

  final String label;
  final IconData? icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(100),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (icon != null) ...<Widget>[
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
        ],
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class MetricTile extends StatelessWidget {
  const MetricTile({
    required this.title,
    required this.value,
    required this.status,
    required this.icon,
    required this.color,
    super.key,
    this.onTap,
  });

  final String title;
  final String value;
  final String status;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GlassCard(
    onTap: onTap,
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const Spacer(),
            const Icon(
              Icons.arrow_outward_rounded,
              size: 16,
              color: AppColors.muted,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(title, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(
            color: AppColors.ink,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          status,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 2, bottom: 12),
    child: Row(
      children: <Widget>[
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        ?trailing,
      ],
    ),
  );
}

class SettingGroup extends StatelessWidget {
  const SettingGroup({required this.children, super.key, this.title});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      if (title != null) SectionTitle(title!),
      GlassCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: <Widget>[
            for (var index = 0; index < children.length; index++) ...<Widget>[
              children[index],
              if (index != children.length - 1)
                const Divider(height: 1, indent: 18, endIndent: 18),
            ],
          ],
        ),
      ),
    ],
  );
}

class SettingTile extends StatelessWidget {
  const SettingTile({
    required this.icon,
    required this.title,
    super.key,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.iconColor = AppColors.leaf,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color iconColor;
  final bool danger;

  @override
  Widget build(BuildContext context) => ListTile(
    minTileHeight: 64,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
    leading: Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: (danger ? AppColors.danger : iconColor).withValues(alpha: .1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, size: 20, color: danger ? AppColors.danger : iconColor),
    ),
    title: Text(
      title,
      style: TextStyle(
        color: danger ? AppColors.danger : AppColors.ink,
        fontSize: 14,
        fontWeight: FontWeight.w700,
      ),
    ),
    subtitle: subtitle == null
        ? null
        : Text(subtitle!, style: const TextStyle(fontSize: 11)),
    trailing:
        trailing ??
        (onTap == null
            ? null
            : Image.asset(
                AppAssets.chevronRightIcon,
                width: 20,
                height: 20,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
                excludeFromSemantics: true,
              )),
    onTap: onTap,
  );
}

class LoadingButton extends StatelessWidget {
  const LoadingButton({
    required this.label,
    required this.loading,
    required this.onPressed,
    super.key,
  });

  final String label;
  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: loading ? null : onPressed,
    child: loading
        ? const SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          )
        : Text(label),
  );
}

void showAppMessage(
  BuildContext context,
  String message, {
  bool success = true,
}) {
  AppToast.show(
    context,
    message,
    tone: success ? AppToastTone.success : AppToastTone.error,
  );
}
