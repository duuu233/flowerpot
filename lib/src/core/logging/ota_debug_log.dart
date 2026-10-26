import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../config/debug_log_gate.dart';

/// OTA 完整调试日志，逐行追加到手机文件（2026-10-26 产品：OTA 失败反复出现，要精确定位是哪一环）。
///
/// 一次升级从检查、发起、原生 SDK 原始回调 / 轮询快照、App 状态判定、版本核验、接回，到界面上
/// 弹了什么、用户点了什么，全部按时间顺序落在同一个文件里。来源标在方括号里：
/// - `native`：原生桥直接转来的 SDK 原始字段（升级信息列表、状态码、进度、错误码 / 文案、轮询结果）；
/// - `sdk`：Dart 收到的原生 OTA 事件原样内容（解析前）；
/// - `app`：状态层的判定（发起、进度合并、核验、接回、超时、设备 DP 上报）；
/// - `ui`：进度弹层显示的内容、升级提醒是否弹出、用户的选择。
///
/// 位置：Android 为应用外部文件目录 `Android/data/<包名>/files/ota_logs/`（USB / adb 可取），
/// 取不到时退到应用文档目录；iOS 为应用文档目录 `ota_logs/`（Info.plist 已开文件共享，「文件」App
/// 可见）。每天一个 `ota-YYYY-MM-DD.log`，保留 [keepDays] 天。
///
/// 与其它联调能力同一个总闸：用户包（`APP_DEBUG_TOOLS=false`）不写。只记设备 ID 末 6 位，不记账号、
/// 令牌和地址。写文件失败只影响日志本身，不影响升级。
abstract final class OtaDebugLog {
  static const int keepDays = 7;
  static const int _recentLimit = 2000;

  /// 单元测试里不碰平台目录；用例需要时把 [enabledForTest] 打开并换掉 [directoryProvider]。
  static final bool _underTest = !kIsWeb &&
      Platform.environment.containsKey('FLUTTER_TEST');
  @visibleForTesting
  static bool enabledForTest = false;

  static bool get enabled =>
      DebugLogGate.enabled && (!_underTest || enabledForTest);

  @visibleForTesting
  static Future<Directory?> Function() directoryProvider = _defaultDirectory;
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  static Future<void> _queue = Future<void>.value();
  static bool _pruned = false;
  static String? _lastPath;
  static final List<String> _recent = <String>[];

  static void native(String line, {String? deviceId}) =>
      write('native', line, deviceId: deviceId);
  static void sdk(String line, {String? deviceId}) =>
      write('sdk', line, deviceId: deviceId);
  static void app(String line, {String? deviceId}) =>
      write('app', line, deviceId: deviceId);
  static void ui(String line, {String? deviceId}) =>
      write('ui', line, deviceId: deviceId);

  static void write(String source, String line, {String? deviceId}) {
    if (!enabled) return;
    final now = clock();
    final device = deviceId == null || deviceId.isEmpty
        ? ''
        : ' dev=${maskDevice(deviceId)}';
    final text = '${_timestamp(now)} [$source]$device $line';
    _recent.add(text);
    if (_recent.length > _recentLimit) _recent.removeAt(0);
    _queue = _queue.then((_) => _append(now, text));
  }

  /// 设备 ID 只留末 6 位，够在同一部手机上区分设备。
  static String maskDevice(String deviceId) => deviceId.length <= 6
      ? deviceId
      : '…${deviceId.substring(deviceId.length - 6)}';

  /// 本次运行内存里最近的日志（最多 2000 行），供联调面板复制。
  static String recentText() => _recent.join('\n');

  /// 今天的日志文件路径；目录取不到为 null。
  static Future<String?> currentPath() async {
    await _queue;
    return _lastPath ?? (await _fileFor(clock()))?.path;
  }

  /// 等排队中的写入落盘（用例用）。
  @visibleForTesting
  static Future<void> flush() => _queue;

  @visibleForTesting
  static void resetForTest() {
    _queue = Future<void>.value();
    _pruned = false;
    _lastPath = null;
    _recent.clear();
    enabledForTest = false;
    directoryProvider = _defaultDirectory;
    clock = DateTime.now;
  }

  static Future<void> _append(DateTime now, String text) async {
    try {
      final file = await _fileFor(now);
      if (file == null) return;
      await file.writeAsString('$text\n', mode: FileMode.append, flush: true);
      _lastPath = file.path;
      if (!_pruned) {
        _pruned = true;
        await _prune(file.parent, now);
      }
    } on Object catch (error) {
      debugPrint('[ota-log] 写入失败：$error');
    }
  }

  static Future<File?> _fileFor(DateTime now) async {
    final base = await directoryProvider();
    if (base == null) return null;
    final dir = Directory('${base.path}${Platform.pathSeparator}ota_logs');
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}${Platform.pathSeparator}ota-${_date(now)}.log');
  }

  static Future<void> _prune(Directory dir, DateTime now) async {
    final oldest = _date(now.subtract(const Duration(days: keepDays - 1)));
    await for (final entry in dir.list()) {
      if (entry is! File) continue;
      final name = entry.uri.pathSegments.last;
      final match = RegExp(r'^ota-(\d{4}-\d{2}-\d{2})\.log$').firstMatch(name);
      if (match != null && match.group(1)!.compareTo(oldest) < 0) {
        await entry.delete();
      }
    }
  }

  static Future<Directory?> _defaultDirectory() async {
    try {
      if (!kIsWeb && Platform.isAndroid) {
        final external = await getExternalStorageDirectory();
        if (external != null) return external;
      }
      return await getApplicationDocumentsDirectory();
    } on Object {
      return null;
    }
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
  static String _date(DateTime t) => '${t.year}-${_two(t.month)}-${_two(t.day)}';
  static String _timestamp(DateTime t) =>
      '${_date(t)} ${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}.'
      '${t.millisecond.toString().padLeft(3, '0')}';
}
