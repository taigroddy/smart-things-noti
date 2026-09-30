import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:washer_notifier/services/device_storage.dart';
import 'package:washer_notifier/services/call_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('New Flow: DeviceStorage & FCM Sync Tests', () {
    test('1. upsertDevice thêm mới thiết bị với isNotificationEnabled = true mặc định', () async {
      final device = await DeviceStorage.upsertDevice(
        id: 'test-washer-101',
        name: 'Máy giặt Thông minh',
        modelCode: 'Samsung AI Ecobubble',
      );

      expect(device.id, equals('test-washer-101'));
      expect(device.name, equals('Máy giặt Thông minh'));
      expect(device.isNotificationEnabled, isTrue);

      final saved = await DeviceStorage.getDevices();
      expect(saved.any((d) => d.id == 'test-washer-101'), isTrue);
    });

    test('2. upsertDevice cập nhật thiết bị hiện có mà không làm mất trạng thái isNotificationEnabled', () async {
      await DeviceStorage.upsertDevice(
        id: 'test-washer-102',
        name: 'Máy giặt Ban đầu',
      );

      // Tắt thông báo cho thiết bị này
      await DeviceStorage.setNotificationEnabled('test-washer-102', false);

      // Nhận lại SYNC_DEVICE từ SmartThings (ví dụ đổi tên)
      final updated = await DeviceStorage.upsertDevice(
        id: 'test-washer-102',
        name: 'Máy giặt Tầng 2 Đã Đổi Tên',
      );

      expect(updated.name, equals('Máy giặt Tầng 2 Đã Đổi Tên'));
      expect(updated.isNotificationEnabled, isFalse); // Vẫn bảo lưu cài đặt của người dùng
    });

    test('3. setNotificationEnabled bật/tắt chính xác cờ nhận thông báo', () async {
      await DeviceStorage.upsertDevice(
        id: 'test-washer-103',
        name: 'Máy sấy',
      );

      await DeviceStorage.setNotificationEnabled('test-washer-103', false);
      var enabled = await DeviceStorage.isNotificationEnabledForDevice('test-washer-103');
      expect(enabled, isFalse);

      await DeviceStorage.setNotificationEnabled('test-washer-103', true);
      enabled = await DeviceStorage.isNotificationEnabledForDevice('test-washer-103');
      expect(enabled, isTrue);
    });
  });

  group('New Flow: CallManager Authorization Tests', () {
    test('4. validateAndAuthorizeCall CHỈ cho phép gọi khi deviceId khớp và isNotificationEnabled == true', () async {
      await DeviceStorage.upsertDevice(
        id: 'washer-active',
        name: 'Máy Giặt Bật Chuông',
      );
      await DeviceStorage.upsertDevice(
        id: 'washer-muted',
        name: 'Máy Giặt Tắt Chuông',
      );
      await DeviceStorage.setNotificationEnabled('washer-muted', false);

      // Test 4.1: Thiết bị bật chuông -> Cho phép kích hoạt cuộc gọi
      final authorized1 = await CallManager.validateAndAuthorizeCall(
        deviceId: 'washer-active',
        eventId: 'event-001',
      );
      expect(authorized1, isNotNull);
      expect(authorized1!.id, equals('washer-active'));

      // Test 4.2: Thiết bị tắt chuông -> Từ chối (null)
      final authorized2 = await CallManager.validateAndAuthorizeCall(
        deviceId: 'washer-muted',
        eventId: 'event-002',
      );
      expect(authorized2, isNull);

      // Test 4.3: DeviceId lạ không tồn tại -> Từ chối (null)
      final authorized3 = await CallManager.validateAndAuthorizeCall(
        deviceId: 'washer-unknown',
        eventId: 'event-003',
      );
      expect(authorized3, isNull);
    });

    test('5. handleFCMMessage với SYNC_DEVICE tự động lưu thiết bị vào Local Storage', () async {
      final syncPayload = {
        'type': 'SYNC_DEVICE',
        'deviceId': 'smartthings-washer-999',
        'deviceName': 'Máy giặt Ban Công',
      };

      await CallManager.handleFCMMessage(syncPayload);

      final devices = await DeviceStorage.getDevices();
      final synced = devices.firstWhere((d) => d.id == 'smartthings-washer-999');
      expect(synced.name, equals('Máy giặt Ban Công'));
      expect(synced.isNotificationEnabled, isTrue);
    });
  });
}
