// Smart Hydration Pod - Full IoT Lab Framework & Medical Engine

let state = {
  profile: 'STANDARD',
  drank: 400,
  goal: 2000,
  cap: 0,
  bottle: 500,
  idle_sec: 12,
  battery_soc: 85,
  safety: 'NORMAL',
  alert_level: 0,
  is_alarm_muted: false,
  user_role: 'caregiver', // 'caregiver' or 'patient'
  is_mqtt_connected: false
};

// Audio Synthesizer
let audioCtx = null;
function initAudio() {
  if (!audioCtx) audioCtx = new (window.AudioContext || window.webkitAudioContext)();
}

function playTone(freq, type = 'sine', dur = 0.15) {
  if (state.is_alarm_muted) return;
  try {
    initAudio();
    if (!audioCtx) return;
    const osc = audioCtx.createOscillator();
    const gain = audioCtx.createGain();
    osc.type = type;
    osc.frequency.setValueAtTime(freq, audioCtx.currentTime);
    gain.gain.setValueAtTime(0.12, audioCtx.currentTime);
    gain.gain.exponentialRampToValueAtTime(0.01, audioCtx.currentTime + dur);
    osc.connect(gain);
    gain.connect(audioCtx.destination);
    osc.start();
    osc.stop(audioCtx.currentTime + dur);
  } catch (e) {}
}

// --- HISTORY LINE CHART (Lab 3 & BTVN 1: History Chart Widget) ---
let intakeChart = null;
const chartData = {
  labels: ['12:00', '12:15', '12:30', '12:45', '13:00'],
  datasets: [{
    label: 'Lượng Nước Nạp Lũy Kế (ml) [V0]',
    data: [100, 200, 250, 300, 400],
    borderColor: '#38bdf8',
    backgroundColor: 'rgba(56, 189, 248, 0.15)',
    borderWidth: 2.5,
    fill: true,
    tension: 0.35,
    pointBackgroundColor: '#38bdf8',
    pointRadius: 4
  }]
};

function initHistoryChart() {
  const ctx = document.getElementById('intakeChart');
  if (!ctx) return;

  intakeChart = new Chart(ctx, {
    type: 'line',
    data: chartData,
    options: {
      responsive: true,
      maintainAspectRatio: false,
      plugins: {
        legend: {
          labels: { color: '#94a3b8', font: { family: 'Inter', size: 12 } }
        }
      },
      scales: {
        x: {
          grid: { color: 'rgba(255, 255, 255, 0.05)' },
          ticks: { color: '#94a3b8', font: { family: 'Inter', size: 11 } }
        },
        y: {
          min: 0,
          suggestedMax: 2000,
          grid: { color: 'rgba(255, 255, 255, 0.05)' },
          ticks: { color: '#94a3b8', font: { family: 'Inter', size: 11 } }
        }
      }
    }
  });
}

function addChartPoint(val) {
  if (!intakeChart) return;
  const now = new Date();
  const timeStr = `${String(now.getHours()).padStart(2, '0')}:${String(now.getMinutes()).padStart(2, '0')}:${String(now.getSeconds()).padStart(2, '0')}`;
  
  if (intakeChart.data.labels.length > 12) {
    intakeChart.data.labels.shift();
    intakeChart.data.datasets[0].data.shift();
  }
  intakeChart.data.labels.push(timeStr);
  intakeChart.data.datasets[0].data.push(val);
  intakeChart.update();
}

// --- DIRECT MQTT CLIENT OVER WEBSOCKETS (Lab 2, 3, 4, 5) ---
let mqttClient = null;
const MQTT_BROKER_WS = 'wss://broker.emqx.io:8084/mqtt';
const TOPIC_TELEMETRY = 'smartbottle/HYDROPOD_01/telemetry';
const TOPIC_CONTROL   = 'smartbottle/HYDROPOD_01/control';
const TOPIC_ACK       = 'smartbottle/HYDROPOD_01/ack';

