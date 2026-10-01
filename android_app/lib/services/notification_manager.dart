import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'device_storage.dart';

/// Dịch vụ quản lý Thông báo đẩy kèm nhạc chuông tùy chỉnh (Custom Sound Notification)
/// Thay thế hoàn toàn CallKit cũ nhưng vẫn giữ nguyên kiến trúc Passive Listener
class NotificationManager {
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static bool _isInitialized = false;

  // Cấu hình Kênh thông báo riêng biệt cho Máy Giặt
  static const String channelId = 'washer_done_channel';
  static const String channelName = 'Thông Báo Máy Giặt Xong';
  static const String channelDescription =
      'Kênh phát chuông báo động âm thanh lớn khi máy giặt hoàn tất chu trình';

  // Tên file âm thanh tùy chỉnh (không kèm đuôi file trên Android)
  static const String soundName = 'samsung_washing_machin';

  // Chống spam: Lưu thời điểm thông báo gần nhất (ms)
  static int _lastNotificationTimestamp = 0;

  // Chống duplicate: Lưu các eventId đã xử lý trong phiên
  static final Set<String> _processedEventIds = {};

  // Cửa sổ chống lặp liên tiếp (60 giây)
  static const int antiSpamWindowMs = 60 * 1000;

  @visibleForTesting
  static void resetAntiSpamForTesting() {
    _lastNotificationTimestamp = 0;
    _processedEventIds.clear();
  }

