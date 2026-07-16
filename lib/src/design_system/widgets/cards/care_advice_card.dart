import 'package:flutter/material.dart';

import 'app_info_card.dart';

class CareAdviceCard extends StatelessWidget {
  const CareAdviceCard({required this.message, super.key, this.title = '建议'});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return AppInfoCard(
      title: title,
      message: message,
      icon: Icons.lightbulb_outline_rounded,
    );
  }
}
