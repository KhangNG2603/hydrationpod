#!/usr/bin/env python3
"""
Smart Hydration Pod - Postman-Friendly HTTP REST API & MQTT Bridge Server
- Connects to EMQX Public MQTT Broker (broker.emqx.io:1883)
- Subscribes to ESP32 Telemetry & ACK topics
- Forwards HTTP POST commands from Postman/cURL directly to MQTT control topic
- Synchronizes Web Dashboard in real time via Server-Sent Events (SSE)
"""

import http.server
import socketserver
import socket
import json
import time
import os
import threading
import sys
import base64
import sqlite3
import ssl
from collections import defaultdict

# Try importing paho.mqtt.client
try:
    import paho.mqtt.client as mqtt
    MQTT_AVAILABLE = True
except ImportError:
    MQTT_AVAILABLE = False
    print("⚠️ paho-mqtt not installed. MQTT bridging disabled.")

PORT = int(os.environ.get("PORT", 8000))
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DIRECTORY = os.path.join(BASE_DIR, 'dashboard')
DB_PATH = os.path.join(BASE_DIR, 'hydrationpod.db')

MQTT_BROKER = os.environ.get("MQTT_BROKER", "broker.emqx.io")
MQTT_PORT = int(os.environ.get("MQTT_PORT", 1883))
MQTT_USE_TLS = os.environ.get("MQTT_USE_TLS", "0") == "1"
MQTT_CA_CERT = os.environ.get("MQTT_CA_CERT", os.path.join(BASE_DIR, "security/certs/ca.crt"))
MQTT_USERNAME = os.environ.get("MQTT_USERNAME", "")
MQTT_PASSWORD = os.environ.get("MQTT_PASSWORD", "")

API_KEY = os.environ.get("HYDROPOD_API_KEY", "hydropod-dev-key-2026")
REQUIRE_AUTH = os.environ.get("HYDROPOD_REQUIRE_AUTH", "0") == "1"

TOPIC_TELEMETRY = "smartbottle/HYDROPOD_01/telemetry"
TOPIC_CONTROL   = "smartbottle/HYDROPOD_01/control"
TOPIC_ACK       = "smartbottle/HYDROPOD_01/ack"
TOPIC_STATUS    = "smartbottle/HYDROPOD_01/status"

db_lock = threading.Lock()
rate_limit_buckets = defaultdict(list)

def init_db():
    with db_lock:
        conn = sqlite3.connect(DB_PATH)
        cur = conn.cursor()
        cur.execute("""
            CREATE TABLE IF NOT EXISTS telemetry_history (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                ts REAL NOT NULL,
                device_id TEXT NOT NULL,
                drank_today_ml REAL,
                bottle_ml REAL,
                goal_ml REAL,
                hard_cap_ml REAL,
                progress_pct REAL,
                rate_hourly_ml REAL,
                idle_sec INTEGER,
                battery_soc INTEGER,
                safety_status TEXT,
                alert_level INTEGER,
                profile TEXT
            )
        """)
        cur.execute("""
            CREATE TABLE IF NOT EXISTS security_audit_logs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                ts REAL NOT NULL,
                actor TEXT NOT NULL,
                method TEXT NOT NULL,
                endpoint TEXT NOT NULL,
                status_code INTEGER NOT NULL,
                detail TEXT
            )
        """)
        conn.commit()
        conn.close()

