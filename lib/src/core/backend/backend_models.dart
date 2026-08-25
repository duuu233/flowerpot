class BackendAuthAccount {
  const BackendAuthAccount({
    required this.userToken,
    required this.tuyaAccount,
    required this.tuyaPassword,
    required this.countryCode,
    required this.nickname,
    required this.account,
    this.avatarUrl,
  });

  final String userToken;
  final String tuyaAccount;
  final String tuyaPassword;
  final String countryCode;
  final String nickname;
  final String account;
  final String? avatarUrl;
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
