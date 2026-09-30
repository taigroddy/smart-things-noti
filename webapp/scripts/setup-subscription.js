import fs from 'node:fs';

// Tự động load file .env bằng tính năng có sẵn của Node.js (Node 20+) hoặc fallback fs
if (process.loadEnvFile && fs.existsSync('.env')) {
  process.loadEnvFile('.env');
} else if (fs.existsSync('.env')) {
  const envContent = fs.readFileSync('.env', 'utf-8');
  for (const line of envContent.split('\n')) {
    const trimmed = line.trim();
    if (trimmed && !trimmed.startsWith('#') && trimmed.includes('=')) {
      const idx = trimmed.indexOf('=');
      const key = trimmed.slice(0, idx).trim();
      const val = trimmed.slice(idx + 1).trim();
      if (!process.env[key]) process.env[key] = val;
    }
  }
}

const SMARTTHINGS_API = 'https://api.smartthings.com/v1';

const PAT = process.env.SMARTTHINGS_PAT;
const WASHER_DEVICE_ID = process.env.SMARTTHINGS_WASHER_DEVICE_ID;
const TARGET_URL = process.env.WEBHOOK_TARGET_URL;

// Các mã màu ANSI cho console log đẹp mắt
const colors = {
  reset: '\x1b[0m',
  bold: '\x1b[1m',
  green: '\x1b[32m',
  blue: '\x1b[34m',
  yellow: '\x1b[33m',
  red: '\x1b[31m',
  cyan: '\x1b[36m',
};

function log(msg, color = colors.reset) {
  console.log(`${color}${msg}${colors.reset}`);
}

/**
 * Hàm gọi API SmartThings với Bearer Token
 */
async function smartthingsFetch(endpoint, options = {}) {
  const url = `${SMARTTHINGS_API}${endpoint}`;
  const headers = {
    Authorization: `Bearer ${PAT}`,
    'Content-Type': 'application/json',
    Accept: 'application/json',
    ...options.headers,
  };

  const response = await fetch(url, { ...options, headers });
  const contentType = response.headers.get('content-type') || '';

  let data = null;
  if (contentType.includes('application/json')) {
    data = await response.json();
  } else {
    data = await response.text();
  }

  return { ok: response.ok, status: response.status, data };
}

