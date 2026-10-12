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

  /// 小于16不弹；协议定义的状态、场景、任务、参数码分别提示。
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
          32 => '机器在充电桩上',
          33 => '请把机器移回边界线内',
          34 => '电量低，请先充电',
          35 => '雨天暂停中',
          48 => '请先选择工作模式',
          49 => '机器在桩等待中',
          52 => '上次任务已取消，请重新选择工作模式再启动',
          53 => '设备正忙，请稍后重试',
          64 => '工作参数超出范围，请检查后重试',
          65 => '设置数据长度不正确，请重新设置',
          66 => '设置内容格式不正确，请重新设置',
          67 => '指令类型不匹配，请检查设备配置',
          68 => '该功能只支持读取，无法设置',
          69 => '请先开启自动时间同步，再设置设备时间',
          70 => '设备不支持该功能，请检查配置或固件版本',
          255 => '操作未生效',
          _ => '操作未生效（码 $code）',
        };
}
