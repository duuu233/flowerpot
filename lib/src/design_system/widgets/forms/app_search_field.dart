import 'package:flutter/material.dart';

import '../../tokens/app_assets.dart';
import 'app_text_field.dart';

class AppSearchField extends StatelessWidget {
  const AppSearchField({
    super.key,
    this.controller,
    this.hintText = '搜索',
    this.onChanged,
    this.onSubmitted,
    this.onClear,
  });

  final TextEditingController? controller;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      controller: controller,
      hintText: hintText,
      prefixIcon: Padding(
        padding: const EdgeInsets.all(12),
        child: Image.asset(
          AppAssets.searchIcon,
          width: 20,
          height: 20,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          excludeFromSemantics: true,
        ),
      ),
      suffixIcon: onClear == null
          ? null
          : IconButton(
              tooltip: '清除',
              onPressed: onClear,
              icon: const Icon(Icons.close_rounded),
            ),
      textInputAction: TextInputAction.search,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
    );
  }
}
