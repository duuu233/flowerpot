import 'package:package_info_plus/package_info_plus.dart';

/// 本机安装包的版本号：pubspec `version` 的 build-name，即 Android `versionName` /
/// iOS `CFBundleShortVersionString`。
///
/// `/Client/Basic/getLastVersion` 拿它和后台配置的最新版本比对。它若写死成某个旧号，
/// 用户装完新包仍会被判成「有新版本」：红点永远亮着，强制升级弹窗关不掉、把人永远挡在
/// 外面。所以从系统读，不写死。`main()` 在 `runApp` 之前读一次；读不到时为空，版本检查
/// 整个跳过——宁可不提示，也不误挡。
abstract final class AppBuildInfo {
  static String version = '';

  static Future<void> load() async {
    try {
      version = (await PackageInfo.fromPlatform()).version.trim();
    } catch (_) {
      version = '';
    }
  }
}
