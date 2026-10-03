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

  // 2. Tạo subscription mới lắng nghe sự kiện của thiết bị washerDevice
  const washerDevices = context.config.washerDevice || [];
  try {
    if (context.api?.subscriptions && washerDevices.length > 0) {
      
      // Đăng ký chuẩn chung (Handler 1)
      await context.api.subscriptions.subscribeToDevices(
        washerDevices,
        'washerOperatingState',
        'machineState',
        'washerHandlerStandard' // <-- Đổi tên
      );

      // Đăng ký chuẩn nội bộ của Samsung (Handler 2)
      await context.api.subscriptions.subscribeToDevices(
        washerDevices,
        'samsungce.washerOperatingState',
        'operatingState',
        'washerHandlerSamsung'  // <-- Đổi tên
      );

      console.log(`[SmartApp] Đã đăng ký subscriptions cho ${washerDevices.length} thiết bị.`);
    }
  } catch (subErr) {
    console.error('[SmartApp ❌] Lỗi subscribeToDevices:', subErr.response?.data || subErr.message);
  }

  // 3. Lấy fcmToken bằng hàm context.configStringValue('fcmToken')
  const fcmToken = context.configStringValue('fcmToken') || process.env.FCM_DEVICE_TOKEN;

  // 4. Lấy danh sách các máy giặt được chọn (gồm deviceId và fetch thêm deviceName nếu cần)
  const devicesList = [];
  const deviceIds = washerDevices.map(item => item.deviceConfig?.deviceId || item).filter(Boolean);

  for (const deviceId of deviceIds) {
    let displayName = 'Máy giặt Samsung';
    try {
      if (context.api?.devices) {
        const deviceDetails = await context.api.devices.get(deviceId);
        displayName = deviceDetails.label || deviceDetails.name || displayName;
      } else {
        console.warn(`[SmartApp ⚠️] context.api.devices không khả dụng cho deviceId ${deviceId}`);
      }
    } catch (error) {
      console.error(`Lỗi lấy thông tin thiết bị ${deviceId}:`, error);
    }

    devicesList.push({
      id: deviceId,
      name: displayName,
    });
  }

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

  // Khi nhận sự kiện máy giặt báo xong (finished, stop hoặc stopped):
  if (value === 'finished' || value === 'stop' || value === 'stopped') {
    const deviceId = event.deviceId;
    let fcmToken = process.env.FCM_DEVICE_TOKEN; // Fallback từ biến môi trường
    
    // Lấy lại fcmToken trực tiếp từ SmartThings Cloud (đề phòng event không mang theo config)
    try {
      if (context.api?.installedApps) {
        const appConfig = await context.api.installedApps.getConfiguration(context.installedAppId);
        const tokenConfig = appConfig.find(item => item.configId === 'fcmToken');
        if (tokenConfig && tokenConfig.stringConfig) {
          fcmToken = tokenConfig.stringConfig.value;
        }
      }
    } catch (configErr) {
      console.warn('[SmartApp ⚠️] Không thể lấy lại cấu hình từ Cloud:', configErr.message);
    }
    
    // Nếu cloud lỗi, fallback về config cũ
    if (!fcmToken) {
      fcmToken = context.configStringValue('fcmToken');
    }

    let deviceName = 'Máy giặt Samsung';
    console.log(`[SmartApp 🔍] Đang lấy tên thiết bị cho sự kiện hoàn tất: ${deviceId}`);
    try {
      if (context.api?.devices && deviceId) {
        const device = await context.api.devices.get(deviceId);
        deviceName = device.label || device.name || deviceName;
      }
    } catch (err) {
      console.warn(`[SmartApp ⚠️] Không thể lấy metadata cho deviceId ${deviceId}: ${err.message}`);
    }

    console.log(`[SmartApp 🎉] MÁY GIẶT ĐÃ XONG! Bắn TRIGGER_CALL tới: ${fcmToken ? fcmToken.slice(0, 12) + '...' : 'LỖI: KHÔNG CÓ TOKEN'}`);
    
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
    } else {
      console.error('[SmartApp ❌] Không tìm thấy fcmToken để gửi thông báo!');
    }
  }
}

// Đăng ký đúng tên Handler ở đây:
smartApp.subscribedEventHandler('washerHandlerStandard', handleWasherEvent);
smartApp.subscribedEventHandler('washerHandlerSamsung', handleWasherEvent);

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
