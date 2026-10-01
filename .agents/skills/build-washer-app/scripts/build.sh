#!/usr/bin/env bash
set -eo pipefail

# ==============================================================================
# Build Script: Washer Notifier Android Release APKs
# Thư mục: .agents/skills/build-washer-app/scripts/build.sh
# ==============================================================================

# Màu sắc hiển thị terminal
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Xác định thư mục gốc dự án
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../../" && pwd)"
APP_DIR="${REPO_ROOT}/android_app"

# Thiết lập biến môi trường nếu chưa có
export PATH="/opt/flutter/bin:${PATH}"
export ANDROID_HOME="${ANDROID_HOME:-/opt/android-sdk}"
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-/opt/android-sdk}"
export JAVA_HOME="${JAVA_HOME:-/opt/jvm/jdk-17.0.12+7}"

# Parse tham số dòng lệnh
SKIP_TESTS=false
DO_CLEAN=false

for arg in "$@"; do
  case $arg in
    --fast|--skip-tests)
      SKIP_TESTS=true
      shift
      ;;
    --clean)
      DO_CLEAN=true
      shift
      ;;
    -h|--help)
      echo "Cách sử dụng: ./build.sh [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --fast, --skip-tests   Bỏ qua bước flutter test & analyze (build nhanh)"
      echo "  --clean                Chạy flutter clean trước khi build"
      echo "  -h, --help             Hiển thị trợ giúp này"
      exit 0
      ;;
    *)
      # Bỏ qua tham số không xác định
      ;;
  esac
done

echo -e "${BLUE}================================================================${NC}"
echo -e "${BLUE}🚀 BẮT ĐẦU QUY TRÌNH BIÊN DỊCH RELEASE APK: WASHER NOTIFIER${NC}"
echo -e "${BLUE}================================================================${NC}"
echo -e "📁 Thư mục mã nguồn: ${YELLOW}${APP_DIR}${NC}"
echo -e "☕ JAVA_HOME:        ${JAVA_HOME}"
echo -e "🤖 ANDROID_HOME:    ${ANDROID_HOME}"
echo ""

cd "${APP_DIR}"

# 1. Clean nếu có yêu cầu
if [ "$DO_CLEAN" = true ]; then
  echo -e "${YELLOW}🧹 [1/4] Đang dọn dẹp thư mục build cũ (flutter clean)...${NC}"
  flutter clean
fi

# 2. Cài đặt dependencies
echo -e "${BLUE}📦 [2/4] Kiểm tra và cập nhật dependencies (flutter pub get)...${NC}"
flutter pub get

# 3. Chạy kiểm tra chất lượng (Verification Gate)
if [ "$SKIP_TESTS" = false ]; then
  echo -e "${BLUE}🔍 [3/4] Chạy Verification Gate (analyze & test)...${NC}"
  
  echo "   -> Đang phân tích mã nguồn (flutter analyze)..."
  flutter analyze
  
  echo "   -> Đang chạy unit tests (flutter test)..."
  flutter test
  
  echo -e "${GREEN}✅ Verification Gate hoàn tất: 0 issues, toàn bộ tests đã PASS!${NC}"
else
  echo -e "${YELLOW}⚡ [3/4] Bỏ qua Verification Gate (--fast mode)...${NC}"
fi

# 4. Biên dịch Release APK
echo -e "${BLUE}🔨 [4/4] Đang biên dịch Release APK (split-per-abi)...${NC}"
flutter build apk --release --split-per-abi --android-skip-build-dependency-validation

# 5. Sao chép kết quả ra thư mục gốc
echo ""
echo -e "${BLUE}📋 Đang sao chép các file APK ra thư mục gốc...${NC}"
OUTPUT_DIR="${APP_DIR}/build/app/outputs/flutter-apk"

cp "${OUTPUT_DIR}/app-arm64-v8a-release.apk" "${REPO_ROOT}/washer-notifier.apk"
cp "${OUTPUT_DIR}/app-arm64-v8a-release.apk" "${REPO_ROOT}/washer-notifier-arm64.apk"
cp "${OUTPUT_DIR}/app-armeabi-v7a-release.apk" "${REPO_ROOT}/washer-notifier-arm32.apk"

echo -e "${GREEN}================================================================${NC}"
echo -e "${GREEN}🎉 BIÊN DỊCH THÀNH CÔNG! CÁC FILE APK SẴN SÀNG TẠI THƯ MỤC GỐC:${NC}"
echo -e "${GREEN}================================================================${NC}"
ls -lh "${REPO_ROOT}"/washer-notifier*.apk | awk '{print "  👉 " $9 " (" $5 ")"}'
echo ""
echo -e "💡 Ghi chú cài đặt:"
echo -e "   - Bản chính (ARM64):  ${YELLOW}washer-notifier.apk${NC} (Tối ưu cho hầu hết máy hiện nay)"
echo -e "   - Bản 32-bit (ARM32): ${YELLOW}washer-notifier-arm32.apk${NC} (Dành cho máy đời cũ)"
echo ""
