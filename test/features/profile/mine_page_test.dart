import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/profile/models/mine_page_model.dart';
import 'package:flowerpot/src/features/profile/presentation/widgets/mine_menu_list.dart';
import 'package:flowerpot/src/features/profile/presentation/widgets/mine_profile_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('mine widgets expose the Figma content at 375x812', (
    tester,
  ) async {
    final selected = <MineMenuKind>[];
    await _pumpMineWidgets(
      tester,
      const Size(375, 812),
      onItemTap: selected.add,
    );

    expect(find.text('江江江'), findsOneWidget);
    expect(find.text('个人信息'), findsOneWidget);
    expect(find.text('账号与安全'), findsOneWidget);
    expect(find.text('123456789@QQ.COM'), findsOneWidget);
    expect(find.text('关于YSplanter'), findsOneWidget);

    await tester.tap(find.text('个人信息'));
    expect(selected, <MineMenuKind>[MineMenuKind.personalInfo]);
  });

  testWidgets('mine menu remains scrollable at 320x568', (tester) async {
    await _pumpMineWidgets(tester, const Size(320, 568));

    final about = find.text('关于YSplanter');
    await tester.ensureVisible(about);
    await tester.pump();

    expect(about, findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpMineWidgets(
  WidgetTester tester,
  Size size, {
  ValueChanged<MineMenuKind>? onItemTap,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  const model = MinePageModel(
    nickname: '江江江',
    avatarPath: null,
    menuItems: <MineMenuItem>[
      MineMenuItem(kind: MineMenuKind.personalInfo, label: '个人信息'),
      MineMenuItem(kind: MineMenuKind.accountSecurity, label: '账号与安全'),
      MineMenuItem(kind: MineMenuKind.helpCenter, label: '帮助中心'),
      MineMenuItem(
        kind: MineMenuKind.feedback,
        label: '意见反馈',
        trailingValue: '123456789@QQ.COM',
      ),
      MineMenuItem(kind: MineMenuKind.privacyPolicy, label: '隐私政策'),
      MineMenuItem(kind: MineMenuKind.userAgreement, label: '用户协议'),
      MineMenuItem(kind: MineMenuKind.about, label: '关于YSplanter'),
    ],
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Column(
            children: <Widget>[
              MineProfileHeader(model: model, onEdit: () {}),
              MineMenuList(
                items: model.menuItems,
                height: 440,
                onItemTap: onItemTap ?? (_) {},
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}
