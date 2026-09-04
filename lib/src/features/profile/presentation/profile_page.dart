import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../../../routes/app_routes.dart';
import '../models/personal_info_page_model.dart';
import 'widgets/personal_info_card.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, this.pageModel});

  final PersonalInfoPageModel? pageModel;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String? _localAvatarPath;
  bool _seeded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_seeded) {
      final state = FlowerpotScope.of(context);
      _localAvatarPath = state.user?.avatarUrl;
      _seeded = true;
      // 别的端改过昵称/头像时这里要能看到，所以进页面重新拉一次
      // `/Client/User/getUserInfo`。
      state.refreshUserInfo();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = FlowerpotScope.of(context);
    final baseModel =
        widget.pageModel ?? PersonalInfoPageModel.fromUser(state.user);
    final model = _localAvatarPath == null
        ? baseModel
        : baseModel.copyWith(avatarPath: _localAvatarPath);
    final avatarImage = _avatarImage(model.avatarPath);

    return AppPageScaffold(
      appBar: const AppPageHeader(title: '个人信息', leading: AppBackButton()),
      background: AppPageBackground.standard,
      body: CustomScrollView(
        key: const Key('personal-info-scroll-view'),
        slivers: <Widget>[
          SliverToBoxAdapter(
            child: ResponsiveContent(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.pageMargin,
                32,
                AppSpacing.pageMargin,
                0,
              ),
              child: PersonalInfoCard(
                model: model,
                avatarImage: avatarImage,
                onAvatarTap: state.busy ? null : _pickAvatar,
                onNicknameTap: state.busy ? null : _editNickname,
                onPhoneTap: state.busy
                    ? null
                    : () => Navigator.pushNamed(context, AppRoutes.settings),
                onAccountIdTap: state.busy
                    ? null
                    : () => _copyAccountId(model.accountId),
              ),
            ),
          ),
          SliverFillRemaining(
            hasScrollBody: false,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: PersonalInfoLogoutButton(
                  onPressed: state.busy ? null : _confirmLogout,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  ImageProvider<Object>? _avatarImage(String? path) {
    final value = path?.trim();
    if (value == null || value.isEmpty) return null;
    final file = File(value);
    if (file.existsSync()) return FileImage(file);
    final uri = Uri.tryParse(value);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      return NetworkImage(value);
    }
    return null;
  }

  Future<void> _pickAvatar() async {
    final previousPath = _localAvatarPath;
    XFile? image;
    try {
      image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 82,
        maxWidth: 1000,
        maxHeight: 1000,
      );
    } on PlatformException catch (error) {
      if (!mounted) return;
      showAppMessage(
        context,
        error.message ?? '无法访问相册，请检查照片权限',
        tone: AppMessageTone.error,
      );
      return;
    }
    final pickedImage = image;
    if (pickedImage == null || !mounted) return;
    setState(() => _localAvatarPath = pickedImage.path);

    final state = FlowerpotScope.of(context);
    final result = await state.updateProfile(
      nickname: state.user?.nickname ?? '',
      avatarUrl: pickedImage.path,
    );
    if (!mounted) return;
    if (!result.success) {
      setState(() => _localAvatarPath = previousPath);
      showAppMessage(context, result.message, tone: AppMessageTone.error);
      return;
    }
    showAppMessage(context, result.message);
  }

  Future<void> _editNickname() async {
    final state = FlowerpotScope.of(context);
    final currentNickname = state.user?.nickname ?? '';
    final nickname = await showDialog<String>(
      context: context,
      builder: (_) => _NicknameEditDialog(initialValue: currentNickname),
    );
    if (nickname == null || nickname == currentNickname || !mounted) return;

    final result = await state.updateProfile(
      nickname: nickname,
      avatarUrl: _localAvatarPath,
    );
    if (!mounted) return;
    showAppMessage(
      context,
      result.message,
      tone: result.success ? AppMessageTone.success : AppMessageTone.error,
    );
  }

  Future<void> _copyAccountId(String accountId) async {
    if (accountId == '—') return;
    await Clipboard.setData(ClipboardData(text: accountId));
    if (!mounted) return;
    showAppMessage(context, '账号ID已复制', tone: AppMessageTone.info);
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: '退出登录',
      message: '确定退出当前账号吗？',
      confirmLabel: '退出登录',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final result = await FlowerpotScope.of(context).logout();
    if (!mounted) return;
    if (!result.success) {
      showAppMessage(context, result.message, tone: AppMessageTone.error);
      return;
    }
    Navigator.pushNamedAndRemoveUntil(context, AppRoutes.auth, (_) => false);
  }
}

class _NicknameEditDialog extends StatefulWidget {
  const _NicknameEditDialog({required this.initialValue});

  final String initialValue;

  @override
  State<_NicknameEditDialog> createState() => _NicknameEditDialogState();
}

class _NicknameEditDialogState extends State<_NicknameEditDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      key: const Key('nickname-edit-dialog'),
      title: '修改昵称',
      message: '最多 20 个字符，将展示在「我的」和设备分享里。',
      icon: Icons.badge_outlined,
      confirmKey: const Key('confirm-nickname-edit'),
      content: AppDialogTextField(
        key: const Key('nickname-edit-field'),
        controller: _controller,
        hintText: '请输入昵称',
        maxLength: 20,
      ),
      onCancel: () => Navigator.pop(context),
      // 空昵称直接吞掉这次点击，而不是把按钮画成灰的：那需要监听输入重建，
      // 而这个弹窗除此之外没有任何状态。
      onConfirm: _submit,
    );
  }

  void _submit([String? value]) {
    final nickname = (value ?? _controller.text).trim();
    if (nickname.isNotEmpty) Navigator.pop(context, nickname);
  }
}
