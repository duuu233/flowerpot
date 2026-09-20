import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../../../state.dart';
import '../../../tuya/tuya_config.dart';
import '../mower_demo.dart';
import '../mower_device.dart';
import 'widgets/mower_bottom_nav.dart';
import 'widgets/mower_card.dart';

/// 消息通知（`割草机-消息通知.png`）。
///
/// 从设置页进来，底部导航照旧画着、停在「设置」那一栏；点「首页 / 割草计划」时
/// 先退回外壳再切到那一栏（[onTabRequested]），而不是在这一页上面再叠一层。
///
/// ## ⚠️ 这一页没有 DP
///
/// 三个分类页（日志 / 提醒 / 告警）要的是**涂鸦消息中心**的数据，不是功能点——
/// 所以进页面按 2026-09-18 的口径提示一句「当前还没有支持的 DPID」，上面那份列表仍是
/// 稿子上的静态数据。
///
/// ## 页面底部的调试板（2026-09-18 产品追加）
///
/// 要回答的问题是：**涂鸦返回的设备消息里到底有没有"类型"字段**，有的话这三个分类页
/// 才做得出来。所以底部挂了一块调试板：点一下就去拉涂鸦消息中心，把每条消息的
/// **所有字段原样打印**（不映射、不挑选），并标出键名里带 `type` 的那些。
/// 顺带按 `msgSrcId` 去已绑定设备里找归属，标出它是不是目标产品
/// （[TuyaConfig.broadcastId] `ehbx83xdh9jkmxvz`——设备自己上报的那个产品标识）。
class MowerMessagesPage extends StatefulWidget {
  const MowerMessagesPage({required this.onTabRequested, super.key});

  /// 退回外壳之后要切到哪一栏。
  final ValueChanged<MowerTab> onTabRequested;

  @override
  State<MowerMessagesPage> createState() => _MowerMessagesPageState();
}

class _MowerMessagesPageState extends State<MowerMessagesPage> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = FlowerpotScope.of(context);
      state.logPageEntry('割草机-消息通知');
      MowerDevice.instance.logUnsupported(state, '消息通知');
      showAppMessage(context, '当前还没有支持的 DPID', tone: AppMessageTone.info);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: AppPageScaffold(
        appBar: const AppPageHeader(title: '消息通知', leading: AppBackButton()),
        body: SingleChildScrollView(
          key: const Key('mower-messages-scroll-view'),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _CategoryTabs(
                current: _tab,
                onChanged: (index) => setState(() => _tab = index),
              ),
              const SizedBox(height: 12),
              const _DateFilterCard(),
              const SizedBox(height: 12),
              for (final message in MowerDemoMessages.items) ...<Widget>[
                _MessageCard(message: message),
                const SizedBox(height: 12),
              ],
              const _MessageDebugPanel(),
            ],
          ),
        ),
      ),
      bottomNavigationBar: MowerBottomNav(
        current: MowerTab.settings,
        onTap: (tab) {
          Navigator.of(context).pop();
          if (tab != MowerTab.settings) widget.onTabRequested(tab);
        },
      ),
    );
  }
}

/// 日志 / 提醒 / 告警。稿子只画了「日志」那一档的内容，另外两档同版式空着——
/// 这里点得动、但列表不换数据，免得凭空造两批不存在的消息。
class _CategoryTabs extends StatelessWidget {
  const _CategoryTabs({required this.current, required this.onChanged});

