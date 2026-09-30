import 'dart:async';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'firebase_options.dart';
import 'audio_service.dart';
import 'screens/device_list_screen.dart';
import 'services/call_manager.dart';

// ============================================================
// BACKGROUND MESSAGE HANDLER — Phải là top-level function
// Được gọi khi app bị kill hoặc chạy ngầm
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
    debugPrint('[FCM Background] Nhận message: ${jsonEncode(data)}');

    // Chuyển qua CallManager kiểm tra trùng deviceId và chống spam 2 phút
    await CallManager.handleFCMMessage(Map<String, dynamic>.from(data));
  } catch (e) {
    debugPrint('[FCM Background Error]: $e');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Khởi tạo Firebase với cơ chế an toàn kép
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

  // Đăng ký background message handler an toàn
  try {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } catch (e) {
    debugPrint('[Background Message Handler Register Error]: $e');
  }

  // Lắng nghe sự kiện từ màn hình cuộc gọi giả (Accept / Decline)
  try {
    FlutterCallkitIncoming.onEvent.listen((CallEvent? event) async {
      if (event == null) return;

      switch (event.event) {
        case Event.actionCallAccept:
          debugPrint('[CallKit] Người dùng nhấn Xem ngay');
          await AudioService.playWasherDoneSound();
          break;
        case Event.actionCallDecline:
          debugPrint('[CallKit] Người dùng nhấn Bỏ qua');
          break;
        case Event.actionCallEnded:
          debugPrint('[CallKit] Cuộc gọi kết thúc');
          break;
        default:
          break;
      }
    });
  } catch (e) {
    debugPrint('[CallKit Event Listener Error]: $e');
  }

  // Tự động subscribe topic 'washer_done_alerts'
  try {
    FirebaseMessaging.instance.subscribeToTopic('washer_done_alerts');
  } catch (_) {}

  // Lắng nghe foreground FCM
  FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
    debugPrint('[FCM Foreground] Nhận message: ${jsonEncode(message.data)}');
    // Chuyển qua CallManager kiểm tra trùng deviceId và chống spam 2 phút
    await CallManager.handleFCMMessage(Map<String, dynamic>.from(message.data));
  });

  runApp(const WasherNotifierApp());
}

class WasherNotifierApp extends StatelessWidget {
  const WasherNotifierApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Washer Notifier',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1565C0),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const DeviceListScreen(),
    );
  }
}
