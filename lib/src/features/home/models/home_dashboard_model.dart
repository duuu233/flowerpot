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
    this.deviceName,
    required this.companionDays,
    required this.battery,
    required this.metrics,
    required this.careTitle,
    required this.careMessages,
    required this.actions,
    required this.helpTopics,
    this.plantImageUrl,
    this.plantMissing = false,
    this.emptyTitle = '还未添加植物',
    this.emptyMessage = '为设备添加植物后，即可生成专属养护建议与\n环境数据分析。',
    this.addPlantLabel = '添加植物',
    this.scene = HomeDashboardScene.withCompanionSummary,
  });

  factory HomeDashboardModel.fromDevice({
    required SmartPlanterDevice? device,
    required String userLabel,
    HomeDashboardScene scene = HomeDashboardScene.withCompanionSummary,
    String language = 'zh',
  }) {
    final english = language.trim().toLowerCase().startsWith('en');
    final settings = device?.settings ?? const DeviceControlSettings();
    final sensors = device?.sensors;
    final waterLevel = sensors?.waterLevel ?? 0;
    final illuminance = sensors?.illuminance ?? 0;
    final humidity = sensors?.relativeHumidity ?? 0;
    // 三张状态卡片的取值和状态页顶部是同一个来源：设备上报的 107/108/115，没上报
    // 时用同一套阈值兜底。首页自己算一套的话，同一台设备会在首页写「偏湿」、在
    // 需水状态页写「喝水中」。
    final report = device?.status ?? const DeviceStatusReport();
    final waterNeeds =
        report.waterNeeds ?? TuyaStatusCopy.waterNeedsFor(waterLevel);
    final lighting = report.lighting ?? TuyaStatusCopy.lightingFor(illuminance);
    final airHumidity = report.humidity ?? TuyaStatusCopy.humidityFor(humidity);
    // 温度卡片显示的是读数，但养护建议要的是 113 的冷热判断，兜底阈值和温度状态
    // 页共用一份，先换算到设备当前上报的单位再比。
    final airTemperature =
        report.temperature ??
        TuyaStatusCopy.temperatureFor(
          sensors?.airTemperature ?? 0,
          low: settings.temperatureFromCelsius(
            TuyaStatusCopy.comfortableLowCelsius,
          ),
          high: settings.temperatureFromCelsius(
            TuyaStatusCopy.comfortableHighCelsius,
          ),
        );

    return HomeDashboardModel(
      userLabel: userLabel,
      deviceId: device?.id,
      deviceName: device?.name,
      // The same device must not read "已陪伴1天" here and "已陪伴127天" one
      // tap later, so both scenes use the bound date.
      companionDays: device?.companionDays ?? 0,
      battery: device?.battery ?? 0,
      plantImageUrl: device?.plant.imageUrl,
      plantMissing:
          device != null && PlantVariety.isMissing(device.plantVariety),
      metrics: <HomeMetricData>[
        HomeMetricData(
          kind: HomeMetricKind.water,
          label: english ? 'Water' : '需水状态',
          value: device == null ? '--' : TuyaStatusCopy.waterNeedsCopy(
            waterNeeds,
            language: language,
          ).label,
        ),
        HomeMetricData(
          kind: HomeMetricKind.light,
          label: english ? 'Light' : '光照状态',
          value: device == null ? '--' : TuyaStatusCopy.lightingCopy(lighting, language: language).label,
        ),
        HomeMetricData(
          kind: HomeMetricKind.temperature,
          label: english ? 'Temperature' : '空气温度',
          // The reading is already in the unit `temp_unit_convert` selects, so
          // only the label follows the device.
          value: device == null ? '--' : settings.formatTemperature(sensors?.airTemperature ?? 0),
        ),
        HomeMetricData(
          kind: HomeMetricKind.humidity,
          label: english ? 'Humidity' : '相对湿度',
          value: device == null ? '--' : TuyaStatusCopy.airHumidityCopy(
            airHumidity,
            language: language,
          ).label,
        ),
      ],
      careTitle: english ? "Today's care" : '今日养护',
      careMessages: device == null ? const <String>[] : _careMessages(
        waterNeeds: waterNeeds,
        lighting: lighting,
        temperature: airTemperature,
        humidity: airHumidity,
        language: language,
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

  /// 养护建议：四条状态功能点（107 / 108 / 113 / 115）当前取值各自对应的一句话，
  /// 顺序和上面四张卡片一致（需水 → 光照 → 温度 → 湿度），由首页的养护卡片
  /// `HomeCareBanner` 轮播。
  ///
  /// 文案和状态详情页读同一张 [TuyaStatusCopy] 表：以前这里是自己写的一句总结，
  /// 卡片说「偏湿」而这条说「今天状态良好」的情况就是这么来的。`very_good` 不算
  /// 警告——按 DP 108 的定义那是「光合效率高」的好状态。
  static List<String> _careMessages({
    required WaterNeedsStatus waterNeeds,
    required LightingCondition lighting,
    required ComfortLevel temperature,
    required ComfortLevel humidity,
    required String language,
  }) => <String>[
    TuyaStatusCopy.waterNeedsCopy(waterNeeds, language: language).description,
    TuyaStatusCopy.lightingCopy(lighting, language: language).description,
    TuyaStatusCopy.airTemperatureCopy(
      temperature,
      language: language,
    ).description,
    TuyaStatusCopy.airHumidityCopy(humidity, language: language).description,
  ];

  final String userLabel;
  final String? deviceId;

  /// 设备名称，首页顶栏正中显示它。没有设备时为 null。
  final String? deviceName;
  final int companionDays;
  final int battery;
  final List<HomeMetricData> metrics;

  /// 养护卡片左边那几个字（「今日养护」）。
  final String careTitle;

  /// 轮播的四条养护建议，顺序与 [metrics] 一致。
  final List<String> careMessages;
  final List<HomeActionData> actions;
  final List<String> helpTopics;

  /// 设备当前绑定的那株植物在后台配置的图片（`getProductPlantList` 的 `plantImg`）。
  /// 为空时首页回落到本地静态图，不自己拼路径。
  final String? plantImageUrl;

  /// 设备明确报了「盆里没有植物」（DP 116 == -1）。
  ///
  /// 此时首页画不带植物的设备图，「今日养护」整行换成提示，植物选择也不让点——
  /// 盆里没东西时选了也会被设备的下一次上报覆盖。
  final bool plantMissing;
  final String emptyTitle;
  final String emptyMessage;
  final String addPlantLabel;
  final HomeDashboardScene scene;

  bool get showCompanionSummary =>
      scene != HomeDashboardScene.withoutCompanionSummary;

  bool get isWithoutPlant => scene == HomeDashboardScene.withoutPlant;

  bool get isWithoutDevice => deviceId == null && !isWithoutPlant;
}
