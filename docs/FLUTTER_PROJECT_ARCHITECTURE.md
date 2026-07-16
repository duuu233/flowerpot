# YSplanter Flutter 项目架构设计

> 用途：指导后续 UI 开发、状态管理拆分、路由扩展、API 接入和测试建设。
>
> 设计依据：docs/FIGMA_DESIGN_ANALYSIS.md。

## 1. 架构目标

- 支持 100 个以上页面持续扩展
- 按业务域进行 Feature 模块化
- 页面逻辑、业务状态与 Widget 解耦
- 高复用 Widget 和统一 Design Token
- 支持异步状态、缓存、错误和刷新
- 支持 REST API、Tuya SDK 与本地缓存组合
- 支持单元测试、Widget 测试、Golden 测试和集成测试

## 2. 推荐架构

采用 Feature-first + MVVM + Repository/Service 分层：

    Page / Widget
        ↓
    Controller / ViewModel
        ↓
    UseCase（仅复杂或跨仓库业务）
        ↓
    Repository Interface
        ↓
    Repository Implementation
        ↓
    API / Tuya SDK / Local DataSource

基础技术建议：

- 状态管理与依赖注入：Riverpod，使用 Notifier、AsyncNotifier 和 AsyncValue
- 路由：go_router，路由按 Feature 注册
- 网络：Dio
- 不可变状态和 Entity：Freezed
- JSON 转换：json_serializable
- 敏感数据：安全存储
- 普通偏好设置：SharedPreferences

参考资料：

- Flutter 官方架构指南：https://docs.flutter.dev/app-architecture/guide
- Riverpod：https://pub.dev/packages/flutter_riverpod
- go_router：https://pub.dev/packages/go_router
- Dio：https://pub.dev/packages/dio
- Freezed：https://pub.dev/packages/freezed
- json_serializable：https://pub.dev/packages/json_serializable

