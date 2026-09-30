import 'dotenv/config';

const PORT = process.env.PORT || 3000;
const WEBHOOK_URL = process.env.TEST_WEBHOOK_URL || `http://localhost:${PORT}/api/webhook`;

const command = process.argv[2] || 'event';

async function sendRequest(lifecycle, payload) {
  console.log(`\n📤 [TEST] Đang gửi payload "${lifecycle}" tới ${WEBHOOK_URL}...`);
  try {
    const res = await fetch(WEBHOOK_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(payload),
    });

    const status = res.status;
    const body = await res.json().catch(() => ({}));
    console.log(`📥 [TEST] Kết quả phản hồi: HTTP ${status}`);
    console.log(JSON.stringify(body, null, 2));
  } catch (err) {
    console.error('❌ [TEST] Lỗi kết nối:', err.message);
  }
}

async function run() {
  switch (command.toLowerCase()) {
    case 'ping': {
      await sendRequest('PING', {
        lifecycle: 'PING',
        executionId: 'mock-ping-exec-id',
        appId: 'mock-app-id',
        pingData: {
          challenge: 'random-challenge-string-123456',
        },
      });
      break;
    }

    case 'confirmation': {
      await sendRequest('CONFIRMATION', {
        lifecycle: 'CONFIRMATION',
        executionId: 'mock-confirm-exec-id',
        appId: 'mock-app-id',
        confirmationData: {
          appId: 'mock-app-id',
          confirmationUrl: 'https://httpbin.org/get?confirmed=true',
        },
      });
      break;
    }

    case 'event':
    default: {
      const deviceId = process.env.SMARTTHINGS_WASHER_DEVICE_ID || 'mock-washer-device-id-123';
      await sendRequest('EVENT', {
        lifecycle: 'EVENT',
        executionId: 'mock-event-exec-id',
        appId: 'mock-app-id',
        eventData: {
          authToken: 'mock-token',
          events: [
            {
              eventType: 'DEVICE_EVENT',
              deviceEvent: {
                eventId: 'mock-event-id-999',
                locationId: 'mock-location-id',
                deviceId: deviceId,
                componentId: 'main',
                capability: 'washerOperatingState',
                attribute: 'washerOperatingState',
                value: 'finished',
                data: {},
              },
            },
          ],
        },
      });
      break;
    }
  }
}

run();
