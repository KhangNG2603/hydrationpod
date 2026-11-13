#!/usr/bin/env bash
set -e

echo "============================================================"
echo "📦 Smart Hydration Pod - Cài đặt & Đóng gói Requirements"
echo "============================================================"

# 1. Python Backend & Test Suite
echo ""
echo "🐍 [1/3] Kiểm tra & cài đặt Python dependencies (requirements.txt)..."
if python3 -c "import paho.mqtt" >/dev/null 2>&1; then
  echo "✅ Python dependencies (paho-mqtt) đã sẵn sàng."
else
  if [ ! -d ".venv" ]; then
    python3 -m venv .venv
  fi
  .venv/bin/pip install -r requirements.txt
  echo "✅ Đã cài đặt Python dependencies trong .venv (chạy bằng: .venv/bin/python3 server.py)."
fi

# 2. ESP32 Firmware (PlatformIO)
echo ""
echo "⚡ [2/3] Kiểm tra & cài đặt thư viện Firmware ESP32 (platformio.ini)..."
PIO_BIN=$(command -v pio || echo "$HOME/.platformio/penv/bin/pio")
if [ -x "$PIO_BIN" ]; then
  "$PIO_BIN" pkg install
  echo "✅ Đã đồng bộ thư viện PlatformIO."
else
  echo "⚠️ Không tìm thấy PlatformIO CLI (pio). Bỏ qua bước này."
fi

# 3. Flutter Mobile App
echo ""
echo "📱 [3/3] Kiểm tra & cài đặt Flutter dependencies (mobile_app/pubspec.yaml)..."
if command -v flutter >/dev/null 2>&1; then
  (cd mobile_app && flutter pub get)
  echo "✅ Đã đồng bộ thư viện Flutter."
else
  echo "⚠️ Chưa cài Flutter SDK trên máy. Bạn vẫn có thể chạy bản Mobile Emulator tại http://localhost:8000/mobile."
fi

echo ""
echo "============================================================"
echo "🎉 Hoàn tất đóng gói & cài đặt requirements!"
echo "👉 Khởi động hệ thống: python3 server.py"
echo "👉 Chạy kiểm thử:     python3 test_system.py"
echo "============================================================"