## 3. 完整目录结构

    flowerpot/
    ├── android/
    ├── ios/
    │
    ├── assets/
    │   ├── fonts/
    │   │   └── source_han_sans_cn/
    │   ├── icons/
    │   │   ├── common/
    │   │   ├── navigation/
    │   │   ├── metrics/
    │   │   ├── devices/
    │   │   └── settings/
    │   ├── images/
    │   │   ├── common/
    │   │   ├── auth/
    │   │   ├── home/
    │   │   ├── plants/
    │   │   ├── pairing/
    │   │   ├── devices/
    │   │   ├── calibration/
    │   │   └── profile/
    │   ├── animations/
    │   └── legal/
    │       ├── privacy_policy_zh.md
    │       └── user_agreement_zh.md
    │
    ├── lib/
    │   ├── main.dart
    │   ├── main_development.dart
    │   ├── main_staging.dart
    │   ├── main_production.dart
    │   ├── bootstrap.dart
    │   │
    │   ├── l10n/
    │   │   ├── app_zh.arb
    │   │   └── app_en.arb
    │   │
    │   └── src/
    │       ├── app/
    │       │   ├── flowerpot_app.dart
    │       │   ├── app_startup.dart
    │       │   ├── config/
    │       │   │   ├── app_environment.dart
    │       │   │   ├── app_config.dart
    │       │   │   ├── api_config.dart
    │       │   │   └── feature_flags.dart
    │       │   ├── router/
    │       │   │   ├── app_router.dart
    │       │   │   ├── route_registry.dart
    │       │   │   ├── route_paths.dart
    │       │   │   ├── route_observer.dart
    │       │   │   ├── navigation_keys.dart
    │       │   │   ├── auth_guard.dart
    │       │   │   └── error_route.dart
    │       │   ├── providers/
    │       │   │   ├── app_startup_provider.dart
    │       │   │   ├── app_lifecycle_provider.dart
    │       │   │   └── connectivity_provider.dart
    │       │   └── localization/
    │       │       ├── locale_controller.dart
    │       │       └── localization_extensions.dart
    │       │
    │       ├── core/
    │       │   ├── constants/
    │       │   │   ├── app_constants.dart
    │       │   │   ├── storage_keys.dart
    │       │   │   └── validation_constants.dart
    │       │   ├── error/
    │       │   │   ├── app_exception.dart
    │       │   │   ├── failure.dart
    │       │   │   ├── error_mapper.dart
    │       │   │   └── error_reporter.dart
    │       │   ├── result/
    │       │   │   ├── result.dart
    │       │   │   └── unit.dart
    │       │   ├── network/
    │       │   │   ├── api_client.dart
    │       │   │   ├── api_endpoints.dart
    │       │   │   ├── network_info.dart
    │       │   │   ├── request_options.dart
    │       │   │   ├── models/
    │       │   │   │   ├── api_envelope.dart
    │       │   │   │   ├── api_error_dto.dart
    │       │   │   │   └── paginated_response.dart
    │       │   │   └── interceptors/
    │       │   │       ├── auth_interceptor.dart
    │       │   │       ├── error_interceptor.dart
    │       │   │       ├── logging_interceptor.dart
    │       │   │       └── retry_interceptor.dart
    │       │   ├── storage/
    │       │   │   ├── key_value_store.dart
    │       │   │   ├── preferences_store.dart
    │       │   │   ├── secure_token_store.dart
    │       │   │   └── cache_store.dart
    │       │   ├── platform/
    │       │   │   ├── tuya/
    │       │   │   │   ├── tuya_service.dart
    │       │   │   │   ├── method_channel_tuya_service.dart
    │       │   │   │   ├── mock_tuya_service.dart
    │       │   │   │   ├── tuya_config.dart
    │       │   │   │   ├── tuya_dp_registry.dart
    │       │   │   │   └── tuya_exception_mapper.dart
    │       │   │   ├── bluetooth/
    │       │   │   │   └── bluetooth_service.dart
    │       │   │   ├── permissions/
    │       │   │   │   └── permission_service.dart
    │       │   │   ├── files/
    │       │   │   │   └── file_picker_service.dart
    │       │   │   └── device_info/
    │       │   │       └── device_info_service.dart
    │       │   ├── observability/
    │       │   │   ├── app_logger.dart
    │       │   │   ├── analytics_service.dart
    │       │   │   └── crash_reporting_service.dart
    │       │   ├── validation/
    │       │   │   ├── validators.dart
    │       │   │   └── validation_result.dart
    │       │   ├── extensions/
    │       │   │   ├── context_extensions.dart
    │       │   │   ├── date_time_extensions.dart
    │       │   │   ├── number_extensions.dart
    │       │   │   └── string_extensions.dart
    │       │   └── utils/
    │       │       ├── debounce.dart
    │       │       ├── date_formatter.dart
    │       │       └── unit_formatter.dart
    │       │
    │       ├── design_system/
    │       │   ├── design_system.dart
    │       │   ├── tokens/
    │       │   │   ├── app_colors.dart
    │       │   │   ├── app_typography.dart
    │       │   │   ├── app_spacing.dart
    │       │   │   ├── app_radius.dart
    │       │   │   ├── app_shadows.dart
    │       │   │   ├── app_durations.dart
    │       │   │   └── app_breakpoints.dart
    │       │   ├── theme/
    │       │   │   ├── app_theme.dart
    │       │   │   ├── light_theme.dart
    │       │   │   └── app_theme_extension.dart
    │       │   └── widgets/
    │       │       ├── layout/
    │       │       │   ├── app_page_scaffold.dart
    │       │       │   ├── app_safe_area.dart
    │       │       │   ├── app_section.dart
    │       │       │   └── responsive_content.dart
    │       │       ├── navigation/
    │       │       │   ├── app_page_header.dart
    │       │       │   ├── app_back_button.dart
    │       │       │   └── app_bottom_navigation.dart
    │       │       ├── buttons/
    │       │       │   ├── app_primary_button.dart
    │       │       │   ├── app_outlined_button.dart
    │       │       │   ├── app_text_button.dart
    │       │       │   └── app_icon_button.dart
    │       │       ├── cards/
    │       │       │   ├── app_surface_card.dart
    │       │       │   ├── app_info_card.dart
    │       │       │   └── app_advice_card.dart
    │       │       ├── forms/
    │       │       │   ├── app_text_field.dart
    │       │       │   ├── app_password_field.dart
    │       │       │   ├── app_phone_field.dart
    │       │       │   ├── app_code_field.dart
    │       │       │   ├── app_search_field.dart
    │       │       │   └── app_checkbox.dart
    │       │       ├── settings/
    │       │       │   ├── settings_list.dart
    │       │       │   ├── settings_tile.dart
    │       │       │   ├── toggle_settings_tile.dart
    │       │       │   └── value_settings_tile.dart
    │       │       ├── feedback/
    │       │       │   ├── app_loading.dart
    │       │       │   ├── app_error_view.dart
    │       │       │   ├── app_empty_state.dart
    │       │       │   ├── app_info_banner.dart
    │       │       │   ├── app_snackbar.dart
    │       │       │   └── app_confirm_dialog.dart
    │       │       ├── data_display/
    │       │       │   ├── app_status_chip.dart
    │       │       │   ├── app_icon_badge.dart
    │       │       │   ├── metric_value.dart
    │       │       │   ├── metric_tile.dart
    │       │       │   ├── date_range_navigator.dart
    │       │       │   └── time_range_selector.dart
    │       │       └── charts/
    │       │           ├── metric_chart_card.dart
    │       │           ├── app_bar_chart.dart
    │       │           ├── app_line_chart.dart
    │       │           └── chart_axis.dart
    │       │
    │       └── features/
    │           ├── shell/
    │           │   ├── shell.dart
    │           │   ├── routes/shell_routes.dart
    │           │   ├── application/shell_navigation_controller.dart
    │           │   └── presentation/
    │           │       ├── pages/app_shell_page.dart
    │           │       └── widgets/shell_navigation_bar.dart
    │           │
    │           ├── auth/
    │           │   ├── auth.dart
    │           │   ├── routes/auth_routes.dart
    │           │   ├── data/
    │           │   │   ├── datasources/
    │           │   │   │   ├── auth_api_data_source.dart
    │           │   │   │   ├── auth_platform_data_source.dart
    │           │   │   │   └── auth_local_data_source.dart
    │           │   │   ├── dtos/
    │           │   │   │   ├── login_request_dto.dart
    │           │   │   │   ├── register_request_dto.dart
    │           │   │   │   └── user_dto.dart
    │           │   │   ├── mappers/user_mapper.dart
    │           │   │   └── repositories/auth_repository_impl.dart
    │           │   ├── domain/
    │           │   │   ├── entities/
    │           │   │   │   ├── app_user.dart
    │           │   │   │   └── auth_session.dart
    │           │   │   ├── repositories/auth_repository.dart
    │           │   │   └── use_cases/
    │           │   │       ├── login.dart
    │           │   │       ├── register.dart
    │           │   │       ├── reset_password.dart
    │           │   │       └── restore_session.dart
    │           │   ├── application/
    │           │   │   ├── auth_providers.dart
    │           │   │   ├── auth_session_controller.dart
    │           │   │   ├── login_controller.dart
    │           │   │   ├── register_controller.dart
    │           │   │   ├── forgot_password_controller.dart
    │           │   │   └── states/
    │           │   │       ├── login_state.dart
    │           │   │       └── registration_state.dart
    │           │   └── presentation/
    │           │       ├── pages/
    │           │       │   ├── verification_login_page.dart
    │           │       │   ├── password_login_page.dart
    │           │       │   ├── register_page.dart
    │           │       │   └── forgot_password_page.dart
    │           │       └── widgets/
    │           │           ├── auth_header.dart
    │           │           ├── auth_mode_selector.dart
    │           │           ├── consent_checkbox.dart
    │           │           └── social_login_actions.dart
    │           │
    │           ├── home/
    │           │   ├── home.dart
    │           │   ├── routes/home_routes.dart
    │           │   ├── domain/
    │           │   │   ├── entities/home_dashboard.dart
    │           │   │   └── use_cases/build_home_dashboard.dart
    │           │   ├── application/
    │           │   │   ├── home_controller.dart
    │           │   │   └── home_state.dart
    │           │   └── presentation/
    │           │       ├── pages/home_page.dart
    │           │       └── widgets/
    │           │           ├── home_device_header.dart
    │           │           ├── planter_hero.dart
    │           │           ├── home_metric_grid.dart
    │           │           ├── daily_care_card.dart
    │           │           ├── home_quick_actions.dart
    │           │           └── no_plant_content.dart
    │           │
    │           ├── plants/
    │           │   ├── plants.dart
    │           │   ├── routes/plant_routes.dart
    │           │   ├── data/
    │           │   │   ├── datasources/
    │           │   │   │   ├── plant_api_data_source.dart
    │           │   │   │   └── plant_local_data_source.dart
    │           │   │   ├── dtos/plant_dto.dart
    │           │   │   ├── mappers/plant_mapper.dart
    │           │   │   └── repositories/plant_repository_impl.dart
    │           │   ├── domain/
    │           │   │   ├── entities/
    │           │   │   │   ├── plant.dart
    │           │   │   │   └── plant_care_profile.dart
    │           │   │   ├── repositories/plant_repository.dart
    │           │   │   └── use_cases/
    │           │   │       ├── search_plants.dart
    │           │   │       └── bind_plant.dart
    │           │   ├── application/
    │           │   │   ├── plant_catalog_controller.dart
    │           │   │   └── plant_selection_controller.dart
    │           │   └── presentation/
    │           │       ├── pages/
    │           │       │   ├── add_plant_page.dart
    │           │       │   ├── select_plant_page.dart
    │           │       │   └── plant_detail_page.dart
    │           │       └── widgets/
    │           │           ├── plant_grid.dart
    │           │           ├── plant_card.dart
    │           │           └── plant_care_banner.dart
    │           │
    │           ├── device_pairing/
    │           │   ├── device_pairing.dart
    │           │   ├── routes/pairing_routes.dart
    │           │   ├── data/
    │           │   │   ├── datasources/
    │           │   │   │   ├── pairing_platform_data_source.dart
    │           │   │   │   └── wifi_scan_data_source.dart
    │           │   │   └── repositories/pairing_repository_impl.dart
    │           │   ├── domain/
    │           │   │   ├── entities/
    │           │   │   │   ├── discovered_device.dart
    │           │   │   │   ├── wifi_network.dart
    │           │   │   │   ├── pairing_request.dart
    │           │   │   │   └── pairing_result.dart
    │           │   │   ├── repositories/pairing_repository.dart
    │           │   │   └── use_cases/
    │           │   │       ├── scan_devices.dart
    │           │   │       └── pair_device.dart
    │           │   ├── application/
    │           │   │   ├── device_scan_controller.dart
    │           │   │   ├── wifi_setup_controller.dart
    │           │   │   └── pairing_controller.dart
    │           │   └── presentation/
    │           │       ├── pages/
    │           │       │   ├── no_devices_page.dart
    │           │       │   ├── nearby_device_search_page.dart
    │           │       │   ├── device_selection_page.dart
    │           │       │   ├── wifi_setup_page.dart
    │           │       │   └── pairing_result_page.dart
    │           │       └── widgets/
    │           │           ├── device_scan_animation.dart
    │           │           ├── discovered_device_tile.dart
    │           │           ├── wifi_selection_dialog.dart
    │           │           └── pairing_troubleshooting_card.dart
    │           │
    │           ├── devices/
    │           │   ├── devices.dart
    │           │   ├── routes/device_routes.dart
    │           │   ├── data/
    │           │   │   ├── datasources/
    │           │   │   │   ├── device_api_data_source.dart
    │           │   │   │   └── device_tuya_data_source.dart
    │           │   │   ├── dtos/
    │           │   │   │   ├── device_dto.dart
    │           │   │   │   └── sensor_snapshot_dto.dart
    │           │   │   ├── mappers/device_mapper.dart
    │           │   │   └── repositories/device_repository_impl.dart
    │           │   ├── domain/
    │           │   │   ├── entities/
    │           │   │   │   ├── planter_device.dart
    │           │   │   │   ├── device_status.dart
    │           │   │   │   └── sensor_snapshot.dart
    │           │   │   ├── repositories/device_repository.dart
    │           │   │   └── use_cases/
    │           │   │       ├── watch_devices.dart
    │           │   │       ├── select_device.dart
    │           │   │       └── remove_device.dart
    │           │   ├── application/
    │           │   │   ├── device_list_controller.dart
    │           │   │   ├── selected_device_controller.dart
    │           │   │   └── device_details_controller.dart
    │           │   └── presentation/
    │           │       ├── pages/
    │           │       │   ├── device_list_page.dart
    │           │       │   └── device_details_page.dart
    │           │       └── widgets/
    │           │           ├── device_tile.dart
    │           │           ├── device_status_badge.dart
    │           │           └── device_identity_table.dart
    │           │
    │           ├── sensor_reports/
    │           │   ├── sensor_reports.dart
    │           │   ├── routes/report_routes.dart
    │           │   ├── data/
    │           │   │   ├── datasources/
    │           │   │   │   ├── sensor_history_api_data_source.dart
    │           │   │   │   └── sensor_history_tuya_data_source.dart
    │           │   │   ├── dtos/metric_sample_dto.dart
    │           │   │   ├── mappers/metric_sample_mapper.dart
    │           │   │   └── repositories/sensor_report_repository_impl.dart
    │           │   ├── domain/
    │           │   │   ├── entities/
    │           │   │   │   ├── sensor_metric.dart
    │           │   │   │   ├── metric_sample.dart
    │           │   │   │   ├── report_range.dart
    │           │   │   │   └── care_advice.dart
    │           │   │   ├── repositories/sensor_report_repository.dart
    │           │   │   └── use_cases/load_sensor_report.dart
    │           │   ├── application/
    │           │   │   ├── sensor_report_controller.dart
    │           │   │   └── water_report_controller.dart
    │           │   └── presentation/
    │           │       ├── pages/
    │           │       │   ├── light_report_page.dart
    │           │       │   ├── water_report_page.dart
    │           │       │   ├── temperature_report_page.dart
    │           │       │   ├── humidity_report_page.dart
    │           │       │   └── battery_report_page.dart
    │           │       └── widgets/
    │           │           ├── metric_summary_card.dart
    │           │           ├── report_range_header.dart
    │           │           ├── sensor_chart.dart
    │           │           └── care_advice_card.dart
    │           │
    │           ├── animations/
    │           │   ├── animations.dart
    │           │   ├── routes/animation_routes.dart
    │           │   ├── data/
    │           │   │   ├── datasources/
    │           │   │   │   ├── animation_api_data_source.dart
    │           │   │   │   └── animation_tuya_data_source.dart
    │           │   │   └── repositories/animation_repository_impl.dart
    │           │   ├── domain/
    │           │   │   ├── entities/animation_asset.dart
    │           │   │   └── repositories/animation_repository.dart
    │           │   ├── application/animation_controller.dart
    │           │   └── presentation/
    │           │       ├── pages/custom_animation_page.dart
    │           │       └── widgets/
    │           │           ├── animation_upload_area.dart
    │           │           ├── animation_file_tile.dart
    │           │           └── animation_sync_status.dart
    │           │
    │           ├── device_settings/
    │           │   ├── device_settings.dart
    │           │   ├── routes/device_settings_routes.dart
    │           │   ├── data/
    │           │   │   ├── datasources/
    │           │   │   │   ├── device_settings_api_data_source.dart
    │           │   │   │   └── device_settings_tuya_data_source.dart
    │           │   │   └── repositories/device_settings_repository_impl.dart
    │           │   ├── domain/
    │           │   │   ├── entities/
    │           │   │   │   ├── device_settings.dart
    │           │   │   │   ├── device_schedule.dart
    │           │   │   │   ├── firmware_info.dart
    │           │   │   │   └── calibration_step.dart
    │           │   │   ├── repositories/device_settings_repository.dart
    │           │   │   └── use_cases/
    │           │   │       ├── update_device_setting.dart
    │           │   │       ├── calibrate_water_sensor.dart
    │           │   │       └── update_firmware.dart
    │           │   ├── application/
    │           │   │   ├── device_settings_controller.dart
    │           │   │   ├── firmware_controller.dart
    │           │   │   ├── calibration_controller.dart
    │           │   │   └── behavior_schedule_controller.dart
    │           │   └── presentation/
    │           │       ├── pages/
    │           │       │   ├── device_settings_page.dart
    │           │       │   ├── more_device_info_page.dart
    │           │       │   ├── other_settings_page.dart
    │           │       │   ├── display_settings_page.dart
    │           │       │   ├── hearing_settings_page.dart
    │           │       │   ├── vibration_settings_page.dart
    │           │       │   ├── touch_settings_page.dart
    │           │       │   └── behavior_settings_page.dart
    │           │       ├── dialogs/
    │           │       │   ├── firmware_update_dialog.dart
    │           │       │   ├── temperature_unit_dialog.dart
    │           │       │   ├── clock_format_dialog.dart
    │           │       │   ├── calibration_wizard_dialog.dart
    │           │       │   ├── reset_factory_dialog.dart
    │           │       │   └── remove_device_dialog.dart
    │           │       └── widgets/
    │           │           ├── device_summary_card.dart
    │           │           ├── sensitivity_control.dart
    │           │           ├── schedule_section.dart
    │           │           └── calibration_stepper.dart
    │           │
    │           ├── profile/
    │           │   ├── profile.dart
    │           │   ├── routes/profile_routes.dart
    │           │   ├── data/
    │           │   │   ├── datasources/
    │           │   │   │   ├── profile_api_data_source.dart
    │           │   │   │   └── profile_local_data_source.dart
    │           │   │   └── repositories/profile_repository_impl.dart
    │           │   ├── domain/
    │           │   │   ├── entities/user_profile.dart
    │           │   │   └── repositories/profile_repository.dart
    │           │   ├── application/
    │           │   │   ├── profile_controller.dart
    │           │   │   └── mine_controller.dart
    │           │   └── presentation/
    │           │       ├── pages/
    │           │       │   ├── mine_page.dart
    │           │       │   └── personal_info_page.dart
    │           │       └── widgets/
    │           │           ├── profile_header.dart
    │           │           └── profile_menu.dart
    │           │
    │           ├── account_security/
    │           │   ├── account_security.dart
    │           │   ├── routes/account_security_routes.dart
    │           │   ├── application/
    │           │   │   ├── account_security_controller.dart
    │           │   │   └── password_controller.dart
    │           │   └── presentation/
    │           │       ├── pages/
    │           │       │   ├── account_security_page.dart
    │           │       │   ├── set_login_password_page.dart
    │           │       │   └── change_password_page.dart
    │           │       └── widgets/password_guidance_card.dart
    │           │
    │           ├── support/
    │           │   ├── support.dart
    │           │   ├── routes/support_routes.dart
    │           │   ├── data/
    │           │   │   ├── datasources/support_api_data_source.dart
    │           │   │   └── repositories/support_repository_impl.dart
    │           │   ├── domain/
    │           │   │   ├── entities/
    │           │   │   │   ├── faq_item.dart
    │           │   │   │   └── feedback_request.dart
    │           │   │   └── repositories/support_repository.dart
    │           │   ├── application/
    │           │   │   ├── help_center_controller.dart
    │           │   │   └── feedback_controller.dart
    │           │   └── presentation/
    │           │       ├── pages/
    │           │       │   ├── help_center_page.dart
    │           │       │   └── feedback_page.dart
    │           │       └── widgets/help_expansion_list.dart
    │           │
    │           ├── legal/
    │           │   ├── legal.dart
    │           │   ├── routes/legal_routes.dart
    │           │   ├── data/
    │           │   │   ├── datasources/
    │           │   │   │   ├── legal_asset_data_source.dart
    │           │   │   │   └── legal_api_data_source.dart
    │           │   │   └── repositories/legal_repository_impl.dart
    │           │   ├── domain/
    │           │   │   ├── entities/legal_document.dart
    │           │   │   └── repositories/legal_repository.dart
    │           │   ├── application/legal_document_controller.dart
    │           │   └── presentation/
    │           │       ├── pages/
    │           │       │   ├── privacy_policy_page.dart
    │           │       │   └── user_agreement_page.dart
    │           │       └── widgets/legal_document_view.dart
    │           │
    │           ├── about/
    │           │   ├── about.dart
    │           │   ├── routes/about_routes.dart
    │           │   ├── application/app_version_controller.dart
    │           │   └── presentation/pages/about_page.dart
    │           │
    │           └── preferences/
    │               ├── preferences.dart
    │               ├── routes/preferences_routes.dart
    │               ├── data/
    │               │   ├── datasources/preferences_local_data_source.dart
    │               │   └── repositories/preferences_repository_impl.dart
    │               ├── domain/
    │               │   ├── entities/app_preferences.dart
    │               │   └── repositories/preferences_repository.dart
    │               ├── application/preferences_controller.dart
    │               └── presentation/pages/app_preferences_page.dart
    │
    ├── test/
    │   ├── helpers/
    │   │   ├── pump_app.dart
    │   │   ├── provider_overrides.dart
    │   │   └── test_data.dart
    │   ├── fixtures/
    │   │   ├── auth/
    │   │   ├── devices/
    │   │   ├── plants/
    │   │   └── reports/
    │   ├── fakes/
    │   │   ├── fake_api_client.dart
    │   │   ├── fake_tuya_service.dart
    │   │   └── fake_repositories.dart
    │   ├── core/
    │   ├── design_system/
    │   │   ├── widget/
    │   │   └── golden/
    │   └── features/
    │       ├── auth/
    │       ├── home/
    │       ├── plants/
    │       ├── device_pairing/
    │       ├── devices/
    │       ├── sensor_reports/
    │       ├── animations/
    │       ├── device_settings/
    │       ├── profile/
    │       ├── account_security/
    │       ├── support/
    │       └── legal/
    │
    ├── integration_test/
    │   ├── auth_flow_test.dart
    │   ├── pairing_flow_test.dart
    │   ├── plant_binding_flow_test.dart
    │   ├── device_settings_flow_test.dart
    │   └── account_flow_test.dart
    │
    ├── tool/
    │   ├── generate_feature.dart
    │   ├── generate_page.dart
    │   └── templates/
    │       ├── feature/
    │       └── page/
    │
    ├── docs/
    │   ├── FIGMA_DESIGN_ANALYSIS.md
    │   ├── FLUTTER_PROJECT_ARCHITECTURE.md
    │   ├── ROUTING.md
    │   ├── STATE_MANAGEMENT.md
    │   └── API_INTEGRATION.md
    │
    ├── analysis_options.yaml
    ├── build.yaml
    ├── l10n.yaml
    ├── pubspec.yaml
    └── README.md

