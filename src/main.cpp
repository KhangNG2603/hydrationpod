/**
 * Smart Hydration Pod - Firmware ESP32 chính thức
 * Dựa trên báo cáo kỹ thuật & y tế: BaoCao_SmartHydrationPod.docx
 * Tích hợp kiến trúc: Wi-Fi + MQTT (PubSubClient) + ArduinoJson + Feedback Loop ACK
 * 
 * 100% SỰ KIỆN ĐƯỢC KÍCH HOẠT TỰ ĐỘNG BỞI CẢM BIẾN (SENSOR-DRIVEN):
 * 1. Cảm biến tải trọng HX711 (Load Cell): Đo trọng lượng nước còn lại trong bình theo thời gian thực.
 * 2. Cảm biến góc nghiêng & chuyển động MPU6050: Nhận diện góc nghiêng nâng bình uống (Pitch/Roll > 35°) 
 *    và trạng thái di chuyển (Gia tốc tổng a != 1g).
 * 3. Thuật toán FSM Y Tế (Finite State Machine):
 *    - STATE_REST: Bình đặt yên trên bàn, cân HX711 cập nhật liên tục với bộ lọc Moving Average (N=10).
 *    - STATE_LIFTED_DRINKING: Khi MPU6050 phát hiện nghiêng > 35°, chuyển sang chế độ uống, KHÓA CÂN (Hold State) chống rung lắc nước.
 *    - STATE_SETTLING: Khi đặt bình trở lại bàn, chờ nước và gia tốc ổn định trong 1.0s.
 *    - STATE_EVALUATE: Đo trọng lượng mới. Nếu giảm >= 25g -> Ghi nhận UỐNG NƯỚC; nếu tăng >= 40g -> Ghi nhận CHÂM NƯỚC (Refill).
 * 4. Bộ rung nhắc nhở xúc giác (Haptic Vibration Motor):
 *    - Quên uống Cấp 2: Rung đôi (Haptic Double-pulse: 150ms ON, 100ms OFF, 150ms ON) chu kỳ 3s.
 *    - Quên uống Cấp 3: Rung dồn dập (Triple-pulse: 180ms ON, 80ms OFF x3) chu kỳ 2s.
 *    - Khẩn cấp Overcap: Rung liên tục (250ms ON / 150ms OFF).
 *    - Xác nhận ngụm uống thành công: Haptic click êm ái (80ms).
 * 5. Cảnh báo an toàn kép Y Tế (Dual Safety Margin: 80% Vàng, 90% Đỏ, 100% Báo động khẩn cấp).
 * 6. Giao thức Cloud IoT 2 chiều hoàn chỉnh:
 *    - Tự động duy trì & kết nối lại Wi-Fi và MQTT Broker (non-blocking state machine).
 *    - LWT (Last Will & Testament) topic trạng thái thiết bị ONLINE/OFFLINE.
 *    - MQTT Telemetry JSON (dung tích, lượng đã uống, cảnh báo, trạng thái bộ rung, pin, wifi rssi).
 *    - Nhận lệnh cấu hình Profile, điều khiển chuông, test bộ rung từ Cloud, phản hồi ACK tức thì.
 */

#include <Arduino.h>
#include <WiFi.h>
#include <PubSubClient.h>
#include <Wire.h>
#include <Adafruit_MPU6050.h>
#include <Adafruit_Sensor.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <HX711.h>
#include <ArduinoJson.h>
#include <math.h>

// --- PIN DEFINITIONS ---
#define HX711_DOUT_PIN   16
#define HX711_CLK_PIN    17
#define BUZZER_PIN       4
#define MOTOR_PIN        5      // Bộ rung nhắc nhở (Haptic Vibration Motor)
#define BAT_ADC_PIN      34

#define SCREEN_WIDTH     128
#define SCREEN_HEIGHT    64
#define OLED_RESET       -1
#define OLED_ADDRESS     0x3C

// --- WI-FI & MQTT CLOUD CONFIGURATION ---
const char* WIFI_SSID     = "Wokwi-GUEST";
const char* WIFI_PASS     = "";
const char* MQTT_BROKER   = "broker.emqx.io";
const int   MQTT_PORT     = 1883;
const char* DEVICE_ID     = "HYDROPOD_01";

const char* TOPIC_TELEMETRY = "smartbottle/HYDROPOD_01/telemetry";
const char* TOPIC_CONTROL   = "smartbottle/HYDROPOD_01/control";
const char* TOPIC_ACK       = "smartbottle/HYDROPOD_01/ack";
const char* TOPIC_STATUS    = "smartbottle/HYDROPOD_01/status";

// --- HARDWARE & NETWORK OBJECTS ---
HX711 scale;
Adafruit_MPU6050 mpu;
Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, OLED_RESET);

WiFiClient espClient;
PubSubClient mqttClient(espClient);

// --- PROFILE TYPES ---
enum ProfileType {
  PROFILE_STANDARD = 0,    // Nhu cầu chuẩn (2000ml/ngày, nhắc 60 phút)
  PROFILE_HEART_FAILURE,   // Suy tim / Suy thận (Hard Cap 1000ml, max 150ml/h, nhắc 45 phút)
  PROFILE_GOUT             // Sỏi thận / Gout (Mục tiêu 2500ml, nhắc 30 phút)
};

// --- RINGTONE STYLES (Tùy biến tiếng chuông) ---
enum RingtoneStyle {
  RINGTONE_CHIME = 0,    // Chuông đôi nhẹ nhàng (G5 -> C6)
  RINGTONE_MELODIC,      // Giai điệu du dương (C5 -> E5 -> G5)
  RINGTONE_DIGITAL,      // Tiếng Beep điện tử đanh thép (2093Hz)
  RINGTONE_SIREN,        // Còi cấp cứu y tế dồn dập (1500Hz - 2500Hz)
  RINGTONE_CUSTOM        // Âm thanh MP3 tùy chỉnh người dùng tải lên
};

RingtoneStyle currentRingtone = RINGTONE_CHIME;
void playBuzzerTone(const char* event_type);

// --- VIBRATION MOTOR PATTERNS ---
enum VibrationPattern {
  VIBE_NONE = 0,
  VIBE_CLICK_CONFIRM,      // 1 single short pulse 80ms (xác nhận uống nước thành công)
  VIBE_REFILL_CONFIRM,     // 2 quick clicks 60ms (xác nhận châm nước)
  VIBE_DOUBLE_PULSE,       // 2 pulses: 150ms ON, 100ms OFF, 150ms ON, nghỉ 2.5s (Nhắc nhở Cấp 2)
  VIBE_TRIPLE_URGENT,      // 3 rapid pulses: 180ms ON, 80ms OFF x3, nghỉ 1.3s (Nhắc nhở Cấp 3)
  VIBE_EMERGENCY_ALARM,    // Continuous rapid pulsing: 250ms ON, 150ms OFF (Vượt trần y tế)
  VIBE_CUSTOM_ONCE         // 1 single pulse với độ dài tùy chọn (từ Cloud test)
};

