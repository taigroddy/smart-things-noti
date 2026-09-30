# SmartThings Washer Notification Monorepo

Hệ thống thông báo máy giặt thông minh gồm 2 thành phần chính:
1. **`webapp/`**: Backend Node.js nhận Webhook từ Samsung SmartThings và gửi Push Notification (Data-Only Message) qua Firebase Admin SDK (hỗ trợ triển khai Docker & Vercel).
2. **`android_app/`**: Ứng dụng di động Flutter nhận Push Notification và hiển thị giao diện giả lập cuộc gọi đến (**Fake Incoming Call**) khi máy giặt giặt xong.

---

## 📁 Cấu trúc Monorepo

```text
smart-things/
├── android_app/               # Ứng dụng di động Flutter
│   ├── android/               # Cấu hình Android (google-services.json, Manifest permissions...)
│   ├── assets/sounds/         # Âm thanh thông báo
│   ├── lib/                   # Mã nguồn Dart (FCM setup, CallKit Incoming UI, AudioService...)
│   ├── pubspec.yaml           # Dependencies Flutter
│   └── washer-notifier.apk    # File APK đã biên dịch sẵn
│
├── webapp/                    # Backend Serverless / Docker
│   ├── api/                   # Serverless Function (/api/webhook.js)
│   ├── lib/                   # Firebase Admin SDK & FCM service
│   ├── scripts/               # CLI script setup subscription & test webhook
│   ├── server.js              # Express server cho Docker
│   ├── Dockerfile             # Cấu hình build Docker image
│   ├── docker-compose.yml     # Khởi chạy dịch vụ Docker
│   ├── vercel.json            # Cấu hình định tuyến Vercel
│   └── .env.example           # Mẫu biến môi trường
│
└── washer-notifier.apk        # File cài đặt APK tiện tải về trực tiếp
```

---

## 🚀 Hướng Dẫn Nhanh

### 1. Ứng dụng Android (`android_app`)
- **Cài đặt ngay:** Tải file `washer-notifier.apk` và cài đặt lên điện thoại Android.
- **Lấy Token:** Mở app, nhấn nút **"Copy Token"** để lấy `FCM_DEVICE_TOKEN`.
- **Cấp quyền:** Cho phép thông báo (Notification) và quyền **Xuất hiện trên cùng (Display over other apps)**.

### 2. Backend Webhook (`webapp`)
- **Triển khai bằng Docker:**
  ```bash
  cd webapp
  cp .env.example .env
  # Điền các biến môi trường vào .env
  docker compose up -d --build
  ```
- **Triển khai trên Vercel:**
  - Cấu hình các biến môi trường trên Vercel Dashboard (Project Settings → Environment Variables):
    - `SMARTTHINGS_PAT`
    - `SMARTTHINGS_WASHER_DEVICE_ID`
    - `FIREBASE_SERVICE_ACCOUNT`
    - `FCM_DEVICE_TOKEN`
    - `WEBHOOK_TARGET_URL`
