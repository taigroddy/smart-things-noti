import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:uuid/uuid.dart';

/// Quản lý kích hoạt cuộc gọi giả lập (Fake Call) cho Passive Listener
class CallManager {
  // Lưu thời điểm gọi gần nhất (ms) để chống spam duplicate message
  static int _lastCallTimestamp = 0;

  // Lưu các eventId đã xử lý trong phiên để chống duplicate FCM
  static final Set<String> _processedEventIds = {};

  // Cửa sổ chống spam (60 giây)
  static const int antiSpamWindowMs = 60 * 1000;

  /// Kích hoạt màn hình cuộc gọi giả lập toàn màn hình (Full-Screen Incoming Call)
  /// Đánh thức màn hình, rung, đổ chuông ngay cả khi tắt màn hình hoặc đang khoá
  static Future<void> triggerIncomingCall({
    String? callerName,
    String? handle,
    String? deviceId,
  }) async {
    final callUuid = const Uuid().v4();
    final name = (callerName != null && callerName.isNotEmpty)
        ? callerName
        : 'Máy Giặt Thông Minh';
    final subtitle = (handle != null && handle.isNotEmpty)
        ? handle
        : 'Quần áo đã giặt xong!';

    final params = CallKitParams(
      id: callUuid,
      nameCaller: name,
      appName: 'Washer Notifier',
      avatar: 'https://img.icons8.com/color/96/washing-machine.png',
      handle: subtitle,
      type: 1,
      textDecline: 'Tắt',
      duration: 45000,
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: true,
        ringtonePath: 'samsung_washing_machin',
        backgroundColor: '#1565C0',
        actionColor: '#4CAF50',
        textColor: '#ffffff',
        isShowCallID: false,
      ),
      headers: <String, dynamic>{
        'type': 'TRIGGER_CALL',
        'deviceId': deviceId ?? '',
        'callUuid': callUuid,
      },
      extra: <String, dynamic>{
        'deviceId': deviceId ?? '',
      },
    );

    debugPrint('[CallManager 📞] Đang kích hoạt cuộc gọi: "$name" ($subtitle)');
    await FlutterCallkitIncoming.showCallkitIncoming(params);
  }

  /// Xử lý Data Message nhận được từ Firebase Cloud Messaging (Background & Foreground)
  /// Hoàn toàn không qua database hay local storage, lập tức kích hoạt Fake Call khi nhận tín hiệu
  static Future<void> handleFCMMessage(Map<String, dynamic> data) async {
    debugPrint('[CallManager 📨] Phân tích FCM data: $data');

    final type = data['type']?.toString();

    // Chỉ nhận các type kích hoạt cuộc gọi
    if (type != 'TRIGGER_CALL' && type != 'WASHING_MACHINE_DONE') {
      debugPrint('[CallManager ℹ️] Bỏ qua message không phải lệnh gọi chuông (type: $type)');
      return;
    }

    final eventId = data['eventId']?.toString() ?? data['event_id']?.toString();
    final deviceName = data['deviceName']?.toString() ??
        data['device_name']?.toString() ??
        data['title']?.toString();
    final deviceId = data['deviceId']?.toString() ?? data['device_id']?.toString();
    final messageBody = data['body']?.toString() ?? 'Quần áo đã giặt xong!';

    // 1. Kiểm tra duplicate qua eventId
    if (eventId != null && eventId.isNotEmpty) {
      if (_processedEventIds.contains(eventId)) {
        debugPrint('[CallManager 🛡️ Anti-Spam] Bỏ qua vì eventId "$eventId" đã được xử lý.');
        return;
      }
      _processedEventIds.add(eventId);
    }

    // 2. Chống lặp nhiều cuộc gọi liên tiếp trong vòng 60 giây
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastCallTimestamp < antiSpamWindowMs) {
      final elapsed = ((now - _lastCallTimestamp) / 1000).toStringAsFixed(1);
      debugPrint('[CallManager 🛡️ Anti-Spam] Bỏ qua: Vừa gọi cách đây ${elapsed}s (chặn lặp 60s).');
      return;
    }
    _lastCallTimestamp = now;

    // 3. Lập tức kích hoạt màn hình cuộc gọi giả lập
    // Hiển thị tên người gọi là "Máy Giặt Thông Minh" (hoặc tên máy nếu backend gửi kèm)
    await triggerIncomingCall(
      callerName: (deviceName != null && deviceName.isNotEmpty)
          ? deviceName
          : 'Máy Giặt Thông Minh',
      handle: messageBody,
      deviceId: deviceId,
    );
  }
}
