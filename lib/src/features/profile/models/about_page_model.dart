import '../../../core/config/app_build_info.dart';

class AboutPageModel {
  const AboutPageModel({
    required this.appName,
    required this.tagline,
    required this.version,
    required this.updateStatus,
    required this.releaseNotes,
    this.hasUpdate = false,
  });

  factory AboutPageModel.current() {
    return AboutPageModel(
      appName: '东方金穗',
      tagline: '您的智能设备贴心伴侣',
      version: AppBuildInfo.version,
      updateStatus: '已是最新版本',
      releaseNotes: const <String>[
        '新增智能设备连接与管理能力',
        '支持水位、温度、湿度、光照和电量状态查看',
        '优化植物养护提醒与传感器校准体验',
      ],
    );
  }

  final String appName;
  final String tagline;

  /// 本机安装的版本号（从系统读，见 [AppBuildInfo]），用来发给
  /// `/Client/Basic/getLastVersion` 做比对。读不到时为空。
  final String version;
  final String updateStatus;
  final List<String> releaseNotes;

  /// 后端说有新版本：「检查更新」那一行点红点。
  final bool hasUpdate;

  AboutPageModel copyWith({
    String? updateStatus,
    List<String>? releaseNotes,
    bool? hasUpdate,
  }) => AboutPageModel(
    appName: appName,
    tagline: tagline,
    version: version,
    updateStatus: updateStatus ?? this.updateStatus,
    releaseNotes: releaseNotes ?? this.releaseNotes,
    hasUpdate: hasUpdate ?? this.hasUpdate,
  );

  String get displayVersion => version.isEmpty ? '--' : 'V$version';
}
