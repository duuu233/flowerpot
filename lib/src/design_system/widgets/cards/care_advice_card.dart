import 'package:flutter/material.dart';

import 'app_info_card.dart';

class CareAdviceCard extends StatelessWidget {
  const CareAdviceCard({
    required this.message,
    super.key,
    this.title = '建议',
    this.emphasized = false,
  });

  final String title;
  final String message;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return AppInfoCard(
      title: title,
      message: message,
      icon: Icons.lightbulb_outline_rounded,
      emphasized: emphasized,
    );
  }
}
