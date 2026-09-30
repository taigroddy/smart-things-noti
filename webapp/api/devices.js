/**
 * API trả về danh sách thiết bị SmartThings (Máy giặt / Máy sấy)
 * để App có thể tự động lấy deviceId mà không cần lưu PAT trên app di động.
 */
export default async function handler(req, res) {
  // Cho phép CORS để app Flutter gọi trực tiếp
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  if (req.method !== 'GET') {
    return res.status(405).json({ error: 'Chỉ hỗ trợ phương thức GET' });
  }

  const authHeader = req.headers['authorization'];
  let pat = authHeader && authHeader.startsWith('Bearer ') ? authHeader.substring(7) : null;
  if (!pat && req.query.token) {
    pat = req.query.token;
  }
  if (!pat) {
    pat = process.env.SMARTTHINGS_PAT;
  }
  if (!pat) {
    return res.status(500).json({ error: 'SMARTTHINGS_PAT hoặc OAuth Token chưa được cung cấp.' });
  }

  try {
    const response = await fetch('https://api.smartthings.com/v1/devices', {
      headers: {
        Authorization: `Bearer ${pat}`,
        Accept: 'application/json',
      },
    });

    if (!response.ok) {
      const errText = await response.text();
      return res.status(response.status).json({
        error: `Lỗi kết nối SmartThings API: ${response.status}`,
        details: errText,
      });
    }

    const data = await response.json();
    const items = data.items || [];

    // Lọc chỉ lấy các thiết bị là Máy giặt (Washer) hoặc Máy sấy (Dryer)
    const washerItems = items.filter((dev) => {
      const categories = dev.components?.flatMap((c) => c.categories?.map((cat) => cat.name)) || [];
      const hasWasherCategory = categories.some((c) => ['Washer', 'Dryer'].includes(c));
      const hasWasherName =
        (dev.name && /washer|dryer|máy giặt|máy sấy/i.test(dev.name)) ||
        (dev.label && /washer|dryer|máy giặt|máy sấy/i.test(dev.label));
      return hasWasherCategory || hasWasherName;
    });

    const washers = washerItems.map((dev) => {
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

    return res.status(200).json({
      success: true,
      count: washers.length,
      devices: washers,
    });
  } catch (error) {
    console.error('[API /devices] Lỗi:', error);
    return res.status(500).json({ error: error.message });
  }
}
