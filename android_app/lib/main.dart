import 'dart:async';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'firebase_options.dart';

import 'screens/home_screen.dart';
import 'services/device_storage.dart';
import 'services/notification_manager.dart';

// ============================================================
// BACKGROUND MESSAGE HANDLER — Phải là top-level function
// Chạy ngay cả khi app bị tắt hoàn toàn (killed state) hoặc chạy ngầm
// ============================================================
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    try {
      await Firebase.initializeApp();
    } catch (_) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }

    final data = message.data;
    debugPrint('[FCM Background Passive] Nhận Data Message: ${jsonEncode(data)}');

    final type = data['type']?.toString();

    // 1. Block xử lý hứng Data Message có type: 'SYNC_DEVICES'
    if (type == 'SYNC_DEVICES' || type == 'SYNC_DEVICE') {
      debugPrint('[FCM Background] Đang lưu danh sách thiết bị vào Local Storage...');
      await DeviceStorage.handleSyncMessage(Map<String, dynamic>.from(data));
      return;
    }

    // 2. Kích hoạt thông báo đẩy kèm nhạc chuông tùy chỉnh
    await NotificationManager.handleFCMMessage(Map<String, dynamic>.from(data));
  } catch (e) {
    debugPrint('[FCM Background Error]: $e');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Khởi tạo Firebase với cơ chế dự phòng an toàn
  try {
    await Firebase.initializeApp();
  } catch (e) {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } catch (e2) {
      debugPrint('[Firebase Init Fallback Error]: $e2');
    }
  }

  // Khởi tạo Notification Channel & dịch vụ thông báo tùy chỉnh
  await NotificationManager.initialize();

  // Xin quyền Notification (bắt buộc cho Android 13+ và iOS)
  try {
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );
    debugPrint('[FCM] Trạng thái cấp quyền Notification: ${settings.authorizationStatus}');
  } catch (e) {
    debugPrint('[FCM Request Permission Error]: $e');
  }

  // Xin quyền hiển thị thông báo qua Local Notifications plugin
  await NotificationManager.requestPermissions();

  // Đăng ký Background Message Handler để bắt Data Message khi killed / background
  try {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } catch (e) {
    debugPrint('[Background Message Handler Register Error]: $e');
  }

  // Tự động subscribe topic chung dự phòng
  try {
    FirebaseMessaging.instance.subscribeToTopic('washer_done_alerts');
  } catch (_) {}

  // Lắng nghe Foreground FCM (khi người dùng đang mở app)
  FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
    final data = message.data;
    debugPrint('[FCM Foreground Passive] Nhận Data Message: ${jsonEncode(data)}');

    final type = data['type']?.toString();

    // 1. Block xử lý hứng Data Message có type: 'SYNC_DEVICES'
    if (type == 'SYNC_DEVICES' || type == 'SYNC_DEVICE') {
      debugPrint('[FCM Foreground] Đang lưu danh sách thiết bị vào Local Storage...');
      await DeviceStorage.handleSyncMessage(Map<String, dynamic>.from(data));
      return;
    }

    // 2. Kích hoạt thông báo đẩy kèm nhạc chuông tùy chỉnh
    await NotificationManager.handleFCMMessage(Map<String, dynamic>.from(data));
  });

  runApp(const WasherNotifierApp());
}

class WasherNotifierApp extends StatelessWidget {
  const WasherNotifierApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Thông Báo Máy Giặt',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1565C0),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
