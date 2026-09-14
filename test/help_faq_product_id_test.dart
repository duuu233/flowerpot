import 'package:flowerpot/src/core/backend/backend.dart';
import 'package:flowerpot/src/core/network/network.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/mock_tuya_repository.dart';

/// 帮助中心常见问题接口的 `broadcastId`（2026-09-14 产品）：取 `getBasicData` 的
/// `deviceIdList` 第一个；不写死兜底；不取设备报的 productId。
void main() {
  test('取 getBasicData 的 deviceIdList 第一个，不取设备报的 productId', () async {
    // 设备（DeviceBean.getProductId）报的是 ehbx83xdh9jkmxvz，后台维护的是
    // yciq4kssu1fv8umn；以前优先取设备值，常见问题整条筛不出来。
    final backend = _FaqBackend();
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

    final faqs = await state.loadFaqs();

    expect(faqs, hasLength(1));
    expect(backend.requestedBroadcastIds.last, 'yciq4kssu1fv8umn');
    expect(backend.basicDataCalls, 1);
    expect(
      state.interactionLog.any(
        (line) => line.contains('broadcastId=yciq4kssu1fv8umn'),
      ),
      isTrue,
    );
  });

  test('不写死兜底：deviceIdList 为空就不带 broadcastId', () async {
    final backend = _FaqBackend(deviceIds: const <String>[]);
    final state = FlowerpotState(
      repository: MockTuyaRepository(latency: Duration.zero),
      backendRepository: backend,
    );
    addTearDown(state.dispose);

    await state.loadFaqs();

    expect(backend.requestedBroadcastIds.last, '');
    expect(
      state.interactionLog.any(
        (line) => line.contains('未带 broadcastId（getBasicData 没有返回 deviceIdList）'),
      ),
      isTrue,
    );
  });

  test('基础数据接口失败也不写死', () async {
    final backend = _FaqBackend(basicDataFails: true);
    final state = FlowerpotState(
      repository: MockTuyaRepository(latency: Duration.zero),
      backendRepository: backend,
    );
    addTearDown(state.dispose);

    await state.loadFaqs();

    expect(backend.requestedBroadcastIds.last, '');
  });
}

class _FaqBackend extends DisabledAppBackendRepository {
  _FaqBackend({
    this.deviceIds = const <String>['yciq4kssu1fv8umn', 'second-id'],
    this.basicDataFails = false,
  });

  final List<String> deviceIds;
  final bool basicDataFails;
  final List<String> requestedBroadcastIds = <String>[];
  int basicDataCalls = 0;

  @override
  bool get enabled => true;

  @override
  bool get hasSession => true;

  @override
  Future<BackendBasicData> getBasicData() async {
    basicDataCalls++;
    if (basicDataFails) throw const ApiException(500, '服务器错误');
    return BackendBasicData(
      const <String, String>{'platformemail': 'a@b.test'},
      deviceIdList: deviceIds,
    );
  }

  @override
  Future<List<BackendFaq>> getFaqs({
    String keyword = '',
    String broadcastId = '',
  }) async {
    requestedBroadcastIds.add(broadcastId);
    return const <BackendFaq>[
      BackendFaq(faqId: 60, question: '测试测试', answer: ''),
    ];
  }
}