function initMQTT() {
  if (typeof mqtt === 'undefined') {
    log('⚠️ MQTT.js chưa tải được, sử dụng HTTP SSE Server Fallback.', 'warn');
    initSSEFallback();
    return;
  }

  const clientId = 'WebDashboard_' + Math.random().toString(16).substring(2, 8);
  log(`🔌 Đang kết nối tới MQTT Broker: ${MQTT_BROKER_WS}...`, 'info');

  try {
    mqttClient = mqtt.connect(MQTT_BROKER_WS, {
      clientId: clientId,
      clean: true,
      connectTimeout: 5000,
      reconnectPeriod: 3000
    });

    mqttClient.on('connect', () => {
      state.is_mqtt_connected = true;
      document.getElementById('conn-text').innerText = '🟢 MQTT Online (broker.emqx.io)';
      document.getElementById('conn-dot').style.background = 'var(--green)';
      log('🟢 Đã kết nối MQTT Broker thành công! Đăng ký topic telemetry & ack.', 'info');

      mqttClient.subscribe(TOPIC_TELEMETRY);
      mqttClient.subscribe(TOPIC_ACK);
    });

    mqttClient.on('message', (topic, message) => {
      try {
        const payload = JSON.parse(message.toString());
        if (topic === TOPIC_TELEMETRY) {
          updateDataFromESP32(payload);
        } else if (topic === TOPIC_ACK) {
          log(`[FEEDBACK ACK - BTVN 3]: Lệnh ${payload.command} -> ${payload.status} (${payload.detail || ''})`, 'ack');
        }
      } catch (e) {}
    });

    mqttClient.on('error', (err) => {
      console.warn('MQTT WS error:', err);
      initSSEFallback();
    });
  } catch (e) {
    initSSEFallback();
  }
}

// Fallback to Server-Sent Events (SSE) if MQTT WS blocked by network
function initSSEFallback() {
  if (typeof EventSource !== "undefined") {
    const evtSource = new EventSource('/events');
    evtSource.onmessage = function(e) {
      try {
        const data = JSON.parse(e.data);
        updateDataFromESP32(data);
      } catch (err) {}
    };
  }
}

// Publish command to MQTT (or HTTP POST fallback)
function sendCommand(cmdObj) {
  const jsonStr = JSON.stringify(cmdObj);
  log(`➡️ [GỬI LỆNH]: ${jsonStr}`, 'info');

  if (mqttClient && mqttClient.connected) {
    mqttClient.publish(TOPIC_CONTROL, jsonStr);
  } else {
    // HTTP fallback to server.py
    fetch('/api/command', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ command: cmdObj.command || cmdObj.target })
    }).catch(() => {});
  }
}

// --- UPDATE METRICS FROM TELEMETRY ---
function updateDataFromESP32(data) {
  let prevDrank = state.drank;

  if (data.drank_today_ml !== undefined) state.drank = data.drank_today_ml;
  if (data.goal_ml !== undefined) state.goal = data.goal_ml;
  if (data.hard_cap_ml !== undefined) state.cap = data.hard_cap_ml;
  if (data.bottle_ml !== undefined) state.bottle = data.bottle_ml;
  if (data.idle_sec !== undefined) state.idle_sec = data.idle_sec;
  if (data.battery_soc !== undefined) state.battery_soc = data.battery_soc;
  if (data.safety_status !== undefined) state.safety = data.safety_status;
  if (data.alert_level !== undefined) state.alert_level = data.alert_level;
  if (data.profile !== undefined) state.profile = data.profile;

  if (state.drank !== prevDrank) {
    addChartPoint(state.drank);
  }

  if (data.last_event) {
    log(`[ESP32 Hardware Event]: ${data.last_event}`);
  }

  updateUI();
}

