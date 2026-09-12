abstract final class AppAssets {
  // Home dashboard.
  static const String homeBackground = 'assets/images/bg01.png';

  // Account entry assets.
  static const String accountBackground = 'assets/images/auth_background.png';
  static const String appLogo = 'assets/images/app_logo.png';
  static const String ysplanterWordmark =
      'assets/images/ysplanter_wordmark.png';
  static const String phoneIcon = 'assets/images/phone_icon.png';
  static const String verificationCodeIcon =
      'assets/images/verification_code_icon.png';
  static const String passwordIcon = 'assets/images/password_icon.png';
  static const String confirmPasswordIcon =
      'assets/images/confirm_password_icon.png';
  static const String wechatLoginIcon = 'assets/images/wechat_login_icon.png';
  static const String alipayLoginIcon = 'assets/images/alipay_login_icon.png';

  // Pairing and device discovery.
  static const String pairingDeviceSearchIllustration =
      'assets/images/pairing_device_search_illustration.png';
  static const String pairingDeviceSelectionIllustration =
      'assets/images/pairing_device_selection_illustration.png';
  static const String pairingWifiSetupIllustration =
      'assets/images/pairing_wifi_setup_illustration.png';
  static const String pairingFailureIllustration =
      'assets/images/pairing_failure_illustration.png';
  static const String pairingSuccessIllustration =
      'assets/images/pairing_success_illustration.png';
  static const String devicePlanterIcon =
      'assets/images/device_planter_icon.png';
  static const String wifi24GhzIcon = 'assets/images/wifi_2_4ghz_icon.png';
  static const String wifiNetworkIcon = 'assets/images/wifi_network_icon.png';
  static const String wifiPasswordIcon = 'assets/images/wifi_password_icon.png';
  static const String wifiSignalIcon = 'assets/images/wifi_signal_icon.png';
  static const String checkmarkIcon = 'assets/images/checkmark_icon.png';
  static const String addIcon = 'assets/images/add_icon.png';
  static const String infoOutlineIcon = 'assets/images/info_outline_icon.png';

  // Device and plant imagery.
  //
  // ⚠️ 这里**没有**按植物 id 查的本地图片表了（2026-09-12 删）。植物图一律来自后端
  // 的 `plantImg`，取不到就留空——留一张本地图当兜底，等于给每一株认不出来的植物都
  // 画上同一张图，看着像有数据，其实一张都没取到。
  static const String smartPlanterWithPlant =
      'assets/images/smart_planter_with_plant.png';
  static const String smartPlanterDevice =
      'assets/images/smart_planter_device.png';
  static const String searchIcon = 'assets/images/search_icon.png';
  static const String plantCareTipIcon =
      'assets/images/plant_care_tip_icon.png';
  static const String metricTemperatureIcon =
      'assets/images/metric_temperature_icon.png';
  static const String metricWaterIcon = 'assets/images/metric_water_icon.png';
  static const String metricLightIcon = 'assets/images/metric_light_icon.png';
  static const String plantIcon = 'assets/images/plant_icon.png';
  static const String statusWaterIcon = 'assets/images/status_water_icon.png';
  static const String statusLightIcon = 'assets/images/status_light_icon.png';
  static const String statusTemperatureIcon =
      'assets/images/status_temperature_icon.png';
  static const String statusHumidityIcon =
      'assets/images/status_humidity_icon.png';
  static const String selectPlantIcon = 'assets/images/select_plant_icon.png';
  static const String customAnimationIcon =
      'assets/images/custom_animation_icon.png';
  static const String batteryStatusIcon =
      'assets/images/battery_status_icon.png';
  static const String deviceSettingsIcon =
      'assets/images/device_settings_icon.png';
  static const String calendarIcon = 'assets/images/calendar_icon.png';
  static const String infoIcon = 'assets/images/info_icon.png';
  static const String plantSelectionBadgeIcon =
      'assets/images/plant_selection_badge_icon.png';
  static const String waterLevelIcon = 'assets/images/water_level_icon.png';
  static const String waterStatusIcon = 'assets/images/water_status_icon.png';
  static const String refreshIcon = 'assets/images/refresh_icon.png';
  static const String animationUploadIllustration =
      'assets/images/animation_upload_illustration.png';
  static const String cloudUploadIcon = 'assets/images/cloud_upload_icon.png';

  // Device settings.
  static const String warningIcon = 'assets/images/warning_icon.png';
  static const String notificationIcon = 'assets/images/notification_icon.png';
  static const String batteryIcon = 'assets/images/battery_icon.png';
  static const String chevronLeftIcon = 'assets/images/chevron_left_icon.png';
  static const String chevronRightIcon = 'assets/images/chevron_right_icon.png';
  static const String settingsPlantIcon =
      'assets/images/settings_plant_icon.png';
  static const String settingsDisplayIcon =
      'assets/images/settings_display_icon.png';
  static const String settingsHearingIcon =
      'assets/images/settings_hearing_icon.png';
  static const String settingsTouchIcon =
      'assets/images/settings_touch_icon.png';
  static const String settingsVibrationIcon =
      'assets/images/settings_vibration_icon.png';
  static const String settingsBehaviorIcon =
      'assets/images/settings_behavior_icon.png';
  static const String settingsOtherIcon =
      'assets/images/settings_other_icon.png';
  static const String editIcon = 'assets/images/edit_icon.png';
  static const String settingOrbitBackground =
      'assets/images/setting_orbit_background.png';
  static const String brightnessSymbol = 'assets/images/brightness_symbol.png';
  static const String hearingWaveformSymbol =
      'assets/images/hearing_waveform_symbol.png';
  static const String vibrationSymbol = 'assets/images/vibration_symbol.png';
  static const String touchGestureSymbol =
      'assets/images/touch_gesture_symbol.png';
  static const String temperatureUnitIcon =
      'assets/images/temperature_unit_icon.png';
  static const String clockModeIcon = 'assets/images/clock_mode_icon.png';
  static const String waterCalibrationIcon =
      'assets/images/water_calibration_icon.png';
  static const String fileSyncIcon = 'assets/images/file_sync_icon.png';
  static const String chipUpdateIcon = 'assets/images/chip_update_icon.png';
  static const String deviceRepairIcon = 'assets/images/device_repair_icon.png';
  static const String globeWarningIcon = 'assets/images/globe_warning_icon.png';
  static const String resetIcon = 'assets/images/reset_icon.png';
  static const String deleteIcon = 'assets/images/delete_icon.png';

  // Water-level calibration.
  static const String waterCalibrationRemoveInnerPot =
      'assets/images/water_calibration_remove_inner_pot.png';
  static const String waterCalibrationAdd30ml =
      'assets/images/water_calibration_add_30ml.png';
  static const String waterCalibrationAddSecond30ml =
      'assets/images/water_calibration_add_second_30ml.png';
  static const String waterCalibrationComplete =
      'assets/images/water_calibration_complete.png';

  // Profile and account security.
  static const String profileAvatarIcon =
      'assets/images/profile_avatar_icon.png';
  static const String helpChatIcon = 'assets/images/help_chat_icon.png';
  static const String profileMenuPersonalInfoIcon =
      'assets/images/profile_menu_personal_info_icon.png';
  static const String profileMenuAccountSecurityIcon =
      'assets/images/profile_menu_account_security_icon.png';
  static const String profileMenuHelpIcon =
      'assets/images/profile_menu_help_icon.png';
  static const String profileMenuFeedbackIcon =
      'assets/images/profile_menu_feedback_icon.png';
  static const String profileMenuPrivacyIcon =
      'assets/images/profile_menu_privacy_icon.png';
  static const String profileMenuAgreementIcon =
      'assets/images/profile_menu_agreement_icon.png';
  static const String profileMenuAboutIcon =
      'assets/images/profile_menu_about_icon.png';
  static const String profileEditIcon = 'assets/images/profile_edit_icon.png';
  static const String accountPasswordHeaderIcon =
      'assets/images/account_password_header_icon.png';
  static const String accountPasswordIcon =
      'assets/images/account_password_icon.png';
  static const String accountPasswordConfirmIcon =
      'assets/images/account_password_confirm_icon.png';
  static const String passwordVisibilityOffIcon =
      'assets/images/password_visibility_off_icon.png';
  static const String aboutCurrentVersionIcon =
      'assets/images/about_current_version_icon.png';
  static const String aboutCheckUpdateIcon =
      'assets/images/about_check_update_icon.png';
  static const String aboutReleaseNotesIcon =
      'assets/images/about_release_notes_icon.png';
}
