import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/app_theme.dart';
import '../../../app/flowerpot_app.dart';
import '../../../shared/shared.dart';

class AnimationsPage extends StatelessWidget {
  const AnimationsPage({required this.deviceId, super.key});

  final String deviceId;

  @override
  Widget build(BuildContext context) {
    final state = FlowerpotScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('定制动画')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: state.busy
            ? null
            : () async {
                final file = await ImagePicker().pickImage(
                  source: ImageSource.gallery,
                  imageQuality: 88,
                );
                if (file == null || !context.mounted) return;
                final result = await state.addAnimation(
                  deviceId,
                  name: file.name,
                  path: file.path,
                );
                if (context.mounted) {
                  showAppMessage(
                    context,
                    result.message,
                    success: result.success,
                  );
                }
              },
        icon: const Icon(Icons.add_photo_alternate_outlined),
        label: const Text('上传图片'),
      ),
      body: AppBackground(
        child: SafeArea(
          top: false,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 100),
            itemCount: state.animations.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              if (index == 0) {
                return const GlassCard(
                  color: AppColors.ink,
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.sync_rounded, color: AppColors.lime),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '列表中的图片会同步到当前花盆；置顶后优先展示。',
                          style: TextStyle(color: Colors.white, height: 1.45),
                        ),
                      ),
                    ],
                  ),
                );
              }
              final item = state.animations[index - 1];
              return GlassCard(
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: AppColors.leaf.withValues(alpha: .1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        item.path.startsWith('builtin')
                            ? Icons.animation_rounded
                            : Icons.image_outlined,
                        color: AppColors.leaf,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            item.name,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 5),
                          StatusPill(
                            label: item.synced ? '已同步' : '待同步',
                            icon: item.synced
                                ? Icons.cloud_done_outlined
                                : Icons.cloud_upload_outlined,
                            color: item.synced ? AppColors.leaf : AppColors.sun,
                          ),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (action) {
                        if (action == 'pin') {
                          state.pinAnimation(item.id);
                        }
                        if (action == 'delete') {
                          state.deleteAnimation(item.id);
                        }
                      },
                      itemBuilder: (_) => const <PopupMenuEntry<String>>[
                        PopupMenuItem(value: 'pin', child: Text('置顶')),
                        PopupMenuItem(value: 'delete', child: Text('删除')),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
