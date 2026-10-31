abstract final class TuyaConfig {
  static const channelName = 'com.common.yikaltd/tuya';

  /// One-way channel the native side pushes device reports on: DP updates,
  /// online state and unbind notices the app never asked for.
  static const eventChannelName = 'com.common.yikaltd/tuya_events';
  static const defaultHomeName = '我的花园';

  /// PID the [dp] table below was exported from.
  ///
  /// Only used to label the table; the app never sends it. A device bound to a
  /// different PID reports different DP ids, so re-export the table instead of
  /// editing rows by hand.
  static const productId = 'yciq4kssu1fv8umn';

  /// 设备 **BLE 广播包里**带的标识（2026-09-11 真机确认）。
  ///
  /// ⚠️ **它和 [productId] 是两个不同的东西，不是"对不上"**：
  ///
  /// | | 是什么 | 谁用 |
  /// | --- | --- | --- |
  /// | [productId] `yciq4kssu1fv8umn` | 涂鸦 IoT 平台上那个**产品**的 ID | 配网、绑定、DP 表——**云端一律以它为准** |
  /// | [broadcastId] `ehbx83xdh9jkmxvz` | 设备**广播**时放进 BLE 包里的标识 | 只用于本地判断「这条广播是不是这款产品」 |
  ///
  /// BLE 扫描回来的 `ScanDeviceBean.getProductId()` 拿到的是**广播里那个**，所以认
  /// 设备时两个都要比——只比 [productId] 会永远认不出来（2026-09-11 真机上扫到
  /// -32dBm 的花盆却没被标成"本产品"，就是这个原因）。
  ///
  /// ⚠️ **2026-09-12：后台那个 `broadcastId` 字段改存平台产品 ID 了**
  /// （后台界面上的文案也从「广播ID」改成了「涂鸦产品ID」）。也就是说后台清单里
  /// 拿到的不再是广播标识，`FlowerpotState._isOurProduct` 认这款花盆靠的就是下面
  /// 这个本地常量。**这一行不能删**，删了搜索页就再也认不出设备。
  ///
  /// ⚠️ **已绑定设备的 `DeviceBean.getProductId()` 报的也是这个值**（2026-09-14 帮助中心调试信息里
  /// 看到的），不是 [productId]。所以要给 APP 后端传「产品 ID」时不要拿设备的 productId，也不要用
  /// 这里的常量兜底——从接口取（帮助中心取 `getBasicData` 的 `deviceIdList`）。
  static const broadcastId = 'ehbx83xdh9jkmxvz';

  /// Product DP table, keyed by the Tuya *identifier* rather than by an app
  /// concept, so a row can be diffed against the platform export character for
  /// character. App-facing names resolve through [setting] and [history];
  /// sensor reads name their identifier at the point of use.
  ///
  /// Source: `assets/智能花盆test(yciq4kssu1fv8umn)_09_16.xlsx`, sheet 功能点,
  /// exported 2026-09-16. Same PID as the 09-07 export, which it reproduces row
  /// for row and extends with 164 (空气温度日历史) and 165 (空气湿度日历史);
  /// 09-07 in turn had added 161 (植物分类) and 162 (植物确认, since renamed
  /// 弹窗提醒) over 09-03, and 09-03 had added 151–160 (standby, language,
  /// memorial days, photo management and the operation receipt) over 08-20.
  /// 163 (自动检测植物开关) started out as a local placeholder and is in the
  /// export since 09-12.
  static const dp = <String, int>{
    // Reported state.
    'device_status': 101, // string, rw
    'together_days': 102, // value 1-1100 天, reported once a day at 00:00
    'battery_level': 103, // value 0-100 %
    'battery_status': 104, // enum shortage/good/charging
    'water_level': 105, // value 0-200 mL
    'soil_moist': 106, // value 0-100 %
    'water_needs_status': 107, // enum shortage/drinking/watery
    'lighting_condition': 108, // enum shortage/good/very_good
    'light_intensity': 109, // value 0-9000 lux
    'light_ppfd_value': 110, // value 0-9000 μmol/m²/s
    'light_par_value': 111, // value 0-9000 μmol/m²
    'air_temperature': 112, // value 0-2200, 倍数 1 -> tenths of a degree
    'air_temperature_status': 113, // enum cold/suitable/heat
    'air_humidity': 114, // value 0-1000, 倍数 1 -> tenths of a percent
    'air_humidity_status': 115, // enum dry/suitable/damp
    // 2026-09-09 起是植物 id：-1 = 盆里没有植物，0..N = 具体植物，数值等于管理
    // 后台植物管理里的「涂鸦标识 ID」（0 是通用植物）。上报 + 下发。
    'plant_variety': 116,
    // Control.
    // 117 = 自动亮度开关：true 自动（跟随环境光）/ false 手动（亮度由 168 决定）。
    // 平台名称仍写「显示屏幕亮度开关」是旧语义，见 docs/app_DP_问题修正说明.md §6。
    'disp_brightness_switch': 117, // bool rw，出厂默认 false（手动）
    'voice_interaction_switch': 118, // bool
    'sound_sensitivity': 119, // value 0-100 %
    'touch_interact_switch': 120, // bool
    'touch_sense_sensitivity': 121, // value 0-100 %
    'vibration_switch': 122, // bool
    'touch_vib_switch': 123, // bool
    'touch_plant_vib_switch': 124, // bool
    'nap_time_switch': 125, // bool
    'nap_start_time': 126, // value 0-1440 minutes past midnight
    'nap_end_time': 127, // value 0-1440 minutes past midnight
    'night_sleep_switch': 128, // bool
    'night_sleep_start_time': 129, // value 0-1440 minutes past midnight
    'night_sleep_end_time': 130, // value 0-1440 minutes past midnight
    // Reported history, raw. See `TuyaHistoryCodec` for the byte layout.
    'tank_level_daily_hist': 131,
    'tank_level_weekly_hist': 132,
    'tank_level_monthly_hist': 133,
    'soil_moist_daily_hist': 134,
    'soil_moist_weekly_hist': 135,
    'soil_moist_monthly_hist': 136,
    'light_daily_hist': 137,
    'light_weekly_hist': 138,
    'light_monthly_hist': 139,

    // Maintenance and media.
    'water_level_calib': 140, // enum step0..step5：0 开始 / 1~3 采样 / 4 保存 / 5 取消
    'factory_reset': 141, // bool, write only
    'dl_url': 142, // raw, write only
    'dl_show': 143, // string, write only
    'dl_cancel': 144, // bool, write only
    'charge_status': 145, // bool
    'temp_unit_convert': 146, // enum C/F
    'time_format': 147, // enum 24h/12h
    'firmware_version': 148, // string
    'hardware_version': 149, // value 1-100
    're_pairing': 150, // bool, write only：清配网信息、重启进配网，本地数据保留
    // Standby, language and the memorial/photo features added by the 09-03
    // export.
    'standby_switch': 151, // bool, default false (never sleep)
    'standby_delay': 152, // value 1-180 minutes
    'language': 153, // enum Chinese/English, factory reset returns to Chinese
    'memorial_set': 154, // raw, upsert/disable/delete one custom memorial day
    'del_photo': 155, // raw, write only: photo file name, ASCII
    'del_all_photos': 156, // bool, write only: true clears the gallery
    'pin_photo': 157, // raw, write only: photo file name, ASCII
    'memorial_birthday': 158, // raw, 8 ASCII bytes YYYYMMDD
    'memorial_wedding': 159, // raw, 8 ASCII bytes YYYYMMDD
    'op_result': 160, // string `<操作>:<对象>:<结果>`
    // Added by the 09-07 export.
    'plant_type': 161, // enum 1/2/3, rw: 后台植物分类，随 116 一起下发
    // 2026-09-09 起两态、且只由设备上报：0 = 不弹窗，1 = 弹「发现新植物」引导窗。
    // App 不再写这条——下发 116 之后固件自己改回 0 并立即上报；116 为 -1 或用户
    // 关掉自动检测时固件同样报 0。
    // ⚠️ **平台 2026-09-12 把它改名了**：`plant_confirm`（植物确认）→ `plant_present`
    // （弹窗提醒）。**DP 号与数据类型都没变**（162 / bool），改的只是标识符与显示名，
    // 所以行为不受影响；这里跟着平台导出走，两个名字都留着，免得别处按旧名查不到。
    'plant_present': 162,
    'plant_confirm': 162,

    // TODO(固件/平台): 自动检测植物的开关。产品要求设备设置页有这个纯开关，但
    // 09-07 的导出里还没有这条功能点，163 与标识符都是本地占位。平台补完导出后
    // 只需要改这一行——App 侧统一走 `TuyaConfig.setting['plantDetection']`。
    // ⚠️ **2026-09-12 平台已正式导出**（此前是本地占位）。平台上的标识符是
    // `plant_confirm_switch`，不是我们当初猜的 `plant_detect_switch`——DP 号 163、
    // 类型 bool 都对得上。两个名字都留着：下发按 DP 号走，改名不影响行为。
    'plant_confirm_switch': 163, // bool, rw
    'plant_detect_switch': 163, // bool, rw（本地旧名，平台已改用上面那个）
    // Added by the 09-16 export: the two daily history packets the 温度 / 湿度
    // status pages had been missing. 帧格式与 131/134/137 的日帧相同，见
    // `TuyaHistoryCodec`。
    'temp_daily_hist': 164, // raw, ro：空气温度日历史
    'humi_daily_hist': 165, // raw, ro：空气湿度日历史
    // 2026-09-28 新增（`docs/新增 DP 说明 — DP166 ~ DP169.md`）。167 power_off 关机暂不对接，这里不登记；
    // 那版说明里的 169 file_download 已作废，169 改为下面的 first_calib。
    'led_switch': 166, // bool rw：双色 LED 灯效总开关，默认 false（关）；和 117 屏幕是两个独立开关
    // 168 = 手动亮度（docs/app_DP_问题修正说明.md §6）：0~100，0 = 灭屏，仅 117 = false 时
    // 生效，出厂 100。09-28 那版说明里 168 是 `ota_result`，按新说明作废，App 不再按 OTA 结果解读。
    'manual_brightness': 168, // value rw 0-100
    // 2026-10-31 产品：首用 / 恢复出厂配网成功 → 设备教程结束 → 自动水位校准，完成、跳过或退出
    // 校准界面任一发生即报 true；恢复出厂清回 false。为 true 时 App 才能进设备页。
    'first_calib': 169, // bool rw，默认 false
  };

  /// DPs the device transmits as an integer scaled by a power of ten (涂鸦
  /// "倍数"). Reads divide, writes multiply.
  static const dpScale = <String, int>{
    'air_temperature': 10,
    'air_humidity': 10,
  };

  /// Writable settings the app exposes, mapped to the DP that backs them.
  ///
  /// The two schedules are absent because each spans a pair of DPs; they are
  /// resolved by [settingDps] instead.
  static const setting = <String, String>{
    'autoBrightness': 'disp_brightness_switch',
    'manualBrightness': 'manual_brightness',
    // LED 设置页走 166 `led_switch`（2026-09-28 固件新增，双色 LED 灯效总开关）。原来 09-03 的功能点表里
    // 没有单独的 LED 开关，和显示页共用 117；新 DP 说明写明「117 = 屏幕背光、166 = 双色 LED，两个独立开关，
    // APP 不要共用一个」。
    'led': 'led_switch',
    'soundInteraction': 'voice_interaction_switch',
    'soundSensitivity': 'sound_sensitivity',
    'touchInteraction': 'touch_interact_switch',
    'touchSensitivity': 'touch_sense_sensitivity',
    'vibration': 'vibration_switch',
    'touchKeyVibration': 'touch_vib_switch',
    'touchPlantVibration': 'touch_plant_vib_switch',
    'napEnabled': 'nap_time_switch',
    'nightEnabled': 'night_sleep_switch',
    'temperatureUnit': 'temp_unit_convert',
    'clockFormat': 'time_format',
    'standby': 'standby_switch',
    'standbyDelay': 'standby_delay',
    'deviceLanguage': 'language',
    // 自动检测植物。关掉之后设备不再比对盆里的植物，也就不会再报 162 异常。
    'plantDetection': 'plant_detect_switch',
  };

  /// Reported history series, keyed by app metric then by range.
  static const history = <String, Map<String, String>>{
    'waterLevel': <String, String>{
      'day': 'tank_level_daily_hist',
      'week': 'tank_level_weekly_hist',
      'month': 'tank_level_monthly_hist',
    },
    'soilMoisture': <String, String>{
      'day': 'soil_moist_daily_hist',
      'week': 'soil_moist_weekly_hist',
      'month': 'soil_moist_monthly_hist',
    },
    'illuminance': <String, String>{
      'day': 'light_daily_hist',
      'week': 'light_weekly_hist',
      'month': 'light_monthly_hist',
    },
    // 2026-09-16 的功能点表补了这两条日历史。**只有日，没有周和月**：DP 表里
    // 就只导出了 164 / 165 两行，所以这两个指标的周 / 月视图依旧没有设备包。
    'temperature': <String, String>{'day': 'temp_daily_hist'},
    'humidity': <String, String>{'day': 'humi_daily_hist'},
  };

  /// Bytes per sample in the raw history DPs. Water level and soil moisture fit
  /// in a single unsigned byte; light, air temperature and air humidity do not.
  ///
  /// 164 / 165 的功能点表没有写「点宽」，09-16 那轮是按它们实时 DP 的量程推的：
  /// 112 的量程是 0–2200（倍数 1），114 是 0–1000（倍数 1），一个字节都装不下，
  /// 所以按 uint16 BE 解，和 137–139 的照度同一套。
  ///
  /// **固件 1.0.12 把这个推断坐实了**：165（空气湿度日历史）的点从「1 字节整数 %」
  /// 改成与 164 对称的 **2 字节大端 ×10**，产品口径是「App 按 2B 解析即可」。所以
  /// 这张表不按固件版本分叉。
  ///
  /// ⚠️ 1.0.12 以下的固件 165 报的还是 1 字节点，App 按 2 字节解出来是一条错位的
  /// 曲线。帧长分不出 1B / 2B（3 + N 和 3 + 2N 都可能是任意长度），认不出来也兜不了，
  /// 只能是设备先升级。真机上照 `historyDiagnostics` 打的「字节数/点数」核一眼。
  static const historySampleBytes = <String, int>{
    'illuminance': 2,
    'temperature': 2,
    'humidity': 2,
  };

  /// 历史点位上报时被放大的倍数（同 [dpScale]，只是按指标而不是按标识符查）。
  /// 温度、湿度的历史点和它们的实时 DP 一样是十分之一度 / 十分之一个百分点。
  static const historyScale = <String, int>{'temperature': 10, 'humidity': 10};

  /// 历史点位上报时被缩小的倍数：水位历史点存的是 mL ÷ 2（1 字节装得下 0~200 mL），
  /// 画之前 ×2 还原成 mL（`docs/app_DP_问题修正说明.md` §4.3）。
  static const historyMultiplier = <String, int>{'waterLevel': 2};

  /// 历史点按**有符号**数解的指标：空气温度日历史（164）是 2 字节有符号大端，支持负温。
  static const historySignedSamples = <String>{'temperature'};

  /// `temp_unit_convert` enum values against the labels the settings sheet
  /// uses.
  static const temperatureUnits = <String, String>{
    'celsius': 'C',
    'fahrenheit': 'F',
  };

  /// `language` (153) enum values against the app's own language codes, which
  /// are the same ones `FlowerpotState.languageCode` uses.
  static const deviceLanguages = <String, String>{
    'zh': 'Chinese',
    'en': 'English',
  };

  /// `plant_type` (161) 的合法枚举值。后台植物分类是数字，枚举 DP 下发的是
  /// 字符串，两边在 [plantTypeValue] 里换算。
  static const plantTypes = <String>['1', '2', '3'];

  /// 把后台的植物分类换成 161 能接受的枚举值；超出 1–3 或为空时返回 null，
  /// 绑定植物时就只下发 116。
  static String? plantTypeValue(int? category) {
    if (category == null) return null;
    final label = '$category';
    return plantTypes.contains(label) ? label : null;
  }

  /// Bounds of `standby_delay` (152), in minutes.
  static const standbyDelayMin = 1;
  static const standbyDelayMax = 180;

  /// `water_level_calib`（140）的枚举值，下标就是 DP140 的编号（固件 1.0.16 起的新语义，
  /// `docs/app_DP_问题修正说明.md` §5）：
  ///
  /// 0 开始会话（不采样）→ 1 采样空杯 → 2 采样 20 mL → 3 采样 40 mL → 4 计算并保存；
  /// 5 取消（丢弃暂存）。**采样发生在报文到达的瞬间**，所以每个采样步都是用户做完
  /// 卡片上的动作、点按钮之后才发。
  static const calibrationSteps = <String>[
    'step0',
    'step1',
    'step2',
    'step3',
    'step4',
  ];
  static const calibrationCancel = 'step5';

  /// 每一步在 DP160 回执里的对象名：`calib:<对象>:ok/fail`。
  static const calibrationReceiptObjects = <String>[
    'begin',
    'step1',
    'step2',
    'step3',
    'step4',
  ];
  static const calibrationCancelReceiptObject = 'step5';

  /// 手动亮度（168）的范围。
  static const manualBrightnessMin = 0;
  static const manualBrightnessMax = 100;

  /// Encodes one app setting into the DPs that carry it.
  ///
  /// Returns null when the product has no DP for [key], which is how the app
  /// tells "not wired up yet" apart from "the device rejected it".
  static Map<int, Object>? settingDps(String key, Object value) {
    switch (key) {
      case 'napPeriod':
        return _periodDps('nap_start_time', 'nap_end_time', value);
      case 'nightPeriod':
        return _periodDps(
          'night_sleep_start_time',
          'night_sleep_end_time',
          value,
        );
      case 'temperatureUnit':
        final unit = temperatureUnits[value];
        if (unit == null) return null;
        return _single('temp_unit_convert', unit);
      case 'deviceLanguage':
        final language = deviceLanguages[value];
        if (language == null) return null;
        return _single('language', language);
      case 'manualBrightness':
        if (value is! num) return null;
        final brightness = value.round().clamp(
          manualBrightnessMin,
          manualBrightnessMax,
        );
        return _single('manual_brightness', brightness);
      case 'standbyDelay':
        if (value is! num) return null;
        final minutes = value.round().clamp(standbyDelayMin, standbyDelayMax);
        return _single('standby_delay', minutes);
    }
    final identifier = setting[key];
    if (identifier == null) return null;
    final scale = dpScale[identifier];
    if (scale != null && value is num) {
      return _single(identifier, (value * scale).round());
    }
    return _single(identifier, value);
  }

  /// Minutes past midnight for a `HH:MM` label, or null when it does not parse.
  static int? minutesOfDay(String label) {
    final parts = label.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts.first);
    final minute = int.tryParse(parts.last);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return hour * 60 + minute;
  }

  /// `HH:MM` for minutes past midnight, or null when out of range.
  ///
  /// The DP allows 1440, which is midnight at the far end of the day; it maps
  /// back onto `00:00`.
  static String? clockLabel(int minutes) {
    if (minutes < 0 || minutes > 1440) return null;
    final wrapped = minutes % 1440;
    final hour = (wrapped ~/ 60).toString().padLeft(2, '0');
    final minute = (wrapped % 60).toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  static Map<int, Object>? _periodDps(
    String startIdentifier,
    String endIdentifier,
    Object value,
  ) {
    if (value is! String) return null;
    final parts = value.split('-');
    if (parts.length != 2) return null;
    final start = minutesOfDay(parts.first);
    final end = minutesOfDay(parts.last);
    if (start == null || end == null) return null;
    final startId = dp[startIdentifier];
    final endId = dp[endIdentifier];
    if (startId == null || endId == null) return null;
    return <int, Object>{startId: start, endId: end};
  }

  static Map<int, Object>? _single(String identifier, Object value) {
    final id = dp[identifier];
    return id == null ? null : <int, Object>{id: value};
  }
}
