import 'package:flutter/material.dart';

import '../../../../app/flowerpot_app.dart';
import '../../../../design_system/design_system.dart';

/// 设备当前这一株植物的图，**来自后端**。
///
/// ⚠️ 2026-09-12 建：设置页与五张状态概览卡此前一律画写死的
/// `const AppDevicePlaceholder(hasPlant: true)`——既不读后端图片，也不管盆里到底有没有
/// 植物（`hasPlant` 是硬编码的 true）。产品口径是「所有都要真实的数据」，所以统一换成
/// 这个组件。
///
/// 三种情形，取数口径和首页 `HomePlantOverview._PlantHeroImage` 完全一致：
///
/// | 情形 | 画什么 |
/// | --- | --- |
/// | 盆里没植物（DP 116 = -1） | `smart_planter_device.png`，一个**空花盆** |
/// | 有植物、后端配了图 | 后端那张（`plantImg` → `PlantProfile.imageUrl`） |
/// | 有植物、后端没配图 / 加载失败 | **留空位**，不画 |
///
/// 第一行是产品 2026-09-12 明确要的：**没有植物时就用这张图表示「没有植物」**。它画的
/// 是事实（这台设备此刻确实是个空盆），所以不算「静态假数据」——和第三行那种拿一张
/// 随便的带植物产品图冒充「盆里种的东西」是两回事。
class DevicePlantArtwork extends StatelessWidget {
  const DevicePlantArtwork({required this.deviceId, this.width = 70, super.key});

  /// 要画哪一台设备的植物。为空时用当前选中的设备。
  final String? deviceId;

  final double width;

  @override
  Widget build(BuildContext context) {
    final state = FlowerpotScope.of(context);
    final id = deviceId ?? state.selectedDevice?.id;
    final missing = state.plantMissing(id);
    // `plantMissing` 收 String?，`deviceById` 只收 String，所以这里自己判一次空。
    final device = id == null ? null : state.deviceById(id);
    // 盆里确实没有植物：画空花盆。见类文档——这是事实的占位，不是冒充数据。
    if (missing) return _emptyPlanter();
    // `device.plant` 不可空，但 `imageUrl` 可空——后台没配图片时就是 null。
    final url = device?.plant.imageUrl?.trim();
    // 有植物但拿不到图：**留空位**（2026-09-12 产品口径「没有就为空，不要用静态数据
    // 兜底」）。这里绝不能回落到带植物的产品图——那张图跟这台设备实际种的东西没有
    // 任何关系，画上去用户会当成真的。位置照留，免得旁边的文字跳动。
    if (url == null || url.isEmpty) {
      return SizedBox(width: width, height: width * 1.29);
    }
    return SizedBox(
      width: width,
      height: width * 1.29,
      child: Image.network(
        url,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        semanticLabel: '设备当前的植物',
        errorBuilder: (_, _, _) => SizedBox(width: width, height: width * 1.29),
      ),
    );
  }

  /// 盆里没有植物时的占位：空花盆。
  Widget _emptyPlanter() => Image.asset(
    AppAssets.smartPlanterDevice,
    width: width,
    height: width * 1.29,
    fit: BoxFit.contain,
    filterQuality: FilterQuality.high,
    semanticLabel: '未种植物的花盆',
  );
}