  /// Khởi tạo thư viện Local Notifications và tạo Kênh thông báo Android
  static Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Cấu hình Android: icon thông báo mặc định
      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      // Cấu hình iOS / Darwin
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );

      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _localNotifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          debugPrint('[NotificationManager 🔔] Người dùng nhấn vào thông báo: ${response.payload}');
        },
      );

      // Tạo Kênh thông báo Android với mức ưu tiên cao nhất và âm thanh tùy chỉnh
      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      if (androidPlugin != null) {
        const androidChannel = AndroidNotificationChannel(
          channelId,
          channelName,
          description: channelDescription,
          importance: Importance.max,
          playSound: true,
          sound: RawResourceAndroidNotificationSound(soundName),
          enableVibration: true,
          showBadge: true,
        );

        await androidPlugin.createNotificationChannel(androidChannel);
        debugPrint('[NotificationManager 📢] Đã tạo Android Notification Channel: $channelId');
      }

      _isInitialized = true;
    } catch (e) {
      debugPrint('[NotificationManager ⚠️] Lỗi khởi tạo Local Notifications: $e');
    }
  }

  /// Xin quyền hiển thị thông báo (Android 13+ và iOS)
  static Future<void> requestPermissions() async {
    try {
      // Xin quyền Android 13+ (POST_NOTIFICATIONS)
      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        final granted = await androidPlugin.requestNotificationsPermission();
        debugPrint('[NotificationManager 🛡️] Quyền thông báo Android: $granted');
      }

      // Xin quyền iOS
      final iosPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>();
      if (iosPlugin != null) {
        final granted = await iosPlugin.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        debugPrint('[NotificationManager 🛡️] Quyền thông báo iOS: $granted');
      }
    } catch (e) {
      debugPrint('[NotificationManager ⚠️] Lỗi xin quyền thông báo: $e');
    }
  }

  /// Hiển thị thông báo đẩy kèm nhạc chuông tùy chỉnh
  static Future<void> showWasherDoneNotification({
    String? title,
    String? body,
    String? deviceId,
    String? deviceName,
  }) async {
    // Đảm bảo đã khởi tạo
    await initialize();

    final notiTitle = (title != null && title.isNotEmpty)
        ? title
        : 'Máy Giặt Xong Rồi!';

    final notiBody = (body != null && body.isNotEmpty)
        ? body
        : (deviceName != null && deviceName.isNotEmpty)
            ? '$deviceName đã hoàn tất chu trình giặt!'
            : 'Quần áo của bạn đã giặt xong!';

    // Cấu hình chi tiết thông báo cho Android
    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.max,
      priority: Priority.high,
      sound: const RawResourceAndroidNotificationSound(soundName),
      playSound: true,
      enableVibration: true,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
      styleInformation: BigTextStyleInformation(
        notiBody,
        contentTitle: notiTitle,
        summaryText: 'Washer Notifier',
      ),
    );

    // Cấu hình chi tiết thông báo cho iOS
    final iosDetails = DarwinNotificationDetails(
      sound: '$soundName.caf',
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
    );

    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    // Tạo ID thông báo duy nhất theo thời gian
    final notificationId = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    try {
      debugPrint('[NotificationManager 🔔] Đang phát thông báo: "$notiTitle" - "$notiBody"');
      await _localNotifications.show(
        notificationId,
        notiTitle,
        notiBody,
        notificationDetails,
        payload: deviceId,
      );
    } catch (e) {
      debugPrint('[NotificationManager ⚠️] Lỗi phát thông báo local: $e');
    }
  }

  /// Xử lý Data Message nhận được từ Firebase Cloud Messaging (Background & Foreground)
  /// Phân tích dữ liệu, kiểm tra client-side toggle, chống spam và kích hoạt thông báo
  static Future<void> handleFCMMessage(Map<String, dynamic> data) async {
    debugPrint('[NotificationManager 📨] Phân tích FCM data: $data');

    final type = data['type']?.toString();

    // Chỉ nhận các type thông báo giặt xong
    if (type != 'TRIGGER_CALL' &&
        type != 'TRIGGER_NOTI' &&
        type != 'WASHING_MACHINE_DONE') {
      debugPrint('[NotificationManager ℹ️] Bỏ qua message không phải lệnh thông báo (type: $type)');
      return;
    }

    final eventId = data['eventId']?.toString() ?? data['event_id']?.toString();
    final deviceName = data['deviceName']?.toString() ??
        data['device_name']?.toString() ??
        data['title']?.toString();
    final deviceId = data['deviceId']?.toString() ?? data['device_id']?.toString();
    final messageBody = data['body']?.toString();
    final messageTitle = data['title']?.toString();

    // 0. Kiểm tra nếu người dùng đã tắt chuông thông báo cho thiết bị này trên ứng dụng
    if (deviceId != null && deviceId.isNotEmpty) {
      final isEnabled = await DeviceStorage.isDeviceEnabled(deviceId);
      if (!isEnabled) {
        debugPrint('[NotificationManager 🔕 Anti-Spam] Thiết bị "$deviceId" đã bị tắt chuông trong cài đặt ứng dụng. Bỏ qua thông báo.');
        return;
      }
    }

    // 1. Kiểm tra duplicate qua eventId
    if (eventId != null && eventId.isNotEmpty) {
      if (_processedEventIds.contains(eventId)) {
        debugPrint('[NotificationManager 🛡️ Anti-Spam] Bỏ qua vì eventId "$eventId" đã được xử lý.');
        return;
      }
      _processedEventIds.add(eventId);
    }

    // 2. Chống lặp nhiều thông báo liên tiếp trong vòng 60 giây
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastNotificationTimestamp < antiSpamWindowMs) {
      final elapsed = ((now - _lastNotificationTimestamp) / 1000).toStringAsFixed(1);
      debugPrint('[NotificationManager 🛡️ Anti-Spam] Bỏ qua: Vừa thông báo cách đây ${elapsed}s (chặn lặp 60s).');
      return;
    }
    _lastNotificationTimestamp = now;

    // 3. Kích hoạt Local Notification kèm nhạc chuông tùy chỉnh
    await showWasherDoneNotification(
      title: messageTitle ?? 'Máy Giặt Xong Rồi!',
      body: messageBody,
      deviceId: deviceId,
      deviceName: deviceName,
    );
  }
}
