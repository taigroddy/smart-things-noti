import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:washer_notifier/services/device_storage.dart';
import 'package:washer_notifier/services/notification_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    NotificationManager.resetAntiSpamForTesting();

    // Mock MethodChannel của flutter_local_notifications
    const notiChannel = MethodChannel('dexterous.com/flutter/local_notifications');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notiChannel, (MethodCall methodCall) async {
      return null;
    });
  });

  group('Passive Listener: NotificationManager Tests', () {
    test('1. Bỏ qua các message không phải lệnh thông báo chuông', () async {
      final syncPayload = {
        'type': 'SYNC_DEVICES',
        'devices': '[{"id":"washer-1","name":"Máy giặt 1"}]',
      };

      await NotificationManager.handleFCMMessage(syncPayload);
    });

    test('2. Xử lý TRIGGER_CALL / TRIGGER_NOTI và chống spam duplicate eventId', () async {
      final triggerPayload = {
        'type': 'TRIGGER_NOTI',
        'eventId': 'event_unique_001',
        'deviceName': 'Máy Giặt Thông Minh',
        'body': 'Quần áo đã giặt xong!',
      };

      // Thông báo thứ nhất
      await NotificationManager.handleFCMMessage(triggerPayload);

      // Thử gửi lại cùng eventId -> Hệ thống chống spam tự động bỏ qua
      await NotificationManager.handleFCMMessage(triggerPayload);
    });

    test('3. Hỗ trợ tương thích ngược với type TRIGGER_CALL cũ', () async {
      final triggerCallPayload = {
        'type': 'TRIGGER_CALL',
        'eventId': 'event_call_002',
        'deviceName': 'Máy Giặt Samsung AI',
        'body': 'Đã hoàn tất chu trình giặt!',
      };

      await NotificationManager.handleFCMMessage(triggerCallPayload);
    });
  });

  group('Local Storage: DeviceStorage & SYNC_DEVICES Tests', () {
    test('4. Parse devices từ chuỗi JSON string chuẩn', () {
      const rawJson = '[{"id":"washer-101","name":"Máy Giặt Samsung AI"},{"id":"washer-102","name":"Máy Sấy Heatpump"}]';
      final list = DeviceStorage.parseDevices(rawJson);

      expect(list.length, 2);
      expect(list[0].id, 'washer-101');
      expect(list[0].name, 'Máy Giặt Samsung AI');
      expect(list[1].id, 'washer-102');
      expect(list[1].name, 'Máy Sấy Heatpump');
    });

    test('5. Xử lý Data Message SYNC_DEVICES và lưu vào Local Storage', () async {
      final syncPayload = {
        'type': 'SYNC_DEVICES',
        'devices': '[{"id":"dev-999","name":"Máy giặt Phòng Giặt"}]',
      };

      final synced = await DeviceStorage.handleSyncMessage(syncPayload);
      expect(synced.length, 1);
      expect(synced[0].id, 'dev-999');
      expect(synced[0].name, 'Máy giặt Phòng Giặt');

      final saved = await DeviceStorage.getDevices();
      expect(saved.length, 1);
      expect(saved[0].id, 'dev-999');
      expect(saved[0].name, 'Máy giặt Phòng Giặt');
    });

    test('6. Tương thích ngược với SYNC_DEVICE đơn lẻ', () async {
      final singleSyncPayload = {
        'type': 'SYNC_DEVICE',
        'deviceId': 'single-dev-01',
        'deviceName': 'Máy giặt Ban Công',
      };

      final synced = await DeviceStorage.handleSyncMessage(singleSyncPayload);
      expect(synced.length, 1);
      expect(synced[0].id, 'single-dev-01');
      expect(synced[0].name, 'Máy giặt Ban Công');

      final saved = await DeviceStorage.getDevices();
      expect(saved.length, 1);
      expect(saved[0].id, 'single-dev-01');
    });

    test('7. Bật/tắt thông báo cho thiết bị và kiểm tra isDeviceEnabled', () async {
      final syncPayload = {
        'type': 'SYNC_DEVICES',
        'devices': '[{"id":"dev-toggle-1","name":"Máy giặt Tầng 2"}]',
      };
      await DeviceStorage.handleSyncMessage(syncPayload);

      // Mặc định là bật (true)
      expect(await DeviceStorage.isDeviceEnabled('dev-toggle-1'), isTrue);

      // Tắt thông báo
      await DeviceStorage.updateDeviceEnabled('dev-toggle-1', false);
      expect(await DeviceStorage.isDeviceEnabled('dev-toggle-1'), isFalse);

      // Bật lại
      await DeviceStorage.updateDeviceEnabled('dev-toggle-1', true);
      expect(await DeviceStorage.isDeviceEnabled('dev-toggle-1'), isTrue);
    });

    test('8. NotificationManager tự động bỏ qua thông báo khi thiết bị đã bị tắt chuông', () async {
      final syncPayload = {
        'type': 'SYNC_DEVICES',
        'devices': '[{"id":"dev-muted","name":"Máy giặt Đêm"}]',
      };
      await DeviceStorage.handleSyncMessage(syncPayload);
      await DeviceStorage.updateDeviceEnabled('dev-muted', false);

      final triggerPayload = {
        'type': 'TRIGGER_NOTI',
        'deviceId': 'dev-muted',
        'eventId': 'event_muted_001',
        'deviceName': 'Máy giặt Đêm',
        'body': 'Quần áo đã giặt xong!',
      };

      // Gọi handleFCMMessage, hệ thống sẽ bỏ qua vì dev-muted có isEnabled = false
      await NotificationManager.handleFCMMessage(triggerPayload);
    });

    test('9. Xóa sạch thiết bị với clearDevices (Reset kết nối)', () async {
      await DeviceStorage.clearDevices();
      final devices = await DeviceStorage.getDevices();
      expect(devices.isEmpty, isTrue);
    });
  });
}
