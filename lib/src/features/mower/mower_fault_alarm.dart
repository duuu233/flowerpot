import 'dart:convert';

/// DP111 四层原始位域；同一个位值必须按层解释。
class MowerFaultAlarm {
  const MowerFaultAlarm({
    required this.device,
    required this.error,
    required this.function,
    required this.circularize,
  });
  final int device;
  final int error;
  final int function;
  final int circularize;

  static MowerFaultAlarm? parse(Object? raw) {
    try {
      final data = raw is String ? jsonDecode(raw) : raw;
      if (data is! Map) return null;
      final values = <int>[];
      for (final key in ['device', 'error', 'function', 'circularize']) {
        final value = data[key];
        if (value is! int || value < 0 || value > 0xffffffff) return null;
        values.add(value);
      }
      return MowerFaultAlarm(
        device: values[0],
        error: values[1],
        function: values[2],
        circularize: values[3],
      );
    } on FormatException {
      return null;
    }
  }

  Map<String, int> get layers => {
    'device': device,
    'error': error,
    'function': function,
    'circularize': circularize,
  };

  /// code 26 只定位 device / error，通知层仅补边界信号的已知升级路径。
  List<String> get recoveryMessages {
    final messages = <String>[];
    void add(String layer, int mask, String text) {
      if ((layers[layer]! & mask) != 0) messages.add(text);
    }

    add('device', 1, '电池异常，请断电重启并检查充电；仍提示请联系售后');
    add('device', 2, '姿态传感器异常，请断电重启；仍提示请联系售后');
    add('device', 4, '存储异常，请断电重启；仍提示请联系售后');
    add('device', 8, '左轮电机通信异常，请断电重启；仍提示请联系售后');
    add('device', 16, '右轮电机通信异常，请断电重启；仍提示请联系售后');
    add('device', 32, '刀盘电机通信异常，请断电重启；仍提示请联系售后');
    add('error', 1, '机器姿态异常，请把它扶正放平');
    add('error', 2, '机器被抬起，请放回地面并合上盖子');
    if ((error & 4) != 0 ||
        (error == 0 && (circularize & (16 | 131072 | 262144)) != 0)) {
      messages.add('请检查边界线供电，并把机器放回线内');
    }
    add('error', 8 | 16 | 32, '左轮异常，请清理缠绕物/障碍物并等冷却');
    add('error', 64 | 128 | 256, '右轮异常，请清理缠绕物/障碍物并等冷却');
    add('error', 512 | 1024 | 2048 | 4096, '刀盘异常，请清理刀盘下方异物并等冷却');
    add('error', 16384, '机器在割草区域外，请移回界内再启动');
    add('error', 32768, '请把机器移到边界线内并离开充电桩，再进行定点作业');
    return messages;
  }

  String get recoveryMessage {
    final messages = recoveryMessages;
    if (messages.isNotEmpty) {
      final more = messages.length > 3 ? '\n另有故障未排除，请逐项检查设备。' : '';
      return '以下故障尚未排除：\n${messages.take(3).join('\n')}$more';
    }
    if ((device & ~64) != 0 || (error & ~8192) != 0) {
      return '设备报告了未识别的残留故障，请检查设备并联系售后。';
    }
    return '暂未检测到残留故障，请等待1～2秒后重新操作。';
  }
}
