import 'package:flowerpot/src/features/auth/domain/auth_validator.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuthValidator.account', () {
    test('normalizes a domestic mobile number', () {
      expect(
        AuthValidator.account(' 13800138000 ', LoginRegion.domestic),
        '13800138000',
      );
    });

    test('accepts an overseas email', () {
      expect(
        AuthValidator.account('user@example.com', LoginRegion.overseas),
        'user@example.com',
      );
    });

    test('rejects malformed accounts before the repository call', () {
      expect(
        () => AuthValidator.account('123', LoginRegion.domestic),
        throwsA(isA<AuthValidationException>()),
      );
    });
  });

  test('password applies the requested minimum length', () {
    expect(
      () => AuthValidator.password('12345', minimumLength: 6),
      throwsA(isA<AuthValidationException>()),
    );
    expect(AuthValidator.password('123456', minimumLength: 6), '123456');
  });
}
