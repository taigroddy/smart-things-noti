---
name: build-washer-app
description: Build, verify, and package the Washer Notifier Android Release APKs (split-per-abi) with automated environment setup and quality gates.
---

# Build Washer App (Agent Skill)

Dùng skill này khi người dùng yêu cầu:
- Biên dịch lại ứng dụng di động: *"build apk"*, *"build app"*, *"biên dịch file apk"*, *"tạo apk mới"*, *"cập nhật file cài đặt"*.
- Đóng gói bản phát hành Release APK cho Android.
- Kiểm tra toàn diện chất lượng mã nguồn Mobile (`flutter analyze` & `flutter test`) trước khi đóng gói.

---

## 🚀 Cách thực thi nhanh nhất

Chạy trực tiếp script đóng gói sẵn của skill:

```bash
# Quy trình chuẩn: Kiểm tra mã nguồn, chạy test và build release APK
./.agents/skills/build-washer-app/scripts/build.sh
```

### Các tùy chọn tham số:
| Tham số | Ý nghĩa | Ví dụ sử dụng |
| :--- | :--- | :--- |
| *(Mặc định)* | Chạy `flutter pub get`, `flutter analyze`, `flutter test` rồi mới build APK. | `./.agents/skills/build-washer-app/scripts/build.sh` |
| `--fast` hoặc `--skip-tests` | Bỏ qua bước test/analyze để build nhanh lập tức khi chỉ sửa UI hoặc tài liệu. | `./.agents/skills/build-washer-app/scripts/build.sh --fast` |
| `--clean` | Chạy `flutter clean` để xóa cache trước khi tải lại packages và build. | `./.agents/skills/build-washer-app/scripts/build.sh --clean` |

---

## ⚙️ Thiết lập môi trường bắt buộc

Nếu thực thi bằng các lệnh shell thủ công, **BẮT BUỘC** phải export các biến môi trường sau trước khi gọi Flutter:

```bash
export PATH="/opt/flutter/bin:$PATH"
export ANDROID_HOME=/opt/android-sdk
export ANDROID_SDK_ROOT=/opt/android-sdk
export JAVA_HOME=/opt/jvm/jdk-17.0.12+7
```

---

## 📋 Quy trình 5 bước chuẩn hóa

1. **Chuẩn bị môi trường & Packages:**
   ```bash
   cd /workspace/smart-things/android_app
   flutter pub get
   ```

2. **Verification Gate 1 — Phân tích chất lượng mã nguồn:**
   ```bash
   flutter analyze
   ```
   *Yêu cầu:* `0 issues found`. Nếu có cảnh báo (warning) hoặc lỗi cú pháp, xử lý dứt điểm trước khi chuyển sang bước tiếp theo.

3. **Verification Gate 2 — Chạy Unit & Widget Tests:**
   ```bash
   flutter test
   ```
   *Yêu cầu:* Toàn bộ các test cases trong `test/new_flow_test.dart` và `test/widget_test.dart` phải `PASS`.

4. **Biên dịch Release APK tối ưu (Split per ABI):**
   ```bash
   flutter build apk --release --split-per-abi --android-skip-build-dependency-validation
   ```
   *Kết quả tạo ra:*
   - `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` (~22 MB)
   - `build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk` (~19 MB)

5. **Đồng bộ Artifacts về thư mục gốc:**
   ```bash
   cp build/app/outputs/flutter-apk/app-arm64-v8a-release.apk /workspace/smart-things/washer-notifier.apk
   cp build/app/outputs/flutter-apk/app-arm64-v8a-release.apk /workspace/smart-things/washer-notifier-arm64.apk
   cp build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk /workspace/smart-things/washer-notifier-arm32.apk
   ```

---

## 📦 Danh mục Sản phẩm Xuất xưởng (Output Artifacts)

Sau khi hoàn tất, các file sau tại thư mục gốc `/workspace/smart-things/` sẽ được cập nhật:
- `washer-notifier.apk`: Bản 64-bit chính (ARM64 - khuyên dùng cho hầu hết điện thoại hiện đại).
- `washer-notifier-arm64.apk`: Bản sao định danh rõ kiến trúc 64-bit.
- `washer-notifier-arm32.apk`: Bản 32-bit (armeabi-v7a) dành cho các thiết bị Android cũ.

---

## 🔧 Xử lý sự cố thường gặp (Troubleshooting)

| Lỗi gặp phải | Nguyên nhân | Cách khắc phục |
| :--- | :--- | :--- |
| `JAVA_HOME is not set` | Chưa export đường dẫn JDK 17 | Chạy: `export JAVA_HOME=/opt/jvm/jdk-17.0.12+7` |
| `Android SDK not found` | Chưa export biến `ANDROID_HOME` | Chạy: `export ANDROID_HOME=/opt/android-sdk` |
| Gradle build bị kẹt hoặc lỗi cache | Build cache Gradle bị xung đột | Dùng cờ `--clean`: `./build.sh --clean` |
| `flutter: command not found` | PATH chưa trỏ tới binary của Flutter | Chạy: `export PATH="/opt/flutter/bin:$PATH"` |
