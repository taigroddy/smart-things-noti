# 📱 Washer Notifier — Mobile App (Flutter)

> Ứng dụng di động Android hoạt động theo mô hình **Passive Listener (Người Lắng Nghe Thụ Động)** siêu nhẹ, nhận Data Message từ Firebase Cloud Messaging (FCM) và kích hoạt cuộc gọi giả lập (**Fake Incoming Call**) qua CallKit khi máy giặt giặt xong.

---

## 📌 Tổng quan Kiến trúc Client
- **Không yêu cầu xác thực SmartThings:** Ứng dụng không gọi REST API của SmartThings, không cần OAuth2 hoặc Personal Access Token (PAT).
- **FCM Data Message:** Bắt trọn tin nhắn ngầm (Silent Push) qua cả Foreground và Background Handler (`@pragma('vm:entry-point')`).
- **Local Storage Cache:** Sử dụng `shared_preferences` để lưu danh sách máy giặt nhận được từ sự kiện `SYNC_DEVICES`.
- **Cuộc gọi toàn màn hình:** Tích hợp `flutter_callkit_incoming` kèm bộ lọc chống spam 60 giây và chống trùng `eventId`.

---

## 📁 Cấu trúc Thư mục

```text
android_app/
├── android/app/src/main/
│   ├── AndroidManifest.xml        # Quyền WakeLock, FullScreenIntent, ForegroundService...
│   └── google-services.json       # Cấu hình Firebase Client Android
├── assets/sounds/                 # Âm thanh giai điệu hoàn tất khi bấm "Xem ngay"
├── lib/
│   ├── main.dart                  # Background Message Handler & khởi chạy ứng dụng
│   ├── audio_service.dart         # Phát nhạc chuông báo giặt xong
│   ├── firebase_options.dart      # Cấu hình Firebase Flutter
│   ├── screens/
│   │   └── home_screen.dart       # Giao diện chính hiển thị FCM Token & máy giặt đồng bộ
│   └── services/
│       ├── call_manager.dart      # Quản lý kích hoạt CallKit & bộ lọc chống lặp spam 60s
│       └── device_storage.dart    # Quản lý Local Storage (SharedPreferences)
├── test/
│   ├── new_flow_test.dart         # Unit tests cho CallManager & DeviceStorage
│   └── widget_test.dart           # Widget smoke test cho HomeScreen
└── pubspec.yaml                   # Khai báo thư viện phụ thuộc
```

---

## 🛠 Lệnh Phát Triển & Kiểm Thử

### 1. Cài đặt dependencies
```bash
flutter pub get
```

### 2. Kiểm tra chất lượng mã nguồn
```bash
flutter analyze
```

### 3. Chạy Unit & Widget Test
```bash
flutter test
```

### 4. Biên dịch Release APK
```bash
flutter build apk --release --split-per-abi --android-skip-build-dependency-validation
```
File APK xuất xưởng sẽ nằm tại:
- `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` (Bản 64-bit hiện đại)
- `build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk` (Bản 32-bit)

---

## 📖 Tài liệu liên quan
- [Tài liệu Tổng quan Dự án (README)](../README.md)
- [Đặc tả Chi tiết Logic Nghiệp vụ (BUSINESS_LOGIC.md)](../BUSINESS_LOGIC.md)
- [Hướng dẫn Mở quyền Chạy ngầm Android (OS_PERMISSIONS_GUIDE.md)](../OS_PERMISSIONS_GUIDE.md)
