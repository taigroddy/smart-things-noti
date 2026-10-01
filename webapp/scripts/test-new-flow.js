/**
 * Kịch bản kiểm thử tự động Flow mới:
 * SmartApp Webhook (@smartthings/smartapp SDK) -> FCM SYNC_DEVICE -> FCM TRIGGER_CALL
 */
import 'dotenv/config';
import webhookHandler, { smartApp } from '../api/webhook.js';

console.log('=======================================================');
console.log('🧪 BẮT ĐẦU KIỂM THỬ ARCHITECTURE MỚI: SMARTAPP SDK & FCM SYNC');
console.log('=======================================================\n');

let passedTests = 0;
let totalTests = 0;

function assert(condition, message) {
  totalTests++;
  if (condition) {
    console.log(`✅ [PASS] ${message}`);
    passedTests++;
  } else {
    console.error(`❌ [FAIL] ${message}`);
  }
}

function createMockRes() {
  const res = {
    statusCode: 200,
    headers: {},
    setHeader: (k, v) => { res.headers[k] = v; },
    status: (s) => { res.statusCode = s; return res; },
    json: (d) => { res.body = d; return res; },
    send: (d) => {
      if (typeof d === 'string') {
        try { res.body = JSON.parse(d); } catch (_) { res.body = d; }
      } else {
        res.body = d;
      }
      return res;
    },
    end: () => res,
  };
  return res;
}

async function runTests() {
  // TEST 1: GET Health / Webhook Status
  console.log('[TEST 1] Kiểm tra GET Webhook status...');
  const res1 = createMockRes();
  await webhookHandler({ method: 'GET', headers: {}, query: {} }, res1);
  assert(res1.statusCode === 200, `GET trả về HTTP 200`);
  assert(res1.body?.status === 'ok', `Body trả về status: ok`);
  assert(res1.body?.smartAppId === 'washer-notifier-smartapp', `Body chứa smartAppId hợp lệ`);
  console.log('');

  // TEST 2: CONFIGURATION Lifecycle (INITIALIZE & PAGE)
  console.log('[TEST 2] Kiểm tra CONFIGURATION lifecycle...');
  const resInit = createMockRes();
  await webhookHandler(
    {
      method: 'POST',
      headers: {},
      query: {},
      body: {
        lifecycle: 'CONFIGURATION',
        executionId: 'exec-conf-init',
        configurationData: { phase: 'INITIALIZE' },
      },
    },
    resInit
  );
  assert(
    resInit.statusCode === 200 && resInit.body?.configurationData?.initialize?.firstPageId === 'mainPage',
    `Phase INITIALIZE trả về firstPageId: "mainPage"`
  );

  const resPage = createMockRes();
  await webhookHandler(
    {
      method: 'POST',
      headers: {},
      query: {},
      body: {
        lifecycle: 'CONFIGURATION',
        executionId: 'exec-conf-page',
        configurationData: { phase: 'PAGE', pageId: 'mainPage' },
      },
    },
    resPage
  );
  const settings = resPage.body?.configurationData?.page?.sections?.flatMap(s => s.settings) || [];
  const washerSetting = settings.find(s => s.id === 'washerDevice');
  const fcmSetting = settings.find(s => s.id === 'fcmToken');

  assert(Boolean(washerSetting), `Phase PAGE có trường washerDevice (DEVICE)`);
  assert(washerSetting?.multiple === true, `Trường washerDevice cho phép chọn nhiều thiết bị (multiple: true)`);
  assert(
    washerSetting?.capabilities?.length === 1 && washerSetting?.capabilities[0] === 'washerOperatingState',
    `Trường washerDevice lọc chính xác 1 capability ['washerOperatingState'] tránh lỗi bộ lọc AND`
  );
  assert(Boolean(fcmSetting), `Phase PAGE có trường fcmToken`);
  assert(fcmSetting?.type === 'TEXT', `Trường fcmToken có type là "TEXT" từ native textSetting`);
  assert(fcmSetting?.required === true, `Trường fcmToken bắt buộc nhập (required: true)`);
  console.log('');

  // TEST 3: INSTALL Lifecycle (Trích xuất token + deviceId và gửi SYNC_DEVICE)
  console.log('[TEST 3] Kiểm tra INSTALL lifecycle...');
  const mockFcmToken = 'fcm_mock_device_token_abc_12345';
  const mockDeviceId = 'test-washer-device-id-8888';
  const resInstall = createMockRes();

  await webhookHandler(
    {
      method: 'POST',
      headers: {},
      query: {},
      body: {
        lifecycle: 'INSTALL',
        executionId: 'exec-install-1',
        installData: {
          installedApp: {
            installedAppId: 'app-installed-uuid-1',
            config: {
              washerDevice: [
                {
                  valueType: 'DEVICE',
                  deviceConfig: { deviceId: mockDeviceId, componentId: 'main' },
                },
              ],
              fcmToken: [
                {
                  valueType: 'STRING',
                  stringConfig: { value: mockFcmToken },
                },
              ],
            },
          },
          authToken: 'mock-auth-token',
        },
      },
    },
    resInstall
  );
  assert(resInstall.statusCode === 200, `INSTALL lifecycle trả về HTTP 200`);
  assert(Boolean(resInstall.body?.installData), `INSTALL lifecycle trả về installData`);
  console.log('');

  // TEST 4: EVENT Lifecycle (Khi máy giặt báo finished -> TRIGGER_CALL)
  console.log('[TEST 4] Kiểm tra EVENT lifecycle (máy giặt finished)...');
  const resEvent = createMockRes();
  await webhookHandler(
    {
      method: 'POST',
      headers: {},
      query: {},
      body: {
        lifecycle: 'EVENT',
        executionId: 'exec-event-1',
        eventData: {
          authToken: 'mock-auth-token',
          installedApp: {
            installedAppId: 'app-installed-uuid-1',
            config: {
              fcmToken: [
                {
                  valueType: 'STRING',
                  stringConfig: { value: mockFcmToken },
                },
              ],
            },
          },
          events: [
            {
              eventType: 'DEVICE_EVENT',
              deviceEvent: {
                subscriptionName: 'washerHandler_0',
                deviceId: mockDeviceId,
                capability: 'washerOperatingState',
                attribute: 'washerOperatingState',
                value: 'finished',
                eventId: 'event-uuid-washer-done-999',
              },
            },
          ],
        },
      },
    },
    resEvent
  );
  assert(resEvent.statusCode === 200, `EVENT lifecycle trả về HTTP 200`);
  assert(Boolean(resEvent.body?.eventData), `Sự kiện giặt xong (finished) được SmartApp xử lý thành công!`);
  console.log('');

  console.log('=======================================================');
  console.log(`📊 KẾT QUẢ KIỂM THỬ BACKEND: ${passedTests}/${totalTests} TESTS PASSED`);
  console.log('=======================================================');
}

runTests().catch(console.error);
