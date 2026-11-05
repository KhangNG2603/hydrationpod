# 📱 HydraPod Patient App (Flutter Mobile)

Ứng dụng di động đa nền tảng viết bằng **Dart / Flutter**, được thiết kế chuyên biệt cho **Bệnh nhân (Patient)** trong hệ sinh thái IoT **Smart Hydration Pod**.

---

## ✨ Tính năng chính (Chuyên biệt cho Bệnh nhân)

1. **Vòng tròn Tiến độ Nạp dịch (Hydration Progress Ring)**:
   - Hiển thị lượng nước đã uống trong ngày (`V0`) so với mục tiêu hoặc trần y tế (`Hard Cap`) do Bác sĩ chỉ định.
   - Đổi màu cảnh báo theo vùng an toàn: Xanh (`0-80%`), Vàng (`80%`), Cam (`90%`), Đỏ khẩn cấp (`≥ 100% Trần Y Tế`).
2. **Mô phỏng Bình Nước Trực Quan (Animated Water Bottle - 500ml)**:
   - Hiển thị sóng nước thời gian thực từ cảm biến **HX711 Load Cell** (`V1`).
   - Tự động bật cảnh báo **Sắp cạn bình (`≤ 40ml`)** kèm nút châm nước nhanh `+350ml`.
3. **Nhắc Nhở Uống Nước & Báo Động Khẩn Cấp**:
   - Cảnh báo khi quên uống nước (`alert_level >= 1`).
   - Banner khẩn cấp khi vượt trần y tế (`EMERGENCY_OVERCAP`) kèm nút xác nhận & tắt còi (`MUTE`).
4. **Thao tác nhanh & Tùy biến âm báo**:
   - Ghi nhận uống nước (`+150ml`), Châm thêm nước (`+350ml`), Tìm bình qua xung rung Haptic (`GPIO 5`), và đổi kiểu chuông (`CHIME`, `MELODIC`, `DIGITAL`, `SIREN`, `CUSTOM`).

---

## 🚀 Cách chạy ứng dụng

### Cách 1: Chạy trực tiếp bằng Flutter SDK (Android / iOS / Desktop / Web)
```bash
cd mobile_app
flutter pub get
flutter run
```
> **Lưu ý khi chạy trên máy ảo Android Emulator**: Nhấn biểu tượng ⚙️ góc trên bên phải ứng dụng và đổi URL Server thành `http://10.0.2.2:8000` (hoặc IP LAN của máy tính). Ứng dụng cũng tự động kết nối trực tiếp tới MQTT Broker `broker.emqx.io:1883`.

### Cách 2: Chạy Bản Giả Lập Trực Tiếp Trên Trình Duyệt (Không cần cài Flutter SDK)
Truy cập ngay địa chỉ:
👉 **[http://localhost:8000/mobile](http://localhost:8000/mobile)**
(Đồng bộ thời gian thực 100% với Wokwi ESP32 và Web Dashboard của Bác sĩ).

