# HƯỚNG DẪN CẤU HÌNH QUYỀN HỆ ĐIỀU HÀNH (OS PERMISSIONS GUIDE)
## Để Cuộc Gọi Giả Lập (Fake Call) Hoạt Động Khi Tắt Màn Hình & Chạy Ngầm

Tài liệu này hướng dẫn chi tiết các cấu hình Native bắt buộc trên cả **Android** và **iOS** để ứng dụng có thể đánh thức màn hình (Wake-up), chạy ngầm (Background Service) và bật giao diện cuộc gọi giả lập toàn màn hình (Full-screen Incoming Call) ngay cả khi điện thoại đang khoá màn hình hoặc bị Kill process.

---

## 1. CẤU HÌNH ANDROID

Dự án đã được tích hợp đầy đủ các quyền này trong file `android_app/android/app/src/main/AndroidManifest.xml`:

### A. Danh sách các Quyền trong `AndroidManifest.xml`
```xml
<!-- 1. Quyền nhận thông báo đẩy trên Android 13+ (API 33+) -->
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>

<!-- 2. Quyền đánh thức CPU và bật sáng màn hình khi nhận tín hiệu giặt xong -->
<uses-permission android:name="android.permission.WAKE_LOCK"/>

<!-- 3. Quyền hiển thị giao diện cuộc gọi đè lên màn hình khoá (Full-Screen Intent) -->
<uses-permission android:name="android.permission.USE_FULL_SCREEN_INTENT"/>
<uses-permission android:name="android.permission.DISABLE_KEYGUARD"/>

<!-- 4. Quyền chạy dịch vụ Foreground / Data Sync dưới nền -->
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC"/>

<!-- 5. Quyền mạng và rung chuông cuộc gọi -->
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
<uses-permission android:name="android.permission.VIBRATE"/>
```

### B. Cấu hình Activity để bật sáng màn hình khi khoá
Trong thẻ `<activity android:name=".MainActivity" ...>` cần có:
```xml
android:showOnLockScreen="true"
android:turnScreenOn="true"
```

### C. Cài đặt tối ưu hóa Pin trên thiết bị Android của người dùng (Cực kỳ quan trọng)
Các dòng máy như **Xiaomi (MIUI/HyperOS), Samsung (OneUI), Oppo/Realme, Huawei** có trình diệt app ngầm rất mạnh. Để không bị lỡ cuộc gọi khi tắt màn hình lâu:
1. Vào **Cài đặt điện thoại** > **Ứng dụng** > Chọn **Washer Notifier**.
2. **Quyền riêng biệt**:
   - Cho phép **"Hiển thị trên màn hình khoá"** (Show on Lock Screen).
   - Cho phép **"Cửa sổ nổi / Hiển thị trên các ứng dụng khác"** (Display pop-up windows).
   - Cho phép **"Tự khởi chạy / Tự động chạy ngầm"** (Auto-start).
3. **Tiết kiệm pin**: Đổi từ *"Tối ưu hóa (Mặc định)"* sang **"Không hạn chế"** (No restrictions).

---

## 2. CẤU HÌNH iOS (APPLE)

Nếu triển khai bản build iOS, Apple có cơ chế bảo mật khắt khe hơn. Cần cấu hình VoIP Push và Background Modes như sau:

### A. Kích hoạt Capabilities trong Xcode (`Signing & Capabilities`)
1. Bật **Push Notifications**.
2. Bật **Background Modes**:
   - Tích chọn `Audio, AirPlay, and Picture in Picture`.
   - Tích chọn `Voice over IP`.
   - Tích chọn `Remote notifications`.
   - Tích chọn `Background fetch`.

### B. Cấu hình file `ios/Runner/Info.plist`
Chèn các khóa cấu hình sau vào trong thẻ `<dict>`:
```xml
<!-- 1. Background Modes cho VoIP và Push -->
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
    <string>fetch</string>
    <string>remote-notification</string>
    <string>voip</string>
</array>

<!-- 2. Quyền Micro (nếu CallKit yêu cầu phiên âm thanh) -->
<key>NSMicrophoneUsageDescription</key>
<string>Ứng dụng cần quyền âm thanh để phát chuông báo khi máy giặt hoàn tất chu trình.</string>

<!-- 3. Cấu hình CallKit Incoming Call -->
<key>supportsVideo</key>
<false/>
```

### C. Cấu hình APNs (Apple Push Notification service) với Firebase
Vì iOS không cho phép Data Message thông thường đánh thức ứng dụng khi bị Kill hoàn toàn nếu không có **VoIP Push Notification (PushKit)** hoặc **High-priority APNs**:
1. Vào **Apple Developer Portal** > Tạo **APNs Auth Key (.p8)** (chọn quyền Apple Push Notifications service).
2. Vào **Firebase Console** > Project Settings > **Cloud Messaging** > Mục **Apple app configuration**:
   - Upload file Key `.p8`.
   - Điền **Key ID** và **Team ID**.
3. Backend Vercel (`webapp/lib/fcmService.js`) đã được cấu hình sẵn header APNs chuẩn:
   ```javascript
   apns: {
     headers: {
       'apns-push-type': 'background',
       'apns-priority': '5', // hoặc '10' nếu dùng VoIP push
     },
     payload: {
       aps: {
         'content-available': 1,
       },
     },
   }
   ```
4. Khi app nhận được VoIP Push trên iOS, `flutter_callkit_incoming` sẽ tự động hiển thị màn hình cuộc gọi chuẩn của hệ thống iOS (CallKit Native UI).