  final int current;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .9),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: <Widget>[
          for (var i = 0; i < MowerDemoMessages.tabs.length; i++)
            Expanded(
              child: GestureDetector(
                key: Key('mower-messages-tab-$i'),
                onTap: () => onChanged(i),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == current
                        ? MowerColors.brand
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    MowerDemoMessages.tabs[i],
                    style: TextStyle(
                      color: i == current ? Colors.white : MowerColors.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DateFilterCard extends StatelessWidget {
  const _DateFilterCard();

  @override
  Widget build(BuildContext context) {
    return MowerCard(
      color: Colors.white.withValues(alpha: .92),
      radius: 15,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SizedBox(
        height: 52,
        child: Row(
          children: <Widget>[
            const Expanded(
              child: Text(
                '日期筛选',
                style: TextStyle(
                  color: MowerColors.ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const Text(
              MowerDemoMessages.dateFilter,
              style: TextStyle(color: MowerColors.brand, fontSize: 15),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.arrow_drop_down_rounded,
              size: 22,
              color: MowerColors.brand.withValues(alpha: .9),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.message});

  final MowerMessage message;

  @override
  Widget build(BuildContext context) {
    return MowerCard(
      color: Colors.white.withValues(alpha: .86),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  message.title,
                  style: const TextStyle(
                    color: MowerColors.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                message.time,
                style: const TextStyle(
                  color: MowerColors.inkSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            message.detail,
            style: const TextStyle(
              color: MowerColors.inkSecondary,
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// 涂鸦消息中心调试板（**排查设施，不是产品功能**）。
///
/// 点「拉取」→ 原生按**设备 ID** 调 `getMessageListByMsgSrcId`、把每条消息 bean 的
/// 所有无参 getter dump 上来（见 `MainActivity.deviceMessages`）。这里只负责**原样打印**：
///
/// - 每条消息的全部字段（键名里带 `type` 的会被标成品牌色，那就是问题的答案）；
/// - 拿不到时把原生的诊断行（试过哪个重载、MessageType 有哪些常量、这个类上有哪些方法）打出来；
/// - 长按整块复制，产品截图/贴给设备端都行。
///
/// ⚠️ **必须按设备取**（产品口径 2026-09-20）：标准的 `getMessageList` 是聚合结果，
/// 按它分页拿不到某台设备的全量消息 —— 之前调的就是它，打出来的东西明显不对。
/// 所以这块板上有设备 ID 输入框（默认填已绑定的第一台）和消息类型三选一
/// （`MSG_REPORT` 设备消息 / `MSG_FAMILY` 家庭 / `MSG_NOTIFY` 通知）。
class _MessageDebugPanel extends StatefulWidget {
  const _MessageDebugPanel();

  @override
  State<_MessageDebugPanel> createState() => _MessageDebugPanelState();
}

class _MessageDebugPanelState extends State<_MessageDebugPanel> {
  /// 涂鸦的消息类型（解包核对：`MessageType` 只有三个常量，`getValue()` 依次是 1 / 2 / 3）。
  ///
  /// 消息中心的三档就是**告警 / 家庭 / 通知**，设备消息推送落在告警那一档（`MSG_REPORT`），
  /// 所以默认选它。`ALL` 是本地约定：原生会把三档依次取一遍，结果里 `perType` 写明每档几条——
  /// 拉不到东西时用它判断「是这台设备没有」还是「哪一档都空」。
  static const Map<String, String> _types = <String, String>{
    'MSG_REPORT': '告警',
    'MSG_FAMILY': '家庭',
    'MSG_NOTIFY': '通知',
    'ALL': '三档都试',
  };

  final TextEditingController _deviceId = TextEditingController();
  bool _loading = false;
  bool _prefilled = false;
  String _msgType = 'MSG_REPORT';
  Map<String, Object?>? _result;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 默认填已绑定的第一台设备，省得每次手打 22 位 ID；填错了直接改这一格。
    if (_prefilled) return;
    final devices = FlowerpotScope.of(context).devices;
    if (devices.isEmpty) return;
    _deviceId.text = devices.first.id;
    _prefilled = true;
  }

  @override
  void dispose() {
    _deviceId.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final state = FlowerpotScope.of(context);
    final deviceId = _deviceId.text.trim();
    if (deviceId.isEmpty) {
      showAppMessage(
        context,
        '先填设备 ID（涂鸦的 msgSrcId）',
        tone: AppMessageTone.info,
      );
      return;
    }
    setState(() => _loading = true);
    final data = await state.loadDeviceMessages(
      deviceId: deviceId,
      msgType: _msgType,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _result = data;
    });
  }

  /// 已绑定设备：devId → productId，用来判断某条消息是不是目标产品的。
  Map<String, String> _deviceProducts(FlowerpotState state) => <String, String>{
    for (final device in state.devices) device.id: device.productId,
  };

  String get _plainText {
    final result = _result;
    if (result == null) return '';
    final buffer = StringBuffer()
      ..writeln('ok=${result['ok']}')
      ..writeln('instance=${result['instance']}')
      ..writeln('method=${result['method']}')
      ..writeln('msgSrcId=${result['msgSrcId']}')
      ..writeln('msgType=${result['msgType']}')
      ..writeln('perType=${result['perType']}')
      ..writeln('count=${result['count']}')
      ..writeln('totalCount=${result['totalCount']}');
    final items = (result['items'] as List<Object?>?) ?? const <Object?>[];
    for (var i = 0; i < items.length; i++) {
      buffer.writeln('--- 第 ${i + 1} 条 ---');
      final item = items[i];
      if (item is Map) {
        item.forEach((key, value) => buffer.writeln('$key = $value'));
      } else {
        buffer.writeln('$item');
      }
    }
    for (final line in (result['diagnostic'] as List<Object?>?) ?? const <Object?>[]) {
      buffer.writeln('· $line');
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final state = FlowerpotScope.of(context);
    final result = _result;
    final items = (result?['items'] as List<Object?>?) ?? const <Object?>[];
    final diagnostic =
        (result?['diagnostic'] as List<Object?>?) ?? const <Object?>[];
    final products = _deviceProducts(state);
    return GestureDetector(
      onLongPress: () {
        if (_plainText.isEmpty) return;
        Clipboard.setData(ClipboardData(text: _plainText));
        showAppMessage(context, '已复制调试板内容');
      },
      child: MowerCard(
        key: const Key('mower-messages-debug-panel'),
        color: Colors.white.withValues(alpha: .92),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text(
              '涂鸦消息调试板',
              style: TextStyle(
                color: MowerColors.ink,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '按设备 ID 拉一次涂鸦消息中心（getMessageListByMsgSrcId，默认取告警那一档），'
              '把每条消息的字段原样打印，用来确认后台配的推送等级落在哪个字段'
              '（目标产品 ${TuyaConfig.broadcastId}）。拉不到就选「三档都试」。长按可复制。',
              style: const TextStyle(
                color: MowerColors.inkSecondary,
                fontSize: 12,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('mower-messages-debug-device'),
              controller: _deviceId,
              style: const TextStyle(
                color: MowerColors.ink,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
              decoration: const InputDecoration(
                labelText: '设备 ID（msgSrcId）',
                isDense: true,
                border: OutlineInputBorder(),
                labelStyle: TextStyle(
                  color: MowerColors.inkSecondary,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: <Widget>[
                for (final entry in _types.entries)
                  ChoiceChip(
                    key: Key('mower-messages-debug-type-${entry.key}'),
                    label: Text(
                      entry.value,
                      style: const TextStyle(fontSize: 12),
                    ),
                    selected: _msgType == entry.key,
                    onSelected: (_) => setState(() => _msgType = entry.key),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 40,
              child: FilledButton(
                key: const Key('mower-messages-debug-load'),
                onPressed: _loading ? null : () => unawaited(_load()),
                style: FilledButton.styleFrom(
                  backgroundColor: MowerColors.brand,
                  foregroundColor: Colors.white,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(10)),
                  ),
                ),
                child: Text(_loading ? '拉取中…' : '拉取涂鸦消息'),
              ),
            ),
            if (result != null) ...<Widget>[
              const SizedBox(height: 12),
              SelectableText(
                'ok=${result['ok']}  count=${result['count'] ?? 0}'
                '  totalCount=${result['totalCount'] ?? '-'}\n'
                'msgSrcId=${result['msgSrcId'] ?? '-'}'
                '  msgType=${result['msgType'] ?? '-'}\n'
                'perType=${result['perType'] ?? '-'}\n'
                'instance=${result['instance'] ?? '-'}\n'
                'method=${result['method'] ?? '-'}',
                style: const TextStyle(
                  color: MowerColors.ink,
                  fontSize: 11,
                  height: 1.5,
                  fontFamily: 'monospace',
                ),
              ),
              for (var i = 0; i < items.length; i++)
                _MessageDump(
                  index: i,
                  raw: items[i],
                  deviceProducts: products,
                ),
              if (diagnostic.isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                const Text(
                  '诊断',
                  style: TextStyle(
                    color: MowerColors.inkSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                for (final line in diagnostic)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: SelectableText(
                      '· $line',
                      style: const TextStyle(
                        color: MowerColors.inkSecondary,
                        fontSize: 11,
                        height: 1.45,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// 一条消息的字段 dump。键名里带 `type` 的标成品牌色——那就是要找的东西。
class _MessageDump extends StatelessWidget {
  const _MessageDump({
    required this.index,
    required this.raw,
    required this.deviceProducts,
  });

  final int index;
  final Object? raw;
  final Map<String, String> deviceProducts;

  @override
  Widget build(BuildContext context) {
    if (raw is! Map) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: SelectableText('第 ${index + 1} 条：$raw'),
      );
    }
    final map = raw! as Map;
    final source = map['msgSrcId']?.toString() ?? '';
    final product = deviceProducts[source];
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '第 ${index + 1} 条'
            '${product == null ? '' : '　msgSrcId 归属产品 $product'
                '${product == TuyaConfig.broadcastId ? '（就是目标产品）' : ''}'}',
            style: const TextStyle(
              color: MowerColors.brand,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          for (final entry in map.entries)
            SelectableText(
              '${entry.key} = ${entry.value}',
              style: TextStyle(
                color: entry.key.toString().toLowerCase().contains('type')
                    ? MowerColors.brand
                    : MowerColors.ink,
                fontSize: 11,
                height: 1.5,
                fontFamily: 'monospace',
                fontWeight: entry.key.toString().toLowerCase().contains('type')
                    ? FontWeight.w700
                    : FontWeight.w400,
              ),
            ),
        ],
      ),
    );
  }
}
