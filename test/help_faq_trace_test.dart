import 'package:flowerpot/src/core/backend/backend.dart';
import 'package:flowerpot/src/core/network/network.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/mock_tuya_repository.dart';

/// 帮助中心列表下方打印的接口调试信息（2026-09-14 产品：「直接打印调了哪个接口、请求参数、
/// 返回什么」）。
void main() {
  test('发了请求：接口、每个参数（含含义）、请求头、返回体、App 解析条数都在，令牌只露头尾', () async {
    final backend = _TraceBackend();
    final state = FlowerpotState(
      repository: MockTuyaRepository(latency: Duration.zero),
      backendRepository: backend,
    );
    addTearDown(state.dispose);

    final faqs = await state.loadFaqs();

    expect(faqs, hasLength(1));
    final trace = state.faqTrace;
    expect(trace, contains('【接口】GET /Client/Product/getProductFaqList'));
    expect(trace, contains('HTTP 200'));
    expect(trace, contains('language = 2（简中）'));
    expect(trace, contains('terminal = 1（安卓）'));
    expect(trace, contains('broadcastId = yciq4kssu1fv8umn（产品ID，取自后台产品列表 broadcastId）'));
    expect(trace, contains('"faqTitle": "测试测试"'));
    expect(trace, contains('接口返回 pageData 1 条（recordCount 1），页面显示 1 条'));
    // 令牌不整段上屏。
    expect(trace, isNot(contains('0123456789abcdef0123')));
    expect(trace, contains('012345…0123'));
    expect(trace, contains('【完整地址】https://api.example.test/Client/Product/getProductFaqList?'));
    expect(trace, isNot(contains('%E2%80%A6')));
  });

  test('产品 ID 取后台产品列表的 broadcastId，不取设备报的 productId', () async {
    // 2026-09-14：设备（DeviceBean.getProductId）报的是 ehbx83xdh9jkmxvz，后台维护的是
    // yciq4kssu1fv8umn；以前优先取设备值，常见问题整条筛不出来。
    final backend = _TraceBackend();
    final state = FlowerpotState(
      repository: MockTuyaRepository(latency: Duration.zero),
      backendRepository: backend,
    );
    addTearDown(state.dispose);
    await state.login(
      account: 'demo@example.test',
      credential: 'demo',
      region: LoginRegion.overseas,
      verificationCode: false,
    );
    // Mock 设备的 productId 是另一个值，正好用来证明不看它。
    expect(state.devices.single.productId, isNot('yciq4kssu1fv8umn'));

    await state.loadFaqs();

    expect(backend.requestedBroadcastIds.last, 'yciq4kssu1fv8umn');
    expect(backend.productListCalls, greaterThanOrEqualTo(1));
  });

  test('后台产品列表拉不到时退回本地常量', () async {
    final backend = _TraceBackend(productsFail: true);
    final state = FlowerpotState(
      repository: MockTuyaRepository(latency: Duration.zero),
      backendRepository: backend,
    );
    addTearDown(state.dispose);

    await state.loadFaqs();

    expect(backend.requestedBroadcastIds.last, 'yciq4kssu1fv8umn');
    expect(state.faqTrace, contains('本地常量 TuyaConfig.productId'));
  });

  test('没发请求时也要说清楚为什么', () async {
    final state = FlowerpotState(
      repository: MockTuyaRepository(latency: Duration.zero),
      backendRepository: _TraceBackend(session: false),
    );
    addTearDown(state.dispose);

    await state.loadFaqs();

    expect(state.faqTrace, contains('没有发请求：APP 后端登录态已失效'));
  });
}

class _TraceBackend extends DisabledAppBackendRepository {
  _TraceBackend({this.session = true, this.productsFail = false});

  final bool session;
  final bool productsFail;
  ApiExchange? _exchange;
  final List<String> requestedBroadcastIds = <String>[];
  int productListCalls = 0;

  @override
  Future<List<BackendProduct>> getProducts() async {
    productListCalls++;
    if (productsFail) throw const ApiException(500, '接口不存在');
    return const <BackendProduct>[
      BackendProduct(
        productId: 15,
        productName: '智能花盆',
        broadcastId: 'yciq4kssu1fv8umn',
      ),
    ];
  }

  @override
  bool get enabled => true;

  @override
  bool get hasSession => session;

  @override
  ApiExchange? lastExchange(String path) =>
      path == AppBackendRepository.faqListPath ? _exchange : null;

  @override
  Future<List<BackendFaq>> getFaqs({
    String keyword = '',
    String broadcastId = '',
  }) async {
    requestedBroadcastIds.add(broadcastId);
    const token = '0123456789abcdef0123';
    _exchange = ApiExchange(
      method: 'GET',
      url: Uri.parse(
        'https://api.example.test${AppBackendRepository.faqListPath}'
        '?terminal=1&language=2&userToken=$token'
        '&pageIndex=1&pageSize=50&broadcastId=$broadcastId',
      ),
      headers: const <String, String>{
        'terminal': '1',
        'language': '2',
        'userToken': token,
        'Authorization': 'Bearer $token',
      },
      statusCode: 200,
      responseBody:
          '{\n  "retCode": 200,\n  "retData": {\n    "pageData": [\n'
          '      {\n        "faqId": 60,\n        "faqTitle": "测试测试"\n      }\n'
          '    ],\n    "recordCount": 1\n  }\n}',
      elapsed: const Duration(milliseconds: 120),
      at: DateTime.now(),
    );
    return const <BackendFaq>[
      BackendFaq(faqId: 60, question: '测试测试', answer: ''),
    ];
  }
}