## 4. 分层职责

### 4.1 Presentation

- 只负责 Widget、布局、动画和用户事件转发
- 不直接调用 API、Dio、SharedPreferences、MethodChannel 或 Tuya SDK
- 页面通过监听 Controller 状态进行渲染
- 页面不保存跨页面业务状态

### 4.2 Application

- Controller 即 ViewModel
- 将 Repository 数据转换为页面状态
- 处理提交、刷新、分页和乐观更新
- 使用 Riverpod Notifier 或 AsyncNotifier
- 每个重要页面或业务流程拥有独立 Controller

### 4.3 Domain

- Entity 不依赖 Flutter、Dio、MethodChannel 和 JSON
- Repository 文件仅声明接口
- UseCase 只用于复杂、复用或跨多个 Repository 的业务
- 简单 CRUD 不需要机械地创建 UseCase

### 4.4 Data

- DataSource 连接 API、Tuya SDK 或本地缓存
- DTO 负责外部数据结构与 JSON
- Mapper 负责 DTO 与 Domain Entity 转换
- Repository Implementation 负责缓存、错误、重试和多数据源组合

## 5. 状态管理规范

### 5.1 App 级状态

- 登录会话
- 当前选中设备
- 语言与主题
- 网络连接状态
- App 生命周期

### 5.2 Feature 级状态

