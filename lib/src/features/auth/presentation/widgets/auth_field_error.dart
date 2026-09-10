import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';

/// 输入框下面那行校验提示（登录 / 注册 / 找回密码三页共用）。
///
/// 2026-09-09 加上手机号格式校验后，号码不合法时「获取验证码」按钮是灰的——**不给一句话，
/// 用户不知道为什么点不动**。这一行就是补那句话；[message] 为 null 时不占位置。
///
/// 什么时候显示由页面决定（失焦一次之后、或点过按钮之后），不在这里判：边打字边报红太吵，
/// 第一个字符输进去就是「格式不对」没有任何意义。
class AuthFieldError extends StatelessWidget {
  const AuthFieldError({required this.message, super.key});

  static const fieldKey = Key('auth-field-error');

  final String? message;

  @override
  Widget build(BuildContext context) {
    final text = message;
    if (text == null) return const SizedBox.shrink();
    return Padding(
      // 左边距对齐输入框里的文字（图标位 56 - 胶囊圆角视觉留白），不是贴着卡片边。
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
      child: Row(
        key: fieldKey,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(
            Icons.error_outline,
            size: 14,
            color: AppColors.danger,
          ),
          const SizedBox(width: AppSpacing.xxs),
          Expanded(
            child: Text(
              text,
              style: AppTypography.compactBody.copyWith(
                color: AppColors.danger,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
