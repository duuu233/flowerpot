import '../../../tuya/tuya_models.dart';

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
    final soilMoisture = sensors?.soilMoisture ?? 58;
    final illuminance = sensors?.illuminance ?? 800;
    final humidity = sensors?.relativeHumidity ?? 60;

    return HomeDashboardModel(
      userLabel: userLabel,
      deviceId: device?.id,
      companionDays: scene == HomeDashboardScene.withoutPlant
          ? 1
          : device?.companionDays ?? 52,
      battery: device?.battery ?? 80,
      metrics: <HomeMetricData>[
        HomeMetricData(
          kind: HomeMetricKind.water,
          label: '需水状态',
          value: switch (soilMoisture) {
            < 40 => '需浇水',
            > 75 => '偏湿',
            _ => '喝水中',
          },
        ),
        HomeMetricData(
          kind: HomeMetricKind.light,
          label: '光照状态',
          value: switch (illuminance) {
            < 500 => '偏弱',
            > 1200 => '偏强',
            _ => '适中',
          },
        ),
        HomeMetricData(
          kind: HomeMetricKind.temperature,
          label: '空气温度',
          value: '${(sensors?.airTemperature ?? 25.5).toStringAsFixed(1)}°C',
        ),
        HomeMetricData(
          kind: HomeMetricKind.humidity,
          label: '相对湿度',
          value: switch (humidity) {
            < 40 => '偏低',
            > 70 => '偏高',
            _ => '适宜',
          },
        ),
      ],
      careMessage: '今天状态良好，傍晚可适度通风',
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
}
