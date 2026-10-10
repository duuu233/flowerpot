import 'dart:convert';

/// V2.6 DP115 回执。序号由设备生成，与 App 的发送队列序号无关。
class MowerCommandResult {
  const MowerCommandResult({
    required this.code,
    required this.seq,
    required this.dp,
    this.value,
  });

  final int code;
  final int seq;
  final int dp;
  final int? value;

  static MowerCommandResult? parse(Object? raw) {
    try {
      final data = raw is String ? jsonDecode(raw) : raw;
      if (data is! Map) return null;
      final code = _integer(data['code']);
      final seq = _integer(data['seq']);
      final dp = _integer(data['dp']);
      final value = _integer(data['val']);
      if (code == null ||
          code < 0 ||
          code > 255 ||
          seq == null ||
          seq < 0 ||
          seq > 255 ||
          dp == null ||
          dp < 1 ||
          dp > 255 ||
          (data.containsKey('val') && value == null)) {
        return null;
      }
      return MowerCommandResult(code: code, seq: seq, dp: dp, value: value);
    } on FormatException {
      return null;
    }
  }

  static int? _integer(Object? value) => value is int ? value : null;

  /// 产品要求小于16不弹；未定义或非状态类的拒绝码不推测处理动作。
  String? get rejectionMessage => code < 16
      ? null
      : switch (code) {
          16 => '机器已关机',
          17 => '开机自检中，请稍候',
          18 => '设备升级中，请稍后再试',
          19 => '机器处于急停',
          21 => '请盖上盖子',
          22 => '面板已锁定，请先解锁',
          23 => '请松开急停按钮',
          24 => '机器正在找线，请稍候或放回线内',
          25 => '检查边界线供电/机器位置',
          26 => '请先排除机器故障',
          _ => '操作未生效（码 $code）',
        };
}