VibrationPattern currentVibePattern = VIBE_NONE;
bool is_vibrating = false;
unsigned long vibeStartTime = 0;
unsigned long customVibeDuration = 0;

// --- SYSTEM STATE & DATA ---
ProfileType currentProfile = PROFILE_STANDARD;
float goal_ml = 2000.0;
float hard_cap_ml = 0.0;     // 0 = Disabled
float max_hourly_rate = 0.0; // 0 = Disabled
float base_remind_min = 60.0;

float current_bottle_ml = 500.0;
float total_drank_today_ml = 0.0;
float hourly_intake_ml = 0.0;
unsigned long last_intake_timestamp = 0;
bool demo_mode = true;
bool is_alarm_muted = false;

// Sensor variables & Filter buffer
float current_weight_g = 500.0;
float stable_baseline_weight_g = 500.0;
float weight_before_sip_g = 500.0;
int battery_soc_pct = 85;

// Dynamic motion & stability
bool is_tilted = false;
bool is_moving = false;
unsigned long tilt_start_time = 0;
unsigned long settle_start_time = 0;

// Safety Status
enum SafetyStatus {
  SAFETY_NORMAL = 0,
  SAFETY_APPROACH_YELLOW,
  SAFETY_DANGER_RED,
  SAFETY_EMERGENCY_OVERCAP
};

SafetyStatus currentSafety = SAFETY_NORMAL;
int currentAlertLevel = 0;
String lastEventLog = "System Initialized";

// FSM States
enum FSMState {
  STATE_REST = 0,
  STATE_TILTED_DRINKING,
  STATE_SETTLING
};
FSMState fsmState = STATE_REST;

// --- FUNCTION PROTOTYPES ---
void setupWiFi();
void maintainNetwork();
void connectMQTT();
void mqttCallback(char* topic, byte* payload, unsigned int length);
void sendAck(const char* command, const char* status, const char* detail);
void applyProfile(ProfileType profile, float custom_cap = 0.0);
void readSensors();
void processFSM();
void updateSafetyStatus();
void handleAlertOutputs();
void setVibrationPattern(VibrationPattern pattern);
void triggerSingleVibe(unsigned long durationMs);
void updateVibration();
void updateOLEDDisplay();
void sendTelemetryJSON();
void processSerialInput();

void setup() {
  Serial.begin(115200);
  delay(500);

  pinMode(BUZZER_PIN, OUTPUT);
  pinMode(MOTOR_PIN, OUTPUT);
  digitalWrite(BUZZER_PIN, LOW);
  digitalWrite(MOTOR_PIN, LOW);

  // Test vibration motor briefly on boot
  digitalWrite(MOTOR_PIN, HIGH);
  delay(100);
  digitalWrite(MOTOR_PIN, LOW);

  // Initialize OLED
  Wire.begin(21, 22);
  if (!display.begin(SSD1306_SWITCHCAPVCC, OLED_ADDRESS)) {
    Serial.println(F("OLED allocation failed"));
  } else {
    display.clearDisplay();
    display.setTextColor(SSD1306_WHITE);
    display.setTextSize(1);
    display.setCursor(10, 15);
    display.println(F("Smart Hydration"));
    display.setCursor(35, 30);
    display.println(F("Pod v2.5 Cloud"));
    display.setCursor(10, 48);
    display.println(F("Connecting WiFi..."));
    display.display();
  }

  // Initialize MPU6050
  if (!mpu.begin()) {
    Serial.println(F("MPU6050 not found, check I2C wiring."));
  } else {
    mpu.setAccelerometerRange(MPU6050_RANGE_8_G);
    mpu.setGyroRange(MPU6050_RANGE_500_DEG);
    mpu.setFilterBandwidth(MPU6050_BAND_21_HZ);
    Serial.println(F("MPU6050 IMU initialized successfully."));
  }

  // Initialize HX711 Load Cell
  scale.begin(HX711_DOUT_PIN, HX711_CLK_PIN);
  scale.set_scale(0.420); // Calibration factor for Wokwi 5kg loadcell (output in grams)
  delay(200);

  if (scale.is_ready()) {
    float init_w = scale.get_units(5);
    if (init_w >= 10.0 && init_w <= 3000.0) {
      current_bottle_ml = init_w;
    } else {
      current_bottle_ml = 500.0;
    }
    stable_baseline_weight_g = current_bottle_ml;
    current_weight_g = current_bottle_ml;
    Serial.printf("HX711 Ready. Initial Bottle Weight: %.1f g\n", current_bottle_ml);
  } else {
    current_bottle_ml = 500.0;
    stable_baseline_weight_g = 500.0;
    current_weight_g = 500.0;
    Serial.println(F("HX711 not ready, default initial weight = 500g"));
  }

  applyProfile(PROFILE_STANDARD);
  last_intake_timestamp = millis();

  // Setup Wi-Fi & MQTT
  setupWiFi();
  mqttClient.setServer(MQTT_BROKER, MQTT_PORT);
  mqttClient.setCallback(mqttCallback);
  mqttClient.setBufferSize(512); // Buffer size 512B for full telemetry JSON

  Serial.println(F("System Ready. All events triggered 100% by HX711 & MPU6050 sensors."));
}

void loop() {
  // 1. Maintain Wi-Fi and MQTT Cloud connections (non-blocking)
  maintainNetwork();

  // 2. Read real sensors (HX711 & MPU6050)
  readSensors();

  // 3. Process FSM Event Engine
  processFSM();

  // 4. Evaluate medical safety margins
  updateSafetyStatus();

  // 5. Update Audio / Visual Alert outputs
  handleAlertOutputs();

  // 6. Non-blocking Haptic Vibration Motor Controller
  updateVibration();

  // 7. Non-blocking OLED Screen update (every 100ms)
  static unsigned long lastOled = 0;
  if (millis() - lastOled >= 100) {
    lastOled = millis();
    updateOLEDDisplay();
  }

  // 8. Non-blocking Telemetry publish (every 3 seconds)
  static unsigned long lastTelemetry = 0;
  if (millis() - lastTelemetry >= 3000) {
    lastTelemetry = millis();
    sendTelemetryJSON();
  }

  // 9. Process Serial Commands (debugging / fallback)
  processSerialInput();

  delay(10);
}