// --- UI UPDATE & DUAL SAFETY MARGIN (Lab 2 & BTVN 2) ---
function updateUI() {
  document.getElementById('val-drank').innerText = Math.round(state.drank);
  document.getElementById('val-goal').innerText = Math.round(state.goal);

  const pct = Math.min(100, Math.round((state.drank / state.goal) * 1000) / 10);
  document.getElementById('val-pct').innerText = pct.toFixed(1) + '%';
  document.getElementById('val-bottle').innerHTML = `${Math.round(state.bottle)} <small>ml</small>`;
  document.getElementById('val-idle').innerHTML = `${state.idle_sec} <small>giây</small>`;
  document.getElementById('val-bat').innerHTML = `${state.battery_soc} <small>%</small>`;

  // Progress Bar
  const fill = document.getElementById('progress-fill');
  fill.style.width = Math.min(100, pct) + '%';

  // Evaluate Dual Safety Margin (Biên An Toàn Kép - BTVN 2)
  const tag = document.getElementById('safety-tag');
  tag.className = 'tag';

  if (state.cap > 0) {
    const ratio = state.drank / state.cap;
    document.getElementById('label-cap-val').innerText = `🚨 Trần: ${state.cap}ml`;

    if (ratio >= 1.0) {
      tag.classList.add('tag-danger');
      tag.innerText = '🚨 BÁO ĐỘNG VƯỢT TRẦN';
      fill.style.background = 'var(--red)';
      document.getElementById('modal').classList.add('active');
      document.getElementById('m-drank').innerText = Math.round(state.drank);
      document.getElementById('m-cap').innerText = Math.round(state.cap);
      playTone(1500, 'sawtooth', 0.3);
    } else if (ratio >= 0.90) {
      tag.classList.add('tag-danger');
      tag.innerText = '🔴 90% HARD CAP';
      fill.style.background = 'var(--red)';
    } else if (ratio >= 0.80) {
      tag.classList.add('tag-warning');
      tag.innerText = '🟡 80% TIỆM CẬN';
      fill.style.background = 'var(--yellow)';
    } else {
      tag.classList.add('tag-success');
      tag.innerText = '🟢 AN TOÀN';
      fill.style.background = 'linear-gradient(90deg, var(--primary), #3b82f6)';
    }
  } else {
    document.getElementById('label-cap-val').innerText = '🚨 Không áp hạn mức';
    tag.classList.add('tag-success');
    tag.innerText = '🟢 AN TOÀN';
    fill.style.background = 'linear-gradient(90deg, var(--primary), #3b82f6)';
  }

  // Update profile buttons active state
  document.querySelectorAll('.btn-opt').forEach(b => b.classList.remove('active'));
  if (state.profile === 'STANDARD' && document.getElementById('btn-std')) {
    document.getElementById('btn-std').classList.add('active');
  } else if (state.profile === 'HEART_FAILURE' && document.getElementById('btn-heart')) {
    document.getElementById('btn-heart').classList.add('active');
  } else if (state.profile === 'GOUT' && document.getElementById('btn-gout')) {
    document.getElementById('btn-gout').classList.add('active');
  }

  updateLEDs();
}

// LED Ring simulation visualizer
function updateLEDs() {
  const dots = document.querySelectorAll('.dot');
  let color = '#334155';

  if (state.safety === 'EMERGENCY_OVERCAP' || (state.cap > 0 && state.drank >= state.cap)) {
    color = (Math.floor(Date.now() / 200) % 2 === 0) ? '#ef4444' : '#000000';
  } else if (state.alert_level >= 2) {
    color = (Math.floor(Date.now() / 300) % 2 === 0) ? '#f59e0b' : '#000000';
  } else if (state.alert_level === 1) {
    color = '#f59e0b';
  } else {
    color = '#22c55e';
  }

  dots.forEach(d => d.style.background = color);
}

// --- USER ROLE SWITCHER (BTVN 3: Phân Quyền Đa Người Dùng) ---
function switchRole(role) {
  state.user_role = role;
  const panel = document.getElementById('control-panel');
  const lock = document.getElementById('lock-badge');

  if (role === 'patient') {
    panel.classList.add('locked');
    lock.style.display = 'inline-block';
    log('👤 Chuyển sang vai trò Bệnh Nhân (Read-Only): Đã khóa quyền thay đổi hạn mức y tế!', 'warn');
  } else {
    panel.classList.remove('locked');
    lock.style.display = 'none';
    log('👨‍⚕️ Chuyển sang vai trò Bác Sĩ / Caregiver: Mở toàn quyền cấu hình chỉ định y tế.', 'info');
  }
}

