class BackendAuthAccount {
  const BackendAuthAccount({
    required this.userToken,
    required this.tuyaAccount,
    required this.tuyaPassword,
    required this.countryCode,
    required this.nickname,
    required this.account,
    this.avatarUrl,
    this.tuyaHomeId,
    this.userId,
    this.registered = false,
  });

  final String userToken;
  final String tuyaAccount;
  final String tuyaPassword;
  final String countryCode;
  final String nickname;
  final String account;
  final String? avatarUrl;

  /// 后端按账号存的涂鸦家庭 id（登录响应里的 `tuYaHomeId`）。
  ///
  /// 家庭 id 由涂鸦云端分配，App 不自己造；后端存一份的意义是「换手机、重装、
  /// 清数据之后仍然用同一个家庭」——本地缓存做不到这一点。后端还没下发这个字段
  /// 时为 null，此时退回本地缓存 + 涂鸦家庭列表解析。
  final String? tuyaHomeId;

  /// 后端用户主键（登录响应里的 `userId`）。
  ///
  /// 家庭 id 仍然只能由涂鸦分配，这个值不是 id 本身，而是「这个家庭属于哪个账号」
  /// 的依据：家庭名标记和本地缓存的键都用它。后端没下发时退回涂鸦 uid（`userNo`）。
  final String? userId;

  /// 这次会话是注册接口建立的，而不是登录接口。登录注册一体的验证码登录里，
  /// 未注册手机号会被补注册，页面据此把提示从「登录成功」换成建号文案。
  final bool registered;
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

/// 用户资料，对应 `/Client/User/getUserInfo`。
///
/// 后端字段名在不同接口之间不完全一致（登录返回 `nickName`/`userMobile`，
/// 资料接口还可能给 `mobile`），解析放在仓库层做，这里只留规范化之后的值。
class BackendUserInfo {
  const BackendUserInfo({
    required this.nickname,
    required this.account,
    this.avatarUrl,
    this.email = '',
    this.userNo = '',
  });

  final String nickname;
  final String account;
  final String? avatarUrl;
  final String email;
  final String userNo;
}

/// `/Client/Basic/getLastVersion` 的结果。
///
/// [hasUpdate] 由后端判定：请求要带上本机版本号，返回里没有明确标记时按
/// 「版本号不一样就是有新版」兜底。
class BackendAppVersion {
  const BackendAppVersion({
    required this.versionNo,
    required this.hasUpdate,
    this.forceUpdate = false,
    this.downloadUrl = '',
    this.releaseNotes = const <String>[],
  });

  final String versionNo;
  final bool hasUpdate;
  final bool forceUpdate;
  final String downloadUrl;
  final List<String> releaseNotes;
}

/// `/Client/Basic/getBasicData` 的结果。
///
/// 这个接口没有 swagger 模型，返回的是一张后台配置表，字段名由运营决定，所以
/// 这里保留整张表，再按几组常见命名去取用户协议、隐私政策和关于我们。取不到
/// 就返回 null，页面回落到内置文案，不会因为后台没配就变成空白页。
class BackendBasicData {
  const BackendBasicData(this.values);

  static const BackendBasicData empty = BackendBasicData(
    <String, String>{},
  );

  final Map<String, String> values;

  bool get isEmpty => values.isEmpty;

  String? get userAgreement => _pick(const <String>[
    'userAgreement',
    'userProtocol',
    'agreement',
    'protocol',
    'serviceAgreement',
    'registrationAgreement',
  ]);

  String? get privacyPolicy => _pick(const <String>[
    'privacyPolicy',
    'privacyAgreement',
    'privacy',
    'privacyProtocol',
  ]);

  String? get aboutUs =>
      _pick(const <String>['aboutUs', 'about', 'companyProfile', 'introduce']);

  String? get contact => _pick(const <String>[
    'serviceEmail',
    'contactEmail',
    'email',
    'servicePhone',
    'contact',
  ]);

  String? _pick(List<String> keys) {
    for (final key in keys) {
      final value = values[key.toLowerCase()];
      if (value == null || value.isEmpty) continue;
      final text = _plain(value);
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  /// 后台的协议正文是富文本编辑器存的，可能带 HTML；页面按纯文本渲染，这里先
  /// 把标签换成换行再去掉，免得整页显示成一串 `<p>`。
  static String _plain(String value) => value
      .replaceAll(RegExp('<br[^>]*>', caseSensitive: false), '\n')
      .replaceAll(RegExp('</(p|div|li|h[1-6]|tr)>', caseSensitive: false), '\n')
      .replaceAll(RegExp('<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .join('\n');
}

/// 常见问题，对应 `/Client/Product/getProductFaqList`。
class BackendFaq {
  const BackendFaq({
    required this.faqId,
    required this.question,
    required this.answer,
  });

  final int faqId;
  final String question;
  final String answer;
}

/// 设备纪念日，对应 `/Client/UserProduct/*Anniversary` 那组接口。
///
/// [anniversaryId] 同时也是写进 DP 154 帧的 id：后端的自增 id 全局唯一且落在
/// 帧要求的 32 位无符号范围内，用它就不必再维护第二套本地 id，换机之后设备上
/// 的条目仍然能和后端记录对上。
class BackendAnniversary {
  const BackendAnniversary({
    required this.anniversaryId,
    required this.deviceId,
    required this.title,
    required this.content,
    required this.imageContent,
    this.date,
    this.enabled = true,
  });

  final int anniversaryId;

  /// 涂鸦 `deviceId`。2026-09-13 核对的 swagger 里，纪念日这组接口已经不再用后端的
  /// `userProductId`，入参和返回体都按涂鸦设备 id 关联。
  final String deviceId;
  final String title;
  final String content;

  /// 后端的 `contentType`：0=文字，1=图片。DP 154 用的是 1=文字、2=图片，
  /// 两套编码不一样，所以这里存成布尔量，两边各自转换。
  final bool imageContent;
  final DateTime? date;
  final bool enabled;
}