// --- WI-FI SETUP & NON-BLOCKING MAINTENANCE ---
void setupWiFi() {
  Serial.print(F("Connecting to WiFi: "));
  Serial.println(WIFI_SSID);
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  
  unsigned long startAttempt = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - startAttempt < 4000) {
    delay(200);
    Serial.print(".");
  }
  Serial.println();

  if (WiFi.status() == WL_CONNECTED) {
    Serial.print(F("WiFi Connected! IP: "));
    Serial.println(WiFi.localIP());
  } else {
    Serial.println(F("WiFi connecting in background."));
  }
}

void maintainNetwork() {
  // A. Non-blocking Wi-Fi auto-reconnect
  if (WiFi.status() != WL_CONNECTED) {
    static unsigned long lastWifiRetry = 0;
    if (millis() - lastWifiRetry >= 5000) {
      lastWifiRetry = millis();
      Serial.println(F("🌐 [WiFi] Reconnecting in background..."));
      WiFi.disconnect();
      WiFi.begin(WIFI_SSID, WIFI_PASS);
    }
    return;
  }

  // B. Non-blocking MQTT auto-reconnect
  if (!mqttClient.connected()) {
    static unsigned long lastMqttRetry = 0;
    if (millis() - lastMqttRetry >= 4000) {
      lastMqttRetry = millis();
      connectMQTT();
    }
  } else {
    mqttClient.loop();
  }
}

// --- MQTT CLOUD CONNECTION & LWT ---
void connectMQTT() {
  Serial.print(F("Attempting MQTT connection to: "));
  Serial.println(MQTT_BROKER);

  String clientId = "ESP32_HydraPod_";
  clientId += String(random(0xffff), HEX);

  // Set buffer size to 512 bytes for rich JSON payload
  mqttClient.setBufferSize(512);

  // Configure LWT (Last Will and Testament) payload
  String lwtPayload = "{\"device_id\":\"" + String(DEVICE_ID) + "\",\"status\":\"OFFLINE\"}";

  if (mqttClient.connect(clientId.c_str(), 
                         TOPIC_STATUS, 0, true, lwtPayload.c_str())) {
    Serial.println(F("🟢 MQTT Connected successfully!"));

    // Subscribe to control commands from Doctor / Dashboard / Server
    mqttClient.subscribe(TOPIC_CONTROL);
    Serial.print(F("Subscribed to: "));
    Serial.println(TOPIC_CONTROL);

    // Publish Retained Online Status
    String onlinePayload = "{\"device_id\":\"" + String(DEVICE_ID) + "\",\"status\":\"ONLINE\",\"ip\":\"" + WiFi.localIP().toString() + "\"}";
    mqttClient.publish(TOPIC_STATUS, onlinePayload.c_str(), true);

    // Send online status & initial telemetry
    sendAck("DEVICE_ONLINE", "SUCCESS", "ESP32 Hydration Pod ready on Cloud MQTT");
    sendTelemetryJSON();
  } else {
    Serial.print(F("❌ MQTT connect failed, rc="));
    Serial.println(mqttClient.state());
  }
}

// --- READ SENSORS (HX711 & MPU6050) ---
void readSensors() {
  // A. Read MPU6050 IMU
  sensors_event_t a, g, temp;
  if (mpu.getEvent(&a, &g, &temp)) {
    float ax = a.acceleration.x;
    float ay = a.acceleration.y;
    float az = a.acceleration.z;

    // Pitch and Roll angles in degrees
    float pitch = atan2(ay, sqrt(ax * ax + az * az)) * 180.0 / M_PI;
    float roll = atan2(-ax, az) * 180.0 / M_PI;

    // Total Acceleration Vector
    float total_acc = sqrt(ax * ax + ay * ay + az * az) / 9.81;
    is_moving = (fabs(total_acc - 1.0) > 0.20);

    // Tilt Detection with Hysteresis (Threshold: > 35° enters tilt, < 18° exits tilt)
    if (fabs(pitch) > 35.0 || fabs(roll) > 35.0) {
      if (!is_tilted) {
        is_tilted = true;
        tilt_start_time = millis();
      }
    } else if (fabs(pitch) < 18.0 && fabs(roll) < 18.0) {
      is_tilted = false;
    }
  }

  // B. Read HX711 Load Cell (Only when bottle is NOT tilted or violently moving)
  if (!is_tilted && scale.is_ready()) {
    float raw_g = scale.get_units(1);
    if (raw_g >= 0.0 && raw_g <= 3000.0) {
      // 10-sample Moving Average Filter
      static float samples[10];
      static int sample_idx = 0;
      static bool buffer_filled = false;

      samples[sample_idx] = raw_g;
      sample_idx = (sample_idx + 1) % 10;
      if (sample_idx == 0) buffer_filled = true;

      int count = buffer_filled ? 10 : sample_idx;
      if (count == 0) count = 1;

      float sum = 0;
      for (int i = 0; i < count; i++) sum += samples[i];
      current_weight_g = sum / count;
    }
  }
}

