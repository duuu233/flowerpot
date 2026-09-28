import 'package:flutter/material.dart';

import '../../../design_system/design_system.dart';
import '../../messages/device_messages_view.dart';
import '../../messages/message_monitor_console.dart';

/// 花盆的消息通知（2026-09-28 产品：「给花盆也加一个消息通知页面，照割草机的做」）。
///
/// 入口在设备「设置」页功能列表里的「消息通知」。列表本身和割草机是同一个 [DeviceMessagesView]：
/// 三栏都来自涂鸦消息中心（这台设备的告警档，翻页取全），按平台推送规则的等级分——
/// **日志 = 通知、提醒 = 轻微、告警 = 严重**，认不出等级的归告警；日期筛选默认全部，来推送自动重拉。
/// 花盆没有底部导航。
///
/// 列表下面挂着 [MessageMonitorConsole]（同日产品追加，排查设施，和割草机共用，只是参数不一样）：
/// 涂鸦后台「设备消息监控」里那批记录（[_records]）原样写死，按记录里的设备 / 触发时间写死去调接口，
/// 逐条对 App 这边查不查得到。联调完删掉这一个 `footer` 即可。
class DeviceMessagesPage extends StatelessWidget {
  const DeviceMessagesPage({
    required this.deviceId,
    super.key,
    this.showMonitorConsole = true,
  });

  final String deviceId;

  /// 底部挂不挂调试台（用例里只看列表时关掉）。
  final bool showMonitorConsole;

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      appBar: const AppPageHeader(title: '消息通知', leading: AppBackButton()),
      background: AppPageBackground.standard,
      body: DeviceMessagesView(
        deviceId: deviceId,
        pageName: '花盆-消息通知',
        keyPrefix: 'device-messages',
        logsEntry: false,
        footer: showMonitorConsole
            ? MessageMonitorConsole(
                title: '调试台 · 花盆后台消息监控对照',
                deviceIds: <String>[
                  for (final id in <String>{
                    for (final record in _records) record.deviceId,
                  })
                    id,
                ],
                windows: _windows,
                records: _records,
                notes: const <String>[
                  '消息推送等级（粘贴里只有 5 个值，对不上 10 行，原样）：轻微、报警、轻微、报警、轻微；'
                      '处理状态 10 条都是「未处理」',
                ],
              )
            : null,
      ),
    );
  }
}

const String _devA = '6c81cbf961a5074c36s0pq';
const String _devB = '54ca8g6cdf16f0a8be7e9f';
const String _devC = '6c2649322ed1365a00cadl';

/// 产品贴来的涂鸦后台「设备消息监控」10 条（2026-09-28）。「设备ID」一列粘贴时被折行拆开，按拼回来的写；
/// 第 2 条的 `54ca8g6cdf16f0a8be7e9f` 按粘贴原样（22 位，没看到被拆开的前半截）。
/// 「消息推送名称」第 4 条粘贴里是 `ext2`、「所属产品」第 6 条是「化盆test」，都照原样。
const List<MonitorRecord> _records = <MonitorRecord>[
  MonitorRecord(
    pushId: 'GYjoVtpHsqHjpZbc',
    name: 'text2',
    content: 'text2',
    deviceId: _devA,
    product: '花盆test',
    account: 'YS391****',
    triggeredAt: '2026-09-23 10:47:32',
  ),
  MonitorRecord(
    pushId: 'GYjoVtpHsqHjpZbc',
    name: 'text2',
    content: 'text2',
    deviceId: _devB,
    product: '花盆test',
    account: 'YS444****',
    triggeredAt: '2026-09-23 10:45:32',
  ),
  MonitorRecord(
    pushId: 'GYjoVtpHsqHjpZbc',
    name: 'text2',
    content: 'text2',
    deviceId: _devC,
    product: '花盆test',
    account: 'YS556****',
    triggeredAt: '2026-09-18 22:43:32',
  ),
  MonitorRecord(
    pushId: 'GYjoVtpHsqHjpZbc',
    name: 'ext2',
    content: 'text2',
    deviceId: _devC,
    product: '花盆test',
    account: 'YS556****',
    triggeredAt: '2026-09-18 22:43:22',
  ),
  MonitorRecord(
    pushId: 'SMmploujUsOI26FQ',
    name: 'text3',
    content: 'text3',
    deviceId: _devC,
    product: '花盆test',
    account: 'YS556****',
    triggeredAt: '2026-09-18 22:43:22',
  ),
  MonitorRecord(
    pushId: 'GYjoVtpHsqHjpZbc',
    name: 'text2',
    content: 'text2',
    deviceId: _devC,
    product: '化盆test',
    account: 'YS556****',
    triggeredAt: '2026-09-18 22:43:12',
  ),
  MonitorRecord(
    pushId: 'SMmploujUsOI26FQ',
    name: 'text3',
    content: 'text3',
    deviceId: _devC,
    product: '花盆test',
    account: 'YS556****',
    triggeredAt: '2026-09-18 22:43:12',
  ),
  MonitorRecord(
    pushId: 'GYjoVtpHsqHjpZbc',
    name: 'text2',
    content: 'text2',
    deviceId: _devC,
    product: '花盆test',
    account: 'YS556****',
    triggeredAt: '2026-09-18 22:43:02',
  ),
  MonitorRecord(
    pushId: 'SMmploujUsOI26FQ',
    name: 'text3',
    content: 'text3',
    deviceId: _devC,
    product: '花盆test',
    account: 'YS556****',
    triggeredAt: '2026-09-18 22:43:02',
  ),
  MonitorRecord(
    pushId: 'SMmploujUsOI26FQ',
    name: 'text3',
    content: 'text3',
    deviceId: _devC,
    product: '花盆test',
    account: 'YS556****',
    triggeredAt: '2026-09-18 22:42:52',
  ),
];

/// 记录里的两段触发时间（北京时间），前后各放宽 1 分钟。
final List<MonitorWindow> _windows = <MonitorWindow>[
  (
    label: '北京时间 2026-09-18 22:41:52 ~ 22:44:32',
    start: DateTime.parse('2026-09-18T22:41:52+08:00'),
    end: DateTime.parse('2026-09-18T22:44:32+08:00'),
  ),
  (
    label: '北京时间 2026-09-23 10:44:32 ~ 10:48:32',
    start: DateTime.parse('2026-09-23T10:44:32+08:00'),
    end: DateTime.parse('2026-09-23T10:48:32+08:00'),
  ),
];
