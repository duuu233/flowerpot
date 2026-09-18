import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../../../routes/app_routes.dart';
import '../../../shared/user_avatar.dart';
import '../../../state.dart';
import '../../../tuya/tuya_models.dart';
import '../../home/models/home_dashboard_model.dart';
import '../../home/presentation/home_page.dart';
import '../../mower/mower_demo.dart';
import 'device_online_guard.dart';

class DeviceListPage extends StatelessWidget {
  const DeviceListPage({super.key, this.devices, this.onOpenProfile});

  final List<SmartPlanterDevice>? devices;

  /// Lets the shell switch to the profile tab instead of stacking a route.
  final VoidCallback? onOpenProfile;

  /// 打开设备页。
  ///
  /// 只剩离线这一道门禁：详情页整屏都是 DP 上报值，设备不在线时显示的是上一次
  /// 快照，而设置、校准、动画这些操作也会被设备直接拒掉。
  ///
  /// 2026-09-09 起**不再按 DP 116 判断有没有植物**：植物的有无由设备上报的
  /// -1 / 0..N 决定，详情页自己会画「未检测到植物」的样子，也会在设备要求时弹
  /// 「发现新植物」引导窗，不需要在列表页先把用户拦去选植物。
  void _openDevice(
    BuildContext context,
    FlowerpotState state,
    SmartPlanterDevice device,
  ) {
    // 这里已经是设备列表页，提示即可，不用再往列表页跳。
    if (!device.online) {
      showAppMessage(context, deviceOfflineMessage, tone: AppMessageTone.error);
      return;
    }
    state.selectDevice(device.id);
    Navigator.pushNamed(
      context,
      AppRoutes.deviceHome,
      arguments: HomeDeviceArguments(
        deviceId: device.id,
        scene: HomeDashboardScene.withCompanionSummary,
      ),
    );
  }

  /// 重新拉设备列表。失败原因用统一的提示条说出来——以前 `onRefresh` 直接把
  /// 异常抛回 `RefreshIndicator`，只进日志，用户下拉半天看不到任何反馈。
  Future<void> _reload(BuildContext context, FlowerpotState state) async {
    final result = await state.reloadDevices();
    if (!context.mounted || result.success) return;
    // 没网时页面本身就写着「当前网络不可用」，全局「网络异常」弹窗也会出来，
    // 再叠一条红色 toast 是第三遍。
    if (state.deviceLoadOffline) return;
    showAppMessage(context, result.message, tone: AppMessageTone.error);
  }