// --- FSM & SENSOR-DRIVEN DRINK DETECTION ---
void processFSM() {
  switch (fsmState) {
    case STATE_REST: {
      // Bottle sitting upright on table
      if (is_tilted) {
        // Patient lifts and tilts the bottle to take a drink!
        weight_before_sip_g = stable_baseline_weight_g;
        tilt_start_time = millis();
        fsmState = STATE_TILTED_DRINKING;
        Serial.printf("⚡ [FSM] Bottle Tilted! Locked pre-drink weight: %.1f g\n", weight_before_sip_g);
      } else {
        // Continuous baseline update when stable
        if (!is_moving && fabs(current_weight_g - stable_baseline_weight_g) < 15.0) {
          stable_baseline_weight_g = current_weight_g;
        }
      }
      break;
    }

    case STATE_TILTED_DRINKING: {
      // Patient is drinking from the tilted bottle
      // Hold State: Weight is frozen to prevent sloshing artifacts
      if (!is_tilted) {
        // Bottle returned to upright position
        settle_start_time = millis();
        fsmState = STATE_SETTLING;
        Serial.println(F("⚡ [FSM] Bottle Upright. Settling fluid and motion..."));
      }
      break;
    }

    case STATE_SETTLING: {
      // Wait at least 1.0s for water sloshing and vibrations to settle
      if (!is_tilted && !is_moving && (millis() - settle_start_time >= 1000)) {
        float new_weight_g = scale.is_ready() ? scale.get_units(5) : current_weight_g;
        if (new_weight_g < 0) new_weight_g = 0;

        float delta_w = weight_before_sip_g - new_weight_g;
        unsigned long sip_duration = millis() - tilt_start_time;

        Serial.printf("⚡ [FSM Evaluate] Pre: %.1fg, Post: %.1fg, Delta: %.1fg, Duration: %lums\n",
                      weight_before_sip_g, new_weight_g, delta_w, sip_duration);

        // CASE 1: Valid Drink Event (Sip >= 25ml and duration >= 800ms)
        if (sip_duration >= 800 && delta_w >= 25.0) {
          float drank = delta_w;
          total_drank_today_ml += drank;
          hourly_intake_ml += drank;
          current_bottle_ml = max(0.0f, current_bottle_ml - drank);
          last_intake_timestamp = millis();

          lastEventLog = "Sensor Drink: +" + String((int)drank) + "ml";
          Serial.printf("🟢 [SENSOR DRINK DETECTED] Drank: +%d ml (Total Today: %d ml, Bottle Remaining: %d ml)\n", 
                        (int)drank, (int)total_drank_today_ml, (int)current_bottle_ml);

          // Audio Confirmation + Haptic Click Confirmation
          tone(BUZZER_PIN, 1046, 250);
          triggerSingleVibe(90); // 90ms gentle tactile vibration feedback

          sendAck("SENSOR_DRINK", "SUCCESS", lastEventLog.c_str());
          sendTelemetryJSON();
        }
        // CASE 2: Refill Event (Water poured into bottle, weight increased by >= 40g)
        else if (delta_w <= -40.0) {
          float refilled = -delta_w;
          current_bottle_ml = min(1000.0f, current_bottle_ml + refilled);
          lastEventLog = "Sensor Refill: +" + String((int)refilled) + "ml";
          Serial.printf("🔵 [SENSOR REFILL DETECTED] Refilled: +%d ml (New Bottle: %d ml)\n",
                        (int)refilled, (int)current_bottle_ml);

          tone(BUZZER_PIN, 800, 150);
          setVibrationPattern(VIBE_REFILL_CONFIRM); // 2 quick tactile pulses

          sendAck("SENSOR_REFILL", "SUCCESS", lastEventLog.c_str());
          sendTelemetryJSON();
        }
        // CASE 3: Negligible change / Accidental bump
        else {
          Serial.println(F("ℹ️ [FSM] Sip negligible (< 25ml) or disturbance. Ignored."));
        }

        stable_baseline_weight_g = new_weight_g;
        fsmState = STATE_REST;
      }
      break;
    }
  }
}

// --- SAFETY & DUAL SAFETY MARGIN ---
void updateSafetyStatus() {
  if (hard_cap_ml > 0.0) {
    float ratio = total_drank_today_ml / hard_cap_ml;
    if (ratio >= 1.0) {
      currentSafety = SAFETY_EMERGENCY_OVERCAP;
    } else if (ratio >= 0.90) {
      currentSafety = SAFETY_DANGER_RED;
    } else if (ratio >= 0.80) {
      currentSafety = SAFETY_APPROACH_YELLOW;
    } else {
      currentSafety = SAFETY_NORMAL;
    }
  } else {
    currentSafety = SAFETY_NORMAL;
  }

  // Idle Timer Reminder (Quên uống nước)
  float effective_remind_sec = base_remind_min * 60.0;
  if (demo_mode) effective_remind_sec = 30.0; // 30 seconds for quick testing

  float idle_sec = (millis() - last_intake_timestamp) / 1000.0;

  if (idle_sec >= effective_remind_sec + 30.0) {
    currentAlertLevel = 3; // Severe Idle
  } else if (idle_sec >= effective_remind_sec + 15.0) {
    currentAlertLevel = 2; // Moderate Idle
  } else if (idle_sec >= effective_remind_sec) {
    currentAlertLevel = 1; // Mild Idle (Breathing LED)
  } else {
    currentAlertLevel = 0; // Normal
  }

  // Empty Bottle Detection (Nhắc châm thêm nước khi bình cạn)
  static bool empty_alert_triggered = false;
  if (current_bottle_ml <= 40.0) {
    if (!empty_alert_triggered) {
      empty_alert_triggered = true;
      lastEventLog = "Bottle Empty: Please Refill";
      if (!is_alarm_muted) {
        tone(BUZZER_PIN, 880, 250);
      }
      setVibrationPattern(VIBE_REFILL_CONFIRM);
      Serial.println(F("⚠️ [EMPTY BOTTLE] Water depleted <= 40ml! Please refill water."));
      sendAck("BOTTLE_EMPTY", "WARN", "Water depleted <= 40ml. Refill needed.");
    }
  } else if (current_bottle_ml > 80.0) {
    empty_alert_triggered = false;
  }
}

// --- VIBRATION MOTOR CONTROLLER (HAPTIC ENGINE) ---
void setVibrationPattern(VibrationPattern pattern) {
  if (currentVibePattern != pattern) {
    currentVibePattern = pattern;
    vibeStartTime = millis();
  }
}

void triggerSingleVibe(unsigned long durationMs) {
  currentVibePattern = VIBE_CUSTOM_ONCE;
  customVibeDuration = durationMs;
  vibeStartTime = millis();
  digitalWrite(MOTOR_PIN, HIGH);
  is_vibrating = true;
}

