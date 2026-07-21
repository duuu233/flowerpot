import 'package:flutter/material.dart';

import '../features/auth/presentation/auth_page.dart';
import '../features/auth/presentation/password_page.dart';
import '../features/auth/presentation/register_page.dart';
import '../features/devices/presentation/animations_page.dart';
import '../features/devices/presentation/battery_status_page.dart';
import '../features/devices/presentation/behavior_settings_page.dart';
import '../features/devices/models/water_status_page_model.dart';
import '../features/devices/presentation/device_dashboard_page.dart';
import '../features/devices/presentation/device_info_page.dart';
import '../features/devices/presentation/device_list_page.dart';
import '../features/devices/presentation/device_other_settings_page.dart';
import '../features/devices/presentation/device_search_page.dart';
import '../features/devices/presentation/device_selection_page.dart';
import '../features/devices/presentation/device_settings_page.dart';
import '../features/devices/presentation/display_settings_page.dart';
import '../features/devices/presentation/hearing_settings_page.dart';
import '../features/devices/presentation/humidity_status_page.dart';
import '../features/devices/presentation/light_status_page.dart';
import '../features/devices/presentation/pairing_page.dart';
import '../features/devices/presentation/pairing_failure_page.dart';
import '../features/devices/presentation/pairing_success_page.dart';
import '../features/devices/presentation/plant_detail_page.dart';
import '../features/devices/presentation/plant_picker_page.dart';
import '../features/devices/presentation/reports_page.dart';
import '../features/devices/presentation/temperature_status_page.dart';
import '../features/devices/presentation/touch_settings_page.dart';
import '../features/devices/presentation/vibration_settings_page.dart';
import '../features/devices/presentation/water_status_page.dart';
import '../features/profile/presentation/about_page.dart';
import '../features/profile/presentation/account_security_page.dart';
import '../features/profile/presentation/help_page.dart';
import '../features/profile/presentation/legal_page.dart';
import '../features/profile/presentation/login_password_page.dart';
import '../features/profile/presentation/mine_page.dart';
import '../features/profile/presentation/modify_password_page.dart';
import '../features/profile/presentation/profile_page.dart';
import '../features/shell/presentation/shell_page.dart';
import '../tuya/tuya_models.dart';

abstract final class AppRoutes {
  static const root = '/';
  static const auth = '/auth';
  static const register = '/register';
  static const password = '/password';
  static const loginPassword = '/login-password';
  static const modifyPassword = '/modify-password';
  static const shell = '/shell';
  static const pairing = '/devices/pairing';
  static const pairingFailure = '/devices/pairing-failure';
  static const pairingSuccess = '/devices/pairing-success';
  static const deviceSearch = '/devices/search';
  static const deviceSelection = '/devices/select';
  static const device = '/devices/detail';
  static const deviceList = '/devices/list';
  static const deviceInfo = '/devices/info';
  static const deviceOtherSettings = '/devices/other-settings';
  static const reports = '/devices/reports';
  static const lightStatus = '/devices/light-status';
  static const waterStatus = '/devices/water-status';
  static const temperatureStatus = '/devices/temperature-status';
  static const humidityStatus = '/devices/humidity-status';
  static const batteryStatus = '/devices/battery-status';
  static const plantPicker = '/devices/plants';
  static const plantDetail = '/devices/plant-detail';
  static const deviceSettings = '/devices/settings';
  static const displaySettings = '/devices/display';
  static const hearingSettings = '/devices/hearing';
  static const touchSettings = '/devices/touch';
  static const vibrationSettings = '/devices/vibration';
  static const behaviorSettings = '/devices/behavior';
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
      loginPassword => LoginPasswordPage(
        arguments:
            settings.arguments as LoginPasswordArguments? ??
            const LoginPasswordArguments(),
      ),
      modifyPassword => ModifyPasswordPage(
        arguments:
            settings.arguments as ModifyPasswordArguments? ??
            const ModifyPasswordArguments(),
      ),
      shell => const AppShell(),
      pairing => const PairingPage(),
      pairingFailure => PairingFailurePage(
        request: settings.arguments as PairingRequest?,
      ),
      pairingSuccess => PairingSuccessPage(
        deviceId: settings.arguments! as String,
      ),
      deviceSearch => DeviceSearchPage(
        request: settings.arguments as PairingRequest?,
      ),
      deviceSelection => DeviceSelectionPage(
        request: settings.arguments as PairingRequest?,
      ),
      device => DeviceDashboardPage(deviceId: settings.arguments! as String),
      deviceList => const DeviceListPage(),
      deviceInfo => DeviceInfoPage(deviceId: settings.arguments! as String),
      deviceOtherSettings => DeviceOtherSettingsPage(
        deviceId: settings.arguments! as String,
      ),
      reports => ReportsPage(arguments: settings.arguments! as ReportArguments),
      lightStatus => LightStatusPage(deviceId: settings.arguments! as String),
      waterStatus => _waterStatusPage(settings.arguments),
      temperatureStatus => TemperatureStatusPage(
        deviceId: settings.arguments! as String,
      ),
      humidityStatus => HumidityStatusPage(
        deviceId: settings.arguments! as String,
      ),
      batteryStatus => BatteryStatusPage(
        deviceId: settings.arguments! as String,
      ),
      plantPicker => PlantPickerPage(deviceId: settings.arguments! as String),
      plantDetail => PlantDetailPage(
        arguments: settings.arguments! as PlantDetailArguments,
      ),
      deviceSettings => DeviceSettingsPage(
        deviceId: settings.arguments! as String,
      ),
      displaySettings => DisplaySettingsPage(
        deviceId: settings.arguments! as String,
      ),
      hearingSettings => HearingSettingsPage(
        deviceId: settings.arguments! as String,
      ),
      touchSettings => TouchSettingsPage(
        deviceId: settings.arguments! as String,
      ),
      vibrationSettings => VibrationSettingsPage(
        deviceId: settings.arguments! as String,
      ),
      behaviorSettings => BehaviorSettingsPage(
        deviceId: settings.arguments! as String,
      ),
      animations => AnimationsPage(deviceId: settings.arguments! as String),
      mine => const MinePage(),
      profile => const ProfilePage(),
      AppRoutes.settings => const AccountSecurityPage(),
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

  static Widget _waterStatusPage(Object? arguments) {
    if (arguments is WaterStatusArguments) {
      return WaterStatusPage(
        deviceId: arguments.deviceId,
        initialMetric: arguments.initialMetric,
      );
    }
    return WaterStatusPage(deviceId: arguments! as String);
  }
}
