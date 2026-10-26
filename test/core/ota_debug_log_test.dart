import 'dart:io';

import 'package:flowerpot/src/core/logging/ota_debug_log.dart';
import 'package:flowerpot/src/tuya/ota_progress_layer.dart';
import 'package:flutter_test/flutter_test.dart';

/// OTA 调试日志写手机文件（2026-10-26 产品）：按天一个文件、保留 7 天、设备 ID 只留末 6 位。
void main() {
  setUp(OtaDebugLog.resetForTest);
  tearDown(OtaDebugLog.resetForTest);

  test('按时间顺序追加到当天文件，带来源和脱敏设备ID，清掉7天前的文件', () async {
    final dir = await Directory.systemTemp.createTemp('ota_log_test');
    addTearDown(() => dir.delete(recursive: true));
    final logs = Directory('${dir.path}${Platform.pathSeparator}ota_logs')
      ..createSync();
    final old = File('${logs.path}${Platform.pathSeparator}ota-2026-10-19.log')
      ..writeAsStringSync('old\n');
    final kept = File('${logs.path}${Platform.pathSeparator}ota-2026-10-20.log')
      ..writeAsStringSync('kept\n');
    final other = File('${logs.path}${Platform.pathSeparator}notes.txt')
      ..writeAsStringSync('x');

    OtaDebugLog.enabledForTest = true;
    OtaDebugLog.directoryProvider = () async => dir;
    OtaDebugLog.clock = () => DateTime(2026, 10, 26, 12, 0, 0, 123);

    OtaDebugLog.native('getFirmwareUpgradeInfo → 1 条', deviceId: 'abcdef123456');
    OtaDebugLog.sdk('事件 {status: running}', deviceId: 'abcdef123456');
    OtaDebugLog.app('进度 ← status=running');
    OtaDebugLog.ui('打开升级进度弹层', deviceId: 'abc');
    await OtaDebugLog.flush();

    final today = File('${logs.path}${Platform.pathSeparator}ota-2026-10-26.log');
    final lines = today.readAsLinesSync();
    expect(lines, <String>[
      '2026-10-26 12:00:00.123 [native] dev=…123456 getFirmwareUpgradeInfo → 1 条',
      '2026-10-26 12:00:00.123 [sdk] dev=…123456 事件 {status: running}',
      '2026-10-26 12:00:00.123 [app] 进度 ← status=running',
      '2026-10-26 12:00:00.123 [ui] dev=abc 打开升级进度弹层',
    ]);
    expect(old.existsSync(), isFalse, reason: '超过 7 天');
    expect(kept.existsSync(), isTrue, reason: '第 7 天保留');
    expect(other.existsSync(), isTrue, reason: '不是日志文件不动');
    expect(await OtaDebugLog.currentPath(), today.path);
    expect(OtaDebugLog.recentText().split('\n'), hasLength(4));
  });

  test('总闸关闭（用户包 / 单元测试默认）时不写也不缓存', () async {
    var asked = false;
    OtaDebugLog.directoryProvider = () async {
      asked = true;
      return Directory.systemTemp;
    };
    OtaDebugLog.app('不该写');
    await OtaDebugLog.flush();
    expect(OtaDebugLog.enabled, isFalse);
    expect(OtaDebugLog.recentText(), isEmpty);
    expect(asked, isFalse);
  });

  test('目录取不到时只丢日志，不抛错', () async {
    OtaDebugLog.enabledForTest = true;
    OtaDebugLog.directoryProvider = () async => null;
    OtaDebugLog.app('没有目录');
    await OtaDebugLog.flush();
    expect(await OtaDebugLog.currentPath(), isNull);
    expect(OtaDebugLog.recentText(), contains('没有目录'));
  });

  test('进度层按设备计数，全部关掉才算关闭', () {
    addTearDown(OtaProgressLayer.resetForTest);
    expect(OtaProgressLayer.anyOpen, isFalse);
    OtaProgressLayer.opened('a');
    OtaProgressLayer.opened('a');
    expect(OtaProgressLayer.isOpenFor('a'), isTrue);
    expect(OtaProgressLayer.isOpenFor('b'), isFalse);
    OtaProgressLayer.closed('a');
    expect(OtaProgressLayer.anyOpen, isTrue);
    OtaProgressLayer.closed('a');
    OtaProgressLayer.closed('a');
    expect(OtaProgressLayer.anyOpen, isFalse);
    expect(OtaProgressLayer.isOpenFor(null), isFalse);
  });
}