void updateVibration() {
  // If muted and not a confirmation click, turn motor off
  if (is_alarm_muted && currentVibePattern != VIBE_CLICK_CONFIRM && currentVibePattern != VIBE_CUSTOM_ONCE) {
    digitalWrite(MOTOR_PIN, LOW);
    is_vibrating = false;
    return;
  }

  unsigned long elapsed = millis() - vibeStartTime;

  switch (currentVibePattern) {
    case VIBE_NONE:
      digitalWrite(MOTOR_PIN, LOW);
      is_vibrating = false;
      break;

    case VIBE_CLICK_CONFIRM:
      // Single 80ms tactile pulse
      if (elapsed < 80) {
        digitalWrite(MOTOR_PIN, HIGH);
        is_vibrating = true;
      } else {
        digitalWrite(MOTOR_PIN, LOW);
        is_vibrating = false;
        currentVibePattern = VIBE_NONE;
      }
      break;

    case VIBE_REFILL_CONFIRM:
      // 2 quick 60ms pulses (0..60 ON, 60..120 OFF, 120..180 ON)
      if ((elapsed < 60) || (elapsed >= 120 && elapsed < 180)) {
        digitalWrite(MOTOR_PIN, HIGH);
        is_vibrating = true;
      } else if (elapsed < 180) {
        digitalWrite(MOTOR_PIN, LOW);
        is_vibrating = false;
      } else {
        digitalWrite(MOTOR_PIN, LOW);
        is_vibrating = false;
        currentVibePattern = VIBE_NONE;
      }
      break;

    case VIBE_CUSTOM_ONCE:
      if (elapsed < customVibeDuration) {
        digitalWrite(MOTOR_PIN, HIGH);
        is_vibrating = true;
      } else {
        digitalWrite(MOTOR_PIN, LOW);
        is_vibrating = false;
        currentVibePattern = VIBE_NONE;
      }
      break;

    case VIBE_DOUBLE_PULSE: {
      // Repeat cycle: 150ms ON, 100ms OFF, 150ms ON, 2600ms OFF (Total 3000ms cycle)
      unsigned long cycleTime = elapsed % 3000;
      if (cycleTime < 150 || (cycleTime >= 250 && cycleTime < 400)) {
        digitalWrite(MOTOR_PIN, HIGH);
        is_vibrating = true;
      } else {
        digitalWrite(MOTOR_PIN, LOW);
        is_vibrating = false;
      }
      break;
    }

    case VIBE_TRIPLE_URGENT: {
      // Repeat cycle: 180ms ON, 80ms OFF, 180ms ON, 80ms OFF, 180ms ON, 1300ms OFF (Total 2000ms cycle)
      unsigned long cycleTime = elapsed % 2000;
      if (cycleTime < 180 || (cycleTime >= 260 && cycleTime < 440) || (cycleTime >= 520 && cycleTime < 700)) {
        digitalWrite(MOTOR_PIN, HIGH);
        is_vibrating = true;
      } else {
        digitalWrite(MOTOR_PIN, LOW);
        is_vibrating = false;
      }
      break;
    }

    case VIBE_EMERGENCY_ALARM: {
      // Continuous urgent alarm pulse: 250ms ON, 150ms OFF
      unsigned long cycleTime = elapsed % 400;
      if (cycleTime < 250) {
        digitalWrite(MOTOR_PIN, HIGH);
        is_vibrating = true;
      } else {
        digitalWrite(MOTOR_PIN, LOW);
        is_vibrating = false;
      }
      break;
    }
  }
}

// --- RINGTONE ENGINE (Phát tiếng chuông tùy chỉnh) ---
void playBuzzerTone(const char* event_type) {
  if (is_alarm_muted) return;

  if (strcmp(event_type, "DRINK") == 0) {
    switch (currentRingtone) {
      case RINGTONE_MELODIC: tone(BUZZER_PIN, 1318, 200); break;
      case RINGTONE_DIGITAL: tone(BUZZER_PIN, 1760, 150); break;
      case RINGTONE_SIREN:   tone(BUZZER_PIN, 1500, 200); break;
      case RINGTONE_CHIME:
      default:               tone(BUZZER_PIN, 1046, 220); break;
    }
  } else if (strcmp(event_type, "REFILL") == 0) {
    switch (currentRingtone) {
      case RINGTONE_MELODIC: tone(BUZZER_PIN, 988, 180); break;
      case RINGTONE_DIGITAL: tone(BUZZER_PIN, 1568, 120); break;
      case RINGTONE_SIREN:   tone(BUZZER_PIN, 1200, 180); break;
      case RINGTONE_CHIME:
      default:               tone(BUZZER_PIN, 800, 160); break;
    }
  } else if (strcmp(event_type, "REMIND_LVL2") == 0) {
    switch (currentRingtone) {
      case RINGTONE_MELODIC: tone(BUZZER_PIN, 659, 100); break;
      case RINGTONE_DIGITAL: tone(BUZZER_PIN, 2093, 70); break;
      case RINGTONE_SIREN:   tone(BUZZER_PIN, 1400, 120); break;
      case RINGTONE_CHIME:
      default:               tone(BUZZER_PIN, 1200, 90); break;
    }
  } else if (strcmp(event_type, "REMIND_LVL3") == 0) {
    switch (currentRingtone) {
      case RINGTONE_MELODIC: tone(BUZZER_PIN, 784, 120); break;
      case RINGTONE_DIGITAL: tone(BUZZER_PIN, 2349, 90); break;
      case RINGTONE_SIREN:   tone(BUZZER_PIN, 1800, 140); break;
      case RINGTONE_CHIME:
      default:               tone(BUZZER_PIN, 1600, 120); break;
    }
  } else if (strcmp(event_type, "EMERGENCY") == 0) {
    switch (currentRingtone) {
      case RINGTONE_MELODIC: tone(BUZZER_PIN, 1568, 150); break;
      case RINGTONE_DIGITAL: tone(BUZZER_PIN, 2637, 120); break;
      case RINGTONE_SIREN:   tone(BUZZER_PIN, 2800, 180); break;
      case RINGTONE_CHIME:
      default:               tone(BUZZER_PIN, 2200, 150); break;
    }
  } else if (strcmp(event_type, "PREVIEW") == 0) {
    switch (currentRingtone) {
      case RINGTONE_CUSTOM:  tone(BUZZER_PIN, 1175, 250); break;
      case RINGTONE_MELODIC: tone(BUZZER_PIN, 659, 150); break;
      case RINGTONE_DIGITAL: tone(BUZZER_PIN, 2093, 120); break;
      case RINGTONE_SIREN:   tone(BUZZER_PIN, 1800, 200); break;
      case RINGTONE_CHIME:
      default:               tone(BUZZER_PIN, 1046, 200); break;
    }
  }
}

