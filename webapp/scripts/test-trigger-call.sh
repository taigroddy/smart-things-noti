#!/usr/bin/env bash
# ==============================================================================
# Script giả lập sự kiện SmartThings: Máy giặt hoàn tất (washer finished)
# Gửi EVENT request đến Backend Vercel để bắn Push Notification (TRIGGER_CALL)
# Cách chạy: ./scripts/test-trigger-call.sh [FCM_TOKEN] [VERCEL_URL]
# ==============================================================================

set -e

# Màu sắc
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Đọc token từ tham số thứ 1 hoặc biến môi trường hoặc nhập từ bàn phím
FCM_TOKEN="${1:-$FCM_DEVICE_TOKEN}"
TARGET_URL="${2:-https://smart-things-noti-81ql.vercel.app/api/webhook}"

if [ -z "$FCM_TOKEN" ] || [ "$FCM_TOKEN" == "your_fcm_device_token_here" ]; then
  echo -e "${YELLOW}Vui lòng nhập FCM Device Token từ app Washer Notifier trên điện thoại:${NC}"
  read -r -p "👉 FCM Token: " FCM_TOKEN
fi

if [ -z "$FCM_TOKEN" ]; then
  echo -e "${RED}❌ Lỗi: FCM Token không được để trống!${NC}"
  echo "Mở ứng dụng Washer Notifier trên điện thoại và nhấn 'Sao Chép FCM Token'."
  exit 1
fi

TIMESTAMP=$(date +%s)
EXECUTION_ID="exec-test-${TIMESTAMP}"
EVENT_ID="event-washer-done-${TIMESTAMP}"

echo -e "${BLUE}================================================================${NC}"
echo -e "${BLUE}🚀 ĐANG GỬI SỰ KIỆN GIẢ LẬP: MÁY GIẶT ĐÃ XONG (FINISHED)${NC}"
echo -e "${BLUE}================================================================${NC}"
echo -e "🌐 Target URL:   ${YELLOW}${TARGET_URL}${NC}"
echo -e "📱 FCM Token:   ${YELLOW}${FCM_TOKEN:0:15}...${FCM_TOKEN: -10}${NC}"
echo -e "🆔 Event ID:    ${EVENT_ID}"
echo ""

HTTP_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${TARGET_URL}" \
  -H "Content-Type: application/json" \
  -d @- <<EOF
{
  "lifecycle": "EVENT",
  "executionId": "${EXECUTION_ID}",
  "eventData": {
    "authToken": "mock-auth-token-test",
    "installedApp": {
      "installedAppId": "test-installed-app-1",
      "config": {
        "fcmToken": [
          {
            "valueType": "STRING",
            "stringConfig": {
              "value": "${FCM_TOKEN}"
            }
          }
        ]
      }
    },
    "events": [
      {
        "eventType": "DEVICE_EVENT",
        "deviceEvent": {
          "subscriptionName": "washerHandler_0",
          "deviceId": "d5281b1f-97f9-c9f1-23ae-f8d77d8b24d1",
          "capability": "washerOperatingState",
          "attribute": "washerOperatingState",
          "value": "finished",
          "eventId": "${EVENT_ID}"
        }
      }
    ]
  }
}
EOF
)

BODY=$(echo "$HTTP_RESPONSE" | sed '$d')
STATUS=$(echo "$HTTP_RESPONSE" | tail -n 1)

if [ "$STATUS" == "200" ]; then
  echo -e "${GREEN}✅ GỬI THÀNH CÔNG (HTTP 200)!${NC}"
  echo -e "📦 Phản hồi từ Server: ${BODY}"
  echo ""
  echo -e "${GREEN}👉 Kiểm tra điện thoại của bạn ngay: Màn hình cuộc gọi 'Máy Giặt Thông Minh' sẽ đổ chuông!${NC}"
  echo -e "⚠️  Lưu ý: Nếu vừa test cách đây chưa đầy 60 giây, app sẽ kích hoạt bộ lọc chống spam để tránh quấy rầy."
else
  echo -e "${RED}❌ Gửi thất bại với mã lỗi HTTP: ${STATUS}${NC}"
  echo -e "Chi tiết: ${BODY}"
fi
echo ""
