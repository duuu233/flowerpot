import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/app_theme.dart';
import '../../../app/flowerpot_app.dart';
import '../../../shared/shared.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final nickname = TextEditingController();
  String? avatarPath;
  bool seeded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!seeded) {
      final user = FlowerpotScope.of(context).user;
      nickname.text = user?.nickname ?? '';
      avatarPath = user?.avatarUrl;
      seeded = true;
    }
  }

  @override
  void dispose() {
    nickname.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = FlowerpotScope.of(context);
    final fileExists = avatarPath != null && File(avatarPath!).existsSync();
    return Scaffold(
      appBar: AppBar(title: const Text('基本信息')),
      body: AppBackground(
        child: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.all(22),
            children: <Widget>[
              Center(
                child: Stack(
                  children: <Widget>[
                    CircleAvatar(
                      radius: 54,
                      backgroundColor: AppColors.lime,
                      backgroundImage: fileExists
                          ? FileImage(File(avatarPath!))
                          : null,
                      child: fileExists
                          ? null
                          : const Icon(
                              Icons.person_rounded,
                              color: AppColors.ink,
                              size: 54,
                            ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: IconButton.filled(
                        onPressed: () async {
                          final image = await ImagePicker().pickImage(
                            source: ImageSource.gallery,
                            imageQuality: 82,
                            maxWidth: 1000,
                          );
                          if (image != null) {
                            setState(() => avatarPath = image.path);
                          }
                        },
                        icon: const Icon(Icons.camera_alt_outlined, size: 18),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              TextField(
                controller: nickname,
                maxLength: 20,
                decoration: const InputDecoration(labelText: '用户名'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: state.user?.account ?? '',
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: '登录账号',
                  prefixIcon: Icon(Icons.verified_user_outlined),
                ),
              ),
              const SizedBox(height: 24),
              LoadingButton(
                label: '保存',
                loading: state.busy,
                onPressed: () async {
                  if (nickname.text.trim().isEmpty) {
                    showAppMessage(context, '用户名不能为空', success: false);
                    return;
                  }
                  final result = await state.updateProfile(
                    nickname: nickname.text,
                    avatarUrl: avatarPath,
                  );
                  if (context.mounted) {
                    showAppMessage(
                      context,
                      result.message,
                      success: result.success,
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
