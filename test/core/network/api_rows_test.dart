import 'package:flowerpot/src/core/network/api_rows.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('extracts the backend pageData shape', () {
    expect(
      extractApiRows(<String, Object?>{
        'pageData': <Object?>[
          <String, Object?>{'id': 1},
          null,
          'ignored',
          <Object, Object?>{2: 'two'},
        ],
      }),
      <Map<String, Object?>>[
        <String, Object?>{'id': 1},
        <String, Object?>{'2': 'two'},
      ],
    );
  });
}
