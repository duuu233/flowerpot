import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';

class AccountPasswordFormCard extends StatelessWidget {
  const AccountPasswordFormCard({required this.fields, super.key});

  final List<AccountPasswordField> fields;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      color: AppColors.surfaceTranslucent,
      borderRadius: AppRadius.large,
      padding: EdgeInsets.zero,
      showShadow: false,
      child: AutofillGroup(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (var index = 0; index < fields.length; index++) ...<Widget>[
              fields[index],
              if (index < fields.length - 1)
                const Divider(indent: 22, endIndent: 22),
            ],
          ],
        ),
      ),
    );
  }
}

class AccountPasswordField extends StatelessWidget {
  const AccountPasswordField({
    required this.controller,
    required this.label,
    required this.hintText,
    required this.visible,
    required this.visibilityKey,
    required this.onVisibilityChanged,
    required this.textInputAction,
    super.key,
    this.assetPath = AppAssets.accountPasswordIcon,
    this.autofillHints,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final String hintText;
  final String assetPath;
  final bool visible;
  final Key visibilityKey;
  final VoidCallback onVisibilityChanged;
  final TextInputAction textInputAction;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 76,
      child: Row(
        children: <Widget>[
          const SizedBox(width: 22),
          AppIconBadge(
            assetPath: assetPath,
            semanticLabel: label,
            backgroundColor: Colors.transparent,
            size: 40,
            iconSize: 40,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: AppTypography.sectionTitle.copyWith(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    height: 1.25,
                  ),
                ),
                SizedBox(
                  height: 27,
                  child: TextField(
                    controller: controller,
                    keyboardType: TextInputType.visiblePassword,
                    textInputAction: textInputAction,
                    obscureText: !visible,
                    enableSuggestions: false,
                    autocorrect: false,
                    autofillHints: autofillHints,
                    onSubmitted: onSubmitted,
                    style: AppTypography.body.copyWith(
                      fontSize: 15,
                      height: 1.2,
                    ),
                    decoration: InputDecoration(
                      hintText: hintText,
                      hintStyle: AppTypography.body.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 15,
                        height: 1.2,
                      ),
                      isDense: true,
                      filled: false,
                      contentPadding: const EdgeInsets.only(top: 2),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: visibilityKey,
            tooltip: visible ? '隐藏密码' : '显示密码',
            onPressed: onVisibilityChanged,
            icon: visible
                ? const Icon(
                    Icons.visibility_outlined,
                    color: AppColors.textSecondary,
                    size: 21,
                  )
                : const SizedBox.square(
                    dimension: 22,
                    child: _PasswordVisibilityOffIcon(),
                  ),
          ),
          const SizedBox(width: 10),
        ],
      ),
    );
  }
}

class _PasswordVisibilityOffIcon extends StatelessWidget {
  const _PasswordVisibilityOffIcon();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      AppAssets.passwordVisibilityOffIcon,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      excludeFromSemantics: true,
    );
  }
}
