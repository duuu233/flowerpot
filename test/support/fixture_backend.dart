import 'package:flowerpot/src/core/backend/backend.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'plant_catalog.dart';

class FixtureBackend extends DisabledAppBackendRepository {
  @override
  bool get enabled => true;
  @override
  bool get hasSession => true;
  @override
  Future<List<PlantProfile>> getProductPlants({String keyword = ''}) async =>
    PlantCatalog.items.where((p) => p.name.contains(keyword) ||
      p.latinName.toLowerCase().contains(keyword.toLowerCase())).toList();
  @override
  Future<BackendAuthAccount> loginWithCode({required String mobile, required String code}) async =>
    BackendAuthAccount(userToken: 'fixture-token', tuyaAccount: 'mock-user',
      tuyaPassword: 'fixture-password', countryCode: '86', nickname: '用户', account: mobile);
  final List<BackendImage> images = [];
  @override
  Future<List<BackendImage>> getImages(String deviceId) async => List.of(images);
  @override
  Future<String?> uploadImage({required String deviceId, required String filePath}) async {
    final url = 'https://example.test/${filePath.split('/').last}';
    images.add(BackendImage(id: images.length + 1, userProductId: 1,
      name: filePath.split('/').last, url: url));
    return url;
  }
  @override
  Future<void> deleteImages(List<int> imageIds) async => images.removeWhere((i) => imageIds.contains(i.id));
}
