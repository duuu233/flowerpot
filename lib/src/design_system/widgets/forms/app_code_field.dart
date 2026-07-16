import 'package:flutter/material.dart';

import '../../tokens/app_colors.dart';
import 'app_text_field.dart';

class AppCodeField extends StatelessWidget {
  const AppCodeField({
    required this.sendLabel,
    super.key,
    this.controller,
    this.label,
    this.hintText = '请输入验证码',
    this.errorText,
    this.onSend,
    this.sending = false,
    this.onChanged,
    this.onSubmitted,
    this.validator,
  });

  final TextEditingController? controller;
  final String? label;
  final String hintText;
  final String sendLabel;
  final String? errorText;
  final VoidCallback? onSend;
  final bool sending;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      controller: controller,
      label: label,
      hintText: hintText,
      errorText: errorText,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.next,
      prefixIcon: const Icon(Icons.verified_user_outlined),
      suffixIcon: sending
          ? const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : TextButton(
              onPressed: onSend,
              child: Text(
                sendLabel,
                style: const TextStyle(color: AppColors.brandPrimary),
              ),
            ),
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      validator: validator,
    );
  }
}
