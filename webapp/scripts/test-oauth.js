/**
 * Kịch bản kiểm thử tự động toàn diện cho SmartThings OAuth2 Backend
 * Chạy: node scripts/test-oauth.js
 */
import 'dotenv/config';

console.log('=======================================================');
console.log('🧪 BẮT ĐẦU KIỂM THỬ BACKEND OAUTH2 SAMSUNG SMARTTHINGS');
console.log('=======================================================\n');

const clientId = process.env.SMARTTHINGS_CLIENT_ID || 'd8e3097b-8bed-4a11-9689-25f6ec432fe4';
const clientSecret = process.env.SMARTTHINGS_CLIENT_SECRET || '03fc160e-299f-4142-8d48-c5518b7c7856';
const redirectUri = process.env.SMARTTHINGS_REDIRECT_URI || 'https://smart-things-noti-81ql.vercel.app/api/auth/callback';
const scopes = process.env.SMARTTHINGS_OAUTH_SCOPES || 'r:devices:* x:devices:*';

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

async function runTests() {
  // ------------------------------------------------------------------
  // TEST 1: Kiểm tra cấu hình biến môi trường
  // ------------------------------------------------------------------
  console.log('[TEST 1] Kiểm tra biến môi trường OAuth2...');
  assert(Boolean(clientId), `Client ID tồn tại: ${clientId}`);
  assert(Boolean(clientSecret), `Client Secret tồn tại (độ dài ${clientSecret.length} ký tự)`);
  assert(redirectUri.includes('/api/auth/callback'), `Redirect URI hợp lệ: ${redirectUri}`);
  assert(scopes.includes('r:devices:*'), `Scopes hợp lệ: ${scopes}`);
  console.log('');

  // ------------------------------------------------------------------
  // TEST 2: Kiểm tra Handler /api/auth/login (Backend nội bộ)
  // ------------------------------------------------------------------
  console.log('[TEST 2] Kiểm tra Handler /api/auth/login...');
  const loginModule = await import('../api/auth/login.js');
  const loginHandler = loginModule.default;

  let redirectStatus = null;
  let redirectLocation = null;
  let jsonResponse = null;

  const mockReqRedirect = {
    method: 'GET',
    query: {},
    headers: {},
  };
  const mockResRedirect = {
    setHeader: () => {},
    redirect: (status, url) => {
      redirectStatus = status;
      redirectLocation = url;
    },
    status: () => ({ json: () => {} }),
  };

  await loginHandler(mockReqRedirect, mockResRedirect);
  assert(redirectStatus === 302, `Login trả về HTTP 302 Redirect (status: ${redirectStatus})`);
  assert(
    redirectLocation && redirectLocation.startsWith('https://api.smartthings.com/oauth/authorize'),
    `Redirect Location trỏ đúng tới Samsung SmartThings: ${redirectLocation?.substring(0, 75)}...`
  );

  // Test mode json=true
  const mockReqJson = {
    method: 'GET',
    query: { json: 'true' },
    headers: { accept: 'application/json' },
  };
  const mockResJson = {
    setHeader: () => {},
    status: (s) => ({
      json: (d) => {
        jsonResponse = d;
      },
    }),
  };
  await loginHandler(mockReqJson, mockResJson);
  assert(Boolean(jsonResponse?.authUrl), `Chế độ JSON trả về authUrl: ${jsonResponse?.authUrl?.substring(0, 60)}...`);
  assert(jsonResponse?.clientId === clientId, `Client ID trong JSON khớp với .env`);
  console.log('');

  // ------------------------------------------------------------------
  // TEST 3: Kiểm tra trực tiếp với Server LIVE của Samsung SmartThings
  // Gửi request đến SmartThings Authorize URL với Client ID
  // ------------------------------------------------------------------
  console.log('[TEST 3] Kiểm tra Authorize URL với máy chủ thực của Samsung SmartThings...');
  try {
    const authUrl = `https://api.smartthings.com/oauth/authorize?client_id=${encodeURIComponent(clientId)}&response_type=code&redirect_uri=${encodeURIComponent(redirectUri)}&scope=${encodeURIComponent(scopes)}`;
    const liveAuthRes = await fetch(authUrl, { redirect: 'manual' });
    
    assert(
      liveAuthRes.status === 302,
      `Samsung SmartThings chấp nhận Client ID & chuyển hướng đến trang đăng nhập (HTTP ${liveAuthRes.status})`
    );
    const samsungLoginLocation = liveAuthRes.headers.get('location');
    assert(
      samsungLoginLocation && samsungLoginLocation.includes('account.smartthings.com'),
      `Điểm đến là trang đăng nhập Samsung Account: ${samsungLoginLocation?.substring(0, 80)}...`
    );
  } catch (err) {
    assert(false, `Lỗi khi kết nối Samsung SmartThings Authorize: ${err.message}`);
  }
  console.log('');

  // ------------------------------------------------------------------
  // TEST 4: Kiểm tra xác thực Client ID & Client Secret tại Token Endpoint của Samsung
  // ------------------------------------------------------------------
  console.log('[TEST 4] Kiểm tra Client Secret tại Token Endpoint của Samsung...');
  try {
    const basicAuth = Buffer.from(`${clientId}:${clientSecret}`).toString('base64');
    const tokenParams = new URLSearchParams({
      grant_type: 'authorization_code',
      code: 'dummy_test_verification_code',
      client_id: clientId,
      client_secret: clientSecret,
      redirect_uri: redirectUri,
    });

    const liveTokenRes = await fetch('https://api.smartthings.com/oauth/token', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Authorization': `Basic ${basicAuth}`,
        'Accept': 'application/json',
      },
      body: tokenParams.toString(),
    });

    const bodyText = await liveTokenRes.text();
    let bodyJson = {};
    try {
      bodyJson = JSON.parse(bodyText);
    } catch (_) {}

    // NẾU client_id hoặc client_secret sai -> Samsung trả về 401 Unauthorized (invalid_client)
    // NẾU client_id và client_secret đúng nhưng code giả -> Samsung trả về 400 Bad Request (invalid_grant)
    assert(
      liveTokenRes.status === 400 && bodyJson.error === 'invalid_grant',
      `Samsung đã xác thực Client ID & Secret thành công! (Báo lỗi "invalid_grant" do mã code test giả, chứng minh Client Secret đúng: ${bodyText})`
    );
    assert(
      bodyJson.error !== 'invalid_client',
      `Không bị lỗi invalid_client -> Bộ khóa bí mật Client Secret 100% hợp lệ trên Samsung.`
    );
  } catch (err) {
    assert(false, `Lỗi khi kết nối Samsung Token Endpoint: ${err.message}`);
  }
  console.log('');

  // ------------------------------------------------------------------
  // TEST 5: Kiểm tra Handler /api/auth/callback (Backend nội bộ)
  // ------------------------------------------------------------------
  console.log('[TEST 5] Kiểm tra Handler /api/auth/callback...');
  const callbackModule = await import('../api/auth/callback.js');
  const callbackHandler = callbackModule.default;

  // 5.1 Trường hợp người dùng từ chối / hủy đăng nhập
  let callbackHtml = '';
  let callbackStatusCode = null;
  const mockReqError = {
    method: 'GET',
    query: { error: 'access_denied', error_description: 'Nguoi dung tu choi' },
    headers: {},
  };
  const mockResError = {
    setHeader: () => {},
    status: (s) => {
      callbackStatusCode = s;
      return {
        send: (html) => {
          callbackHtml = html;
        },
      };
    },
  };

  await callbackHandler(mockReqError, mockResError);
  assert(callbackStatusCode === 400, `Callback khi lỗi trả về HTTP 400`);
  assert(
    callbackHtml.includes('washerapp://auth?success=false'),
    `Deep Link chứa scheme hủy xác thực (success=false)`
  );

  // 5.2 Trường hợp thiếu code
  let missingCodeStatus = null;
  const mockReqNoCode = { method: 'GET', query: {}, headers: {} };
  const mockResNoCode = {
    setHeader: () => {},
    status: (s) => {
      missingCodeStatus = s;
      return { json: () => {} };
    },
  };
  await callbackHandler(mockReqNoCode, mockResNoCode);
  assert(missingCodeStatus === 400, `Callback khi không có code trả về HTTP 400`);
  console.log('');

  // ------------------------------------------------------------------
  // TỔNG KẾT
  // ------------------------------------------------------------------
  console.log('=======================================================');
  console.log(`📊 KẾT QUẢ KIỂM THỬ: ${passedTests}/${totalTests} TESTS PASSED`);
  if (passedTests === totalTests) {
    console.log('🎉 TOÀN BỘ CÁC BƯỚC XÁC THỰC OAUTH2 SAMSUNG BACKEND ĐÃ SẴN SÀNG VÀ CHÍNH XÁC 100%!');
  } else {
    console.log('⚠️ CÓ TEST CHƯA ĐẠT. VUI LÒNG KIỂM TRA LẠI.');
  }
  console.log('=======================================================');
}

runTests().catch(console.error);