  @override
  Widget build(BuildContext context) {
    final state = FlowerpotScope.of(context);
    final items = devices ?? state.devices;
    return AppPageScaffold(
      appBar: AppPageHeader(
        title: '设备列表',
        // This is the root screen: the Figma frame draws a back chevron here,
        // but there is nothing to pop back to, so the slot holds the profile
        // entry instead. Do not re-add the chevron from the design.
        automaticallyImplyLeading: false,
        leading: _ProfileEntryButton(
          avatarImage: resolveUserAvatar(state.user?.avatarUrl),
          onPressed:
              onOpenProfile ??
              () => Navigator.pushNamed(context, AppRoutes.mine),
        ),
        actions: <Widget>[
          _AddDeviceButton(
            onPressed: () =>
                Navigator.pushNamed(context, AppRoutes.deviceSearch),
          ),
        ],
      ),
      background: AppPageBackground.standard,
      body: RefreshIndicator(
        color: AppColors.brandPrimary,
        onRefresh: () => _reload(context, state),
        child: ResponsiveContent(
          padding: EdgeInsets.zero,
          // 读取失败和「账号下真的没有设备」要分开：都画成「暂无设备」的话，
          // 重新登录后列表拉不出来，用户看到的就是设备全部消失。
          child: items.isEmpty && state.deviceLoadOffline
              ? _DeviceListOffline(onRetry: () => _reload(context, state))
              : items.isEmpty && state.deviceLoadError != null
              ? _DeviceListError(
                  message: state.deviceLoadError!,
                  diagnostics: state.sessionDiagnostics,
                  onRetry: () => _reload(context, state),
                )
              : items.isEmpty
              ? _EmptyDeviceList(diagnostics: state.sessionDiagnostics)
              : ListView.separated(
                  key: const Key('device-list-view'),
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.pageMargin,
                    35,
                    AppSpacing.pageMargin,
                    24,
                  ),
                  // 割草机那条是**写死的静态数据**，排在真实设备后面，只做一件事：
                  // 点进去看割草机那套静态页（2026-09-18 产品要求）。它不经过
                  // `state.devices`，也就碰不到花盆设备的任何一条逻辑——上面
                  // `items` 的取值、离线门禁、下拉重拉全都原样。门禁 [MowerDemo.enabled]。
                  //
                  // ⚠️ 只在**列表本身画得出来**时才追加：`items` 为空时这一页画的是
                  // 「暂无设备」整屏缺省页，在它下面挂一台设备既说不通也不好看；
                  // 那种情况下从「添加设备 → 搜索设备」那条静态行照样进得去。
                  itemCount: items.length + (MowerDemo.enabled ? 1 : 0),
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    if (index == items.length) {
                      return _MowerDemoListCard(
                        onTap: () => Navigator.pushNamed(
                          context,
                          AppRoutes.mowerHome,
                        ),
                      );
                    }
                    final device = items[index];
                    return _DeviceListCard(
                      key: Key('device-list-item-${device.id}'),
                      device: device,
                      onTap: () => _openDevice(context, state, device),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

class _ProfileEntryButton extends StatelessWidget {
  const _ProfileEntryButton({required this.onPressed, this.avatarImage});

  final VoidCallback onPressed;
  final ImageProvider<Object>? avatarImage;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        button: true,
        label: '个人中心',
        child: AppAvatar(
          key: const Key('device-list-profile-button'),
          size: 32,
          imageProvider: avatarImage,
          fallback: Image.asset(
            AppAssets.profileAvatarIcon,
            width: 32,
            height: 32,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            excludeFromSemantics: true,
          ),
          backgroundColor: AppColors.brandSurface,
          onTap: onPressed,
        ),
      ),
    );
  }
}

class _AddDeviceButton extends StatelessWidget {
  const _AddDeviceButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: IconButton(
        key: const Key('device-list-add-button'),
        tooltip: '添加设备',
        onPressed: onPressed,
        style: IconButton.styleFrom(
          minimumSize: const Size.square(40),
          padding: EdgeInsets.zero,
        ),
        icon: Image.asset(
          AppAssets.addIcon,
          width: 30,
          height: 30,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        ),
      ),
    );
  }
}

class _DeviceListCard extends StatelessWidget {
  const _DeviceListCard({required this.device, required this.onTap, super.key});

  final SmartPlanterDevice device;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: AppRadius.card,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 92,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 7, 17, 7),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 52,
                  child: Center(child: _DeviceListIcon(url: device.iconUrl)),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        device.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _OnlinePill(online: device.online),
                    ],
                  ),
                ),
                const AppTrailingChevron(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 设备列表那一列的图：**直接用涂鸦平台上配的产品图**（`DeviceBean.getIconUrl`）。
///
/// 2026-09-12 产品口径：「设备列表页面的列表的图片就直接用涂鸦官网配置的图片，
/// 这里的数据都是来自涂鸦，和后端接口没有交集。」所以这里既不画写死的静态图
/// （那是最早的做法，和设备实际种的东西无关），也不去读 APP 后端的植物图
/// （`DevicePlantArtwork` 那一套只服务详情、设置、状态卡那几页）。
///
/// 涂鸦没配图就留空位——位置照占，免得右边的文字跳动。
/// 设备列表里那条固定的割草机（`docs/UI/v2/割草机/设备列表页面.png` 的第四张卡）。
///
/// 和 [_DeviceListCard] 同一套外壳、同一套尺寸，差别只有三处：图标是本地整机俯视图、
/// 名字和在线态写死、点它进割草机静态页而不是花盆详情页。**没有复用 [_DeviceListCard]**
/// 是因为那个吃的是 `SmartPlanterDevice`——为了一条静态数据造一台假的花盆设备，
/// 等于把假数据塞进真模型里，之后每加一个字段都要跟着编一份。
class _MowerDemoListCard extends StatelessWidget {
  const _MowerDemoListCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: AppRadius.card,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const Key('device-list-mower-demo'),
        onTap: onTap,
        child: SizedBox(
          height: 92,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 7, 17, 7),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 52,
                  child: Center(
                    child: Image.asset(
                      MowerAssets.deviceThumb,
                      width: 48,
                      height: 62,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                      semanticLabel: '设备图片',
                    ),
                  ),
                ),
                const SizedBox(width: 15),
                const Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        MowerDemoDevice.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(height: 8),
                      _OnlinePill(online: true),
                    ],
                  ),
                ),
                const AppTrailingChevron(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DeviceListIcon extends StatelessWidget {
  const _DeviceListIcon({required this.url});

  static const double _width = 48;
  static const double _height = 62;

  final String url;

  @override
  Widget build(BuildContext context) {
    final source = url.trim();
    if (source.isEmpty) return _blank();
    return Image.network(
      source,
      width: _width,
      height: _height,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      semanticLabel: '设备图片',
      errorBuilder: (_, _, _) => _blank(),
    );
  }

  Widget _blank() => const SizedBox(width: _width, height: _height);
}

class _OnlinePill extends StatelessWidget {
  const _OnlinePill({required this.online});

  final bool online;

  @override
  Widget build(BuildContext context) {
    final foreground = online
        ? AppColors.brandPrimary
        : AppColors.textSecondary;
    final background = online
        ? AppColors.brandSurface
        : AppColors.divider.withValues(alpha: .72);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadius.full,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            DecoratedBox(
              decoration: BoxDecoration(
                color: foreground,
                shape: BoxShape.circle,
              ),
              child: const SizedBox.square(dimension: 7),
            ),
            const SizedBox(width: 7),
            Text(
              online ? '在线' : '离线',
              style: TextStyle(color: foreground, fontSize: 14, height: 1),
            ),
          ],
        ),
      ),
    );
  }
}

