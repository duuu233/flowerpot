import 'package:flowerpot/src/shared/widgets/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows one centered toast and replaces the previous message', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (value) {
            context = value;
            return const Scaffold(body: SizedBox.expand());
          },
        ),
      ),
    );

    AppToast.show(context, 'first');
    await tester.pump();
    expect(find.text('first'), findsOneWidget);

    AppToast.warn(context, 'second');
    await tester.pump();
    expect(find.text('first'), findsNothing);
    expect(find.text('second'), findsOneWidget);

    AppToast.dismiss();
    await tester.pump();
    expect(find.text('second'), findsNothing);
  });
}
