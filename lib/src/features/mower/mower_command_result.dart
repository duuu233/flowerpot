import 'dart:convert';

/// DP115 命令结果（V3.0 §5）：code 0 成功、非 0 为拒绝理由码。序号由设备生成，与 App 的发送队列序号无关。
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

  /// 拒绝文案，逐码照《拒绝理由与文案 V1.0》§6 速查表（唯一依据，2026-10-22）。
  ///
  /// 0 成功、1/2 保留未用 → null 不弹；3 是设备内部写失败（非业务拒绝）也要提示重试。
  /// 在桩等待的三种拒绝各自独立：35 有雨（原来也会落 49）、54 电量 <70% 已进入充电等待（新增）、
  /// 49 其余不可打断的在桩等待。26 这里只是兜底，实际按 DP111 定位具体故障（`MowerDevice.commandFaultMessage`）。
  String? get rejectionMessage => code == 3
      ? '操作未生效，请重试'
      : code < 16
      ? null
      : switch (code) {
          16 => '机器已关机',
          17 => '开机自检中，请稍候',
          18 => '固件升级中，暂不接受操作',
          19 => '机器处于急停状态',
          21 => '请合上盖子',
          22 => '机器已锁定',
          23 => '请松开急停按钮',
          24 => '机器正在寻找边界线，请稍候',
          25 => '边界信号丢失，请检查边界线',
          26 => '请先排除机器故障',
          32 => '机器已在充电桩上',
          33 => '机器在界外，请移回界内',
          34 => '电量低，正在充电',
          35 => '雨天暂停中，雨停后自动继续',
          48 => '请先选择工作模式',
          49 => '机器在桩等待中',
          52 => '上次任务已取消，请重新选择模式',
          53 => '设备正忙，请稍后重试',
          54 => '机器电量小于70%，已进入充电等待',
          64 => '参数不在允许范围内',
          65 => '数据长度不正确',
          66 => '数据格式不正确',
          67 => '数据类型不匹配',
          68 => '该功能不支持设置',
          69 => '请先开启自动同步',
          70 => '设备不支持该功能',
          _ => '操作未生效（码 $code）',
        };
}