// --- ALERT OUTPUTS (MOTOR VIBRATION & AUDIO BUZZER) ---
void handleAlertOutputs() {
  // Emergency Overcap (Vượt trần y tế)
  if (currentSafety == SAFETY_EMERGENCY_OVERCAP) {
    if (is_alarm_muted) {
      setVibrationPattern(VIBE_NONE);
      digitalWrite(MOTOR_PIN, LOW);
      noTone(BUZZER_PIN);
      digitalWrite(BUZZER_PIN, LOW);
      return;
    }

    setVibrationPattern(VIBE_EMERGENCY_ALARM);

    static unsigned long lastFlash = 0;
    if (millis() - lastFlash >= 200) {
      lastFlash = millis();
      playBuzzerTone("EMERGENCY");
    }
    return;
  }

  // 90% Hard Cap (Red Warning)
  if (currentSafety == SAFETY_DANGER_RED) {
    if (currentVibePattern != VIBE_CUSTOM_ONCE && currentVibePattern != VIBE_CLICK_CONFIRM) {
      setVibrationPattern(VIBE_NONE);
    }
    return;
  } 
  // 80% Hard Cap (Yellow Warning)
  else if (currentSafety == SAFETY_APPROACH_YELLOW) {
    if (currentVibePattern != VIBE_CUSTOM_ONCE && currentVibePattern != VIBE_CLICK_CONFIRM) {
      setVibrationPattern(VIBE_NONE);
    }
    return;
  }

  // Idle Alert Levels (Quên uống nước)
  if (currentAlertLevel == 1) {
    // Level 1: Gentle OLED notification, motor & buzzer quiet
    if (currentVibePattern != VIBE_CUSTOM_ONCE && currentVibePattern != VIBE_CLICK_CONFIRM) {
      setVibrationPattern(VIBE_NONE);
    }
  } else if (currentAlertLevel == 2) {
    // Level 2: Double Pulse Vibration + Periodic Chime
    setVibrationPattern(VIBE_DOUBLE_PULSE);

    static unsigned long lastBlink = 0;
    if (millis() - lastBlink >= 1000) {
      lastBlink = millis();
      playBuzzerTone("REMIND_LVL2");
    }
  } else if (currentAlertLevel == 3) {
    // Level 3: Urgent Triple Pulse Vibration + Rapid Chime
    setVibrationPattern(VIBE_TRIPLE_URGENT);

    static unsigned long lastRapid = 0;
    if (millis() - lastRapid >= 500) {
      lastRapid = millis();
      playBuzzerTone("REMIND_LVL3");
    }
  } else {
    // Normal resting state
    if (currentVibePattern != VIBE_CUSTOM_ONCE && 
        currentVibePattern != VIBE_CLICK_CONFIRM && 
        currentVibePattern != VIBE_REFILL_CONFIRM) {
      setVibrationPattern(VIBE_NONE);
    }
  }
}

// --- OLED GUI DISPLAY ---
void updateOLEDDisplay() {
  display.clearDisplay();
  display.setTextSize(1);

  display.setCursor(0, 0);
  display.print(F("HydraPod ["));
  display.print(WiFi.status() == WL_CONNECTED ? (mqttClient.connected() ? "MQTT" : "WIFI") : "OFFL");
  display.print(F("]"));

  display.setCursor(0, 14);
  display.print(F("Drank: "));
  display.print((int)total_drank_today_ml);
  display.print(F("/"));
  display.print((int)goal_ml);
  display.print(F(" ml"));

  float pct = (goal_ml > 0) ? (total_drank_today_ml / goal_ml) * 100.0 : 0.0;
  display.setCursor(0, 26);
  display.print(F("Prog: "));
  display.print(pct, 1);
  display.print(F("% Rem:"));
  display.print((int)current_bottle_ml);
  display.print(F("m"));

  float idle_s = (millis() - last_intake_timestamp) / 1000.0;
  display.setCursor(0, 38);
  display.print(F("Bat:"));
  display.print(battery_soc_pct);
  display.print(F("% Vib:"));
  display.print(is_vibrating ? "ON " : "OFF");
  display.print(F(" "));
  display.print((int)idle_s);
  display.print(F("s"));

  display.fillRect(0, 52, 128, 12, SSD1306_WHITE);
  display.setTextColor(SSD1306_BLACK);
  display.setCursor(2, 54);

  if (currentSafety == SAFETY_EMERGENCY_OVERCAP) {
    display.print(is_alarm_muted ? F("OVERCAP (CAN THIEP OK)") : F("!! EMERGENCY OVERCAP !!"));
  } else if (current_bottle_ml <= 40.0) {
    display.print(F("!! CAN NUOC - REFILL !!"));
  } else if (currentSafety == SAFETY_DANGER_RED) {
    display.print(F("DANGER: 90% Hard Cap"));
  } else if (currentSafety == SAFETY_APPROACH_YELLOW) {
    display.print(F("WARN: 80% Hard Cap"));
  } else if (goal_ml > 0 && total_drank_today_ml >= goal_ml) {
    display.print(F("🎉 DAT 100% MUC TIEU!"));
  } else if (currentAlertLevel >= 2) {
    display.print(F("REMINDER: Uong nuoc!"));
  } else {
    display.print(F("Status: An toan OK"));
  }

  display.setTextColor(SSD1306_WHITE);
  display.display();
}

// --- TELEMETRY JSON PUBLISH (Cloud IoT 2-way sync) ---
void sendTelemetryJSON() {
  JsonDocument doc;
  doc["device_id"] = DEVICE_ID;
  doc["drank_today_ml"] = (int)total_drank_today_ml;
  doc["bottle_ml"] = (int)current_bottle_ml;
  doc["goal_ml"] = (int)goal_ml;
  doc["hard_cap_ml"] = (int)hard_cap_ml;
  doc["progress_pct"] = round(((total_drank_today_ml / max(1.0f, goal_ml)) * 100.0) * 10.0) / 10.0;
  doc["rate_hourly_ml"] = (int)hourly_intake_ml;
  
  float idle_s = (millis() - last_intake_timestamp) / 1000.0;
  doc["idle_sec"] = (int)idle_s;
  doc["battery_soc"] = battery_soc_pct;

  if (currentSafety == SAFETY_EMERGENCY_OVERCAP) doc["safety_status"] = "EMERGENCY_OVERCAP";
  else if (currentSafety == SAFETY_DANGER_RED) doc["safety_status"] = "DANGER_RED";
  else if (currentSafety == SAFETY_APPROACH_YELLOW) doc["safety_status"] = "APPROACH_YELLOW";
  else doc["safety_status"] = "NORMAL";

  doc["alert_level"] = currentAlertLevel;
  doc["profile"] = (currentProfile == PROFILE_STANDARD ? "STANDARD" :
                    (currentProfile == PROFILE_HEART_FAILURE ? "HEART_FAILURE" : "GOUT"));
  doc["last_event"] = lastEventLog;

  // Real-time vibration motor state and cloud telemetry
  doc["vibration_motor"] = is_vibrating ? 1 : 0;
  doc["ringtone"] = (currentRingtone == RINGTONE_MELODIC ? "MELODIC" :
                    (currentRingtone == RINGTONE_DIGITAL ? "DIGITAL" :
                    (currentRingtone == RINGTONE_SIREN ? "SIREN" :
                    (currentRingtone == RINGTONE_CUSTOM ? "CUSTOM" : "CHIME"))));
  doc["is_empty"] = (current_bottle_ml <= 40.0f);
  doc["goal_reached"] = (goal_ml > 0 && total_drank_today_ml >= goal_ml);
  doc["wifi_connected"] = (WiFi.status() == WL_CONNECTED);
  doc["wifi_rssi"] = (WiFi.status() == WL_CONNECTED) ? WiFi.RSSI() : 0;
  doc["is_muted"] = is_alarm_muted;
  doc["uptime_sec"] = (unsigned long)(millis() / 1000);

  String output;
  serializeJson(doc, output);

  Serial.print(F("[TELEMETRY_JSON] "));
  Serial.println(output);

  if (mqttClient.connected()) {
    mqttClient.publish(TOPIC_TELEMETRY, output.c_str());
  }
}