- 设备列表
- 植物列表
- 传感器历史数据
- 设备设置
- 动画文件列表

### 5.3 Page 级状态

- 表单输入和校验
- 当前 Tab
- 筛选条件
- 图表时间范围
- 分页游标
- 提交和局部加载状态

### 5.4 Widget 本地状态

- 动画控制器
- 输入焦点
- 临时展开/收起
- 不需要跨页面保存的选中状态

### 5.5 当前全局状态迁移

现有 FlowerpotState 建议拆分为：

- AuthSessionController
- DeviceListController
- SelectedDeviceController
- HomeController
- SensorReportController
- AnimationController
- DeviceSettingsController
- ProfileController
- PreferencesController

禁止继续向单一全局 ChangeNotifier 添加新功能。

## 6. 路由规范

- app/router 只负责聚合 Feature 路由
- 每个 Feature 在自己的 routes 目录注册页面
- 登录重定向由 auth_guard 统一处理
- 主导航容器使用 ShellRoute
- 设备 ID、报告类型等使用路径参数
- 搜索、筛选、日期范围使用查询参数
- 弹窗和页面状态不应全部建成独立路由
- Wi-Fi 选择、温度单位、时钟模式和校准步骤优先实现为 Dialog/Sheet
- 页面之间禁止直接依赖另一个 Feature 的内部 Page 文件

