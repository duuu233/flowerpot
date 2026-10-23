import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../app/network_alert.dart';
import '../../../core/backend/backend.dart';
import '../../../design_system/design_system.dart';
import '../models/about_page_model.dart';
import 'widgets/about_brand_lockup.dart';
import 'widgets/about_version_card.dart';
import 'widgets/app_update_dialog.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key, this.pageModel});

  final AboutPageModel? pageModel;

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage>
    with NetworkRetryAware<AboutPage> {
  bool _requested = false;

  AboutPageModel get _baseModel =>
      widget.pageModel ?? AboutPageModel.current();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requested) return;
    _requested = true;
    // 更新状态和版本说明来自 `/Client/Basic/getLastVersion`，要把本机版本号发
    // 过去做比对。后端没开或查不到就用页面自带的「已是最新版本」。
    FlowerpotScope.maybeOf(context)?.checkAppVersion(_baseModel.version);
  }

  @override
  Future<void> reloadForNetworkRetry() async {
    final state = FlowerpotScope.maybeOf(context);
    if (state == null) return;
    await state.checkAppVersion(_baseModel.version);
  }

  /// 后端的判定覆盖到页面模型上。当前版本号仍然显示本机的那个——`version`
  /// 是「我装的是哪一版」，不是「线上最新是哪一版」。
  static AboutPageModel _merge(AboutPageModel model, BackendAppVersion? latest) {
    if (latest == null) return model;
    return model.copyWith(
      updateStatus: latest.hasUpdate ? '发现新版本 V${latest.versionNo}' : '已是最新版本',
      releaseNotes: latest.releaseNotes.isEmpty ? null : latest.releaseNotes,
      hasUpdate: latest.hasUpdate,
    );
  }

  @override
  Widget build(BuildContext context) {
    final model = _merge(
      _baseModel,
      FlowerpotScope.maybeOf(context)?.appVersion,
    );
    final compact = MediaQuery.sizeOf(context).height < 700;

    return AppPageScaffold(
      appBar: const AppPageHeader(
        title: '关于东方金穗',
        leading: AppBackButton(),
      ),
      background: AppPageBackground.standard,
      body: SingleChildScrollView(
        key: const Key('about-scroll-view'),
        child: ResponsiveContent(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.pageMargin,
            compact ? 68 : 100,
            AppSpacing.pageMargin,
            48,
          ),
          child: Column(
            children: <Widget>[
              AboutBrandLockup(model: model),
              const SizedBox(height: 36),
              AboutVersionCard(
                model: model,
                onCheckUpdate: () => _checkUpdate(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 点「检查更新」：当场再问一次后端，有新版本就弹升级弹窗（强制升级的那条
  /// 由 `AppShell` 在 App 打开时就弹过了，这里保持同一套判定）。
  Future<void> _checkUpdate(BuildContext context) async {
    final state = FlowerpotScope.maybeOf(context);
    if (state == null) return;
    final latest = await state.checkAppVersion(_baseModel.version);
    if (!context.mounted) return;
    if (latest == null || !latest.hasUpdate) {
      showAppMessage(context, '已是最新版本');
      return;
    }
    await showAppUpdateDialog(
      context,
      version: latest,
      // 与启动时一致：后台没配下载地址就不按强制弹，否则关不掉又打不开下载页。
      force: latest.forceUpdate && latest.downloadUrl.trim().isNotEmpty,
    );
  }
}
