import 'package:flutter/material.dart';

import '../mower/mower_ui.dart';

class MessageCategoryTabs extends StatelessWidget {
  const MessageCategoryTabs({
    required this.keyPrefix,
    required this.current,
    required this.onChanged,
    this.labels = const ['日志', '提醒', '告警'],
    this.unreadAlarm = false,
    super.key,
  });

  final String keyPrefix;
  final int current;
  final ValueChanged<int> onChanged;
  final List<String> labels;
  final bool unreadAlarm;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (var index = 0; index < labels.length; index++)
            Expanded(
              child: Semantics(
                selected: index == current,
                button: true,
                child: InkWell(
                  key: Key('$keyPrefix-tab-$index'),
                  onTap: () => onChanged(index),
                  borderRadius: BorderRadius.circular(9),
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: index == current
                          ? MowerColors.brand
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          labels[index],
                          style: TextStyle(
                            color: index == current
                                ? Colors.white
                                : MowerColors.ink,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (index == 2 && unreadAlarm)
                          const Padding(
                            padding: EdgeInsets.only(left: 4),
                            child: Icon(
                              Icons.circle,
                              size: 6,
                              color: Colors.red,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
