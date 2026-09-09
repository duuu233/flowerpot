import 'package:shared_preferences/shared_preferences.dart';

/// Runtime API session with serialized token persistence.
class ApiSession {
  ApiSession({this.storageKey = 'flowerpot.api.userToken'});

  static final ApiSession instance = ApiSession();

  final String storageKey;
  String _userToken = '';
  int _revision = 0;
  int get revision => _revision;
  int _languageCode = 2;
  Future<void> _persistQueue = Future<void>.value();

  String get userToken => _userToken;
  int get languageCode => _languageCode;
  bool get isLoggedIn => _userToken.isNotEmpty;

  void setToken(String token) {
    _revision++;
    _userToken = token.trim();
    _enqueuePersist(_userToken);
  }

  void clear() {
    _revision++;
    _userToken = '';
    _enqueuePersist('');
  }

  Future<bool> restore() async {
    final revision = _revision;
    await _persistQueue;
    try {
      final preferences = await SharedPreferences.getInstance();
      if (revision != _revision) return isLoggedIn;
      _revision++;
      _userToken = preferences.getString(storageKey)?.trim() ?? '';
    } catch (_) {
      if (revision != _revision) return isLoggedIn;
      _revision++;
      _userToken = '';
    }
    return isLoggedIn;
  }

  void setLanguage(String languageCode) {
    _languageCode = switch (languageCode.toLowerCase()) {
      'en' => 1,
      'zh-hant' || 'zh_tw' || 'zh-tw' => 3,
      'ja' => 4,
      _ => 2,
    };
  }

  Future<void> flush() => _persistQueue;

  void _enqueuePersist(String token) {
    _persistQueue = _persistQueue.then((_) async {
      try {
        final preferences = await SharedPreferences.getInstance();
        if (token.isEmpty) {
          await preferences.remove(storageKey);
        } else {
          await preferences.setString(storageKey, token);
        }
      } catch (_) {
        // Persistence failure must not invalidate the current in-memory session.
      }
    });
  }
}
