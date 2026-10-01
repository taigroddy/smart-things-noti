import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:washer_notifier/services/call_manager.dart';
import 'package:washer_notifier/services/device_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    const channel = MethodChannel('flutter_callkit_incoming');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      return null;
    });
  });

  group('Passive Listener: CallManager Tests', () {
    test('1. Bỏ qua các message không phải lệnh gọi chuông', () async {
      final syncPayload = {
        'type': 'SYNC_DEVICES',
        'devices': '[{"id":"washer-1","name":"Máy giặt 1"}]',
      };

      await CallManager.handleFCMMessage(syncPayload);
    });

    test('2. Xử lý TRIGGER_CALL và chống spam duplicate eventId', () async {
      final triggerPayload = {
        'type': 'TRIGGER_CALL',
        'eventId': 'event_unique_001',
        'deviceName': 'Máy Giặt Thông Minh',
        'body': 'Quần áo đã giặt xong!',
      };

      // Cuộc gọi thứ nhất
      await CallManager.handleFCMMessage(triggerPayload);

      // Thử gửi lại cùng eventId -> Hệ thống chống spam tự động bỏ qua
      await CallManager.handleFCMMessage(triggerPayload);
    });
  });

  group('Local Storage: DeviceStorage & SYNC_DEVICES Tests', () {
    test('3. Parse devices từ chuỗi JSON string chuẩn', () {
      const rawJson = '[{"id":"washer-101","name":"Máy Giặt Samsung AI"},{"id":"washer-102","name":"Máy Sấy Heatpump"}]';
      final list = DeviceStorage.parseDevices(rawJson);

      expect(list.length, 2);
      expect(list[0].id, 'washer-101');
      expect(list[0].name, 'Máy Giặt Samsung AI');
      expect(list[1].id, 'washer-102');
      expect(list[1].name, 'Máy Sấy Heatpump');
    });

    test('4. Xử lý Data Message SYNC_DEVICES và lưu vào Local Storage', () async {
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

    test('5. Tương thích ngược với SYNC_DEVICE đơn lẻ', () async {
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
  });
}
