import 'dart:async';

import 'package:flutter/foundation.dart';

/// Reusable resend lock shared by login, registration and password reset.
class VerificationCodeCountdown extends ChangeNotifier {
  VerificationCodeCountdown({this.totalSeconds = 60});

  final int totalSeconds;
  Timer? _timer;
  int _remaining = 0;

  int get remaining => _remaining;
  bool get active => _remaining > 0;
  String get label => active ? '$_remaining秒后重试' : '获取验证码';

  void start() {
    _timer?.cancel();
    _remaining = totalSeconds;
    notifyListeners();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remaining <= 1) {
        timer.cancel();
        _timer = null;
        _remaining = 0;
      } else {
        _remaining--;
      }
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
