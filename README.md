# 💧 Smart Hydration Pod - Sensor-Driven IoT & Medical Hydration Engine

> **Dự án Internet of Things**: Module Thông Minh Gắn Rời Cho Bình Nước Nhắc Nhở Uống Nước Tự Động & Giám Sát Y Tế  
> **Kiến trúc tích hợp**: ESP32 (Wokwi) + Load Cell HX711 + IMU MPU6050 + Haptic Vibration Motor + NeoPixel WS2812B + OLED SSD1306 + EMQX Cloud MQTT + Python REST API Bridge + Web Dashboard + Node-RED + Postman Suite.

---

## 📋 MỤC LỤC
1. [Giới Thiệu Đề Tài & Bài Toán Thực Tế](#1-giới-thiệu-đề-tài--bài-toán-thực-tế)
2. [Sơ Đồ Kiến Trúc Hệ Thống IoT](#2-sơ-đồ-kiến-trúc-hệ-thống-iot)
3. [Phần Cứng & Sơ Đồ Đấu Nối (Pinout)](#3-phần-cứng--sơ-đồ-đấu-nối-pinout)
4. [Thuật Toán FSM & Logic Xử Lý Cảm Biến](#4-thuật-toán-fsm--logic-xử-lý-cảm-biến)
5. [Bộ Rung Nhắc Nhở Xúc Giác (Haptic Vibration Engine)](#5-bộ-rung-nhắc-nhở-xúc-giác-haptic-vibration-engine)
6. [Biên An Toàn Kép Y Tế (Dual Safety Margin)](#6-biên-an-toàn-kép-y-tế-dual-safety-margin)
7. [Giao Thức Cloud IoT: MQTT & HTTP REST API](#7-giao-thức-cloud-iot-mqtt--http-rest-api)
8. [Web Dashboard, Node-RED & Postman Suite](#8-web-dashboard-node-red--postman-suite)
9. [Hướng Dẫn Cài Đặt & Chạy Mô Phỏng](#9-hướng-dẫn-cài-đặt--chạy-mô-phỏng)
10. [Kịch Bản Kiểm Thử Thực Nghiệm (Demo Scenarios)](#10-kịch-bản-kiểm-thử-thực-nghiệm-demo-scenarios)
11. [Bộ Câu Hỏi Phản Biện & Trả Lời Trọng Tâm](#11-bộ-câu-hỏi-phản-biện--trả-lời-trọng-tâm)

---

## 🎯 1. GIỚI THIỆU ĐỀ TÀI & BÀI TOÁN THỰC TẾ

### 1.1. Vấn đề thực tiễn
- **Hạn chế giải pháp hiện nay**: Bình nước thông minh nguyên khối đắt đỏ (\$50–\$100), khó cọ rửa vệ sinh do dễ chập mạch điện tử. Đế lót ly (Smart Coaster) chỉ cố định trên bàn, mất khả năng theo dõi khi mang đi làm, tập thể thao.
- **Đối tượng làm việc tĩnh tại (Văn phòng, sinh viên)**: Thường xuyên quên uống nước do tập trung cao độ, chỉ uống khi cơ thể đã phát tín hiệu khát nghiêm trọng (khi cơ thể đã mất 1.5–2% lượng nước).
- **Đối tượng bệnh lý y tế đặc thù**:
  - **Bệnh nhân cần hạn chế dịch nghiêm ngặt (Suy tim ứ huyết, suy thận mạn giai đoạn 3–5, chạy thận chu kỳ)**: Khả năng đào thải nước qua thận suy giảm trầm trọng. Uống dồn dập hoặc vượt quá dung tích cho phép gây phù phổi cấp, tăng huyết áp kịch phát và suy hô hấp đe dọa tính mạng.
  - **Bệnh nhân mất dịch / cần bài tiết liên tục (Sỏi thận, Gout)**: Cần duy trì dòng nước vào đều đặn liên tục để đào thải tinh thể urat và cặn lắng, ngăn kết tinh sỏi mới.
  - **Người cao tuổi / Alzheimer / Parkinson**: Suy giảm phản xạ khát tự nhiên, cần hệ thống cảnh báo tại chỗ kết hợp báo động từ xa tới người chăm sóc (Caregiver/Doctor).

### 1.2. Giải pháp kỹ thuật của Smart Hydration Pod
- **Thiết kế dạng Capsule gắn rời**: Module đĩa tròn lắp đáy bình nước tiêu chuẩn (đường kính 70–80mm), tháo rời nhanh chóng khi cọ rửa bình.
- **Tự động đo lường 100% bằng cảm biến**: Kết hợp cảm biến tải trọng (HX711 Load Cell) và cảm biến chuyển động 6 trục (MPU6050) để nhận diện chính xác hành vi uống, loại trừ sai số lắc sóng sánh.
- **Đồng bộ hóa Cloud IoT 2 chiều**: Cập nhật Telemetry theo thời gian thực lên Cloud MQTT, nhận lệnh can thiệp phác đồ y tế từ Bác sĩ/Dashboard, phản hồi Feedback ACK tức thời.

---

## 🏗️ 2. SƠ ĐỒ KIẾN TRÚC HỆ THỐNG IOT

```
+-----------------------------------------------------------------------------------+
|                            SMART HYDRATION POD ARCHITECTURE                       |
+-----------------------------------------------------------------------------------+
|                                                                                   |
|  [EDGE HARDWARE - ESP32 NODE]                                                     |
|  +-------------------+    +--------------------+    +---------------------------+ |
|  | Load Cell + HX711 |    | MPU6050 (Pitch/Roll|    | Haptic Vibration Motor    | |
|  | (Đo khối lượng ΔW)|    | nhận diện nâng bình|    | (Nhắc nhở & phản hồi ngụm)| |
|  +---------+---------+    +---------+----------+    +-------------+-------------+ |
|            |                        |                             ^               |
|            v                        v                             |               |
|  +----------------------------------------------------------------+-------------+ |
|  |             ESP32 Core Engine (FSM Y Tế + Moving Average Filter)             | |
|  | - Khóa cân khi nâng bình (Hold State)   - Bộ đếm nhàn rỗi thích ứng           | |
|  | - Biên an toàn kép (80% Vàng, 90% Đỏ)   - Non-blocking Network Reconnect     | |
|  +-----------------------------------+------------------------------------------+ |
|                                      |                                            |
|                                      v                                            |
|  [NETWORK / CLOUD BROKER]                                                         |
|  +------------------------------------------------------------------------------+ |
|  |                  Public EMQX MQTT Broker (broker.emqx.io:1883)               | |
|  |  Topics:                                                                     | |
|  |  • smartbottle/HYDROPOD_01/telemetry  (Telemetry JSON định kỳ 3s)            | |
|  |  • smartbottle/HYDROPOD_01/control    (Lệnh điều khiển / Profile / Vibrate)  | |
|  |  • smartbottle/HYDROPOD_01/ack        (Phản hồi Feedback Loop ACK tức thì)   | |
|  |  • smartbottle/HYDROPOD_01/status     (LWT Status ONLINE/OFFLINE)            | |
|  +-----------------------------------+------------------------------------------+ |
|                                      |                                            |
|       +------------------------------+-------------------------------+            |
|       v                                                              v            |
|  [SERVER BRIDGE / GATEWAY]                                   [APPLICATION LAYER]  |
|  +--------------------------------+                          +------------------+ |
|  | Python Server (server.py:8000) |                          | Web Dashboard UI | |
|  | - HTTP REST API Server         |                          | (app.js / SSE)   | |
|  | - MQTT Bridge to EMQX          |                          +------------------+ |
|  | - Server-Sent Events (SSE)     |                          | Postman Suite    | |
|  +--------------------------------+                          +------------------+ |
|                                                              | Node-RED Flows   | |
|                                                              +------------------+ |
+-----------------------------------------------------------------------------------+
```

---

## 🔌 3. PHẦN CỨNG & SƠ ĐỒ ĐẤU NỐI (PINOUT)

| Module / Linh Kiện | Chân Module | Chân ESP32 | Giao Thức / Chức Năng |
| :--- | :--- | :--- | :--- |
| **Micro Load Cell 5kg** | DT / DOUT | **GPIO 16** | Tín hiệu dữ liệu ADC 24-bit từ HX711 |
| | SCK / CLK | **GPIO 17** | Xung Clock tạo mẫu từ ESP32 |
| | VCC / GND | **3V3 / GND** | Nguồn ổn áp cảm biến |
| **IMU MPU6050 (6 trục)** | SDA | **GPIO 21** | I2C Data (Nhận diện góc nghiêng > 35°) |
| | SCL | **GPIO 22** | I2C Clock (Gia tốc tổng xác thực chuyển động) |
| | VCC / GND | **3V3 / GND** | Nguồn cấp cho IMU |
| **Màn Hình OLED SSD1306** | SDA / SCL | **GPIO 21 / 22** | Bus I2C chung (Địa chỉ 0x3C, 128x64 px) |
| | VCC / GND | **3V3 / GND** | Hiển thị tiến độ, % pin, trạng thái rung |
| **Vòng 8 LED WS2812B** | DIN | **GPIO 15** | Đèn viền báo hiệu đổi màu trực quan |
| | VCC / GND | **5V / GND** | Nguồn công suất LED RGB |
| **Còi Báo Động (Buzzer)** | Pin (+) | **GPIO 4** | Phát âm báo nhắc nhở & chuông cứu hộ |
| **Bộ Rung (Vibration Motor)**| Pin (+) | **GPIO 5** | Bộ rung xúc giác Haptic nhắc nhở & phản hồi |
| | Pin (-) | **GND** | Nối Mass chung ESP32 |

---

## 🧠 4. THUẬT TOÁN FSM & LOGIC XỬ LÝ CẢM BIẾN

Hệ thống hoạt động theo **Máy trạng thái hữu hạn (FSM)** kết hợp bộ lọc số trung bình trượt (**Moving Average Filter N=10**) để triệt tiêu nhiễu dao động cơ học khi cầm bình:

```
                  +--------------------------------+
                  |           STATE_REST           |
                  | Bình đứng yên trên mặt bàn     |
                  | HX711 cập nhật Moving Avg N=10 |
                  +---------------+----------------+
                                  |
               Góc nghiêng > 35°  | (Nhấc bình lên uống)
                                  v
                  +--------------------------------+
                  |     STATE_TILTED_DRINKING      |
                  | Khóa cân (Hold State)          |
                  | Chống nhiễu nước sóng sánh    |
                  +---------------+----------------+
                                  |
               Góc nghiêng < 18°  | (Đặt bình trở lại bàn)
                                  v
                  +--------------------------------+
                  |         STATE_SETTLING         |
                  | Chờ 1.0s nước và lực ổn định   |
                  +---------------+----------------+
                                  |
                                  v
                  +--------------------------------+
                  |        ĐÁNH GIÁ SỰ KIỆN        |
                  +---------------+----------------+
                                  |
           +----------------------+----------------------+
           | ΔW >= 25g & t >= 0.8s| ΔW <= -40g           | |ΔW| < 25g
           v                      v                      v
     [UỐNG HỢP LỆ]          [CHÂM NƯỚC (REFILL)]   [NHIỄU / BỎ QUA]
  - Cộng tổng nạp ngày    - Cập nhật dung tích   - Giữ nguyên số đo
  - Haptic click 90ms     - Haptic rung đôi 60ms - Không tính tiến độ
  - LED Xanh + Beep       - LED Cyan + Chime
  - Đẩy Telemetry & ACK   - Đẩy Telemetry & ACK
```

- **Công thức quy đổi thể tích**:
  $$\Delta V = (W_{\text{trước}} - W_{\text{sau}}) \times \rho_{\text{nước}}^{-1} \quad (\rho_{\text{nước}} \approx 1.0\text{ g/ml})$$
- **Tính tiến độ hoàn thành ngày**:
  $$P\% = \left(\frac{V_{\text{tích lũy}}}{V_{\text{mục tiêu}}}\right) \times 100\%$$

---

## 📳 5. BỘ RUNG NHẮC NHỞ XÚC GIÁC (HAPTIC VIBRATION ENGINE)

Bộ rung trên chân **GPIO 5** được điều khiển qua máy trạng thái thời gian thực (`updateVibration()`), hoàn toàn phi chặn (**non-blocking**), mang lại cảm giác xúc giác y khoa tự nhiên:

| Cấp Độ Cảnh Báo | Điều Kiện Kích Hoạt | Kiểu Xung Rung Haptic | LED & Còi Kèm Theo |
| :--- | :--- | :--- | :--- |
| **Xác nhận ngụm uống** | Uống nước hợp lệ $\ge 25\text{ml}$ | **1 nhịp click êm ái (90ms)** | LED Xanh lá + Chime 1046Hz |
| **Xác nhận châm nước** | Châm thêm nước $\ge 40\text{ml}$ | **2 nhịp nhanh (60ms ON - 60ms OFF)** | LED Cyan + Beep 800Hz |
| **Quên uống Cấp 1** | Nhàn rỗi $\ge T_{\text{remind}}$ (30s demo / 45–60m) | Không rung | LED Cam thở nhẹ (Breathing LED) |
| **Quên uống Cấp 2** | Nhàn rỗi $\ge T_{\text{remind}} + 15\text{s}$ | **Rung đôi (150ms ON - 100ms OFF - 150ms ON)**, lặp mỗi 3s | LED Cam nháy + Chime ngắn 1200Hz |
| **Quên uống Cấp 3** | Nhàn rỗi $\ge T_{\text{remind}} + 30\text{s}$ | **Rung 3 nhịp dồn dập (180ms ON - 80ms OFF $\times 3$)**, lặp mỗi 2s | LED Đỏ chớp + Chuông dồn dập 1800Hz |
| **Khẩn cấp (Overcap)** | Vượt trần y tế ($V_{\text{nạp}} \ge V_{\text{cap}}$) | **Rung xung liên tục (250ms ON / 150ms OFF)** | LED Đỏ khẩn cấp + Còi báo động 2500Hz |
| **Lệnh test từ xa** | Nhận lệnh `vibrate` từ Cloud | **Rung đơn 300ms** (hoặc theo tham số) | Cập nhật Telemetry `vibration_motor: 1` |

---

## 🛡️ 6. BIÊN AN TOÀN KÉP Y TẾ (DUAL SAFETY MARGIN)

Dành riêng cho bệnh nhân **Suy tim ứ huyết** và **Suy thận mạn**, hệ thống áp dụng cơ chế 2 cấp bảo vệ trước khi chạm trần nguy hiểm:

$$V_{\text{trần}} = \text{Hard Cap (ví dụ: 1000ml/ngày)}$$

```
[0ml] -------------- [80% Trần: 800ml] ----------- [90% Trần: 900ml] ------------ [100% Trần: 1000ml]
  |                          |                             |                              |
  v                          v                             v                              v
🟢 BÌNH THƯỜNG          🟡 TIỆM CẬN (VÀNG)            🔴 NGUY HIỂM (ĐỎ)          🚨 BÁO ĐỘNG KHẨN CẤP
Nước nạp an toàn         LED Vàng cảnh báo sớm        LED Đỏ cảnh báo khẩn cấp   Còi 2500Hz + Rung dồn dập
                         Nhắc bệnh nhân uống chậm      Cảnh báo bác sĩ can thiệp  Modal Pop-up đỏ trên Web
```

- **Mục tiêu**: Tuyệt đối không chờ đến khi bệnh nhân nạp quá 100% mới báo động, mà kích hoạt phòng ngừa sớm từ 80% và 90% để tránh quá tải tuần hoàn.

---

## 🌐 7. GIAO THỨC CLOUD IOT: MQTT & HTTP REST API

### 7.1. Cấu hình MQTT Broker
- **Broker**: `broker.emqx.io` (Cổng TCP: 1883, Cổng WebSockets: 8084)
- **ID Thiết Bị**: `HYDROPOD_01`
- **Bộ nhớ đệm (Buffer Size)**: Đã mở rộng lên **512 Bytes** trên ESP32 để không bị mất gói tin JSON.
- **Cơ chế LWT (Last Will and Testament)**: Tự động công bố trạng thái `OFFLINE` khi ESP32 mất kết nối đột ngột.

### 7.2. Cấu trúc Topic MQTT
| Tên Topic | Hướng Truyền | Chức Năng |
| :--- | :---: | :--- |
| `smartbottle/HYDROPOD_01/telemetry` | ESP32 $\to$ Cloud | Báo cáo toàn bộ thông số mỗi 3 giây hoặc tức thì khi uống |
| `smartbottle/HYDROPOD_01/control` | Cloud $\to$ ESP32 | Nhận lệnh đổi phác đồ, mute chuông, test rung từ xa |
| `smartbottle/HYDROPOD_01/ack` | ESP32 $\to$ Cloud | Phản hồi xác nhận lệnh (Feedback Loop ACK) |
| `smartbottle/HYDROPOD_01/status` | ESP32 $\to$ Cloud | Trạng thái sống còn LWT (`ONLINE` / `OFFLINE`) |

#### Mẫu gói tin Telemetry JSON:
```json
{
  "device_id": "HYDROPOD_01",
  "drank_today_ml": 400,
  "bottle_ml": 500,
  "goal_ml": 2000,
  "hard_cap_ml": 0,
  "progress_pct": 20.0,
  "rate_hourly_ml": 0,
  "idle_sec": 12,
  "battery_soc": 85,
  "safety_status": "NORMAL",
  "alert_level": 0,
  "profile": "STANDARD",
  "vibration_motor": 0,
  "wifi_connected": true,
  "wifi_rssi": -48,
  "is_muted": false,
  "uptime_sec": 425,
  "last_event": "Sensor Drink: +150ml"
}
```

### 7.3. Bảng HTTP REST API Endpoints (`server.py`)
| Phương thức | Endpoint URL | Request Body Mẫu | Chức Năng |
| :---: | :--- | :--- | :--- |
| `GET` | `/api/telemetry` | Không | Lấy dữ liệu thời gian thực hiện tại của bình |
| `GET` | `/api/help` | Không | Xem danh sách routes & hướng dẫn API |
| `POST` | `/api/drink` | `{"amount_ml": 150}` | Mô phỏng nạp nước từ xa |
| `POST` | `/api/vibrate` | `{"duration_ms": 300}` | Kích hoạt kiểm thử bộ rung xúc giác |
| `POST` | `/api/profile` | `{"profile": "HEART_FAILURE", "hard_cap": 1000}` | Chỉ định phác đồ y tế (STANDARD, HEART_FAILURE, GOUT) |
| `POST` | `/api/alarm` | `{"action": "MUTE"}` | Bật / Tắt chuông báo động (`MUTE` / `UNMUTE`) |
| `POST` | `/api/reset` | `{}` | Reset bộ đếm lượng nước ngày về 0 |
| `POST` | `/api/command` | `{"command": "SIM_DEMO_SCENARIO_1"}` | Chạy nhanh các kịch bản demo kiểm thử |

---

## 🖥️ 8. WEB DASHBOARD, NODE-RED & POSTMAN SUITE

### 8.1. Web Dashboard thời gian thực (`dashboard/`)
- Tích hợp kết nối trực tiếp **MQTT over WebSockets** (`wss://broker.emqx.io:8084/mqtt`) kèm cơ chế dự phòng **Server-Sent Events (SSE)**.
- Hiển thị Gauge đo nạp dịch, thanh tiến độ 4 mốc màu an toàn y tế.
- Bảng điều khiển chọn Profile bệnh nhân, thanh trượt cài đặt trần cứng (Slider Hard Cap).
- Nút bấm **"📳 Test Rung"** điều khiển trực tiếp haptic motor qua Cloud.
- Ô theo dõi trạng thái bộ rung (`Sẵn sàng` / `Đang rung` kèm animation rung lắc).
- Biểu đồ lịch sử nạp dịch theo dòng thời gian (**Chart.js Line Chart**).
- Phân quyền người dùng (**Caregiver / Patient Switcher**) chống chỉnh nhầm thông số.

### 8.2. Node-RED Flow (`nodered/flows_smart_hydration_pod.json`)
- Ánh xạ trực quan các thông số Telemetry sang **Virtual Pins**:
  - `V0`: Lượng nước nạp lũy kế trong ngày (Gauge + Chart).
  - `V1`: Lượng nước còn lại trong bình.
  - `V3`: Thời gian nhàn rỗi (giây).
  - `V5`: Dung lượng pin (%).
  - `V6`: Nhận lệnh cấu hình Profile & Hard Cap từ xa.
  - `V7`: Nút Mute / Unmute còi báo động.

### 8.3. Postman Test Suite (`postman_collection.json`)
Bộ sưu tập đầy đủ các kịch bản kiểm thử HTTP REST API & MQTT Bridge:
1. `GET Current Telemetry`: Kiểm tra phản hồi thông số Virtual Pins.
2. `POST Test Vibration Motor`: Kiểm thử bộ rung từ xa.
3. `POST Drink Water (+150ml)`: Kiểm thử phản ứng khi uống nước.
4. `POST Set Profile Heart Failure (1000ml)`: Kiểm tra chuyển phác đồ suy tim.
5. `POST Alarm Mute`: Kiểm thử tắt chuông báo động.
6. `POST Run Scenario 1, 2, 3`: Kịch bản demo tự động.

---

## 🚀 9. HƯỚNG DẪN CÀI ĐẶT & CHẠY MÔ PHỎNG

### Bước 1: Biên dịch Firmware ESP32
```bash
~/.platformio/penv/bin/pio run
```
File nhị phân `firmware.bin` và `firmware.elf` sẽ được tạo tại `.pio/build/az-delivery-devkit-v4/`.

### Bước 2: Chạy Mô Phỏng Wokwi
- Mở VS Code, nhấn `F1` $\to$ chọn **Wokwi: Start Simulator** (hoặc mở trực tiếp file `diagram.json`).
- Nhìn vào bảng mạch mô phỏng:
  - Cân **HX711** nối GPIO 16, 17.
  - Cảm biến **MPU6050** nối SDA 21, SCL 22.
  - Đèn LED cam **motor1** (Vibration Motor) nối GPIO 5.
  - Còi **bz1** nối GPIO 4.
  - Vòng 8 LED **ring1** nối GPIO 15.
  - Màn hình OLED hiển thị `HydraPod [MQTT]` và trạng thái `Vib: ON/OFF`.

### Bước 3: Khởi động Server REST API & Web Dashboard
```bash
python3 server.py
```
- Mở trình duyệt Web tại: **[http://localhost:8000](http://localhost:8000)**
- Xem tài liệu API tại: **[http://localhost:8000/api/help](http://localhost:8000/api/help)**

### Bước 4: Kiểm thử bằng Phím Tắt Serial Monitor
Trên cửa sổ Serial Terminal của Wokwi (tốc độ 115200 baud):
- Bấm phím `1`: Mô phỏng uống 150ml nước.
- Bấm phím `2`: Mô phỏng cảnh báo nhàn rỗi quá 35s (kích hoạt Rung đôi + Còi).
- Bấm phím `3`: Mô phỏng bệnh nhân suy tim uống vượt trần 1050/1000ml (kích hoạt Rung khẩn cấp + Còi 2500Hz + Pop-up đỏ).
- Bấm phím `v`: Kiểm thử kích hoạt bộ rung trong 300ms.
- Bấm phím `r`: Reset bộ đếm ngày về 0.

---

## 🧪 10. KỊCH BẢN KIỂM THỬ THỰC NGHIỆM (DEMO SCENARIOS)

### Kịch bản 1: Uống nước hợp lệ (Valid Drinking)
1. Bình ban đầu 500ml, mục tiêu 2000ml.
2. Người dùng nhấc bình, nghiêng góc $> 35^\circ$ trên MPU6050 trong 2 giây rồi đặt bình xuống bàn.
3. Load Cell cân lại thấy hao hụt 150ml ($\Delta W \ge 25\text{g}$).
4. **Kết quả**: Vòng LED chớp xanh 1 nhịp, còi kêu tiếng bíp êm tai, bộ rung haptic **click 1 nhịp 90ms**. Dashboard cập nhật ngay lập tức: Đã uống +150ml, Nước còn lại 350ml, bộ đếm nhàn rỗi tự reset về 0.

### Kịch bản 2: Cảnh báo quên uống nước thích ứng (Idle Reminder)
1. Đặt bình đứng yên trên bàn. Trong chế độ demo, ngưỡng nhắc nhở là 30 giây.
2. **Sau 30 giây**: LED đáy chuyển sang màu cam thở nhẹ (Breathing LED) - Cấp 1.
3. **Sau 45 giây**: Bộ rung kích hoạt **nhịp Rung đôi (Double Pulse 150ms-100ms-150ms)** lặp mỗi 3s, kèm âm bíp ngắn 1200Hz - Cấp 2.
4. **Sau 60 giây**: Rung dồn dập 3 nhịp liên tục, chuông reo dồn dập - Cấp 3.
5. Khi người dùng nhấc bình uống $\ge 25\text{ml}$, toàn bộ đèn, còi và rung tự động tắt ngay lập tức.

### Kịch bản 3: Bệnh nhân suy tim uống vượt trần y tế (Emergency Overcap)
1. Trên Dashboard hoặc Postman chọn Profile: `Suy Tim` (Hard Cap = 1000ml).
2. Lượng nước tích lũy ban đầu đang là 950ml.
3. Người dùng nhấc bình uống thêm 100ml (tổng nạp vượt lên 1050ml $\ge 1000\text{ml}$).
4. **Kết quả**: Ngay khi đặt bình xuống, vòng LED nhấp nháy đỏ rực rỡ, còi kêu hú dồn dập 2500Hz, **bộ rung haptic rung nhịp khẩn cấp liên tục**. Màn hình Web Dashboard bật Pop-up đỏ toàn màn hình cảnh báo: *"NGUY HIỂM: Bệnh nhân đã vượt trần nạp dịch 1050/1000ml!"* cùng thông báo khẩn cấp đẩy lên Cloud.

---

## ❓ 11. BỘ CÂU HỎI PHẢN BIỆN & TRẢ LỜI TRỌNG TÂM

**Q1: Tại sao nhóm chọn Load Cell ở đáy module mà không dùng cảm biến khoảng cách siêu âm hoặc ToF gắn trên nắp bình?**  
*Trả lời:* Cảm biến siêu âm/ToF gắn trên nắp gặp nhược điểm chí mạng là hơi nước từ trong bình bốc lên ngưng tụ làm mờ và ẩm ướt mắt đọc quang học, đồng thời không đo được chính xác khi mặt nước sóng sánh hoặc có đá viên nổi bấp bênh. Dùng Load Cell ở module đáy đo áp lực trọng lượng trực tiếp, cách ly 100% khỏi nước, bền bỉ, dễ dàng tháo rời bình mang đi rửa sạch sẽ.

**Q2: ESP32 kết nối Wi-Fi liên tục tiêu hao pin rất lớn, làm thế nào để thiết bị di động dùng được nhiều ngày?**  
*Trả lời:* ESP32 hỗ trợ chế độ Deep Sleep với dòng tiêu thụ chỉ $\approx 10\text{–}15\mu\text{A}$. Mạch sử dụng chân ngắt phần cứng (Hardware Interrupt) từ chân `INT` của MPU6050 để chỉ đánh thức ESP32 khi người dùng nhấc bình lên, hoặc định kỳ 15–30 phút bằng RTC Timer để kiểm tra chu kỳ nhắc nhở. Khi mang bình ra ngoài, thiết bị ưu tiên sử dụng BLE thay vì Wi-Fi.

**Q3: Đối với bệnh nhân suy tim/suy thận, nếu thiết bị đo sai khiến họ uống quá nhiều thì hậu quả y tế ra sao?**  
*Trả lời:* Hệ thống định vị là thiết bị IoT hỗ trợ theo dõi thói quen, không thay thế y lệnh bác sĩ. Tuy nhiên, về mặt kỹ thuật thuật toán, nhóm đã áp dụng **Biên an toàn kép (Dual Safety Margin)**: cảnh báo vàng sớm tại 80% hạn mức ngày và cảnh báo đỏ tại 90% hạn mức (thay vì đợi chạm 100%). Đồng thời thuật toán Moving Average và cơ chế khóa cân (Hold State) giúp độ chính xác đạt $\pm 5\text{g}$, đảm bảo tính tin cậy cao.

**Q4: Làm sao thiết bị phân biệt được giữa việc uống nước thật với việc nhấc bình lên ngắm hoặc lắc lư khi di chuyển?**  
*Trả lời:* Thuật toán FSM kết hợp đồng thời 2 điều kiện bắt buộc: MPU6050 ghi nhận góc nghiêng bình $> 35^\circ$ duy trì tối thiểu 0.8 giây, và Load Cell ghi nhận độ hụt khối lượng thực tế $\Delta W \ge 25\text{g}$ sau khi bình đã đứng yên ổn định 1.0 giây trên mặt bàn. Nếu chỉ nhấc lên lắc rồi đặt xuống mà $\Delta W < 25\text{g}$, hệ thống hủy chu kỳ và không tính vào tiến độ nạp dịch.

**Q5: Tại sao chọn giao thức MQTT thay vì HTTP POST truyền thống?**  
*Trả lời:* MQTT là giao thức Publish/Subscribe hướng sự kiện với kích thước Header siêu nhẹ (chỉ từ 2 byte so với hàng trăm byte của HTTP Header), giúp tối ưu hóa băng thông mạng và tiết kiệm pin đáng kể cho vi điều khiển. Ngoài ra, MQTT cho phép kết nối hai chiều thời gian thực (Full-duplex): ESP32 vừa gửi Telemetry, vừa có thể nhận lệnh can thiệp phác đồ y tế từ Bác sĩ ngay lập tức mà không cần polling liên tục.

---

## 👥 THÀNH VIÊN & BẢN QUYỀN
- **Đồ án môn học**: Lập Trình Ứng Dụng Internet of Things (IoT)
- **Thiết bị**: ESP32 DevKit V4 - PlatformIO Arduino Framework
- **Phiên bản**: v2.5 Cloud & Haptic Engine Release
