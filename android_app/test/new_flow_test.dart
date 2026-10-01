import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:washer_notifier/services/call_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    const channel = MethodChannel('flutter_callkit_incoming');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      return null;
    });
  });

  group('Passive Listener: CallManager Tests', () {
    test('1. Bỏ qua các message không phải lệnh gọi chuông', () async {
      final syncPayload = {
        'type': 'SYNC_DEVICE',
        'deviceId': 'smartthings-washer-999',
        'deviceName': 'Máy giặt Ban Công',
      };

      // Passive listener bỏ qua SYNC_DEVICE vì không còn lưu local storage
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
}
