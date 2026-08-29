class BackendAuthAccount {
  const BackendAuthAccount({
    required this.userToken,
    required this.tuyaAccount,
    required this.tuyaPassword,
    required this.countryCode,
    required this.nickname,
    required this.account,
    this.avatarUrl,
    this.raw = '',
  });

  final String userToken;
  final String tuyaAccount;
  final String tuyaPassword;
  final String countryCode;
  final String nickname;
  final String account;
  final String? avatarUrl;

  /// APP 后端登录/注册接口返回的原始 `retData`。
  ///
  /// TODO(联调): 涂鸦账号映射问题排查完后删除本字段，以及 [FlowerpotState.login]
  /// 里把它拼进 toast 的那段 —— 它会把 `tuYaPwd` 显示在屏幕上。
  final String raw;
}

class BackendProduct {
  const BackendProduct({
    required this.productId,
    required this.productName,
    required this.broadcastId,
  });

  final int productId;
  final String productName;
  final String broadcastId;
}

class BackendUserProduct {
  const BackendUserProduct({
    required this.userProductId,
    required this.deviceId,
    required this.productName,
    this.productId,
    this.deleted = false,
  });

  final int userProductId;
  final int? productId;
  final String deviceId;
  final String productName;
  final bool deleted;

  BackendUserProduct copyWith({int? productId}) => BackendUserProduct(
    userProductId: userProductId,
    productId: productId ?? this.productId,
    deviceId: deviceId,
    productName: productName,
    deleted: deleted,
  );
}

class BackendImage {
  const BackendImage({
    required this.id,
    required this.userProductId,
    required this.name,
    required this.url,
  });

  final int id;
  final int userProductId;
  final String name;
  final String url;
}
