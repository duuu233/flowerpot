import 'package:flutter/material.dart';

import 'app_empty_state.dart';
import 'app_error_view.dart';
import 'app_loading.dart';

enum AppLoadState { loading, content, empty, error }

class AppLoadStateView extends StatelessWidget {
  const AppLoadStateView({
    required this.state,
    required this.content,
    super.key,
    this.loadingLabel,
    this.emptyTitle = '暂无内容',
    this.emptyMessage = '当前没有可展示的数据',
    this.errorMessage = '加载失败，请稍后重试',
    this.onRetry,
  });

  final AppLoadState state;
  final Widget content;
  final String? loadingLabel;
  final String emptyTitle;
  final String emptyMessage;
  final String errorMessage;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      AppLoadState.loading => AppLoading(label: loadingLabel),
      AppLoadState.content => content,
      AppLoadState.empty => AppEmptyState(
        title: emptyTitle,
        message: emptyMessage,
      ),
      AppLoadState.error => AppErrorView(
        message: errorMessage,
        onRetry: onRetry,
      ),
    };
  }
}
