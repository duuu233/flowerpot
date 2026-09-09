import 'package:flutter/material.dart';

import '../core/config/debug_tools_config.dart';
import '../features/auth/presentation/auth_page.dart';
import '../features/auth/presentation/password_page.dart';
import '../features/auth/presentation/register_page.dart';
import '../features/devices/presentation/animations_page.dart';
import '../features/devices/presentation/battery_status_page.dart';
import '../features/devices/presentation/behavior_settings_page.dart';
import '../features/devices/models/water_status_page_model.dart';
import '../features/devices/presentation/device_info_page.dart';
import '../features/devices/presentation/device_list_page.dart';
import '../features/devices/presentation/device_other_settings_page.dart';
import '../features/devices/presentation/device_search_page.dart';
import '../features/devices/presentation/device_selection_page.dart';
import '../features/devices/presentation/device_settings_page.dart';
import '../features/devices/presentation/display_settings_page.dart';
import '../features/devices/presentation/hearing_settings_page.dart';
import '../features/devices/presentation/humidity_status_page.dart';
import '../features/devices/presentation/led_settings_page.dart';
import '../features/devices/presentation/light_status_page.dart';
import '../features/devices/presentation/memorial_edit_page.dart';
import '../features/devices/presentation/memorial_page.dart';
import '../features/devices/presentation/pairing_page.dart';
import '../features/devices/presentation/pairing_failure_page.dart';
import '../features/devices/presentation/pairing_success_page.dart';
import '../features/devices/presentation/plant_detail_page.dart';
import '../features/devices/presentation/plant_detection_settings_page.dart';
import '../features/devices/presentation/plant_picker_page.dart';
import '../features/devices/presentation/reports_page.dart';
import '../features/devices/presentation/temperature_status_page.dart';
import '../features/devices/presentation/touch_settings_page.dart';
import '../features/devices/presentation/vibration_settings_page.dart';
import '../features/devices/presentation/water_status_page.dart';
import '../features/devtools/presentation/tuya_debug_page.dart';
import '../features/profile/presentation/about_page.dart';
import '../features/profile/presentation/account_security_page.dart';
import '../features/profile/presentation/help_page.dart';
import '../features/profile/presentation/legal_page.dart';
import '../features/profile/presentation/login_password_page.dart';
import '../features/profile/presentation/mine_page.dart';
import '../features/profile/presentation/modify_password_page.dart';
import '../features/profile/presentation/profile_page.dart';
import '../features/home/presentation/home_page.dart';
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
  static const deviceList = '/devices/list';
  static const deviceHome = '/devices/home';
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
  static const ledSettings = '/devices/led';
  static const plantDetectionSettings = '/devices/plant-detection';
  static const memorial = '/devices/memorial';
  static const memorialEdit = '/devices/memorial-edit';
  static const behaviorSettings = '/devices/behavior';
  static const animations = '/devices/animations';
  static const profile = '/profile';
  static const mine = '/mine';
  static const settings = '/settings';
  static const help = '/help';
  static const privacy = '/legal/privacy';
  static const agreement = '/legal/agreement';
  static const about = '/about';

  /// Tuya SDK console. Reachable before login and only while
  /// [DebugToolsConfig.enabled].
  static const tuyaDebug = '/devtools/tuya';

  static Route<dynamic> onGenerateRoute(
    RouteSettings settings, {
    required bool authenticated,
  }) {
    final public = <String>{
      auth,
      register,
      password,
      privacy,
      agreement,
      if (DebugToolsConfig.enabled) tuyaDebug,
    };
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
      pairing => PairingPage(
        arguments: settings.arguments as PairingArguments?,
      ),
      pairingFailure => _pairingFailurePage(settings.arguments),
      pairingSuccess => PairingSuccessPage(
        deviceId: settings.arguments! as String,
      ),
      deviceSearch => DeviceSearchPage(
        request: settings.arguments as PairingRequest?,
      ),
      deviceSelection => DeviceSelectionPage(
        request: settings.arguments as PairingRequest?,
      ),
      deviceList => const DeviceListPage(),
      deviceHome => _deviceHomePage(settings.arguments),
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
      plantPicker => _plantPickerPage(settings.arguments),
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
      ledSettings => LedSettingsPage(deviceId: settings.arguments! as String),
      plantDetectionSettings => PlantDetectionSettingsPage(
        deviceId: settings.arguments! as String,
      ),
      memorial => MemorialPage(deviceId: settings.arguments! as String),
      memorialEdit => MemorialEditPage(
        arguments: settings.arguments! as MemorialEditArguments,
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
      tuyaDebug when DebugToolsConfig.enabled => const TuyaDebugPage(),
      _ => const AuthPage(),
    };
    return MaterialPageRoute<dynamic>(
      builder: (_) => page,
      settings: RouteSettings(name: name, arguments: settings.arguments),
    );
  }

  /// Accepts the richer failure arguments, and still the bare request that the
  /// retry path and older call sites pass.
  static Widget _pairingFailurePage(Object? arguments) {
    if (arguments is PairingFailureArguments) {
      return PairingFailurePage(
        request: arguments.request,
        code: arguments.code,
        message: arguments.message,
      );
    }
    return PairingFailurePage(request: arguments as PairingRequest?);
  }

  static Widget _deviceHomePage(Object? arguments) {
    if (arguments is HomeDeviceArguments) {
      return HomePage(
        deviceId: arguments.deviceId,
        scene: arguments.scene,
        showBackButton: true,
      );
    }
    return HomePage(deviceId: arguments as String?, showBackButton: true);
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

  static Widget _plantPickerPage(Object? arguments) {
    if (arguments is PlantPickerArguments) {
      return PlantPickerPage(
        deviceId: arguments.deviceId,
        mode: arguments.mode,
      );
    }
    return PlantPickerPage(deviceId: arguments! as String);
  }
}
