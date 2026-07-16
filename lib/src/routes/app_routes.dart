import 'package:flutter/material.dart';

import '../features/auth/presentation/auth_page.dart';
import '../features/auth/presentation/password_page.dart';
import '../features/auth/presentation/register_page.dart';
import '../features/devices/presentation/animations_page.dart';
import '../features/devices/presentation/device_dashboard_page.dart';
import '../features/devices/presentation/device_settings_page.dart';
import '../features/devices/presentation/light_status_page.dart';
import '../features/devices/presentation/pairing_page.dart';
import '../features/devices/presentation/plant_picker_page.dart';
import '../features/devices/presentation/reports_page.dart';
import '../features/profile/presentation/about_page.dart';
import '../features/profile/presentation/app_settings_page.dart';
import '../features/profile/presentation/help_page.dart';
import '../features/profile/presentation/legal_page.dart';
import '../features/profile/presentation/mine_page.dart';
import '../features/profile/presentation/profile_page.dart';
import '../features/shell/presentation/shell_page.dart';

abstract final class AppRoutes {
  static const root = '/';
  static const auth = '/auth';
  static const register = '/register';
  static const password = '/password';
  static const shell = '/shell';
  static const pairing = '/devices/pairing';
  static const device = '/devices/detail';
  static const reports = '/devices/reports';
  static const lightStatus = '/devices/light-status';
  static const plantPicker = '/devices/plants';
  static const deviceSettings = '/devices/settings';
  static const animations = '/devices/animations';
  static const profile = '/profile';
  static const mine = '/mine';
  static const settings = '/settings';
  static const help = '/help';
  static const privacy = '/legal/privacy';
  static const agreement = '/legal/agreement';
  static const about = '/about';

  static Route<dynamic> onGenerateRoute(
    RouteSettings settings, {
    required bool authenticated,
  }) {
    final public = <String>{auth, register, password, privacy, agreement};
    final requested = settings.name ?? root;
    final name =
        !authenticated && requested != root && !public.contains(requested)
        ? auth
        : requested;
    final page = switch (name) {
      root => authenticated ? const AppShell() : const AuthPage(),
      auth => const AuthPage(),
      register => const RegisterPage(),
      password => PasswordPage(
        arguments:
            settings.arguments as PasswordArguments? ??
            const PasswordArguments(),
      ),
      shell => const AppShell(),
      pairing => const PairingPage(),
      device => DeviceDashboardPage(deviceId: settings.arguments! as String),
      reports => ReportsPage(arguments: settings.arguments! as ReportArguments),
      lightStatus => LightStatusPage(deviceId: settings.arguments! as String),
      plantPicker => PlantPickerPage(deviceId: settings.arguments! as String),
      deviceSettings => DeviceSettingsPage(
        deviceId: settings.arguments! as String,
      ),
      animations => AnimationsPage(deviceId: settings.arguments! as String),
      mine => const MinePage(),
      profile => const ProfilePage(),
      AppRoutes.settings => const AppSettingsPage(),
      help => const HelpPage(),
      privacy => const LegalPage(privacy: true),
      agreement => const LegalPage(privacy: false),
      about => const AboutPage(),
      _ => const AuthPage(),
    };
    return MaterialPageRoute<dynamic>(
      builder: (_) => page,
      settings: RouteSettings(name: name, arguments: settings.arguments),
    );
  }
}
