# SmartThings Washer FCM Webhook Service (Docker & Vercel)

Hệ thống Node.js trung gian nhận Webhook từ Samsung SmartThings khi máy giặt hoàn thành chu trình giặt, sau đó gửi **Push Notification dạng Data-Only Message** qua **Firebase Cloud Messaging (FCM)** đến thiết bị di động (được tối ưu độ ưu tiên cao để đánh thức ứng dụng dưới nền).

Dự án hỗ trợ triển khai linh hoạt bằng **Docker** (Docker Compose) hoặc **Vercel Serverless Function**.

---

## 1. Cấu trúc thư mục

```text
smart-things/
├── api/
│   └── webhook.js             # Xử lý các Lifecycle của SmartThings (CONFIRMATION, PING, EVENT)
├── lib/
│   └── fcmService.js          # Khởi tạo Firebase Admin SDK & hàm sendFCMAlert (Data-Only Message)
├── scripts/
│   ├── setup-subscription.js  # CLI tự động đăng ký Webhook và Subscription với SmartThings API
│   └── test-webhook.js        # Script test giả lập SmartThings PING, CONFIRMATION, EVENT
├── server.js                  # Máy chủ Express chạy trong Docker / local environment
├── Dockerfile                 # Image Docker production trên nền Node.js 22 Alpine
├── docker-compose.yml         # File cấu hình triển khai Docker Compose
├── .dockerignore              # Danh sách loại trừ khi build Docker
├── package.json               # Khai báo dependencies và scripts
├── vercel.json                # Cấu hình rewrite URL cho Vercel (nếu dùng Vercel)
├── .env.example               # Mẫu khai báo biến môi trường
└── README.md                  # Hướng dẫn chi tiết
```

---

## 2. Cấu hình biến môi trường (`.env`)

Sao chép `.env.example` thành `.env`:
```bash
cp .env.example .env
```

Điền đầy đủ 5 biến môi trường bắt buộc:

| Tên biến | Mô tả | Cách lấy |
| :--- | :--- | :--- |
| `SMARTTHINGS_PAT` | Personal Access Token của SmartThings | Tạo tại [SmartThings Tokens](https://account.smartthings.com/tokens) (chọn quyền `devices`, `installedapps`, `apps`). |
| `SMARTTHINGS_WASHER_DEVICE_ID` | ID của máy giặt Samsung | Xem qua script setup hoặc API SmartThings. |
| `FIREBASE_SERVICE_ACCOUNT` | Chuỗi JSON của Firebase Service Account | Tải từ **Firebase Console** -> **Project Settings** -> **Service accounts** -> **Generate new private key**. Nén chuỗi JSON trên 1 dòng. |
| `FCM_DEVICE_TOKEN` | Token FCM của thiết bị di động | Lấy từ ứng dụng Android/iOS của người dùng. |
| `WEBHOOK_TARGET_URL` | Đường dẫn công khai tới endpoint Webhook | Phải là URL **HTTPS** hợp lệ (ví dụ: qua Cloudflare Tunnel, ngrok, VPS có SSL, hoặc Vercel). |

---

## 3. Triển khai bằng Docker 🐳

### Cách 1: Sử dụng Docker Compose (Khuyên dùng)

1. Tạo file `.env` và cấu hình các biến môi trường như trên.
2. Khởi chạy container:
   ```bash
   docker compose up -d --build
   ```
3. Xem log hoạt động:
   ```bash
   docker compose logs -f
   ```
4. Kiểm tra sức khỏe dịch vụ:
   ```bash
   curl http://localhost:3000/health
   ```
5. Dừng dịch vụ:
   ```bash
   docker compose down
   ```

### Cách 2: Sử dụng Docker CLI thuần

```bash
# Build image
docker build -t smartthings-fcm-webhook:latest .

# Run container kèm file .env
docker run -d \
  --name smartthings-webhook \
  --restart unless-stopped \
  -p 3000:3000 \
  --env-file .env \
  smartthings-fcm-webhook:latest
```

> **Lưu ý quan trọng về Webhook URL với SmartThings:**  
> Samsung SmartThings yêu cầu Webhook URL công khai và bắt buộc có **HTTPS**.  
> Khi chạy Docker trên máy tính cục bộ hoặc mạng nội bộ (homelab/NAS), bạn có thể dùng **Cloudflare Tunnel** (miễn phí, ổn định) hoặc **ngrok**:
> ```bash
> # Ví dụ dùng Cloudflare Tunnel:
> cloudflared tunnel --url http://localhost:3000
> # Hoặc ngrok:
> ngrok http 3000
> ```
> Sau đó gán URL HTTPS sinh ra kèm path `/api/webhook` vào biến `WEBHOOK_TARGET_URL` trong file `.env`.

---

## 4. Triển khai trên Vercel (Tùy chọn) ⚡

Nếu muốn triển khai dạng Serverless không cần quản lý máy chủ:
1. Cài đặt Vercel CLI hoặc kết nối GitHub repo với Vercel Dashboard.
2. Thêm các biến môi trường trong **Project Settings -> Environment Variables** trên Vercel:
   - `SMARTTHINGS_PAT`
   - `SMARTTHINGS_WASHER_DEVICE_ID`
   - `FIREBASE_SERVICE_ACCOUNT`
   - `FCM_DEVICE_TOKEN`
   - `WEBHOOK_TARGET_URL` (ví dụ: `https://your-app.vercel.app/api/webhook`)
3. Deploy:
   ```bash
   vercel --prod
   ```

---

## 5. Quy trình Đăng ký Webhook & Subscription SmartThings 📡

Sau khi container hoặc endpoint Webhook đã hoạt động và có URL HTTPS công khai:

Chạy script tự động:
```bash
npm run setup:subscription
```

Script sẽ thực hiện:
1. Kiểm tra Token SmartThings và quét danh sách thiết bị để tìm máy giặt.
2. Đăng ký SmartApp Webhook trỏ về `WEBHOOK_TARGET_URL`. SmartThings sẽ gửi request `CONFIRMATION` tới máy chủ, máy chủ của bạn sẽ tự động xác thực URL đó.
3. Hướng dẫn hoặc tự động đăng ký Subscription lắng nghe sự kiện `washerOperatingState`.

---

## 6. Kiểm tra giả lập (Mock Test) 🧪

Bạn có thể kiểm tra trực tiếp phản hồi của server và gửi thử thông báo mà không cần đợi máy giặt thật kết thúc:

```bash
# 1. Test phản hồi PING challenge từ SmartThings
npm run test:ping

# 2. Test phản hồi CONFIRMATION xác thực Webhook URL
npm run test:confirm

# 3. Test giả lập sự kiện máy giặt "finished" (sẽ kích hoạt gửi FCM tới thiết bị)
npm run test:event
```

---

## 7. Chi tiết Payload FCM (Data-Only Message)

Để ứng dụng di động có thể nhận thông báo kể cả khi đang đóng hoàn toàn hoặc chạy dưới nền:
- **Android:** Gửi dạng `data` thuần túy kèm `android.priority: "high"` để đánh thức thiết bị (High Priority FCM Data Message).
- **iOS:** Thiết lập `apns.headers["apns-push-type"]: "background"`, `apns.payload.aps["content-available"]: 1` (Silent/Background Push).
- Payload nhận được trong app di động:
  ```json
  {
    "type": "WASHING_MACHINE_DONE",
    "title": "Máy giặt",
    "body": "Quần áo đã giặt xong!",
    "finishedAt": "2026-09-30T10:00:00.000Z",
    "deviceId": "..."
  }
  ```
