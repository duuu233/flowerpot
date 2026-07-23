import 'dart:async';

import 'package:flutter/material.dart';

import '../features/preview/preview_config.dart';
import '../routes/app_routes.dart';
import '../state.dart';
import '../tuya/tuya_repository.dart';
import 'app_theme.dart';

class FlowerpotApp extends StatefulWidget {
  const FlowerpotApp({super.key, this.repository});

  final TuyaRepository? repository;

  @override
  State<FlowerpotApp> createState() => _FlowerpotAppState();
}

class _FlowerpotAppState extends State<FlowerpotApp> {
  late final FlowerpotState state = FlowerpotState(
    repository: widget.repository ?? TuyaRepository.create(),
  );

  @override
  void initState() {
    super.initState();
    unawaited(_initializeState());
  }

  Future<void> _initializeState() async {
    await state.initialize();
    if (StaticPreviewConfig.enabled) {
      await state.enterDemo();
    }
  }

  @override
  void dispose() {
    state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        return FlowerpotScope(
          state: state,
          child: MaterialApp(
            title: '智能花盆',
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(),
            locale: Locale(state.languageCode),
            initialRoute: AppRoutes.root,
            onGenerateRoute: (settings) => AppRoutes.onGenerateRoute(
              settings,
              authenticated: state.authenticated,
            ),
          ),
        );
      },
    );
  }
}

class FlowerpotScope extends InheritedNotifier<FlowerpotState> {
  const FlowerpotScope({
    required FlowerpotState state,
    required super.child,
    super.key,
  }) : super(notifier: state);

  static FlowerpotState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<FlowerpotScope>();
    assert(scope != null, 'FlowerpotScope is missing above this context.');
    return scope!.notifier!;
  }
}
