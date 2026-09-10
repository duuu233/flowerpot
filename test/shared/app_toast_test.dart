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

  testWidgets('登录页那句协议提示在常见屏宽下不折行', (tester) async {
    // 气泡宽度写死 300 时，留给文字的只有 236，而这句 16 个汉字在 14px 下要 224，
    // 只差 12px——系统字号调大一档就折行。宽度改成跟屏宽走之后要留足余量。
    const message = '请先阅读并同意用户协议与隐私政策';
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
    );
    final context = tester.element(find.byType(SizedBox));
    AppToast.show(context, message);
    await tester.pump();
    addTearDown(AppToast.dismiss);

    final text = tester.renderObject<RenderBox>(find.text(message));
    final line = tester.widget<Text>(find.text(message));
    final painter = TextPainter(
      text: TextSpan(text: message, style: line.style),
      textDirection: TextDirection.ltr,
    )..layout();

    // 单行：排版后的高度不超过一行行高（14 × 1.45 向上取整）。
    expect(text.size.height, lessThan(22));
    // 可用宽度要比这句话本身宽出一截，字号放大一档也还是一行。
    expect(text.size.width, greaterThanOrEqualTo(painter.width - 0.5));
    expect(tester.takeException(), isNull);
  });
}