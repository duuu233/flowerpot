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
    // 意见反馈的邮箱来自后台基础信息配置，这里由 fixture 给。
    expect(find.text('service@example.test'), findsOneWidget);
    // 帮助中心已搬到设备设置页。
    expect(find.text('帮助中心'), findsNothing);
    expect(find.text('关于东方金穗'), findsOneWidget);

    await tester.tap(find.text('个人信息'));
    expect(selected, <MineMenuKind>[MineMenuKind.personalInfo]);
  });

  test('菜单里没有「设备设置」；意见反馈带着后台配的平台邮箱', () {
    // 2026-09-21 产品：「我的」页去掉设备设置；意见反馈读后台配置的邮箱。
    final model = MinePageModel.fromUser(
      null,
      feedbackEmail: ' service@example.test ',
    );

    expect(model.menuItems.map((item) => item.label), <String>[
      '个人信息',
      '账号与安全',
      '意见反馈',
      '隐私政策',
      '用户协议',
      '关于东方金穗',
    ]);
    final feedback = model.menuItems.firstWhere(
      (item) => item.kind == MineMenuKind.feedback,
    );
    expect(feedback.trailingValue, 'service@example.test');
    // 后台没配就不显示，也就没有可复制的东西。
    final unset = MinePageModel.fromUser(null, feedbackEmail: '  ');
    expect(
      unset.menuItems
          .firstWhere((item) => item.kind == MineMenuKind.feedback)
          .trailingValue,
      isNull,
    );
  });

  testWidgets('有新版本时「关于东方金穗」点红点，意见反馈仍是复制图标', (tester) async {
    Future<void> pumpMenu({required bool hasAppUpdate}) async {
      final model = MinePageModel.fromUser(
        null,
        feedbackEmail: 'service@example.test',
        hasAppUpdate: hasAppUpdate,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: MineMenuList(
                items: model.menuItems,
                height: 440,
                onItemTap: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    await pumpMenu(hasAppUpdate: true);
    final aboutRow = find.ancestor(
      of: find.text('关于东方金穗'),
      matching: find.byType(ListTile),
    );
    expect(
      find.descendant(of: aboutRow, matching: find.byType(AppNoticeDot)),
      findsOneWidget,
    );
    expect(find.byType(AppNoticeDot), findsOneWidget);
    // 红点不能顶掉意见反馈的复制图标，也不能画成复制图标。
    expect(find.byIcon(Icons.copy_rounded), findsOneWidget);
    expect(
      find.descendant(of: aboutRow, matching: find.byIcon(Icons.copy_rounded)),
      findsNothing,
    );

    await pumpMenu(hasAppUpdate: false);
    expect(find.byType(AppNoticeDot), findsNothing);
    expect(find.byIcon(Icons.copy_rounded), findsOneWidget);
  });

  testWidgets('mine menu remains scrollable at 320x568', (tester) async {
    await _pumpMineWidgets(tester, const Size(320, 568));

    final about = find.text('关于东方金穗');
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
      MineMenuItem(
        kind: MineMenuKind.feedback,
        label: '意见反馈',
        trailingValue: 'service@example.test',
      ),
      MineMenuItem(kind: MineMenuKind.privacyPolicy, label: '隐私政策'),
      MineMenuItem(kind: MineMenuKind.userAgreement, label: '用户协议'),
      MineMenuItem(kind: MineMenuKind.about, label: '关于东方金穗'),
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
