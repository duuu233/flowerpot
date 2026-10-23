class AboutPageModel {
  const AboutPageModel({
    required this.appName,
    required this.tagline,
    required this.version,
    required this.updateStatus,
    required this.releaseNotes,
  });

  factory AboutPageModel.current() {
    return const AboutPageModel(
      appName: '东方金穗',
      tagline: '您的智能设备贴心伴侣',
      version: '1.0.0',
      updateStatus: '已是最新版本',
      releaseNotes: <String>[
        '新增智能设备连接与管理能力',
        '支持水位、温度、湿度、光照和电量状态查看',
        '优化植物养护提醒与传感器校准体验',
      ],
    );
  }

  final String appName;
  final String tagline;

  /// 本机安装的版本号，用来发给 `/Client/Basic/getLastVersion` 做比对。
  final String version;
  final String updateStatus;
  final List<String> releaseNotes;

  AboutPageModel copyWith({
    String? updateStatus,
    List<String>? releaseNotes,
  }) => AboutPageModel(
    appName: appName,
    tagline: tagline,
    version: version,
    updateStatus: updateStatus ?? this.updateStatus,
    releaseNotes: releaseNotes ?? this.releaseNotes,
  );

  String get displayVersion => 'V$version';
}
