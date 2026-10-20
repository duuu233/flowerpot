/// App 接收到的 OTA 里程碑。只诊断，不控制升级、重试、轮询或界面状态。
/// 仅在启用调试的构建中创建；不记录设备标识、地址、账号和凭证。
class OtaTimingTrace {
  OtaTimingTrace({
    required this.attempt,
    required DateTime Function() clock,
    required void Function(String) emit,
  }) : _clock = clock,
       _emit = emit,
       _startedAt = clock();

  final int attempt;
  final DateTime Function() _clock;
  final void Function(String) _emit;
  final DateTime _startedAt;
  DateTime? _previousAt;
  final Set<String> _events = {};

  /// 相同里程碑只记录第一次，重复 SDK 快照不会刷屏或移动时间基线。
  /// 使用 App 接收时间；不能当成固件内部下载、烧录或重启的精确耗时。
  void mark(String event, {String? detail}) {
    if (!_events.add(event)) return;
    final now = _clock();
    int elapsed(DateTime from) =>
        now.isBefore(from) ? 0 : now.difference(from).inMilliseconds;
    _emit(
      '[ota-timing] attempt=$attempt event=$event '
      'elapsedMs=${elapsed(_startedAt)} '
      'sincePreviousMs=${elapsed(_previousAt ?? _startedAt)}'
      '${detail == null ? "" : " $detail"}',
    );
    _previousAt = now;
  }
}
