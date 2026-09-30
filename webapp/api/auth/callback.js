/**
 * API Xử lý OAuth2 Callback từ Samsung SmartThings
 * Endpoint: /api/auth/callback
 */
export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  const { code, error, error_description } = req.query;

  // Trường hợp người dùng từ chối cấp quyền hoặc có lỗi từ Samsung
  if (error) {
    const errorMsg = error_description || error;
    const errorDeepLink = `washerapp://auth?success=false&error=${encodeURIComponent(errorMsg)}`;

    return res.status(400).send(`
      <!DOCTYPE html>
      <html lang="vi">
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Lỗi Kết Nối Samsung SmartThings</title>
        <style>
          body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #FFF5F5; color: #333; padding: 24px; text-align: center; }
          .card { max-width: 480px; margin: 40px auto; background: #fff; padding: 32px 24px; border-radius: 16px; box-shadow: 0 4px 20px rgba(0,0,0,0.08); }
          .icon { font-size: 54px; color: #E53E3E; margin-bottom: 16px; }
          h2 { color: #C53030; margin-bottom: 12px; }
          p { color: #718096; line-height: 1.5; margin-bottom: 24px; }
          .btn { display: inline-block; background: #E53E3E; color: white; padding: 14px 28px; border-radius: 12px; text-decoration: none; font-weight: 600; font-size: 16px; }
        </style>
      </head>
      <body>
        <div class="card">
          <div class="icon">⚠️</div>
          <h2>Kết Nối Không Thành Công</h2>
          <p>${escapeHtml(errorMsg)}</p>
          <a href="${errorDeepLink}" class="btn">Quay lại Ứng Dụng</a>
        </div>
        <script>
          window.location.href = "${errorDeepLink}";
        </script>
      </body>
      </html>
    `);
  }

  if (!code) {
    return res.status(400).json({ error: 'Mã ủy quyền (authorization code) bị thiếu.' });
  }

  const clientId = process.env.SMARTTHINGS_CLIENT_ID || 'd8e3097b-8bed-4a11-9689-25f6ec432fe4';
  const clientSecret = process.env.SMARTTHINGS_CLIENT_SECRET || '03fc160e-299f-4142-8d48-c5518b7c7856';
  const redirectUri = process.env.SMARTTHINGS_REDIRECT_URI || 'https://smart-things-noti-81ql.vercel.app/api/auth/callback';

  try {
    // 1. Đổi code lấy Access Token từ Samsung SmartThings
    const tokenParams = new URLSearchParams({
      grant_type: 'authorization_code',
      code: code,
      client_id: clientId,
      client_secret: clientSecret,
      redirect_uri: redirectUri,
    });

    const basicAuth = Buffer.from(`${clientId}:${clientSecret}`).toString('base64');

    const tokenResponse = await fetch('https://api.smartthings.com/oauth/token', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Authorization': `Basic ${basicAuth}`,
        'Accept': 'application/json',
      },
      body: tokenParams.toString(),
    });

    if (!tokenResponse.ok) {
      const errText = await tokenResponse.text();
      console.error('[OAuth Callback] Lỗi lấy token:', tokenResponse.status, errText);
      return res.status(tokenResponse.status).send(`
        <h3>Lỗi trao đổi mã OAuth2 với SmartThings: ${tokenResponse.status}</h3>
        <pre>${escapeHtml(errText)}</pre>
      `);
    }

    const tokenData = await tokenResponse.json();
    const accessToken = tokenData.access_token;
    const refreshToken = tokenData.refresh_token || '';

    // 2. Gọi SmartThings Devices API để lấy danh sách máy giặt ngay lập tức
    let washers = [];
    try {
      const devicesResponse = await fetch('https://api.smartthings.com/v1/devices', {
        headers: {
          'Authorization': `Bearer ${accessToken}`,
          'Accept': 'application/json',
        },
      });

      if (devicesResponse.ok) {
        const devData = await devicesResponse.json();
        const items = devData.items || [];

        const washerItems = items.filter((dev) => {
          const categories = dev.components?.flatMap((c) => c.categories?.map((cat) => cat.name)) || [];
          const hasWasherCategory = categories.some((c) => ['Washer', 'Dryer'].includes(c));
          const hasWasherName =
            (dev.name && /washer|dryer|máy giặt|máy sấy/i.test(dev.name)) ||
            (dev.label && /washer|dryer|máy giặt|máy sấy/i.test(dev.label));
          return hasWasherCategory || hasWasherName;
        });

        washers = washerItems.map((dev) => {
          const categories = dev.components?.flatMap((c) => c.categories?.map((cat) => cat.name)) || [];
          return {
            deviceId: dev.deviceId,
            name: dev.name,
            label: dev.label || dev.name || 'Máy giặt Samsung',
            modelNumber: dev.ocf?.modelNumber || dev.deviceTypeName || 'Samsung Smart Washer',
            manufacturer: dev.manufacturerName || 'Samsung Electronics',
            categories,
            roomId: dev.roomId,
            locationId: dev.locationId,
          };
        });
      }
    } catch (devErr) {
      console.error('[OAuth Callback] Lỗi lấy thiết bị:', devErr);
    }

    // 3. Chuẩn bị Deep Link về Washer App
    const encodedDevices = encodeURIComponent(JSON.stringify(washers));
    const deepLinkUrl = `washerapp://auth?success=true&token=${encodeURIComponent(accessToken)}&refreshToken=${encodeURIComponent(refreshToken)}&devices=${encodedDevices}`;

    // 4. Trả về trang xác nhận và tự động mở Deep Link
    const washerListHtml = washers.length > 0
      ? washers.map(w => `
          <div style="background: #EBF8FF; border-left: 4px solid #3182CE; padding: 12px; margin-bottom: 8px; border-radius: 8px; text-align: left;">
            <strong style="color: #2B6CB0;">${escapeHtml(w.label)}</strong><br>
            <span style="font-size: 13px; color: #4A5568;">Model: ${escapeHtml(w.modelNumber)} | ID: ${escapeHtml(w.deviceId.substring(0, 13))}...</span>
          </div>
        `).join('')
      : '<p style="color: #718096; font-style: italic;">Chưa tìm thấy máy giặt trong tài khoản Samsung của bạn.</p>';

    return res.status(200).send(`
      <!DOCTYPE html>
      <html lang="vi">
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Kết Nối Samsung SmartThings Thành Công</title>
        <style>
          body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #F0F4F8; color: #2D3748; padding: 24px; margin: 0; }
          .card { max-width: 480px; margin: 40px auto; background: #ffffff; padding: 32px 24px; border-radius: 20px; box-shadow: 0 10px 30px rgba(0,0,0,0.08); text-align: center; }
          .icon-badge { width: 72px; height: 72px; background: #EBF8FF; border-radius: 50%; display: inline-flex; align-items: center; justify-content: center; font-size: 36px; margin-bottom: 18px; border: 2px solid #BEE3F8; }
          h2 { color: #1A365D; margin: 0 0 10px 0; font-size: 22px; }
          p { color: #4A5568; line-height: 1.5; margin-bottom: 20px; font-size: 14px; }
          .devices-box { margin-bottom: 24px; }
          .btn { display: block; background: #0057B8; color: #ffffff; padding: 16px 24px; border-radius: 12px; text-decoration: none; font-weight: bold; font-size: 16px; box-shadow: 0 4px 12px rgba(0, 87, 184, 0.3); transition: background 0.2s; }
          .btn:active { background: #003F88; }
          .subtext { font-size: 12px; color: #A0AEC0; margin-top: 14px; }
        </style>
      </head>
      <body>
        <div class="card">
          <div class="icon-badge">✨</div>
          <h2>Đã Kết Nối SmartThings!</h2>
          <p>Tài khoản Samsung đã được xác thực thành công. Danh sách thiết bị máy giặt đã sẵn sàng.</p>
          
          <div class="devices-box">
            ${washerListHtml}
          </div>

          <a href="${deepLinkUrl}" class="btn" id="open-btn">Mở Ứng Dụng Washer Notifier</a>
          <div class="subtext">Đang tự động chuyển hướng về ứng dụng...</div>
        </div>

        <script>
          // Tự động kích hoạt Deep Link
          window.location.href = "${deepLinkUrl}";
        </script>
      </body>
      </html>
    `);
  } catch (err) {
    console.error('[OAuth Callback] Ngoại lệ:', err);
    return res.status(500).json({ error: err.message });
  }
}

function escapeHtml(str) {
  if (!str) return '';
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}