// --- CONTROL HANDLERS (Lab 4: Switch, Button, Slider) ---
function setProfile(prof) {
  if (state.user_role === 'patient') {
    alert('Bệnh nhân không có quyền thay đổi Profile chỉ định của Bác sĩ!');
    return;
  }

  state.profile = prof;
  if (prof === 'STANDARD') {
    state.goal = 2000;
    state.cap = 0;
    sendCommand({ target: 'profile', mode: 'STANDARD', hard_cap: 0 });
  } else if (prof === 'HEART_FAILURE') {
    const sliderVal = parseFloat(document.getElementById('cap-slider').value) || 1000;
    state.goal = sliderVal;
    state.cap = sliderVal;
    sendCommand({ target: 'profile', mode: 'HEART_FAILURE', hard_cap: sliderVal });
  } else if (prof === 'GOUT') {
    state.goal = 2500;
    state.cap = 0;
    sendCommand({ target: 'profile', mode: 'GOUT', hard_cap: 0 });
  }
  updateUI();
}

function onCapSliderChange(val) {
  document.getElementById('slider-val-txt').innerText = `${val} ml`;
  if (state.profile === 'HEART_FAILURE') {
    state.goal = parseFloat(val);
    state.cap = parseFloat(val);
    sendCommand({ target: 'profile', mode: 'HEART_FAILURE', hard_cap: state.cap });
    updateUI();
  }
}

function toggleMute() {
  state.is_alarm_muted = !state.is_alarm_muted;
  const btn = document.getElementById('btn-mute');
  const txt = document.getElementById('txt-mute');

  if (state.is_alarm_muted) {
    btn.classList.add('active');
    txt.innerText = 'Đã Tắt Chuông Báo';
    sendCommand({ target: 'alarm', action: 'MUTE' });
  } else {
    btn.classList.remove('active');
    txt.innerText = 'Tắt Còi Báo Động';
    sendCommand({ target: 'alarm', action: 'UNMUTE' });
  }
}

function resetDay() {
  if (state.user_role === 'patient') {
    alert('Chỉ Bác sĩ / Điều dưỡng mới có quyền Reset dữ liệu ngày!');
    return;
  }
  state.drank = 0;
  state.bottle = 500;
  state.idle_sec = 0;
  sendCommand({ target: 'reset' });
  addChartPoint(0);
  updateUI();
}

// --- DEMO SCENARIOS ---
function runDemo(n) {
  if (n === 1) {
    state.drank += 150;
    state.bottle = Math.max(0, state.bottle - 150);
    state.idle_sec = 0;
    state.alert_level = 0;
    sendCommand({ target: 'drink', amount: 150 });
    addChartPoint(state.drank);
    playTone(1046, 'sine', 0.2);
  } else if (n === 2) {
    state.idle_sec = 35;
    state.alert_level = 2;
    sendCommand({ command: 'SIM_DEMO_SCENARIO_2' });
    playTone(880, 'triangle', 0.25);
  } else if (n === 3) {
    setProfile('HEART_FAILURE');
    state.drank = 1050;
    sendCommand({ command: 'SIM_DEMO_SCENARIO_3' });
    addChartPoint(state.drank);
  }
  updateUI();
}

function ackEmergency() {
  document.getElementById('modal').classList.remove('active');
  log('Bác sĩ/Caregiver đã xác nhận can thiệp báo động vượt trần.', 'info');
}

// Logger
function log(msg, type = 'info') {
  const box = document.getElementById('log-box');
  if (!box) return;
  const time = new Date().toTimeString().split(' ')[0];
  const line = document.createElement('div');
  line.className = `log-line ${type}`;
  line.innerText = `[${time}] ${msg}`;
  box.insertBefore(line, box.firstChild);
}

function clearLog() {
  const box = document.getElementById('log-box');
  if (box) box.innerHTML = '';
}

// Background timer
setInterval(() => {
  state.idle_sec += 1;
  updateUI();
}, 1000);

window.addEventListener('DOMContentLoaded', () => {
  initHistoryChart();
  updateUI();
  initMQTT();
});
