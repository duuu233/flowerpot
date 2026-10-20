import 'package:flowerpot/src/tuya/ota_timing_trace.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'milestones keep initial timing and deduplicate repeated SDK snapshots',
    () {
      var now = DateTime(2026, 10, 20, 10);
      final lines = <String>[];
      final trace = OtaTimingTrace(
        attempt: 7,
        clock: () => now,
        emit: lines.add,
      );
      trace.mark('start');
      now = now.add(const Duration(seconds: 8));
      trace.mark('first_progress', detail: 'percent=1');
      now = now.add(const Duration(seconds: 8));
      trace.mark('first_progress', detail: 'percent=1');
      now = now.add(const Duration(seconds: 80));
      trace.mark('installing', detail: 'percent=96');
      now = now.add(const Duration(seconds: 24));
      trace.mark('result_success');
      expect(lines, hasLength(4));
      expect(lines[1], contains('elapsedMs=8000 sincePreviousMs=8000'));
      expect(lines[2], contains('elapsedMs=96000 sincePreviousMs=88000'));
      expect(lines[3], contains('elapsedMs=120000 sincePreviousMs=24000'));
      expect(lines.every((line) => line.contains('attempt=7')), isTrue);
    },
  );

  test('an adjusted wall clock cannot emit negative elapsed durations', () {
    var now = DateTime(2026, 10, 20, 10);
    final lines = <String>[];
    final trace = OtaTimingTrace(attempt: 1, clock: () => now, emit: lines.add);
    trace.mark('start');
    now = now.subtract(const Duration(minutes: 1));
    trace.mark('first_progress');
    expect(lines.last, contains('elapsedMs=0 sincePreviousMs=0'));
  });
}
