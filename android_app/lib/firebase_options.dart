// File này được tự động tạo bởi FlutterFire CLI.
// Chạy: flutterfire configure --project=smart-things-noti
// để tạo lại file này từ Firebase project thực tế.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions have not been configured for web. '
        'You can reconfigure this by running the FlutterFire CLI again.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for iOS. '
          'Chỉ hỗ trợ Android trong dự án này.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  // ====================================================================
  // LẤY CÁC GIÁ TRỊ NÀY TỪ FILE google-services.json:
  // Project: smart-things-noti
  // Package: com.smartthingnoti.app
  // ====================================================================
  static const FirebaseOptions android = FirebaseOptions(
    // project_info.project_number
    appId: '1:438119016666:android:36fa5413cb225509b25de3',
    // client[0].api_key[0].current_key
    apiKey: 'AIzaSyBn3waGdWjic3k7SBroxWclU8aQDepMja0',
    // project_info.project_id
    projectId: 'smart-things-noti',
    // project_info.storage_bucket
    storageBucket: 'smart-things-noti.firebasestorage.app',
    // project_info.project_number
    messagingSenderId: '438119016666',
  );
}