async function main() {
  log('===============================================================', colors.bold);
  log('   🚀 SAMSUNG SMARTTHINGS WEBHOOK & SUBSCRIPTION SETUP CLI', colors.cyan);
  log('===============================================================\n', colors.bold);

  // 1. Kiểm tra biến môi trường
  if (!PAT) {
    log('❌ LỖI: Chưa cấu hình biến môi trường SMARTTHINGS_PAT!', colors.red);
    log('👉 Hãy lấy Personal Access Token tại https://account.smartthings.com/tokens', colors.yellow);
    process.exit(1);
  }

  if (!TARGET_URL) {
    log('❌ LỖI: Chưa cấu hình biến môi trường WEBHOOK_TARGET_URL!', colors.red);
    log('👉 Ví dụ: https://your-domain.vercel.app/api/webhook hoặc https://xxxx.ngrok-free.app/api/webhook', colors.yellow);
    process.exit(1);
  }

  if (!TARGET_URL.startsWith('https://')) {
    log('⚠️  CẢNH BÁO: Samsung SmartThings bắt buộc Webhook URL phải sử dụng giao thức HTTPS!', colors.yellow);
  }

  log(`[1/4] Kiểm tra kết nối tới SmartThings API...`, colors.bold);
  const locationRes = await smartthingsFetch('/locations');
  if (!locationRes.ok) {
    log(`❌ Không thể xác thực Token SmartThings (HTTP ${locationRes.status}):`, colors.red);
    console.error(locationRes.data);
    process.exit(1);
  }
  log(`✅ Kết nối thành công! Tìm thấy ${(locationRes.data.items || []).length} Location(s).`, colors.green);

  // 2. Kiểm tra thiết bị máy giặt
  log(`\n[2/4] Kiểm tra thiết bị máy giặt...`, colors.bold);
  if (WASHER_DEVICE_ID) {
    const devRes = await smartthingsFetch(`/devices/${WASHER_DEVICE_ID}`);
    if (devRes.ok) {
      log(`✅ Đã tìm thấy thiết bị: "${devRes.data.label || devRes.data.name}" (ID: ${WASHER_DEVICE_ID})`, colors.green);
    } else {
      log(`⚠️ Không tìm thấy thiết bị với ID ${WASHER_DEVICE_ID} (HTTP ${devRes.status}). Tiếp tục cấu hình Webhook...`, colors.yellow);
    }
  } else {
    log('ℹ️  Chưa cấu hình SMARTTHINGS_WASHER_DEVICE_ID. Đang quét danh sách thiết bị...', colors.blue);
    const devicesRes = await smartthingsFetch('/devices');
    if (devicesRes.ok) {
      const devices = devicesRes.data.items || [];
      const washerFound = devices.filter((d) => {
        const str = `${d.label} ${d.name} ${d.deviceTypeName}`.toLowerCase();
        return str.includes('wash') || str.includes('dryer') || str.includes('machine');
      });

      if (washerFound.length > 0) {
        log('💡 Tìm thấy các thiết bị máy giặt tiềm năng:', colors.cyan);
        for (const w of washerFound) {
          log(`   - Tên: ${w.label || w.name} | ID: ${w.deviceId}`, colors.cyan);
        }
        log('👉 Bạn có thể copy Device ID trên vào biến SMARTTHINGS_WASHER_DEVICE_ID trong .env', colors.yellow);
      }
    }
  }

  // 3. Đăng ký Webhook App
  log(`\n[3/4] Đăng ký / Cập nhật Webhook SmartApp với SmartThings...`, colors.bold);
  log(`🔗 Target URL: ${TARGET_URL}`, colors.blue);

  const APP_NAME = 'washer-finished-webhook';
  const listAppsRes = await smartthingsFetch('/apps');
  let existingApp = null;

  if (listAppsRes.ok && listAppsRes.data.items) {
    existingApp = listAppsRes.data.items.find(
      (app) => app.appName === APP_NAME || app.webhookSmartApp?.targetUrl === TARGET_URL
    );
  }

  let appId = null;

  if (existingApp) {
    appId = existingApp.appId;
    log(`ℹ️  Tìm thấy App đã tồn tại: "${existingApp.displayName || existingApp.appName}" (ID: ${appId})`, colors.blue);
    log(`Đang cập nhật Target URL mới...`, colors.blue);

    const updateRes = await smartthingsFetch(`/apps/${appId}`, {
      method: 'PUT',
      body: JSON.stringify({
        displayName: 'Washer Finished Webhook',
        description: 'Webhook nhận thông báo giặt xong và gửi FCM',
        webhookSmartApp: {
          targetUrl: TARGET_URL,
        },
      }),
    });

    if (updateRes.ok) {
      log(`✅ Đã cập nhật Webhook App thành công!`, colors.green);
    } else {
      log(`⚠️ Cập nhật App trả về mã: ${updateRes.status}`, colors.yellow);
      console.log(updateRes.data);
    }
  } else {
    log(`Đang tạo App mới: "${APP_NAME}"...`, colors.blue);
    const createAppRes = await smartthingsFetch('/apps', {
      method: 'POST',
      body: JSON.stringify({
        appName: APP_NAME,
        displayName: 'Washer Finished Webhook',
        description: 'Webhook nhận thông báo giặt xong và gửi FCM',
        appType: 'WEBHOOK_SMART_APP',
        classifications: ['AUTOMATION'],
        singleInstance: true,
        webhookSmartApp: {
          targetUrl: TARGET_URL,
        },
        permissions: ['r:devices:*', 'x:devices:*'],
      }),
    });

    if (createAppRes.ok) {
      appId = createAppRes.data.app.appId;
      log(`✅ Đã đăng ký Webhook App thành công! (App ID: ${appId})`, colors.green);
      log(`🔔 SmartThings đã tự động gửi request CONFIRMATION tới: ${TARGET_URL}`, colors.cyan);
      log(`   Nếu máy chủ của bạn đang chạy, endpoint /api/webhook đã tự động xác thực URL này.`, colors.cyan);
    } else {
      log(`❌ Không thể đăng ký App (HTTP ${createAppRes.status}):`, colors.red);
      console.error(createAppRes.data);
      process.exit(1);
    }
  }

  // 4. Tạo Subscription lắng nghe capability washerOperatingState
  log(`\n[4/4] Cấu hình Subscription lắng nghe washerOperatingState...`, colors.bold);

  // Tìm Installed App để gắn subscription
  const installedAppsRes = await smartthingsFetch(`/installedapps?appId=${appId}`);
  const installedApps = installedAppsRes.ok ? installedAppsRes.data.items || [] : [];

  if (installedApps.length === 0) {
    log(`ℹ️  SmartApp chưa được cài đặt vào Location trong app di động SmartThings.`, colors.yellow);
    log(`👉 Các bước tiếp theo:`, colors.cyan);
    log(`   1. Mở ứng dụng di động SmartThings trên điện thoại.`, colors.cyan);
    log(`   2. Bật chế độ "Developer Mode" trong Settings -> Developer mode.`, colors.cyan);
    log(`   3. Vào "Automations / Tự động hóa" -> Thêm mới -> Chọn SmartApp "Washer Finished Webhook".`, colors.cyan);
    log(`   4. Chọn máy giặt và bấm Hoàn tất (Done).`, colors.cyan);
    log(`   5. Chạy lại script này để tự động kiểm tra và đăng ký Subscription.`, colors.cyan);
  } else {
    for (const instApp of installedApps) {
      const instAppId = instApp.installedAppId;
      log(`📍 Tìm thấy Installed App: ${instAppId} (Location: ${instApp.locationId})`, colors.blue);

      // Liệt kê các subscription hiện tại
      const subListRes = await smartthingsFetch(`/installedapps/${instAppId}/subscriptions`);
      const existingSubs = subListRes.ok ? subListRes.data.items || [] : [];

      const hasWasherSub = existingSubs.some(
        (s) => s.device?.capability === 'washerOperatingState' || s.device?.capability === 'machineState'
      );

      if (hasWasherSub) {
        log(`✅ Installed App này đã đăng ký subscription lắng nghe trạng thái máy giặt!`, colors.green);
      } else if (WASHER_DEVICE_ID) {
        log(`Đang đăng ký subscription cho thiết bị ${WASHER_DEVICE_ID}...`, colors.blue);
        const createSubRes = await smartthingsFetch(`/installedapps/${instAppId}/subscriptions`, {
          method: 'POST',
          body: JSON.stringify({
            sourceType: 'DEVICE',
            device: {
              deviceId: WASHER_DEVICE_ID,
              capability: 'washerOperatingState',
              attribute: 'washerOperatingState',
              stateChangeOnly: true,
              value: '*',
            },
          }),
        });

        if (createSubRes.ok) {
          log(`🎉 ĐÃ ĐĂNG KÝ THÀNH CÔNG SUBSCRIPTION CHO washerOperatingState!`, colors.green);
        } else {
          log(`⚠️ Không thể tạo subscription tự động (HTTP ${createSubRes.status}):`, colors.yellow);
          console.error(createSubRes.data);
        }
      } else {
        log(`⚠️ Cần có SMARTTHINGS_WASHER_DEVICE_ID để đăng ký subscription trực tiếp vào thiết bị.`, colors.yellow);
      }
    }
  }

  log('\n===============================================================', colors.bold);
  log('✨ HOÀN TẤT QUÁ TRÌNH THIẾT LẬP!', colors.green);
  log('===============================================================\n', colors.bold);
}

main().catch((err) => {
  console.error('❌ Lỗi ngoại lệ trong quá trình thiết lập:', err);
  process.exit(1);
});
