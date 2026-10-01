import { SmartApp } from '@smartthings/smartapp';
import { sendSyncDevicesAlert, sendSyncDeviceAlert, sendTriggerCallAlert } from '../lib/fcmService.js';

/**
 * Khởi tạo SmartApp bằng thư viện chính thức @smartthings/smartapp
 */
export const smartApp = new SmartApp();

smartApp.enableEventLogging(2);

// =========================================================================
// 1. Khởi tạo SmartApp & Giao diện cấu hình (Configuration Lifecycle)
// =========================================================================
smartApp.page('mainPage', (context, page, configData) => {
  page.name('Washer Notifier');
  page.section('configSection', section => {
    // 2. configSection Label
    section.name('Lựa chọn');

    // 1. Input FCM token
    section.textSetting('fcmToken')
      .name('Lấy mã từ Ứng dụng Washer Notifier')
      .required(true);

    // 3. Máy giặt samsung
    section.deviceSetting('washerDevice')
      .name('Danh sách máy giặt')
      .capabilities(['washerOperatingState'])
      .permissions('r')
      .multiple(true)
      .required(true);
  });
});

// =========================================================================
// 2. Xử lý Cài đặt / Cập nhật (Install & Update Lifecycle)
// =========================================================================
async function handleInstallOrUpdate(context) {
  console.log(`[SmartApp] Bắt đầu xử lý ${context.lifecycle} cho installedAppId: ${context.installedAppId}`);

  // 1. Xóa tất cả các subscription cũ (unsubscribeAll)
  try {
    if (context.api?.subscriptions) {
      await context.api.subscriptions.unsubscribeAll();
      console.log('[SmartApp] Đã xóa toàn bộ subscriptions cũ (unsubscribeAll).');
    }
  } catch (err) {
    console.warn('[SmartApp] Bỏ qua lỗi unsubscribeAll:', err.message);
  }

  // 2. Tạo subscription mới lắng nghe sự kiện của thiết bị washerDevice vừa chọn,
  // cụ thể là thuộc tính machineState hoặc washerOperatingState khi giá trị chuyển thành finished hoặc stop.
  const washerDevices = context.config.washerDevice || [];
  try {
    if (context.api?.subscriptions && washerDevices.length > 0) {
      await context.api.subscriptions.subscribeToDevices(
        washerDevices,
        'washerOperatingState',
        'washerOperatingState',
        'washerHandler'
      );
      await context.api.subscriptions.subscribeToDevices(
        washerDevices,
        'machineState',
        'machineState',
        'washerHandler'
      );
      console.log(`[SmartApp] Đã đăng ký subscriptions cho ${washerDevices.length} thiết bị.`);
    }
  } catch (subErr) {
    console.warn('[SmartApp] Bỏ qua lỗi subscribeToDevices:', subErr.message);
  }

  // 3. Lấy fcmToken bằng hàm context.configStringValue('fcmToken')
  const fcmToken = context.configStringValue('fcmToken') || process.env.FCM_DEVICE_TOKEN;

  // 4. Lấy danh sách các máy giặt được chọn (gồm deviceId và fetch thêm deviceName nếu cần)
  const devicesList = [];
  for (const item of washerDevices) {
    const deviceId = item.deviceConfig?.deviceId;
    if (!deviceId) continue;

    let deviceName = 'Máy giặt Samsung';
    try {
      if (context.api?.devices) {
        const device = await context.api.devices.get(deviceId);
        deviceName = device.label || device.name || deviceName;
      }
    } catch (_) {}

    devicesList.push({
      id: deviceId,
      name: deviceName,
    });
  }

  // 5. Dùng Firebase Admin đẩy một tin nhắn Data Message tới fcmToken này với payload:
  // { data: { type: 'SYNC_DEVICES', devices: '[{"id":"...","name":"..."}]' } }
  if (fcmToken && devicesList.length > 0) {
    console.log(`[SmartApp 🚀] Gửi SYNC_DEVICES (${devicesList.length} máy) về fcmToken: ${fcmToken.slice(0, 12)}...`);
    try {
      await sendSyncDevicesAlert({ fcmToken, devices: devicesList });
      console.log('[SmartApp ✅] Gửi SYNC_DEVICES thành công!');
    } catch (fcmErr) {
      console.error('[SmartApp ❌] Lỗi gửi SYNC_DEVICES:', fcmErr.message);
    }
  }
}

smartApp.installed(async (context) => {
  await handleInstallOrUpdate(context);
});

smartApp.updated(async (context) => {
  await handleInstallOrUpdate(context);
});

// =========================================================================
// 3. Xử lý Sự kiện (Event Lifecycle)
// =========================================================================
async function handleWasherEvent(context, event) {
  const value = String(event.value || '').toLowerCase();
  console.log(`[SmartApp Event] Nhận sự kiện: attribute=${event.attribute}, value=${value}, deviceId=${event.deviceId}`);

  // Khi nhận sự kiện máy giặt báo xong (finished hoặc stop):
  if (value === 'finished' || value === 'stop') {
    // Lấy fcmToken của phiên bản app này bằng lệnh context.configStringValue('fcmToken')
    const fcmToken = context.configStringValue('fcmToken') || process.env.FCM_DEVICE_TOKEN;
    const deviceId = event.deviceId;
    let deviceName = 'Máy giặt Samsung';

    try {
      if (context.api?.devices && deviceId) {
        const device = await context.api.devices.get(deviceId);
        deviceName = device.label || device.name || deviceName;
      }
    } catch (_) {}

    console.log(`[SmartApp 🎉] MÁY GIẶT ĐÃ XONG! Bắn TRIGGER_CALL tới: ${fcmToken ? fcmToken.slice(0, 12) + '...' : 'null'}`);
    // Gọi Firebase Admin bắn Data Message tới fcmToken đó với payload:
    // { type: "TRIGGER_CALL", deviceId: "...", deviceName: "..." }
    if (fcmToken) {
      try {
        await sendTriggerCallAlert({
          fcmToken,
          deviceId,
          deviceName,
          eventId: event.eventId || `${Date.now()}`,
        });
        console.log('[SmartApp ✅] Đã bắn TRIGGER_CALL thành công!');
      } catch (fcmErr) {
        console.error('[SmartApp ❌] Lỗi khi gửi TRIGGER_CALL:', fcmErr.message);
      }
    }
  }
}

smartApp.subscribedEventHandler('washerHandler', handleWasherEvent);
smartApp.subscribedEventHandler('washerOperatingState', handleWasherEvent);
smartApp.subscribedEventHandler('machineState', handleWasherEvent);

// =========================================================================
// 4. Cấu hình Vercel / Express: POST /api/webhook
// =========================================================================
export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  // GET check health
  if (req.method === 'GET') {
    return res.status(200).json({
      status: 'ok',
      message: 'Samsung SmartThings SmartApp Webhook Endpoint is running.',
      smartAppId: 'washer-notifier-smartapp',
      timestamp: new Date().toISOString(),
    });
  }

  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method Not Allowed' });
  }

  // Tự động route request tới SmartApp SDK
  try {
    if (process.env.SMARTTHINGS_VERIFY_SIGNATURE === 'true') {
      await smartApp.handleHttpCallback(req, res);
    } else {
      await smartApp.handleHttpCallbackUnverified(req, res);
    }
  } catch (err) {
    console.error('[SmartThings Webhook Error]:', err);
    if (!res.headersSent) {
      res.status(500).json({ error: 'Internal Server Error', message: err.message });
    }
  }
}
