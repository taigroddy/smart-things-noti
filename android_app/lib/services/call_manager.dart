import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:uuid/uuid.dart';
import '../models/device_model.dart';
import 'device_storage.dart';

/// Quản lý kích hoạt cuộc gọi giả lập với cơ chế kiểm tra trùng ID và chống spam 2 phút
class CallManager {
  // Lưu thời điểm gọi gần nhất theo từng deviceId (ms)
  static final Map<String, int> _lastCallTimestamps = {};

  // Lưu các eventId đã xử lý trong phiên để tránh nhận duplicate FCM message
  static final Set<String> _processedEventIds = {};

  // Cửa sổ chống spam (2 phút = 120.000 ms)
  static const int antiSpamWindowMs = 2 * 60 * 1000;

  /// Kiểm tra toàn diện xem có cho phép kích hoạt cuộc gọi hay không:
  /// 1. deviceId từ FCM có trùng với máy nào trong danh sách thiết bị của App không?
  /// 2. Thiết bị đó có đang BẬT thông báo (isNotificationEnabled) không?
  /// 3. Sự kiện (eventId) này đã từng gọi chưa?
  /// 4. Thiết bị này có vừa gọi trong vòng 2 phút qua không (chống spam)?
  static Future<DeviceItem?> validateAndAuthorizeCall({
    required String? deviceId,
    String? eventId,
  }) async {
    if (deviceId == null || deviceId.isEmpty) {
      debugPrint('[CallManager ⚠️] Bỏ qua vì FCM message không chứa deviceId.');
      return null;
    }

    // 1. Kiểm tra sự kiện trùng lặp qua eventId
    if (eventId != null && eventId.isNotEmpty) {
      if (_processedEventIds.contains(eventId)) {
        debugPrint('[CallManager 🛡️ Anti-Spam] Bỏ qua vì eventId "$eventId" đã được xử lý trước đó.');
        return null;
      }
    }

    // 2. Lấy danh sách thiết bị đã lưu trên máy
    final savedDevices = await DeviceStorage.getDevices();

    // 3. Kiểm tra xem deviceId có khớp với thiết bị nào đã thêm không
    DeviceItem? matchedDevice;
    for (final d in savedDevices) {
      if (d.id == deviceId || d.modelCode.contains(deviceId) || deviceId.contains(d.id)) {
        matchedDevice = d;
        break;
      }
    }

    if (matchedDevice == null) {
      debugPrint('[CallManager 🛡️ Anti-Spam] Bỏ qua: deviceId "$deviceId" KHÔNG TRÙNG với bất kỳ thiết bị nào đã thêm trong App.');
      return null;
    }

    // 4. Kiểm tra thiết bị có đang BẬT thông báo không
    if (!matchedDevice.isNotificationEnabled) {
      debugPrint('[CallManager 🔕] Bỏ qua: Thiết bị "${matchedDevice.name}" đang TẮT nhận thông báo.');
      return null;
    }

    // 5. Kiểm tra chống spam trong vòng 2 phút cho cùng một thiết bị
    final now = DateTime.now().millisecondsSinceEpoch;
    final lastCallTime = _lastCallTimestamps[matchedDevice.id] ?? 0;
    final elapsedMs = now - lastCallTime;

    if (elapsedMs < antiSpamWindowMs) {
      final remainingSec = ((antiSpamWindowMs - elapsedMs) / 1000).ceil();
      debugPrint('[CallManager 🛡️ Anti-Spam] Bỏ qua cuộc gọi cho "${matchedDevice.name}": Vừa gọi cách đây ${(elapsedMs / 1000).toStringAsFixed(1)}s (Chặn lặp trong vòng 2 phút, còn $remainingSec s).');
      return null;
    }

    // Ghi nhận cuộc gọi hợp lệ
    _lastCallTimestamps[matchedDevice.id] = now;
    if (eventId != null && eventId.isNotEmpty) {
      _processedEventIds.add(eventId);
    }

    debugPrint('[CallManager ✅ Cho phép] Thiết bị "${matchedDevice.name}" (ID: ${matchedDevice.id}) đủ điều kiện kích hoạt cuộc gọi.');
    return matchedDevice;
  }

  /// Kích hoạt màn hình cuộc gọi giả lập
  static Future<void> triggerIncomingCall(DeviceItem device, {String? callerName}) async {
    final callUuid = const Uuid().v4();
    final displayName = (callerName != null && callerName.isNotEmpty) ? callerName : device.name;

    final params = CallKitParams(
      id: callUuid,
      nameCaller: displayName,
      appName: 'Washer Notifier',
      avatar: 'https://img.icons8.com/color/96/washing-machine.png',
      handle: 'Quần áo đã giặt xong! (${device.modelCode.isNotEmpty ? device.modelCode : "SmartThings"})',
      type: 0,
      textAccept: 'Xem ngay',
      textDecline: 'Bỏ qua',
      duration: 45000,
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: true,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#1565C0',
        actionColor: '#4CAF50',
        textColor: '#ffffff',
        isShowCallID: false,
      ),
      headers: <String, dynamic>{
        'type': 'TRIGGER_CALL',
        'deviceId': device.id,
        'callUuid': callUuid,
      },
      extra: <String, dynamic>{
        'deviceId': device.id,
      },
    );

    await FlutterCallkitIncoming.showCallkitIncoming(params);
  }

  /// Xử lý dữ liệu FCM nhận được từ background hoặc foreground
  static Future<void> handleFCMMessage(Map<String, dynamic> data) async {
    final type = data['type'];

    // 1. Phản hồi sự kiện đồng bộ thiết bị từ SmartApp Webhook INSTALL / UPDATE
    if (type == 'SYNC_DEVICE') {
      final deviceId = data['deviceId'] ?? data['device_id'];
      final deviceName = data['deviceName'] ?? data['device_name'] ?? 'Máy giặt Samsung';
      if (deviceId != null && deviceId.toString().isNotEmpty) {
        debugPrint('[CallManager 🔄 SYNC_DEVICE] Nhận thông tin đồng bộ thiết bị: $deviceId ($deviceName)');
        await DeviceStorage.upsertDevice(
          id: deviceId.toString(),
          name: deviceName.toString(),
          modelCode: 'SmartThings Washer',
        );
      }
      return;
    }

    // 2. Phản hồi sự kiện giặt xong: TRIGGER_CALL (hoặc WASHING_MACHINE_DONE)
    if (type != 'TRIGGER_CALL' && type != 'WASHING_MACHINE_DONE') {
      debugPrint('[CallManager] Bỏ qua message không thuộc luồng: $type');
      return;
    }

    final deviceId = data['deviceId'] ?? data['device_id'];
    final deviceName = data['deviceName'] ?? data['device_name'];
    final eventId = data['eventId'] ?? data['event_id'];

    // Kiểm tra trong Local Storage: CHỈ gọi hàm hiển thị Fake Call UI nếu isNotificationEnabled === true
    final authorizedDevice = await validateAndAuthorizeCall(
      deviceId: deviceId,
      eventId: eventId,
    );

    if (authorizedDevice != null) {
      await triggerIncomingCall(authorizedDevice, callerName: deviceName);
    }
  }
}
