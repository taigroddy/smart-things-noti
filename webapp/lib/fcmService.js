import admin from 'firebase-admin';

/**
 * Khởi tạo Firebase Admin SDK một lần duy nhất (tránh lỗi duplicate app khi chạy trên Vercel hoặc serverless container).
 */
function getFirebaseAdmin() {
  if (admin.apps.length === 0) {
    const rawServiceAccount = process.env.FIREBASE_SERVICE_ACCOUNT;
    if (!rawServiceAccount) {
      throw new Error('Biến môi trường FIREBASE_SERVICE_ACCOUNT chưa được cấu hình.');
    }

    let serviceAccount;
    try {
      serviceAccount = typeof rawServiceAccount === 'string'
        ? JSON.parse(rawServiceAccount)
        : rawServiceAccount;
    } catch (error) {
      throw new Error(`Lỗi parse JSON cho FIREBASE_SERVICE_ACCOUNT: ${error.message}`);
    }

    // Đảm bảo private_key có định dạng xuống dòng chuẩn nếu bị escape dạng \\n trong chuỗi JSON
    if (serviceAccount.private_key && typeof serviceAccount.private_key === 'string') {
      serviceAccount.private_key = serviceAccount.private_key.replace(/\\n/g, '\n');
    }

    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
    });
  }

  return admin;
}

/**
 * Gửi Push Notification dạng Data-Only Message (không dùng khóa `notification`)
 * Đặt độ ưu tiên cao:
 * - Android: priority = "high"
 * - iOS: content-available = 1 (kèm apns-push-type = background) để đánh thức app dưới nền
 */
async function sendRawDataMessage(targetToken, dataPayload) {
  const firebaseApp = getFirebaseAdmin();
  const topicName = process.env.FCM_TOPIC || 'washer_done_alerts';
  const token = targetToken || process.env.FCM_DEVICE_TOKEN;

  // Chuyển đổi mọi giá trị trong data thành string theo yêu cầu bắt buộc của FCM
  const stringifiedData = {};
  for (const [key, val] of Object.entries(dataPayload)) {
    stringifiedData[key] = typeof val === 'string' ? val : JSON.stringify(val);
  }

  const message = {
    data: stringifiedData,
    android: {
      priority: 'high',
    },
    apns: {
      headers: {
        'apns-push-type': 'background',
        'apns-priority': '5',
      },
      payload: {
        aps: {
          'content-available': 1,
        },
      },
    },
  };

  if (token) {
    message.token = token;
    console.log(`[FCM] Đang gửi Data Message (type: ${dataPayload.type}) tới Token: ${token.slice(0, 12)}...`);
  } else {
    message.topic = topicName;
    console.log(`[FCM] Đang gửi Data Message (type: ${dataPayload.type}) tới Topic chung: '${topicName}'`);
  }

  const messageId = await firebaseApp.messaging().send(message);
  console.log(`[FCM ✅] Đã gửi messageId thành công: ${messageId}`);
  return messageId;
}

/**
 * 1. Bắn Data Message tự động đồng bộ danh sách thiết bị (SYNC_DEVICES)
 * Kích hoạt khi SmartThings gửi INSTALL hoặc UPDATE lifecycle.
 * Payload: { type: 'SYNC_DEVICES', devices: '[{"id":"...","name":"..."}]' }
 */
export async function sendSyncDevicesAlert({ fcmToken, devices }) {
  const devicesJson = typeof devices === 'string' ? devices : JSON.stringify(devices);
  return sendRawDataMessage(fcmToken, {
    type: 'SYNC_DEVICES',
    devices: devicesJson,
    timestamp: new Date().toISOString(),
  });
}

/**
 * Bắn Data Message tự động đồng bộ thiết bị đơn lẻ (SYNC_DEVICE - tương thích ngược)
 */
export async function sendSyncDeviceAlert({ fcmToken, deviceId, deviceName }) {
  return sendRawDataMessage(fcmToken, {
    type: 'SYNC_DEVICE',
    deviceId: String(deviceId || ''),
    deviceName: String(deviceName || 'Máy giặt Samsung'),
    timestamp: new Date().toISOString(),
  });
}

/**
 * 2. Bắn Data Message kích hoạt cuộc gọi giả lập (TRIGGER_CALL)
 * Kích hoạt khi máy giặt báo finished trong EVENT lifecycle.
 */
export async function sendTriggerCallAlert({ fcmToken, deviceId, deviceName, eventId }) {
  return sendRawDataMessage(fcmToken, {
    type: 'TRIGGER_CALL',
    deviceId: String(deviceId || ''),
    deviceName: String(deviceName || 'Máy giặt Samsung'),
    eventId: String(eventId || Date.now()),
    title: 'Máy giặt',
    body: `Quần áo trong ${deviceName || 'máy giặt'} đã giặt xong!`,
    timestamp: new Date().toISOString(),
  });
}

/**
 * 3. Hàm tương thích ngược
 */
export async function sendFCMAlert(overrideTarget, customData = {}) {
  return sendRawDataMessage(overrideTarget, {
    type: 'TRIGGER_CALL',
    title: 'Máy giặt',
    body: 'Quần áo đã giặt xong!',
    ...customData,
  });
}

export default {
  sendSyncDevicesAlert,
  sendSyncDeviceAlert,
  sendTriggerCallAlert,
  sendFCMAlert,
};