## 7. Widget 复用规范

### 7.1 抽离层级

- 仅单页面使用：放在页面附近或本 Feature widgets
- 同一 Feature 多页面使用：放在 Feature 公共 widgets
- 三个以上 Feature 使用：提升到 design_system/widgets
- 带业务含义的 Widget 不进入 Design System

### 7.2 推荐的 Design System Widget

- AppPageScaffold
- AppPageHeader
- AppSurfaceCard
- AppPrimaryButton
- AppOutlinedButton
- AppTextField
- AppSearchField
- SettingsTile
- ToggleSettingsTile
- AppStatusChip
- AppInfoBanner
- AppEmptyState
- AppErrorView
- AppConfirmDialog
- MetricTile
- MetricChartCard
- DateRangeNavigator
- TimeRangeSelector

### 7.3 推荐的业务 Widget

- PlantCard
- PlantGrid
- HomeMetricGrid
- PlanterHero
- DeviceTile
- MetricSummaryCard
- SensorChart
- CalibrationStepper
- AnimationFileTile
- ProfileMenu

## 8. API 接入规范

- Page 和 Controller 不直接调用网络层
- API JSON 只进入 DTO
- DTO 经 Mapper 转换为 Domain Entity
- Repository 是业务数据唯一入口
- Repository 可组合 API、Tuya SDK 与缓存
- API 鉴权、错误、日志、重试和超时集中处理
- Token 使用安全存储
- 普通显示偏好使用 SharedPreferences
- 上传动画文件时使用可取消请求和进度回调
- 列表接口统一使用分页响应模型
- API 错误统一转换为 Failure

