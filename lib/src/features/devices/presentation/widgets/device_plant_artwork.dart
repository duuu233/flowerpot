import 'package:flutter/material.dart';

import '../../../../app/flowerpot_app.dart';

/// 设备当前这一株植物的图，**来自后端**。
///
/// ⚠️ 2026-09-12 建：设置页与五张状态概览卡此前一律画写死的
/// `const AppDevicePlaceholder(hasPlant: true)`——既不读后端图片，也不管盆里到底有没有
/// 植物（`hasPlant` 是硬编码的 true）。产品口径是「所有都要真实的数据」，所以统一换成
/// 这个组件。
///
/// 取数与首页 `HomePlantOverview._PlantHeroImage` 同一套口径：
/// 后端 `plantImg` → `PlantProfile.imageUrl`；没配、取不回来、或盆里没植物（DP 116 = -1）
/// 时才回落到本地静态图——那是**占位**，不是冒充数据。
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
    // `device.plant` 不可空，但 `imageUrl` 可空——后台没配图片时就是 null。
    final url = missing ? null : device?.plant.imageUrl?.trim();
    // ⚠️ **不做静态兜底**（2026-09-12 产品口径：「没有就为空，不要用静态数据兜底」）。
    // 后端没配图 / 盆里没植物 / 图片加载失败，一律留空位——占位图会让人以为"有数据"，
    // 而那张图跟这台设备实际种的东西没有任何关系。位置照留，免得旁边的文字跳动。
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
}