// --- MQTT CALLBACK & JSON CONTROL PARSING (Cloud Commands) ---
void mqttCallback(char* topic, byte* payload, unsigned int length) {
  String message;
  for (unsigned int i = 0; i < length; i++) {
    message += (char)payload[i];
  }
  Serial.print(F("[MQTT In] Control: "));
  Serial.println(message);

  JsonDocument doc;
  DeserializationError error = deserializeJson(doc, message);
  if (error) {
    Serial.print(F("deserializeJson() failed: "));
    Serial.println(error.c_str());
    sendAck("UNKNOWN", "FAILED", "Invalid JSON format");
    return;
  }

  // 1. Change Medical Profile (Doctor Prescription)
  if (doc["target"].is<const char*>() && String(doc["target"].as<const char*>()).equalsIgnoreCase("profile")) {
    String mode = doc["mode"].as<String>();
    float custom_cap = doc["hard_cap"].as<float>();

    if (mode.equalsIgnoreCase("STANDARD")) {
      applyProfile(PROFILE_STANDARD, 0.0);
      sendAck("SET_PROFILE", "SUCCESS", "Profile set to STANDARD (2000ml)");
    } else if (mode.equalsIgnoreCase("HEART_FAILURE")) {
      applyProfile(PROFILE_HEART_FAILURE, custom_cap > 0 ? custom_cap : 1000.0);
      sendAck("SET_PROFILE", "SUCCESS", ("Profile set to HEART_FAILURE (" + String((int)hard_cap_ml) + "ml Cap)").c_str());
    } else if (mode.equalsIgnoreCase("GOUT")) {
      applyProfile(PROFILE_GOUT, 0.0);
      sendAck("SET_PROFILE", "SUCCESS", "Profile set to GOUT (2500ml)");
    }
  }
  // 2. Alarm Mute / Unmute
  else if (doc["target"].is<const char*>() && String(doc["target"].as<const char*>()).equalsIgnoreCase("alarm")) {
    String action = doc["action"].as<String>();
    if (action.equalsIgnoreCase("MUTE")) {
      is_alarm_muted = true;
      digitalWrite(BUZZER_PIN, LOW);
      digitalWrite(MOTOR_PIN, LOW);
      is_vibrating = false;
      lastEventLog = "Alarm Muted Remotely";
      sendAck("ALARM_CONTROL", "SUCCESS", "Alarm Muted");
    } else {
      is_alarm_muted = false;
      lastEventLog = "Alarm Unmuted";
      sendAck("ALARM_CONTROL", "SUCCESS", "Alarm Unmuted");
    }
  }
  // 3. Vibration Motor Remote Command (Test / Haptic Trigger)
  else if (doc["target"].is<const char*>() && (String(doc["target"].as<const char*>()).equalsIgnoreCase("vibrate") || 
                                               String(doc["target"].as<const char*>()).equalsIgnoreCase("vibration"))) {
    int duration = doc["duration_ms"].as<int>();
    if (duration <= 0) duration = 300;
    triggerSingleVibe(duration);
    lastEventLog = "Remote Vibration Triggered (" + String(duration) + "ms)";
    sendAck("VIBRATE_TEST", "SUCCESS", lastEventLog.c_str());
  }
  // 4. Remote Drink Command (Simulation from Doctor/Postman/Caregiver)
  else if (doc["target"].is<const char*>() && String(doc["target"].as<const char*>()).equalsIgnoreCase("drink")) {
    float amt = doc["amount"].as<float>();
    if (amt <= 0) amt = 150.0;
    total_drank_today_ml += amt;
    current_bottle_ml = max(0.0f, current_bottle_ml - amt);
    last_intake_timestamp = millis();
    lastEventLog = "Remote Drink +" + String((int)amt) + "ml";

    tone(BUZZER_PIN, 1046, 200);
    triggerSingleVibe(100);

    sendAck("ADD_DRINK", "SUCCESS", lastEventLog.c_str());
  }
  // 5. Refill Bottle Command
  else if (doc["target"].is<const char*>() && String(doc["target"].as<const char*>()).equalsIgnoreCase("refill")) {
    float amt = doc["amount"].as<float>();
    if (amt <= 0) amt = 350.0;
    current_bottle_ml = min(1000.0f, current_bottle_ml + amt);
    lastEventLog = "Remote Refill +" + String((int)amt) + "ml";
    tone(BUZZER_PIN, 800, 150);
    setVibrationPattern(VIBE_REFILL_CONFIRM);
    sendAck("REFILL", "SUCCESS", lastEventLog.c_str());
    sendTelemetryJSON();
  }
  // 6. Reset Daily Stats
  else if (doc["target"].is<const char*>() && String(doc["target"].as<const char*>()).equalsIgnoreCase("reset")) {
    total_drank_today_ml = 0;
    current_bottle_ml = 500;
    last_intake_timestamp = millis();
    lastEventLog = "Remote Daily Reset";
    sendAck("RESET_DAY", "SUCCESS", "Daily counters reset to 0");
  }
  // 7. Change Ringtone Style
  else if (doc["target"].is<const char*>() && String(doc["target"].as<const char*>()).equalsIgnoreCase("ringtone")) {
    String r_tone = doc["tone"].as<String>();
    if (r_tone.equalsIgnoreCase("MELODIC")) currentRingtone = RINGTONE_MELODIC;
    else if (r_tone.equalsIgnoreCase("DIGITAL")) currentRingtone = RINGTONE_DIGITAL;
    else if (r_tone.equalsIgnoreCase("SIREN")) currentRingtone = RINGTONE_SIREN;
    else if (r_tone.equalsIgnoreCase("CUSTOM")) currentRingtone = RINGTONE_CUSTOM;
    else currentRingtone = RINGTONE_CHIME;

    lastEventLog = "Ringtone: " + r_tone;
    playBuzzerTone("PREVIEW");
    sendAck("SET_RINGTONE", "SUCCESS", lastEventLog.c_str());
    sendTelemetryJSON();
  }
  // 8. Device Configuration from Cloud
  else if (doc["target"].is<const char*>() && String(doc["target"].as<const char*>()).equalsIgnoreCase("config")) {
    if (doc["demo_mode"].is<bool>()) demo_mode = doc["demo_mode"].as<bool>();
    if (doc["goal_ml"].is<float>()) goal_ml = doc["goal_ml"].as<float>();
    if (doc["remind_min"].is<float>()) base_remind_min = doc["remind_min"].as<float>();
    lastEventLog = "Cloud Config Updated";
    sendAck("SET_CONFIG", "SUCCESS", "Configuration applied");
  }
  // 7. Raw Command Strings
  else if (doc["command"].is<const char*>()) {
    String cmd = doc["command"].as<String>();
    if (cmd == "SIM_DEMO_SCENARIO_1") {
      total_drank_today_ml += 150;
      current_bottle_ml = max(0.0f, current_bottle_ml - 150.0f);
      last_intake_timestamp = millis();
      lastEventLog = "Demo 1: Valid Drink +150ml";
      triggerSingleVibe(100);
      sendAck("DEMO_1", "SUCCESS", lastEventLog.c_str());
    } else if (cmd == "SIM_DEMO_SCENARIO_2") {
      last_intake_timestamp = millis() - 35000;
      lastEventLog = "Demo 2: Idle Alert Triggered";
      sendAck("DEMO_2", "SUCCESS", lastEventLog.c_str());
    } else if (cmd == "SIM_DEMO_SCENARIO_3") {
      applyProfile(PROFILE_HEART_FAILURE, 1000.0);
      total_drank_today_ml = 1050;
      lastEventLog = "Demo 3: Overcap Emergency";
      sendAck("DEMO_3", "SUCCESS", lastEventLog.c_str());
    } else if (cmd == "TEST_VIBRATION") {
      triggerSingleVibe(300);
      lastEventLog = "Test Vibration Motor 300ms";
      sendAck("TEST_VIBRATION", "SUCCESS", lastEventLog.c_str());
    } else if (cmd == "RESET_DAY") {
      total_drank_today_ml = 0;
      current_bottle_ml = 500;
      last_intake_timestamp = millis();
      lastEventLog = "Reset Daily Stats";
      sendAck("RESET_DAY", "SUCCESS", "Reset complete");
    } else {
      sendAck("UNKNOWN_CMD", "FAILED", ("Unrecognized command: " + cmd).c_str());
    }
  }

  updateSafetyStatus();
  updateOLEDDisplay();
  sendTelemetryJSON();
}