/// 列表拉取失败时的占位：保持可下拉（`RefreshIndicator` 需要一个可滚动的孩子），
/// 并给一个显式的「重试」。
class _DeviceListError extends StatelessWidget {
  const _DeviceListError({
    required this.message,
    required this.diagnostics,
    required this.onRetry,
  });

  final String message;
  final String diagnostics;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('device-list-error'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pageMargin,
        120,
        AppSpacing.pageMargin,
        24,
      ),
      children: <Widget>[
        AppErrorView(
          title: '设备列表没读出来',
          message: message,
          onRetry: onRetry,
        ),
        const SizedBox(height: 20),
        _SessionDiagnosticsLine(text: diagnostics),
      ],
    );
  }
}

/// 手机没网、设备列表没读出来时的缺省页（2026-09-15 产品）。
///
/// 文案固定「当前网络不可用，请检查网络后重试」+「重试」。和全局「网络异常」弹窗并存：
/// 弹窗点「取消」之后，用户落在这一页上仍然知道发生了什么、还能再试。版式照
/// [_EmptyDeviceList]：保持可下拉，下拉和「重试」走同一个刷新。
class _DeviceListOffline extends StatelessWidget {
  const _DeviceListOffline({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('device-list-offline'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pageMargin,
        180,
        AppSpacing.pageMargin,
        24,
      ),
      children: <Widget>[
        const Icon(
          Icons.wifi_off_rounded,
          size: 54,
          color: AppColors.brandPrimary,
        ),
        const SizedBox(height: 16),
        const Text(
          '当前网络不可用，请检查网络后重试',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 24),
        Center(
          child: SizedBox(
            width: 160,
            child: AppPrimaryButton(
              key: const Key('device-list-offline-retry'),
              label: '重试',
              onPressed: onRetry,
            ),
          ),
        ),
      ],
    );
  }
}

/// 现场信息：涂鸦账号、这次查的家庭、读到几台。
///
/// 设备清单是按家庭查的，「一台都没有」最常见的原因是查的家庭和配网时用的不是
/// 同一个——这两项不摆在页面上就只能靠联调页翻。可长按复制，方便直接发出来。
class _SessionDiagnosticsLine extends StatelessWidget {
  const _SessionDiagnosticsLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return SelectableText(
      text,
      key: const Key('device-list-diagnostics'),
      textAlign: TextAlign.center,
      style: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
    );
  }
}

class _EmptyDeviceList extends StatelessWidget {
  const _EmptyDeviceList({required this.diagnostics});

  final String diagnostics;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pageMargin,
        180,
        AppSpacing.pageMargin,
        24,
      ),
      children: <Widget>[
        Image.asset(
          AppAssets.devicePlanterIcon,
          key: const Key('empty-device-list-illustration'),
          width: 54,
          height: 54,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          excludeFromSemantics: true,
        ),
        const SizedBox(height: 16),
        const Text(
          '暂无设备',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 20),
        _SessionDiagnosticsLine(text: diagnostics),
      ],
    );
  }
}
