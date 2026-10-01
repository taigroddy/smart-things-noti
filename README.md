# 🧺 SmartThings Washer Notifier (Monorepo)

> Hệ thống theo dõi máy giặt thông minh qua Samsung SmartThings và tự động kích hoạt cuộc gọi giả lập (**Fake Incoming Call**) đến điện thoại khi chu trình giặt hoàn tất.
>
> **Đặc tả cốt lõi:**
> - **Backend:** Node.js chạy trên Vercel Serverless (hoặc Docker), sử dụng thư viện chính thức `@smartthings/smartapp` và `firebase-admin`. **Hoàn toàn KHÔNG sử dụng Database ở Backend.**
> - **Mobile App:** Flutter (Android) hoạt động theo mô hình **Passive Listener (Người Lắng Nghe Thụ Động)** siêu nhẹ, nhận Data Message từ FCM, lưu cache danh sách máy giặt bằng Local Storage (`SharedPreferences`) và kích hoạt giao diện cuộc gọi CallKit toàn màn hình.

---

## 📑 Mục lục
1. [Kiến trúc hệ thống (Architecture)](#-kiến-trúc-hệ-thống)
2. [Cấu trúc Monorepo](#-cấu-trúc-monorepo)
3. [Luồng hoạt động (Data Flow)](#-luồng-hoạt-động)
4. [Backend (Vercel / Docker)](#-backend-webapp)
   - [Đặc điểm kỹ thuật](#đặc-điểm-kỹ-thuật-backend)
   - [Biến môi trường](#cấu-hình-biến-môi-trường)
   - [Cài đặt & Triển khai](#triển-khai-backend)
5. [Mobile App (Flutter Android)](#-mobile-app-android_app)
   - [Tính năng chính](#tính-năng-chính-mobile-app)
   - [Quyền hệ điều hành Android](#quyền-hệ-thống-quan-trọng)
   - [Cài đặt APK sẵn có](#cài-đặt-file-apk)
   - [Biên dịch mã nguồn](#biên-dịch-mobile-app)
6. [Hướng dẫn cấu hình trên SmartThings App](#-hướng-dẫn-kết-nối-smartthings)
7. [Kiểm thử tự động (Testing)](#-kiểm-thử-tự-động)

---

## 🏗 Kiến trúc hệ thống

```mermaid
flowchart TD
    subgraph Samsung Cloud
        ST_Dev["Máy Giặt Samsung (Washer)"] -->|"wash finished / stop"| ST_Cloud["Samsung SmartThings Cloud"]
    end

    subgraph Backend [Vercel Serverless Webhook]
        ST_Cloud -->|"POST /api/webhook\n(SmartApp SDK)"| Webhook["webhook.js (@smartthings/smartapp)"]
        Webhook -->|"INSTALL / UPDATE:\nSYNC_DEVICES"| FCM_Admin["Firebase Admin SDK"]
        Webhook -->|"EVENT (finished):\nTRIGGER_CALL"| FCM_Admin
    end

    subgraph Google Cloud
        FCM_Admin -->|"Silent Push\n(Data-Only Message)"| FCM_Server["Firebase Cloud Messaging (FCM)"]
    end

    subgraph Mobile Device [Android Phone - Passive Listener]
        FCM_Server -->|"Data: SYNC_DEVICES"| BG_Handler["FCM Background / Foreground Handler"]
        FCM_Server -->|"Data: TRIGGER_CALL"| BG_Handler
        
        BG_Handler -->|"Lưu danh sách máy"| LocalStorage["Local Storage (SharedPreferences)"]
        LocalStorage -->|"Hiển thị máy giặt & Toast"| UI["HomeScreen UI"]
        
        BG_Handler -->|"Đánh thức & Đổ chuông"| CallKit["Full-Screen Fake Call UI\n(flutter_callkit_incoming)"]
    end
```

---

## 📁 Cấu trúc Monorepo

```text
smart-things/
├── android_app/                        # Ứng dụng di động Flutter (Android)
│   ├── android/app/src/main/
│   │   ├── AndroidManifest.xml        # Quyền WakeLock, FullScreenIntent, ForegroundService...
│   │   └── google-services.json       # Cấu hình Firebase Client Android
│   ├── assets/sounds/                 # File âm thanh chuông giặt xong
│   ├── lib/
│   │   ├── main.dart                  # Background Message Handler & khởi chạy ứng dụng
│   │   ├── audio_service.dart         # Phát nhạc chuông khi người dùng bấm "Xem ngay"
│   │   ├── firebase_options.dart      # Cấu hình Firebase Flutter
│   │   ├── screens/
│   │   │   └── home_screen.dart       # Giao diện chính hiển thị FCM Token & máy giặt đồng bộ
│   │   └── services/
│   │       ├── call_manager.dart      # Quản lý kích hoạt CallKit & bộ lọc chống lặp spam 60s
│   │       └── device_storage.dart    # Quản lý Local Storage (SharedPreferences)
│   ├── test/
│   │   ├── new_flow_test.dart         # Unit tests cho CallManager & DeviceStorage
│   │   └── widget_test.dart           # Widget smoke test cho HomeScreen
│   └── pubspec.yaml                   # Khai báo thư viện (CallKit, FCM, SharedPreferences...)
│
├── webapp/                             # Backend Node.js SmartThings Webhook
│   ├── api/
│   │   └── webhook.js                 # Handler SmartApp chính thức (Configuration, Install, Event)
│   ├── lib/
│   │   └── fcmService.js              # Service gửi FCM Data-Only Message qua Firebase Admin SDK
│   ├── scripts/
│   │   └── test-new-flow.js           # Kịch bản kiểm thử tự động toàn diện cho SmartApp SDK
│   ├── server.js                      # Express server (hỗ trợ chạy Docker cục bộ)
│   ├── vercel.json                    # Cấu hình rewrite định tuyến cho Vercel Serverless
│   ├── package.json                   # Dependencies (@smartthings/smartapp, firebase-admin...)
│   └── .env.example                   # Mẫu cấu hình biến môi trường
│
├── washer-notifier.apk                 # File cài đặt Release APK cho Android ARM64 (Khuyên dùng)
├── washer-notifier-arm64.apk           # File cài đặt Release APK cho Android ARM64 (22 MB)
├── washer-notifier-arm32.apk           # File cài đặt Release APK cho Android ARM32 cũ (19 MB)
├── OS_PERMISSIONS_GUIDE.md             # Hướng dẫn mở quyền chạy ngầm trên Xiaomi/Samsung/Oppo
└── README.md                           # Tài liệu tổng quan dự án (Tài liệu này)
```

---

## 🔄 Luồng hoạt động (Data Flow)

### 1. Luồng Cấu hình & Đồng bộ Thiết bị (`SYNC_DEVICES`)
1. Người dùng mở ứng dụng **Washer Notifier** trên điện thoại, bấm nút **"Sao Chép FCM Token"**.
2. Trên ứng dụng **Samsung SmartThings**, mở cài đặt SmartApp **Washer Notifier**:
   - Dán token vào ô: `Lấy mã từ Ứng dụng Washer Notifier`.
   - Chọn máy giặt cần giám sát trong ô: `Danh sách máy giặt`.
   - Nhấn **Hoàn tất (Done)**.
3. SmartThings gửi sự kiện `INSTALL` hoặc `UPDATE` đến `POST /api/webhook`:
   - SmartApp xóa các subscription cũ (`unsubscribeAll()`).
   - Đăng ký subscription mới theo dõi `washerOperatingState` và `machineState`.
   - Backend lấy `fcmToken` từ cấu hình và duyệt danh sách máy giặt đã chọn để lấy `id` và `name`.
   - Firebase Admin gửi Data Message đến điện thoại:
     ```json
     {
       "data": {
         "type": "SYNC_DEVICES",
         "devices": "[{\"id\":\"d5281b1f-...\",\"name\":\"Máy giặt Cửa trước Samsung\"}]"
       }
     }
     ```
4. Mobile App nhận Data Message:
   - Tự động parse danh sách thiết bị và lưu vào **Local Storage** (`SharedPreferences`).
   - Giao diện chính hiển thị thẻ **"Máy Giặt Đang Được Giám Sát"** kèm thông báo nổi: **"Kết nối SmartThings thành công"**.

### 2. Luồng Báo Giặt Xong & Đổ Chuông Giả Lập (`TRIGGER_CALL`)
1. Khi máy giặt hoàn tất chu trình, SmartThings Cloud gửi sự kiện `EVENT` đến `POST /api/webhook`:
   - Thuộc tính: `washerOperatingState` hoặc `machineState`.
   - Giá trị: `finished` hoặc `stop`.
2. SmartApp Webhook nhận diện sự kiện, trích xuất `fcmToken` và gửi Data Message ưu tiên cao (`high priority`):
   ```json
   {
     "data": {
       "type": "TRIGGER_CALL",
       "deviceId": "d5281b1f-...",
       "deviceName": "Máy giặt Cửa trước Samsung",
       "eventId": "1775199600000",
       "title": "Máy giặt",
       "body": "Quần áo trong máy giặt đã giặt xong!"
     }
   }
   ```
3. Mobile App xử lý ngầm (kể cả khi app bị tắt hoàn toàn hoặc điện thoại đang khóa màn hình):
   - Kiểm tra trùng lặp `eventId` và cơ chế chống spam trong 60 giây.
   - Kích hoạt giao diện cuộc gọi đến toàn màn hình (`flutter_callkit_incoming`):
     - Người gọi: Tên máy giặt (ví dụ: *"Máy giặt Cửa trước Samsung"* hoặc mặc định *"Máy Giặt Thông Minh"*).
     - Phụ đề: *"Quần áo trong máy giặt đã giặt xong!"*.
     - Bật sáng màn hình, đổ chuông hệ thống và rung liên tục.
   - Khi người dùng bấm **"Xem ngay"** (Accept): Tự động phát âm thanh chuông hoàn tất.
   - Khi người dùng bấm **"Bỏ qua"** (Decline): Tắt màn hình cuộc gọi.

---

## 🖥 Backend (`webapp`)

### Đặc điểm kỹ thuật Backend
- Sử dụng SDK chuẩn `@smartthings/smartapp` phiên bản **4.3.8** giúp tương thích 100% với giao diện SmartThings App thế hệ mới.
- Khởi tạo `firebase-admin` theo cơ chế Singleton chống lỗi lặp ứng dụng khi chạy trên Serverless Functions của Vercel.
- Gửi tin nhắn ngầm dạng **Data-Only Message** (không chứa trường `notification`) để ứng dụng di động tự toàn quyền điều khiển UI CallKit.

### Cấu hình biến môi trường
Tạo file `.env` tại thư mục `webapp/` (tham khảo [.env.example](file:///workspace/smart-things/webapp/.env.example)):

```bash
# 1. Firebase Admin SDK Service Account (Bắt buộc)
# Lấy file JSON từ: Firebase Console -> Project Settings -> Service Accounts -> Generate new private key
# Rút gọn nội dung JSON lên 1 dòng duy nhất:
FIREBASE_SERVICE_ACCOUNT={"type":"service_account","project_id":"smart-things-noti","private_key_id":"...","private_key":"-----BEGIN PRIVATE KEY-----\\n...\\n-----END PRIVATE KEY-----\\n","client_email":"firebase-adminsdk-xxx@smart-things-noti.iam.gserviceaccount.com"}

# 2. Token thiết bị dự phòng (Tùy chọn)
FCM_DEVICE_TOKEN=your_fcm_token_fallback

# 3. URL Webhook công khai (HTTPS)
WEBHOOK_TARGET_URL=https://your-domain.vercel.app/api/webhook

# 4. Cổng lắng nghe khi chạy Docker
PORT=3000
```

### Triển khai Backend

#### Cách 1: Triển khai lên Vercel (Khuyên dùng)
1. Cài đặt Vercel CLI hoặc kết nối GitHub repo với Vercel.
2. Vào **Project Settings → Environment Variables** trên Vercel Dashboard, thêm biến `FIREBASE_SERVICE_ACCOUNT`.
3. Vercel sẽ tự động build và cung cấp endpoint tại `https://<ten-project>.vercel.app/api/webhook`.

#### Cách 2: Chạy cục bộ hoặc Docker
```bash
cd webapp
npm install

# Chạy server development
npm run dev

# Hoặc khởi chạy bằng Docker
docker compose up -d --build
```

---

## 📱 Mobile App (`android_app`)

### Tính năng chính Mobile App
- **Giao diện Passive Listener:** Hiển thị mã FCM Token, trạng thái lắng nghe, danh sách các máy giặt đã được kết nối từ SmartThings và nút kiểm thử cuộc gọi nhanh.
- **Local Storage Cache:** Lưu danh sách máy giặt cục bộ qua `SharedPreferences`, tự phục hồi giao diện ngay khi mở lại ứng dụng.
- **Bộ lọc chống spam thông minh:**
  - Lọc theo `eventId` của SmartThings (không kích hoạt lại nếu nhận trùng).
  - Cửa sổ chặn lặp 60 giây giữa các cuộc gọi liên tiếp.

### Quyền hệ thống quan trọng
Trong [AndroidManifest.xml](file:///workspace/smart-things/android_app/android/app/src/main/AndroidManifest.xml), ứng dụng đã cấu hình sẵn các quyền:
- `POST_NOTIFICATIONS`: Nhận tin nhắn thông báo (Android 13+).
- `WAKE_LOCK`: Đánh thức CPU và bật sáng màn hình khi máy giặt báo xong.
- `USE_FULL_SCREEN_INTENT`: Hiển thị giao diện cuộc gọi đè lên màn hình khóa.
- `DISABLE_KEYGUARD`: Bỏ qua khóa màn hình tạm thời khi có cuộc gọi đến.
- `FOREGROUND_SERVICE` & `FOREGROUND_SERVICE_DATA_SYNC`: Duy trì dịch vụ xử lý dữ liệu nền.
- `VIBRATE`: Rung chuông cảnh báo.

> [!IMPORTANT]
> **Lưu ý đối với các dòng máy Android tùy biến (Xiaomi MIUI/HyperOS, OPPO ColorOS, Samsung OneUI):**
> Vui lòng tham khảo tệp [OS_PERMISSIONS_GUIDE.md](file:///workspace/smart-things/OS_PERMISSIONS_GUIDE.md) để bật quyền **"Hiển thị trên màn hình khóa"** và tắt **"Tối ưu hóa pin"** cho ứng dụng nhằm đảm bảo cuộc gọi luôn kích hoạt 100% khi màn hình tắt.

### Cài đặt file APK
File APK đã được biên dịch sẵn tại thư mục gốc của dự án:
- [washer-notifier.apk](file:///workspace/smart-things/washer-notifier.apk) (hoặc `washer-notifier-arm64.apk`): Bản tối ưu cho hầu hết điện thoại Android 64-bit hiện đại (22 MB).
- [washer-notifier-arm32.apk](file:///workspace/smart-things/washer-notifier-arm32.apk): Dành cho các thiết bị Android 32-bit cũ (19 MB).

### Biên dịch Mobile App
Nếu muốn tự biên dịch file APK từ mã nguồn:
```bash
cd android_app
flutter pub get
flutter build apk --release --split-per-abi --android-skip-build-dependency-validation
```

---

## 📲 Hướng dẫn kết nối SmartThings

1. **Bước 1:** Cài đặt file `washer-notifier.apk` lên điện thoại, mở ứng dụng và nhấn **"Sao Chép FCM Token"**.
2. **Bước 2:** Truy cập [SmartThings Developer Workspace](https://smartthings.developer.samsung.com/workspace/):
   - Đăng ký SmartApp dạng **Webhook SmartApp**.
   - Điền Target URL là endpoint Backend: `https://your-domain.vercel.app/api/webhook`.
   - Chọn quyền `r:devices:*` và `x:devices:*`.
3. **Bước 3:** Trên điện thoại, mở ứng dụng **Samsung SmartThings**:
   - Vào mục **Menu / Dấu 3 chấm** → Bật **Developer Mode** (Chế độ nhà phát triển).
   - Vào tab **Tự động hóa (Automations)** hoặc **Thêm thiết bị** → Chọn SmartApp **Washer Notifier** (trong mục Custom/Developer).
4. **Bước 4:** Thiết lập cấu hình SmartApp:
   - Dán chuỗi Token vào ô **"Lấy mã từ Ứng dụng Washer Notifier"**.
   - Chọn máy giặt trong ô **"Danh sách máy giặt"**.
   - Nhấn **Hoàn tất (Done)**.
5. **Bước 5:** Mở lại ứng dụng **Washer Notifier** trên điện thoại:
   - Màn hình sẽ hiển thị thẻ **"Máy Giặt Đang Được Giám Sát"** cùng thông báo **"Kết nối SmartThings thành công"**.

---

## 🧪 Kiểm thử tự động

### Kiểm thử Backend (Vercel Webhook & SmartApp SDK)
Chạy script kiểm thử giả lập toàn bộ vòng đời SmartApp (Configuration, Install, Event):
```bash
cd webapp
node scripts/test-new-flow.js
```
*Kết quả:* **14/14 tests PASSED** (Kiểm tra cấu hình input, phân quyền 1 capability, INSTALL SYNC_DEVICES và EVENT TRIGGER_CALL).

### Kiểm thử Mobile App (Flutter)
Chạy unit tests cho logic CallManager và DeviceStorage:
```bash
cd android_app
flutter test
```
*Kết quả:* **6/6 tests PASSED**.

Kiểm tra cú pháp và chất lượng mã nguồn:
```bash
cd android_app
flutter analyze
```
*Kết quả:* **No issues found!**