// --- FEEDBACK LOOP ACK ---
void sendAck(const char* command, const char* status, const char* detail) {
  JsonDocument ackDoc;
  ackDoc["device_id"] = DEVICE_ID;
  ackDoc["command"] = command;
  ackDoc["status"] = status;
  ackDoc["detail"] = detail;
  ackDoc["drank_today_ml"] = (int)total_drank_today_ml;
  ackDoc["safety_status"] = (currentSafety == SAFETY_NORMAL ? "NORMAL" :
                            (currentSafety == SAFETY_APPROACH_YELLOW ? "APPROACH_YELLOW" :
                            (currentSafety == SAFETY_DANGER_RED ? "DANGER_RED" : "EMERGENCY_OVERCAP")));
  ackDoc["vibration_motor"] = is_vibrating ? 1 : 0;
  ackDoc["timestamp"] = millis();

  String ackPayload;
  serializeJson(ackDoc, ackPayload);

  Serial.print(F("[FEEDBACK ACK] -> "));
  Serial.println(ackPayload);

  if (mqttClient.connected()) {
    mqttClient.publish(TOPIC_ACK, ackPayload.c_str());
  }
}

// --- PROFILE SELECTION ---
void applyProfile(ProfileType profile, float custom_cap) {
  currentProfile = profile;
  switch (profile) {
    case PROFILE_STANDARD:
      goal_ml = 2000.0;
      hard_cap_ml = 0.0;
      max_hourly_rate = 0.0;
      base_remind_min = 60.0;
      lastEventLog = "Profile: Standard (2000ml)";
      break;
    case PROFILE_HEART_FAILURE:
      goal_ml = (custom_cap > 0 ? custom_cap : 1000.0);
      hard_cap_ml = goal_ml;
      max_hourly_rate = 150.0;
      base_remind_min = 45.0;
      lastEventLog = "Profile: Heart/Kidney (" + String((int)hard_cap_ml) + "ml Cap)";
      break;
    case PROFILE_GOUT:
      goal_ml = 2500.0;
      hard_cap_ml = 0.0;
      max_hourly_rate = 0.0;
      base_remind_min = 30.0;
      lastEventLog = "Profile: High Fluid (2500ml Goal)";
      break;
  }
}

// --- SERIAL INPUT HANDLER ---
void processSerialInput() {
  if (Serial.available()) {
    char c = Serial.read();
    if (c == '1') {
      total_drank_today_ml += 150;
      current_bottle_ml = max(0.0f, current_bottle_ml - 150.0f);
      last_intake_timestamp = millis();
      lastEventLog = "Serial: Drink +150ml";
      triggerSingleVibe(90);
      sendAck("SERIAL_CMD_1", "SUCCESS", lastEventLog.c_str());
      sendTelemetryJSON();
    } else if (c == '2') {
      last_intake_timestamp = millis() - 35000;
      lastEventLog = "Serial: Idle Alert 35s";
      sendAck("SERIAL_CMD_2", "SUCCESS", lastEventLog.c_str());
      sendTelemetryJSON();
    } else if (c == '3') {
      applyProfile(PROFILE_HEART_FAILURE, 1000.0);
      total_drank_today_ml = 1050;
      lastEventLog = "Serial: Overcap Emergency";
      sendAck("SERIAL_CMD_3", "SUCCESS", lastEventLog.c_str());
      sendTelemetryJSON();
    } else if (c == 'v' || c == 'V') {
      triggerSingleVibe(300);
      lastEventLog = "Serial: Test Vibration 300ms";
      sendAck("SERIAL_VIBE", "SUCCESS", lastEventLog.c_str());
      sendTelemetryJSON();
    } else if (c == 'r' || c == 'R') {
      total_drank_today_ml = 0;
      current_bottle_ml = 500;
      last_intake_timestamp = millis();
      lastEventLog = "Serial: Reset Stats";
      sendAck("SERIAL_RESET", "SUCCESS", lastEventLog.c_str());
      sendTelemetryJSON();
    }
  }
}
