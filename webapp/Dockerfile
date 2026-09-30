# Sử dụng Node.js 22 Alpine nhẹ và an toàn
FROM node:22-alpine

# Đặt thư mục làm việc
WORKDIR /app

# Đặt biến môi trường cho môi trường production
ENV NODE_ENV=production
ENV PORT=3000

# Copy file định nghĩa package để tận dụng Docker layer cache
COPY package*.json ./

# Cài đặt các dependencies cần thiết cho production
RUN npm ci --omit=dev || npm install --omit=dev

# Copy toàn bộ mã nguồn vào image
COPY . .

# Chuyển sang người dùng 'node' (non-root) để tăng cường bảo mật
USER node

# Mở cổng 3000
EXPOSE 3000

# Thiết lập healthcheck cho container
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:3000/health || exit 1

# Lệnh khởi chạy server Express
CMD ["npm", "start"]
