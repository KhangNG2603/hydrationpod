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

# Try importing paho.mqtt.client
try:
    import paho.mqtt.client as mqtt
    MQTT_AVAILABLE = True
except ImportError:
    MQTT_AVAILABLE = False
    print("⚠️ paho-mqtt not installed. MQTT bridging disabled.")

PORT = 8000
DIRECTORY = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'dashboard')

MQTT_BROKER = "broker.emqx.io"
MQTT_PORT = 1883
TOPIC_TELEMETRY = "smartbottle/HYDROPOD_01/telemetry"
TOPIC_CONTROL   = "smartbottle/HYDROPOD_01/control"
TOPIC_ACK       = "smartbottle/HYDROPOD_01/ack"
TOPIC_STATUS    = "smartbottle/HYDROPOD_01/status"

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
        self.send_header('Access-Control-Allow-Headers', 'Content-Type, Authorization')

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

        super().do_GET()

    def do_POST(self):
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

        # 5. POST /api/vibrate (Trigger vibration motor test)
        elif self.path.startswith('/api/vibrate'):
            duration = int(body_json.get('duration_ms', body_json.get('duration', 300)))
            pattern = body_json.get('pattern', 'CUSTOM')
            latest_telemetry['vibration_motor'] = 1
            latest_telemetry['last_event'] = f"Vibration Test Triggered ({duration}ms)"
            publish_to_mqtt({"target": "vibrate", "duration_ms": duration, "pattern": pattern})
            broadcast_sse(latest_telemetry)
            response_data = {
                "status": "success",
                "message": f"Triggered vibration motor ({duration}ms)",
                "mqtt_published": True,
                "current_telemetry": latest_telemetry
            }

        # 6. POST /api/refill
        elif self.path.startswith('/api/refill'):
            amount = float(body_json.get('amount_ml', body_json.get('amount', 350)))
            latest_telemetry['bottle_ml'] = min(1000, latest_telemetry['bottle_ml'] + amount)
            latest_telemetry['last_event'] = f"Refilled +{int(amount)}ml"
            publish_to_mqtt({"target": "refill", "amount": amount})
            broadcast_sse(latest_telemetry)
            response_data = {"status": "success", "message": f"Refilled +{int(amount)}ml", "bottle_ml": latest_telemetry['bottle_ml']}

        # 7. POST /api/reset
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

        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self._send_cors_headers()
        self.end_headers()
        self.wfile.write(json.dumps(response_data, indent=2).encode('utf-8'))

class ThreadedHTTPServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True

def run_server():
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
