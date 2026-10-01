import 'dotenv/config';
import express from 'express';
import webhookHandler from './api/webhook.js';

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware parse JSON body
app.use(express.json());

// Health check endpoint cho Docker / Load Balancer
app.get('/health', (req, res) => {
  res.status(200).json({ status: 'healthy', uptime: process.uptime() });
});

// Endpoint webhook chính (hỗ trợ cả /api/webhook và /api/webhook.js khi chạy qua Vercel rewrite)
app.all(['/api/webhook', '/api/webhook.js'], async (req, res) => {
  await webhookHandler(req, res);
});

// Cho phép gọi trực tiếp root URL nếu webhook target trỏ tới root
app.post('/', async (req, res) => {
  await webhookHandler(req, res);
});

app.get('/', (req, res) => {
  res.status(200).json({
    name: 'SmartThings Washer FCM Webhook Service v0.0.1.1',
    status: 'running',
    endpoints: {
      webhook: '/api/webhook',
      health: '/health',
    },
  });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`=======================================================`);
  console.log(`🚀 SmartThings Webhook Server đang chạy trên cổng ${PORT}`);
  console.log(`📡 Webhook URL endpoint: http://localhost:${PORT}/api/webhook`);
  console.log(`🔍 Health check endpoint: http://localhost:${PORT}/health`);
  console.log(`=======================================================`);
});

export default app;

