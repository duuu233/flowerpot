import 'package:flutter/material.dart';

import 'app_text_field.dart';

class AppPhoneField extends StatelessWidget {
  const AppPhoneField({
    super.key,
    this.controller,
    this.label,
    this.hintText = '请输入手机号',
    this.countryCode = '+86',
    this.errorText,
    this.onChanged,
    this.onSubmitted,
    this.validator,
  });

  final TextEditingController? controller;
  final String? label;
  final String hintText;
  final String countryCode;
  final String? errorText;
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
      keyboardType: TextInputType.phone,
      textInputAction: TextInputAction.next,
      prefixIcon: Padding(
        padding: const EdgeInsets.only(left: 16, right: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.phone_iphone_rounded, size: 20),
            const SizedBox(width: 6),
            Text(countryCode),
          ],
        ),
      ),
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      validator: validator,
    );
  }
}