def record_telemetry(t):
    try:
        with db_lock:
            conn = sqlite3.connect(DB_PATH)
            conn.execute(
                """INSERT INTO telemetry_history
                   (ts, device_id, drank_today_ml, bottle_ml, goal_ml, hard_cap_ml,
                    progress_pct, rate_hourly_ml, idle_sec, battery_soc,
                    safety_status, alert_level, profile)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                (
                    time.time(),
                    str(t.get("device_id", "HYDROPOD_01")),
                    float(t.get("drank_today_ml", 0)),
                    float(t.get("bottle_ml", 500)),
                    float(t.get("goal_ml", 2000)),
                    float(t.get("hard_cap_ml", 0)),
                    float(t.get("progress_pct", 0)),
                    float(t.get("rate_hourly_ml", 0)),
                    int(t.get("idle_sec", 0)),
                    int(t.get("battery_soc", 85)),
                    str(t.get("safety_status", "NORMAL")),
                    int(t.get("alert_level", 0)),
                    str(t.get("profile", "STANDARD")),
                ),
            )
            conn.commit()
            conn.close()
    except Exception:
        pass

def record_audit(actor, method, endpoint, status_code, detail=""):
    try:
        with db_lock:
            conn = sqlite3.connect(DB_PATH)
            conn.execute(
                """INSERT INTO security_audit_logs (ts, actor, method, endpoint, status_code, detail)
                   VALUES (?, ?, ?, ?, ?, ?)""",
                (time.time(), str(actor), str(method), str(endpoint), int(status_code), str(detail)[:240]),
            )
            conn.commit()
            conn.close()
    except Exception:
        pass

def analyze_hydration_trend():
    with db_lock:
        conn = sqlite3.connect(DB_PATH)
        conn.row_factory = sqlite3.Row
        rows = conn.execute(
            "SELECT ts, drank_today_ml, bottle_ml, goal_ml, hard_cap_ml, safety_status, idle_sec "
            "FROM telemetry_history ORDER BY id DESC LIMIT 60"
        ).fetchall()
        conn.close()

    if not rows:
        return {
            "sample_count": 0,
            "trend": "INSUFFICIENT_DATA",
            "rate_ml_per_hour": 0.0,
            "warning": "Chưa đủ dữ liệu lịch sử để phân tích xu hướng",
            "recent": [],
        }

    ordered = list(reversed([dict(r) for r in rows]))
    first, last = ordered[0], ordered[-1]
    dt_hours = max((last["ts"] - first["ts"]) / 3600.0, 1.0 / 60.0)
    delta_drank = max(0.0, (last["drank_today_ml"] or 0) - (first["drank_today_ml"] or 0))
    rate_ml_h = round(delta_drank / dt_hours, 1)

    cap = last["hard_cap_ml"] or 0
    goal = last["goal_ml"] or 2000
    drank = last["drank_today_ml"] or 0

    if cap > 0 and drank >= cap * 0.85:
        trend = "RISK_OVERCAP"
        warning = f"Cảnh báo xu hướng: Lượng nạp ({int(drank)}ml) đang tiệm cận/vượt trần y tế ({int(cap)}ml)"
    elif (last["idle_sec"] or 0) >= 1800 or (rate_ml_h < 50.0 and drank < goal * 0.5):
        trend = "DEHYDRATION_RISK"
        warning = "Cảnh báo xu hướng: Tốc độ uống nước thấp, nguy cơ thiếu nước"
    elif delta_drank > 0:
        trend = "INCREASING"
        warning = "Xu hướng uống nước ổn định và tích cực"
    else:
        trend = "STEADY"
        warning = "Trạng thái nạp dịch ổn định"

    return {
        "sample_count": len(ordered),
        "trend": trend,
        "rate_ml_per_hour": rate_ml_h,
        "latest_drank_ml": drank,
        "goal_ml": goal,
        "hard_cap_ml": cap,
        "warning": warning,
        "recent": ordered[-10:],
    }

# Global System Telemetry State
latest_telemetry = {
    "bottle_ml": 500,
    "drank_today_ml": 400,
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
    "ringtone": "CHIME",
    "has_custom_mp3": os.path.exists(os.path.join(DIRECTORY, 'custom_alarm.mp3')),
    "custom_mp3_name": "custom_alarm.mp3" if os.path.exists(os.path.join(DIRECTORY, 'custom_alarm.mp3')) else "",
    "wifi_connected": True,
    "wifi_rssi": -45,
    "uptime_sec": 0,
    "last_event": "HTTP REST API Server Ready"
}

connected_clients = []
clients_lock = threading.Lock()
mqtt_client = None

def broadcast_sse(data):
    with clients_lock:
        msg = f"data: {json.dumps(data)}\n\n".encode('utf-8')
        to_remove = []
        for client in connected_clients:
            try:
                client.wfile.write(msg)
                client.wfile.flush()
            except Exception:
                to_remove.append(client)
        for client in to_remove:
            connected_clients.remove(client)

def evaluate_safety():
    cap = latest_telemetry.get("hard_cap_ml", 0)
    drank = latest_telemetry.get("drank_today_ml", 0)
    bottle = latest_telemetry.get("bottle_ml", 500)
    latest_telemetry["is_empty"] = (bottle <= 40)
    if cap > 0:
        ratio = drank / cap
        if ratio >= 1.0:
            latest_telemetry["safety_status"] = "EMERGENCY_OVERCAP"
        elif ratio >= 0.90:
            latest_telemetry["safety_status"] = "DANGER_RED"
        elif ratio >= 0.80:
            latest_telemetry["safety_status"] = "APPROACH_YELLOW"
        else:
            latest_telemetry["safety_status"] = "NORMAL"
    else:
        latest_telemetry["safety_status"] = "NORMAL"

wokwi_socket = None
wokwi_lock = threading.Lock()

def send_to_wokwi(text):
    global wokwi_socket
    with wokwi_lock:
        if wokwi_socket:
            try:
                wokwi_socket.sendall(text.encode('utf-8') + b'\n')
            except Exception:
                pass

def wokwi_serial_bridge_thread():
    global wokwi_socket, latest_telemetry
    while True:
        s = None
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.settimeout(2.0)
            s.connect(("127.0.0.1", 4000))
            print("🟢 [Wokwi Bridge] Connected to Wokwi ESP32 Serial at localhost:4000!")
            with wokwi_lock:
                wokwi_socket = s
            s.settimeout(None)
            buffer = ""
            while True:
                data = s.recv(1024)
                if not data:
                    break
                buffer += data.decode('utf-8', errors='ignore')
                while "\n" in buffer:
                    line, buffer = buffer.split("\n", 1)
                    line = line.strip()
                    if "[TELEMETRY_JSON]" in line:
                        json_str = line.split("[TELEMETRY_JSON]", 1)[1].strip()
                        try:
                            t_data = json.loads(json_str)
                            for k, v in t_data.items():
                                latest_telemetry[k] = v
                            broadcast_sse(latest_telemetry)
                            print(f"🔄 [Wokwi Serial Telemetry]: Drank={t_data.get('drank_today_ml')}ml, Bottle={t_data.get('bottle_ml')}ml")
                        except Exception:
                            pass
                    elif "[SENSOR DRINK DETECTED]" in line:
                        print(f"🌊 [Wokwi Sensor Event]: {line}")
                        latest_telemetry['last_event'] = line
                        broadcast_sse(latest_telemetry)
        except Exception:
            with wokwi_lock:
                wokwi_socket = None
            if s:
                try: s.close()
                except Exception: pass
            time.sleep(2.0)

def publish_to_mqtt(payload_dict):
    global mqtt_client
    payload_str = json.dumps(payload_dict)
    if mqtt_client and mqtt_client.is_connected():
        print(f"📡 [MQTT Pub -> ESP32] Topic: {TOPIC_CONTROL} | Payload: {payload_str}")
        mqtt_client.publish(TOPIC_CONTROL, payload_str)
    else:
        print("⚠️ [MQTT] Client not connected, command handled locally/serial.")
    send_to_wokwi(payload_str)

# --- MQTT SETUP ---
def on_mqtt_connect(client, userdata, flags, rc, properties=None):
    if rc == 0:
        print(f"🟢 [MQTT Connected] Connected to {MQTT_BROKER}:{MQTT_PORT}")
        client.subscribe(TOPIC_TELEMETRY)
        client.subscribe(TOPIC_ACK)
        client.subscribe(TOPIC_STATUS)
        print(f"📥 [MQTT Subscribed] {TOPIC_TELEMETRY}, {TOPIC_ACK} & {TOPIC_STATUS}")
    else:
        print(f"❌ [MQTT Connection Failed] Return code {rc}")

def on_mqtt_message(client, userdata, msg):
    global latest_telemetry
    try:
        payload = json.loads(msg.payload.decode('utf-8'))
        if msg.topic == TOPIC_TELEMETRY:
            print(f"🔄 [MQTT Telemetry Received]: Drank={payload.get('drank_today_ml')}ml, Bottle={payload.get('bottle_ml')}ml, Safety={payload.get('safety_status')}, Vib={payload.get('vibration_motor')}")
            for k, v in payload.items():
                latest_telemetry[k] = v
            record_telemetry(latest_telemetry)
            broadcast_sse(latest_telemetry)
        elif msg.topic == TOPIC_ACK:
            print(f"✅ [MQTT ACK Received]: Command={payload.get('command')} -> Status={payload.get('status')}")
            latest_telemetry["last_ack"] = payload
            broadcast_sse({"ack": payload, "current_telemetry": latest_telemetry})
        elif msg.topic == TOPIC_STATUS:
            print(f"📡 [MQTT Device Status]: Device={payload.get('device_id')} Status={payload.get('status')}")
            latest_telemetry["device_online"] = (payload.get("status") == "ONLINE")
            broadcast_sse({"device_status": payload, "current_telemetry": latest_telemetry})
    except Exception as e:
        print(f"⚠️ Error parsing MQTT message: {e}")

def start_mqtt_client():
    global mqtt_client
    if not MQTT_AVAILABLE:
        return
    client_id = f"HydroPod_Server_Bridge_{int(time.time())}"
    try:
        mqtt_client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id)
    except Exception:
        mqtt_client = mqtt.Client(client_id)
        
    mqtt_client.on_connect = on_mqtt_connect
    mqtt_client.on_message = on_mqtt_message
    if MQTT_USERNAME:
        mqtt_client.username_pw_set(MQTT_USERNAME, MQTT_PASSWORD)
    if MQTT_USE_TLS and os.path.exists(MQTT_CA_CERT):
        mqtt_client.tls_set(ca_certs=MQTT_CA_CERT, tls_version=ssl.PROTOCOL_TLS_CLIENT)

    def mqtt_loop():
        try:
            print(f"🔌 [MQTT] Connecting to {MQTT_BROKER}:{MQTT_PORT}...")
            mqtt_client.connect(MQTT_BROKER, MQTT_PORT, 60)
            mqtt_client.loop_forever()
        except Exception as e:
            print(f"❌ [MQTT Error] {e}")

    t = threading.Thread(target=mqtt_loop, daemon=True)
    t.start()

# --- HTTP REQUEST HANDLER ---
class PostmanAPIHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIRECTORY, **kwargs)

    def _send_cors_headers(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-API-Key')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('X-Frame-Options', 'DENY')

    def _check_auth_and_rate(self, method):
        client_ip = self.client_address[0] if self.client_address else 'unknown'
        now = time.time()
        bucket = [t for t in rate_limit_buckets[client_ip] if now - t < 10.0]
        bucket.append(now)
        rate_limit_buckets[client_ip] = bucket
        if len(bucket) > 60:
            record_audit(client_ip, method, self.path, 429, "Rate limit exceeded")
            self.send_response(429)
            self.send_header('Content-Type', 'application/json')
            self._send_cors_headers()
            self.end_headers()
            self.wfile.write(json.dumps({"status": "error", "message": "Too many requests"}).encode('utf-8'))
            return False

        provided_key = self.headers.get('X-API-Key', '').strip()
        auth_hdr = self.headers.get('Authorization', '').strip()
        if not provided_key and auth_hdr.lower().startswith('bearer '):
            provided_key = auth_hdr[7:].strip()

        if provided_key and provided_key != API_KEY:
            record_audit(client_ip, method, self.path, 401, "Invalid API key")
            self.send_response(401)
            self.send_header('Content-Type', 'application/json')
            self._send_cors_headers()
            self.end_headers()
            self.wfile.write(json.dumps({"status": "error", "message": "Unauthorized: invalid API key"}).encode('utf-8'))
            return False

        if REQUIRE_AUTH and provided_key != API_KEY:
            record_audit(client_ip, method, self.path, 401, "Missing API key")
            self.send_response(401)
            self.send_header('Content-Type', 'application/json')
            self._send_cors_headers()
            self.end_headers()
            self.wfile.write(json.dumps({"status": "error", "message": "Unauthorized: API key required"}).encode('utf-8'))
            return False

        return True

    def do_OPTIONS(self):
        self.send_response(200)
        self._send_cors_headers()
        self.end_headers()

    def do_HEAD(self):
        self.send_response(200)
        self._send_cors_headers()
        self.end_headers()

    def do_GET(self):
        # 1. SSE Stream endpoint for Web
        if self.path == '/events':
            self.send_response(200)
            self.send_header('Content-Type', 'text/event-stream')
            self.send_header('Cache-Control', 'no-cache')
            self.send_header('Connection', 'keep-alive')
            self._send_cors_headers()
            self.end_headers()

            with clients_lock:
                connected_clients.append(self)
                init_msg = f"data: {json.dumps(latest_telemetry)}\n\n".encode('utf-8')
                self.wfile.write(init_msg)
                self.wfile.flush()

            try:
                while True:
                    time.sleep(1)
            except Exception:
                with clients_lock:
                    if self in connected_clients:
                        connected_clients.remove(self)
            return

        # 2. Get Telemetry Endpoint for Postman
        elif self.path.startswith('/api/telemetry'):
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self._send_cors_headers()
            self.end_headers()
            self.wfile.write(json.dumps(latest_telemetry, indent=2).encode('utf-8'))
            return

        # 3. Postman API Documentation / Help endpoint
        elif self.path.startswith('/api/help') or self.path.startswith('/api/routes'):
            help_data = {
                "title": "Smart Hydration Pod - Postman Test API & MQTT Bridge",
                "broker": f"{MQTT_BROKER}:{MQTT_PORT}",
                "mqtt_topics": {
                    "telemetry": TOPIC_TELEMETRY,
                    "control": TOPIC_CONTROL,
                    "ack": TOPIC_ACK
                },
                "endpoints": [
                    {"method": "GET", "url": "http://localhost:8000/api/telemetry", "desc": "Lấy toàn bộ thông số thời gian thực từ ESP32"},
                    {"method": "POST", "url": "http://localhost:8000/api/command", "body": {"command": "SIM_DEMO_SCENARIO_1"}, "desc": "Gửi lệnh Demo 1 (uống 150ml), Demo 2 (quên uống), Demo 3 (vượt trần)"},
                    {"method": "POST", "url": "http://localhost:8000/api/drink", "body": {"amount_ml": 150}, "desc": "Mô phỏng nạp nước (gửi lệnh xuống ESP32)"},
                    {"method": "POST", "url": "http://localhost:8000/api/profile", "body": {"profile": "HEART_FAILURE", "hard_cap": 1000}, "desc": "Chỉ định phác đồ y tế (STANDARD, HEART_FAILURE, GOUT)"},
                    {"method": "POST", "url": "http://localhost:8000/api/alarm", "body": {"action": "MUTE"}, "desc": "Tắt/bật chuông cảnh báo (MUTE/UNMUTE)"},
                    {"method": "POST", "url": "http://localhost:8000/api/vibrate", "body": {"duration_ms": 300}, "desc": "Kích hoạt kiểm thử bộ rung nhắc nhở (Haptic Vibration Motor)"},
                    {"method": "POST", "url": "http://localhost:8000/api/reset", "body": {}, "desc": "Reset dữ liệu nạp dịch ngày"}
                ]
            }
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self._send_cors_headers()
            self.end_headers()
            self.wfile.write(json.dumps(help_data, indent=2).encode('utf-8'))
            return

        # 4. Serve Postman Collection JSON directly
        elif self.path.startswith('/postman_collection.json'):
            col_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'postman_collection.json')
            if os.path.exists(col_path):
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self._send_cors_headers()
                self.end_headers()
                with open(col_path, 'rb') as f:
                    self.wfile.write(f.read())
                return

        # 5. Serve OpenAPI 3.0 Specification JSON directly
        elif self.path.startswith('/openapi.json'):
            oa_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'openapi.json')
            if os.path.exists(oa_path):
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self._send_cors_headers()
                self.end_headers()
                with open(oa_path, 'rb') as f:
                    self.wfile.write(f.read())
                return

        # 6. Serve Interactive Web Postman / API Docs Tester
        elif self.path in ['/docs', '/docs/', '/tester', '/postman']:
            doc_file = os.path.join(DIRECTORY, 'docs.html')
            if os.path.exists(doc_file):
                self.send_response(200)
                self.send_header('Content-Type', 'text/html; charset=utf-8')
                self._send_cors_headers()
                self.end_headers()
                with open(doc_file, 'rb') as f:
                    self.wfile.write(f.read())
                return

        # 7. Unified Web Dashboard (redirect legacy /mobile, /app, /patient routes to /)
        elif self.path in ['/mobile', '/mobile/', '/app', '/patient']:
            self.send_response(302)
            self.send_header('Location', '/')
            self._send_cors_headers()
            self.end_headers()
            return

        # 8. GET /api/analytics/trend (Structured SQLite Trend Analysis)
        elif self.path.startswith('/api/analytics/trend'):
            trend_data = analyze_hydration_trend()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self._send_cors_headers()
            self.end_headers()
            self.wfile.write(json.dumps(trend_data, indent=2).encode('utf-8'))
            return

        # 9. GET /api/audit_logs (Security & Control Audit Trail)
        elif self.path.startswith('/api/audit_logs'):
            if not self._check_auth_and_rate('GET'):
                return
            with db_lock:
                conn = sqlite3.connect(DB_PATH)
                conn.row_factory = sqlite3.Row
                rows = conn.execute(
                    "SELECT id, ts, actor, method, endpoint, status_code, detail "
                    "FROM security_audit_logs ORDER BY id DESC LIMIT 50"
                ).fetchall()
                conn.close()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self._send_cors_headers()
            self.end_headers()
            self.wfile.write(json.dumps({"logs": [dict(r) for r in rows]}, indent=2).encode('utf-8'))
            return

        super().do_GET()

    def do_POST(self):
        if not self._check_auth_and_rate('POST'):
            return
        content_length = int(self.headers.get('Content-Length', 0))
        body_bytes = self.rfile.read(content_length) if content_length > 0 else b'{}'
        
        try:
            body_json = json.loads(body_bytes.decode('utf-8')) if body_bytes else {}
        except Exception:
            body_json = {}

        response_data = {}

        # 1. POST /api/command (Postman command test)
        if self.path.startswith('/api/command'):
            cmd = body_json.get('command', '')
            if cmd == 'SIM_DEMO_SCENARIO_1' or cmd == '1':
                latest_telemetry['drank_today_ml'] += 150
                latest_telemetry['bottle_ml'] = max(0, latest_telemetry['bottle_ml'] - 150)
                latest_telemetry['idle_sec'] = 0
                latest_telemetry['last_event'] = 'Postman Executed Demo 1 (+150ml)'
                publish_to_mqtt({"command": "SIM_DEMO_SCENARIO_1"})
            elif cmd == 'SIM_DEMO_SCENARIO_2' or cmd == '2':
                latest_telemetry['idle_sec'] = 35
                latest_telemetry['alert_level'] = 2
                latest_telemetry['last_event'] = 'Postman Executed Demo 2 (35s Idle Warning)'
                publish_to_mqtt({"command": "SIM_DEMO_SCENARIO_2"})
            elif cmd == 'SIM_DEMO_SCENARIO_3' or cmd == '3':
                latest_telemetry['profile'] = 'HEART_FAILURE'
                latest_telemetry['goal_ml'] = 1000
                latest_telemetry['hard_cap_ml'] = 1000
                latest_telemetry['drank_today_ml'] = 1050
                latest_telemetry['last_event'] = 'Postman Executed Demo 3 (Overcap Emergency 1050/1000ml)'
                publish_to_mqtt({"command": "SIM_DEMO_SCENARIO_3"})
            elif cmd == 'RESET_DAY':
                latest_telemetry['drank_today_ml'] = 0
                latest_telemetry['bottle_ml'] = 500
                latest_telemetry['idle_sec'] = 0
                latest_telemetry['last_event'] = 'Postman Executed Day Reset'
                publish_to_mqtt({"command": "RESET_DAY"})
            else:
                publish_to_mqtt({"command": cmd})

            evaluate_safety()
            latest_telemetry['progress_pct'] = round((latest_telemetry['drank_today_ml'] / max(1, latest_telemetry['goal_ml'])) * 100, 1)
            broadcast_sse(latest_telemetry)

            response_data = {
                "status": "success",
                "received_command": cmd,
                "mqtt_published": True,
                "current_telemetry": latest_telemetry
            }

        # 2. POST /api/drink (Postman direct drink test)
        elif self.path.startswith('/api/drink'):
            amount = float(body_json.get('amount_ml', body_json.get('amount', 150)))
            latest_telemetry['drank_today_ml'] += amount
            latest_telemetry['bottle_ml'] = max(0, latest_telemetry['bottle_ml'] - amount)
            latest_telemetry['idle_sec'] = 0
            latest_telemetry['last_event'] = f"Postman Drank +{int(amount)}ml"
            evaluate_safety()
            latest_telemetry['progress_pct'] = round((latest_telemetry['drank_today_ml'] / max(1, latest_telemetry['goal_ml'])) * 100, 1)
            
            # Forward to ESP32 over MQTT
            publish_to_mqtt({"target": "drink", "amount": amount})
            broadcast_sse(latest_telemetry)

            response_data = {
                "status": "success",
                "added_amount_ml": amount,
                "total_drank_ml": latest_telemetry['drank_today_ml'],
                "mqtt_published": True,
                "current_telemetry": latest_telemetry
            }

        # 3. POST /api/profile (Postman profile switch test)
        elif self.path.startswith('/api/profile'):
            prof = body_json.get('profile', body_json.get('mode', 'STANDARD')).upper()
            hard_cap = float(body_json.get('hard_cap', 0))
            
            latest_telemetry['profile'] = prof
            if prof == 'STANDARD':
                latest_telemetry['goal_ml'] = 2000
                latest_telemetry['hard_cap_ml'] = 0
            elif prof == 'HEART_FAILURE':
                latest_telemetry['goal_ml'] = hard_cap if hard_cap > 0 else 1000
                latest_telemetry['hard_cap_ml'] = latest_telemetry['goal_ml']
            elif prof == 'GOUT':
                latest_telemetry['goal_ml'] = 2500
                latest_telemetry['hard_cap_ml'] = 0

            evaluate_safety()
            latest_telemetry['progress_pct'] = round((latest_telemetry['drank_today_ml'] / max(1, latest_telemetry['goal_ml'])) * 100, 1)
            
            # Forward to ESP32 over MQTT
            publish_to_mqtt({"target": "profile", "mode": prof, "hard_cap": latest_telemetry['hard_cap_ml']})
            broadcast_sse(latest_telemetry)

            response_data = {
                "status": "success",
                "active_profile": prof,
                "hard_cap_ml": latest_telemetry['hard_cap_ml'],
                "mqtt_published": True,
                "current_telemetry": latest_telemetry
            }

        # 4. POST /api/alarm (Postman alarm mute/unmute)
        elif self.path.startswith('/api/alarm'):
            action = body_json.get('action', 'MUTE').upper()
            publish_to_mqtt({"target": "alarm", "action": action})
            response_data = {"status": "success", "alarm_action": action, "mqtt_published": True}

        # 5. POST /api/vibrate (Trigger vibration motor test / Find Pod with buzzer)
        elif self.path.startswith('/api/vibrate'):
            duration = int(body_json.get('duration_ms', body_json.get('duration', 300)))
            pattern = body_json.get('pattern', 'CUSTOM')
            with_buzzer = bool(body_json.get('with_buzzer', str(pattern).upper() == 'FIND'))
            latest_telemetry['vibration_motor'] = 1
            latest_telemetry['last_event'] = (
                f"Find Pod (Vibration + Buzzer {duration}ms)"
                if with_buzzer
                else f"Vibration Test Triggered ({duration}ms)"
            )
            publish_to_mqtt({
                "target": "vibrate",
                "duration_ms": duration,
                "pattern": pattern,
                "with_buzzer": with_buzzer,
            })
            broadcast_sse(latest_telemetry)
            response_data = {
                "status": "success",
                "message": (
                    f"Triggered Find Pod: vibration + buzzer ({duration}ms)"
                    if with_buzzer
                    else f"Triggered vibration motor ({duration}ms)"
                ),
                "mqtt_published": True,
                "current_telemetry": latest_telemetry
            }

        # 6. POST /api/refill
        elif self.path.startswith('/api/refill'):
            amount = float(body_json.get('amount_ml', body_json.get('amount', 350)))
            latest_telemetry['bottle_ml'] = min(1000, latest_telemetry['bottle_ml'] + amount)
            latest_telemetry['last_event'] = f"Refilled +{int(amount)}ml"
            evaluate_safety()
            publish_to_mqtt({"target": "refill", "amount": amount})
            broadcast_sse(latest_telemetry)
            response_data = {"status": "success", "message": f"Refilled +{int(amount)}ml", "bottle_ml": latest_telemetry['bottle_ml']}

        # 7. POST /api/ringtone (Change Ringtone Style)
        elif self.path.startswith('/api/ringtone'):
            r_tone = body_json.get('tone', body_json.get('ringtone', 'CHIME')).upper()
            latest_telemetry['ringtone'] = r_tone
            latest_telemetry['last_event'] = f"Ringtone set to {r_tone}"
            publish_to_mqtt({"target": "ringtone", "tone": r_tone, "preview": True})
            broadcast_sse(latest_telemetry)
            response_data = {"status": "success", "ringtone": r_tone, "mqtt_published": True}

        # 8. POST /api/upload_audio (Upload custom .mp3 file)
        elif self.path.startswith('/api/upload_audio'):
            try:
                data_b64 = body_json.get('data', '')
                filename = body_json.get('filename', 'custom_alarm.mp3')
                if data_b64:
                    if ',' in data_b64:
                        data_b64 = data_b64.split(',', 1)[1]
                    audio_bytes = base64.b64decode(data_b64)
                    save_path = os.path.join(DIRECTORY, 'custom_alarm.mp3')
                    with open(save_path, 'wb') as f:
                        f.write(audio_bytes)
                    latest_telemetry['ringtone'] = 'CUSTOM'
                    latest_telemetry['has_custom_mp3'] = True
                    latest_telemetry['custom_mp3_name'] = filename
                    latest_telemetry['last_event'] = f"Uploaded MP3: {filename}"
                    publish_to_mqtt({"target": "ringtone", "tone": "CUSTOM", "filename": filename})
                    broadcast_sse(latest_telemetry)
                    response_data = {
                        "status": "success",
                        "message": f"Saved {filename} ({len(audio_bytes)} bytes)",
                        "url": "/custom_alarm.mp3",
                        "ringtone": "CUSTOM"
                    }
                else:
                    response_data = {"status": "error", "message": "No audio data provided"}
            except Exception as e:
                response_data = {"status": "error", "message": str(e)}

        # 9. POST /api/reset
        elif self.path.startswith('/api/reset'):
            latest_telemetry['drank_today_ml'] = 0
            latest_telemetry['bottle_ml'] = 500
            latest_telemetry['idle_sec'] = 0
            latest_telemetry['alert_level'] = 0
            evaluate_safety()
            publish_to_mqtt({"target": "reset"})
            broadcast_sse(latest_telemetry)
            response_data = {"status": "success", "message": "Daily stats reset", "mqtt_published": True}

        else:
            response_data = {"status": "error", "message": "Endpoint not found"}

        record_telemetry(latest_telemetry)
        client_ip = self.client_address[0] if self.client_address else 'unknown'
        record_audit(client_ip, 'POST', self.path, 200, response_data.get('status', 'ok'))

        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self._send_cors_headers()
        self.end_headers()
        self.wfile.write(json.dumps(response_data, indent=2).encode('utf-8'))

class ThreadedHTTPServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True

def run_server():
    init_db()
    start_mqtt_client()
    
    # Start Wokwi RFC2217 background bridge
    w_thread = threading.Thread(target=wokwi_serial_bridge_thread, daemon=True)
    w_thread.start()

    with ThreadedHTTPServer(("", PORT), PostmanAPIHandler) as httpd:
        print(f"\n==================================================================")
        print(f"🟢 [Smart Hydration Pod Server] Running at: http://localhost:{PORT}")
        print(f"👉 API Docs & Endpoints: http://localhost:{PORT}/api/help")
        print(f"👉 Web Dashboard:        http://localhost:{PORT}")
        print(f"👉 Public MQTT Broker:   {MQTT_BROKER}:{MQTT_PORT}")
        print(f"👉 Wokwi Serial Bridge:  localhost:4000 (Auto-connecting)")
        print(f"==================================================================\n")
        httpd.serve_forever()

if __name__ == '__main__':
    run_server()
