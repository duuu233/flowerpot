import '../../../tuya/tuya_models.dart';

enum BehaviorScheduleKind { nap, night }

class BehaviorClockTime {
  const BehaviorClockTime(this.hour, this.minute);

  factory BehaviorClockTime.parse(
    String value, {
    required BehaviorClockTime fallback,
  }) {
    final parts = value.split(':');
    if (parts.length != 2) return fallback;
    final hour = int.tryParse(parts.first);
    final minute = int.tryParse(parts.last);
    if (hour == null || minute == null) return fallback;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return fallback;
    return BehaviorClockTime(hour, minute);
  }

  final int hour;
  final int minute;

  int get totalMinutes => hour * 60 + minute;

  String get label =>
      '${hour.toString().padLeft(2, '0')}:'
      '${minute.toString().padLeft(2, '0')}';
}

class BehaviorSchedulePageModel {
  const BehaviorSchedulePageModel({
    required this.kind,
    required this.title,
    required this.enabled,
    required this.descriptionLines,
    required this.start,
    required this.end,
  });

  final BehaviorScheduleKind kind;
  final String title;
  final bool enabled;
  final List<String> descriptionLines;
  final BehaviorClockTime start;
  final BehaviorClockTime end;

  String get status => enabled ? '已开启' : '已关闭';
  String get description => descriptionLines.join('\n');
  String get startLabel => start.label;
  String get endLabel =>
      end.totalMinutes <= start.totalMinutes ? '次日${end.label}' : end.label;
  String get period => '${start.label}-${end.label}';
}

class BehaviorSettingsPageModel {
  const BehaviorSettingsPageModel({required this.nap, required this.night});

  factory BehaviorSettingsPageModel.fromSettings(
    DeviceControlSettings settings,
  ) {
    final napPeriod = _period(
      settings.napPeriod,
      fallbackStart: const BehaviorClockTime(12, 0),
      fallbackEnd: const BehaviorClockTime(13, 30),
    );
    final nightPeriod = _period(
      settings.nightPeriod,
      fallbackStart: const BehaviorClockTime(22, 0),
      fallbackEnd: const BehaviorClockTime(7, 30),
    );
    return BehaviorSettingsPageModel(
      nap: BehaviorSchedulePageModel(
        kind: BehaviorScheduleKind.nap,
        title: '中午小憩',
        enabled: settings.napEnabled,
        descriptionLines: const <String>['让 YSplanter 在正午稍作休息，可自定义她的小憩时', '间。'],
        start: napPeriod.$1,
        end: napPeriod.$2,
      ),
      night: BehaviorSchedulePageModel(
        kind: BehaviorScheduleKind.night,
        title: '夜间睡眠',
        enabled: settings.nightEnabled,
        descriptionLines: const <String>['设定 YSplanter 的夜间作息选择她的入睡与醒来时间。'],
        start: nightPeriod.$1,
        end: nightPeriod.$2,
      ),
    );
  }

  final BehaviorSchedulePageModel nap;
  final BehaviorSchedulePageModel night;

  static (BehaviorClockTime, BehaviorClockTime) _period(
    String value, {
    required BehaviorClockTime fallbackStart,
    required BehaviorClockTime fallbackEnd,
  }) {
    final parts = value.split('-');
    if (parts.length != 2) return (fallbackStart, fallbackEnd);
    return (
      BehaviorClockTime.parse(parts.first, fallback: fallbackStart),
      BehaviorClockTime.parse(parts.last, fallback: fallbackEnd),
    );
  }
}
