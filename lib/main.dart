import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/app.dart';
import 'src/core/config/app_build_info.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Color(0xFFF4F7F1),
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  // App 升级比对要用本机版本号，进首页就会查，先读好。
  await AppBuildInfo.load();
  runApp(const FlowerpotApp());
}