推荐数据流：

    Widget
      → Controller
      → Repository
      → RemoteDataSource
      → ApiClient
      → Backend API

Tuya 设备数据流：

    Widget
      → Controller
      → Repository
      → TuyaDataSource
      → TuyaService
      → MethodChannel
      → Android / iOS Tuya SDK

## 9. Feature 依赖约束

- app 可以依赖所有 Feature 的 routes
- Feature 可以依赖 core 和 design_system
- Feature 不直接依赖其他 Feature 的 data 或 presentation
- 跨模块业务通过 Repository、UseCase 或公开 Provider 协作
- core 不依赖任何 Feature
- design_system 不依赖任何 Feature
- Domain 不依赖 Data 和 Presentation
- Data 可以实现 Domain 中定义的 Repository
- Presentation 只依赖 Application、Domain 和 Design System

## 10. 100+ 页面扩展规范

新增普通页面：

1. 在对应 Feature 的 presentation/pages 中添加页面。
2. 为需要业务状态的页面添加独立 Controller。
3. 在 Feature 自己的 routes 文件中注册。
4. 页面私有 Widget 留在 Feature 内。
5. 不修改其他 Feature。

新增业务模块：

1. 创建 feature_name 目录。
2. 建立 routes、application、presentation。
3. 只有存在数据访问时才增加 data。
4. 只有存在独立业务模型或规则时才增加 domain。
5. 将 Feature 路由加入 app 的 route_registry。

