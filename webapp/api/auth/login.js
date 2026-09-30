/**
 * API Khởi tạo luồng đăng nhập OAuth2 Samsung SmartThings
 * Endpoint: /api/auth/login
 */
export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  const clientId = process.env.SMARTTHINGS_CLIENT_ID || 'd8e3097b-8bed-4a11-9689-25f6ec432fe4';
  const redirectUri = process.env.SMARTTHINGS_REDIRECT_URI || 'https://smart-things-noti-81ql.vercel.app/api/auth/callback';
  const scopes = process.env.SMARTTHINGS_OAUTH_SCOPES || 'r:devices:* x:devices:*';

  const authUrl = `https://api.smartthings.com/oauth/authorize?client_id=${encodeURIComponent(clientId)}&response_type=code&redirect_uri=${encodeURIComponent(redirectUri)}&scope=${encodeURIComponent(scopes)}`;

  // Nếu client yêu cầu JSON hoặc có query param ?json=true
  if (req.query.json === 'true' || req.headers.accept?.includes('application/json')) {
    return res.status(200).json({
      authUrl,
      clientId,
      redirectUri,
      scopes,
    });
  }

  // Chuyển hướng trình duyệt đến trang đăng nhập Samsung SmartThings
  return res.redirect(302, authUrl);
}
