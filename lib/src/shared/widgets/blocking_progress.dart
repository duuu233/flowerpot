import 'dart:async';

import 'package:flutter/material.dart';

/// 跑一件要等的事，期间盖一层**不可点穿**的进度圈。
///
/// ## 为什么要它
///
/// 「点一下要等云端往返」的操作，光靠 `FlowerpotState.busy` 把按钮禁掉是不够的：
///
/// - `busy` 只在状态层 `_guard` 里翻，**动作开始之前那几十毫秒**按钮还是活的；
/// - 有些动作前面还夹着系统弹层（选图、确认框），那段时间根本不在 `busy` 里；
/// - 有些动作是**一串**请求（例如逐张删图），两次请求之间 `busy` 会掉回 false，
///   按钮闪回可点状态。
///
/// 用户看不到反馈就会再点一次，于是同一条指令被下发两遍。盖一层进度圈，这三种
/// 缝隙一起堵上，顺带也告诉用户「在跑了，等一下」。
///
/// ## 用法
///
/// ```dart
/// final result = await withBlockingProgress(context, () => state.doSomething());
/// if (!mounted || result == null) return;   // null = 页面已经不在了
/// ```
///
/// 返回 null 表示调用时页面已经被弹走，**不代表动作失败**——那种情况下动作压根
/// 没发起。
Future<T?> withBlockingProgress<T>(
  BuildContext context,
  Future<T> Function() action,
) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  unawaited(
    showDialog<void>(
      context: context,
      // 不可关闭：这段时间点什么都不该生效。
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: .18),
      builder: (_) => const PopScope(
        canPop: false,
        child: Center(
          child: SizedBox.square(
            dimension: 44,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
        ),
      ),
    ),
  );
  try {
    return await action();
  } finally {
    // 用一开始拿到的 navigator，不再查 context——这一刻页面可能已经被弹走了。
    if (navigator.canPop()) navigator.pop();
  }
}