禁止：

- 所有页面集中到 pages 根目录
- 所有 Provider 集中到一个 providers.dart
- 所有 Repository 集中到一个 repository.dart
- 通过巨大 shared 目录存放无法归类的代码
- 为每个简单操作机械创建 UseCase
- 页面直接解析 JSON 或操作 MethodChannel

## 11. 测试策略

- Domain Entity 和 UseCase：单元测试
- Repository：使用 Fake DataSource 测试
- Controller：使用 ProviderContainer 和 Repository Override 测试
- 通用 Widget：Widget 测试
- Figma 核心页面：Golden 测试
- 登录、配网、植物绑定和设置：Integration Test
- API 与 Tuya SDK 不进入普通 Widget Test

## 12. 建议实施顺序

1. 建立 Design Token 和 Design System。
2. 引入 Riverpod，先拆分 AuthSession 和 Device 状态。
3. 将 onGenerateRoute 迁移为 go_router。
4. 将 TuyaRepository 拆为低层 TuyaService 和业务 Repository。
5. 按 Feature 迁移现有页面。
6. 建立 Dio API 基础层和环境配置。
7. 建立 Fake Repository，确保无后端时仍可开发 UI。
8. 为登录、首页、配网和设置页面补充 Golden 测试。
9. 最后移除旧 FlowerpotState、旧 routes 和旧 shared 聚合文件。

## 13. 生成文件说明

Freezed、Riverpod Generator 和 json_serializable 可能产生：

- .g.dart
- .freezed.dart

这些文件由工具自动生成，不手工修改，也不作为业务目录设计的一部分。
