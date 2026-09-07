import '../../../tuya/tuya_models.dart';
import '../../../tuya/tuya_status_copy.dart';

enum HomeMetricKind { water, light, temperature, humidity }

enum HomeActionKind { animation, battery, settings }

enum HomeDashboardScene {
  withCompanionSummary,
  withoutCompanionSummary,
  withoutPlant,
}

class HomeMetricData {
  const HomeMetricData({
    required this.kind,
    required this.label,
    required this.value,
  });

  final HomeMetricKind kind;
  final String label;
  final String value;
}

class HomeActionData {
  const HomeActionData({required this.kind, required this.label});

  final HomeActionKind kind;
  final String label;
}

class HomeDashboardModel {
  const HomeDashboardModel({
    required this.userLabel,
    required this.deviceId,
    required this.companionDays,
    required this.battery,
    required this.metrics,
    required this.careMessage,
    required this.actions,
    required this.helpTopics,
    this.emptyTitle = '还未添加植物',
    this.emptyMessage = '为设备添加植物后，即可生成专属养护建议与\n环境数据分析。',
    this.addPlantLabel = '添加植物',
    this.scene = HomeDashboardScene.withCompanionSummary,
  });

  factory HomeDashboardModel.fromDevice({
    required SmartPlanterDevice? device,
    required String userLabel,
    HomeDashboardScene scene = HomeDashboardScene.withCompanionSummary,
  }) {
    final sensors = device?.sensors;
    final waterLevel = sensors?.waterLevel ?? 78;
    final illuminance = sensors?.illuminance ?? 800;
    final humidity = sensors?.relativeHumidity ?? 60;
    // 三张状态卡片的取值和状态页顶部是同一个来源：设备上报的 107/108/115，没上报
    // 时用同一套阈值兜底。首页自己算一套的话，同一台设备会在首页写「偏湿」、在
    // 需水状态页写「喝水中」。
    final report = device?.status ?? const DeviceStatusReport();
    final waterNeeds =
        report.waterNeeds ?? TuyaStatusCopy.waterNeedsFor(waterLevel);
    final lighting = report.lighting ?? TuyaStatusCopy.lightingFor(illuminance);
    final airHumidity = report.humidity ?? TuyaStatusCopy.humidityFor(humidity);

    return HomeDashboardModel(
      userLabel: userLabel,
      deviceId: device?.id,
      // The same device must not read "已陪伴1天" here and "已陪伴127天" one
      // tap later, so both scenes use the bound date.
      companionDays: device?.companionDays ?? 52,
      battery: device?.battery ?? 80,
      metrics: <HomeMetricData>[
        HomeMetricData(
          kind: HomeMetricKind.water,
          label: '需水状态',
          value: TuyaStatusCopy.waterNeeds[waterNeeds]!.label,
        ),
        HomeMetricData(
          kind: HomeMetricKind.light,
          label: '光照状态',
          value: TuyaStatusCopy.lighting[lighting]!.label,
        ),
        HomeMetricData(
          kind: HomeMetricKind.temperature,
          label: '空气温度',
          // The reading is already in the unit `temp_unit_convert` selects, so
          // only the label follows the device.
          value: (device?.settings ?? const DeviceControlSettings())
              .formatTemperature(sensors?.airTemperature ?? 25.5),
        ),
        HomeMetricData(
          kind: HomeMetricKind.humidity,
          label: '相对湿度',
          value: TuyaStatusCopy.airHumidity[airHumidity]!.label,
        ),
      ],
      careMessage: _careMessage(
        waterNeeds: waterNeeds,
        lighting: lighting,
        humidity: airHumidity,
      ),
      actions: const <HomeActionData>[
        HomeActionData(kind: HomeActionKind.animation, label: '定制动画'),
        HomeActionData(kind: HomeActionKind.battery, label: '电池状态'),
        HomeActionData(kind: HomeActionKind.settings, label: '设置'),
      ],
      helpTopics: const <String>[
        '首次使用指南',
        '如何设定YSplanter的表情',
        '如何将YSplanter重新连接到Wi-Fi?',
      ],
      scene: scene,
    );
  }

  /// Advice that follows the readings shown right above it. A constant line
  /// read as "今天状态良好" while the cards said 偏湿 and 偏弱.
  ///
  /// 现在直接读三条状态功能点，和上面几张卡片同源；`very_good` 不再算警告——按 DP
  /// 108 的定义那是「光合效率高」的好状态，不是原来那句「光照偏强」。
  static String _careMessage({
    required WaterNeedsStatus waterNeeds,
    required LightingCondition lighting,
    required ComfortLevel humidity,
  }) {
    if (waterNeeds == WaterNeedsStatus.shortage) return '水仓快见底了，记得今天加一次水';
    if (waterNeeds == WaterNeedsStatus.watery) return '水有点多，先暂停加水并保持通风';
    if (lighting == LightingCondition.shortage) {
      return '光线有点弱，可以把花盆挪到更亮堂的地方';
    }
    if (humidity == ComfortLevel.low) return '空气有点干，可以喷点水雾提高湿度';
    if (humidity == ComfortLevel.high) return '空气有点潮，多通通风避免闷根';
    return '今天状态良好，傍晚可适度通风';
  }

  final String userLabel;
  final String? deviceId;
  final int companionDays;
  final int battery;
  final List<HomeMetricData> metrics;
  final String careMessage;
  final List<HomeActionData> actions;
  final List<String> helpTopics;
  final String emptyTitle;
  final String emptyMessage;
  final String addPlantLabel;
  final HomeDashboardScene scene;

  bool get showCompanionSummary =>
      scene != HomeDashboardScene.withoutCompanionSummary;

  bool get isWithoutPlant => scene == HomeDashboardScene.withoutPlant;

  bool get isWithoutDevice => deviceId == null && !isWithoutPlant;
}
