import 'package:flutter/material.dart';

import 'app_colors.dart';

abstract final class AppShadows {
  static const List<BoxShadow> card = <BoxShadow>[
    BoxShadow(color: Color(0x0F252525), blurRadius: 20, offset: Offset(0, 8)),
  ];

  static const List<BoxShadow> floating = <BoxShadow>[
    BoxShadow(color: Color(0x1A252525), blurRadius: 28, offset: Offset(0, 12)),
  ];

  static const BoxShadow focus = BoxShadow(
    color: AppColors.brandSoft,
    blurRadius: 8,
  );
}
