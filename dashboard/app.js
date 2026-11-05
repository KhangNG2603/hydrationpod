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
  vibration_motor: 0,
  is_alarm_muted: false,
  user_role: 'caregiver', // 'caregiver' or 'patient'
  is_mqtt_connected: false,
  is_emergency_acked: false,
  has_alerted_empty: false,
  ringtone: localStorage.getItem('hydropod_ringtone') || 'CHIME',
  custom_mp3_data: localStorage.getItem('hydropod_custom_mp3') || '',
  custom_mp3_name: localStorage.getItem('hydropod_custom_mp3_name') || ''
};

// Audio Synthesizer
let audioCtx = null;
function initAudio() {
  if (!audioCtx) audioCtx = new (window.AudioContext || window.webkitAudioContext)();
}

function playTone(freq, type = 'sine', dur = 0.15) {
  if (state.is_alarm_muted) return;

  // If user selected Custom MP3 and file is loaded, play MP3
  if (state.ringtone === 'CUSTOM' && (state.custom_mp3_data || state.has_custom_mp3)) {
    playRingtoneMelody('CUSTOM');
    return;
  }

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

// Play distinctive melody based on chosen ringtone style
function playRingtoneMelody(style) {
  if (state.is_alarm_muted) return;

  // Custom MP3 audio playback
  if (style === 'CUSTOM') {
    const audioPlayer = document.getElementById('custom-audio-player');
    if (audioPlayer) {
      if (state.custom_mp3_data) {
        audioPlayer.src = state.custom_mp3_data;
      } else {
        audioPlayer.src = '/custom_alarm.mp3';
      }
      audioPlayer.currentTime = 0;
      audioPlayer.play().catch(e => {
        console.warn('Custom MP3 audio play failed, falling back to chime:', e);
        playTone(1046, 'sine', 0.25);
      });
      return;
    }
  }

  try {
    initAudio();
    if (!audioCtx) return;
    const now = audioCtx.currentTime;

    if (style === 'MELODIC') {
      // 3 melodic notes C5 (523) -> E5 (659) -> G5 (784)
      [523, 659, 784].forEach((f, i) => {
        const osc = audioCtx.createOscillator();
        const gain = audioCtx.createGain();
        osc.type = 'triangle';
        osc.frequency.setValueAtTime(f, now + i * 0.12);
        gain.gain.setValueAtTime(0.14, now + i * 0.12);
        gain.gain.exponentialRampToValueAtTime(0.01, now + i * 0.12 + 0.15);
        osc.connect(gain);
        gain.connect(audioCtx.destination);
        osc.start(now + i * 0.12);
        osc.stop(now + i * 0.12 + 0.15);
      });
    } else if (style === 'DIGITAL') {
      // High-tech staccato double-beep 2093Hz
      [0, 0.08].forEach(delay => {
        const osc = audioCtx.createOscillator();
        const gain = audioCtx.createGain();
        osc.type = 'square';
        osc.frequency.setValueAtTime(2093, now + delay);
        gain.gain.setValueAtTime(0.08, now + delay);
        gain.gain.exponentialRampToValueAtTime(0.01, now + delay + 0.05);
        osc.connect(gain);
        gain.connect(audioCtx.destination);
        osc.start(now + delay);
        osc.stop(now + delay + 0.05);
      });
    } else if (style === 'SIREN') {
      // Sweeping medical siren tone 1400Hz -> 2400Hz
      const osc = audioCtx.createOscillator();
      const gain = audioCtx.createGain();
      osc.type = 'sawtooth';
      osc.frequency.setValueAtTime(1400, now);
      osc.frequency.linearRampToValueAtTime(2400, now + 0.22);
      gain.gain.setValueAtTime(0.10, now);
      gain.gain.exponentialRampToValueAtTime(0.01, now + 0.25);
      osc.connect(gain);
      gain.connect(audioCtx.destination);
      osc.start(now);
      osc.stop(now + 0.25);
    } else {
      // CHIME (Default gentle two-tone chime 784Hz -> 1046Hz)
      [784, 1046].forEach((f, i) => {
        const osc = audioCtx.createOscillator();
        const gain = audioCtx.createGain();
        osc.type = 'sine';
        osc.frequency.setValueAtTime(f, now + i * 0.14);
        gain.gain.setValueAtTime(0.15, now + i * 0.14);
        gain.gain.exponentialRampToValueAtTime(0.01, now + i * 0.14 + 0.18);
        osc.connect(gain);
        gain.connect(audioCtx.destination);
        osc.start(now + i * 0.14);
        osc.stop(now + i * 0.14 + 0.18);
      });
    }
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
  if (data.vibration_motor !== undefined) state.vibration_motor = data.vibration_motor;
  if (data.ringtone !== undefined) state.ringtone = data.ringtone;

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
  
  // Empty Bottle / Refill Notification
  const bBadge = document.getElementById('bottle-refill-badge');
  const bCard = document.getElementById('card-bottle');
  if (state.bottle <= 40) {
    if (bBadge) bBadge.style.display = 'block';
    if (bCard) bCard.style.borderColor = 'rgba(245, 158, 11, 0.7)';
    if (!state.has_alerted_empty) {
      state.has_alerted_empty = true;
      log('⚠️ [BÌNH CẠN NƯỚC]: Lượng nước trong bình chỉ còn ' + Math.round(state.bottle) + 'ml! Vui lòng châm thêm nước (Refill).', 'warn');
      playTone(700, 'triangle', 0.15);
      setTimeout(() => playTone(900, 'sine', 0.2), 180);
    }
  } else {
    if (bBadge) bBadge.style.display = 'none';
    if (bCard) bCard.style.borderColor = '';
    state.has_alerted_empty = false;
  }

  document.getElementById('val-idle').innerHTML = `${state.idle_sec} <small>giây</small>`;
  document.getElementById('val-bat').innerHTML = `${state.battery_soc} <small>%</small>`;

  // Visual Water Reservoir Animation (HX711 Load Cell)
  const resFluid = document.getElementById('res-fluid');
  if (resFluid) {
    const fluidPct = Math.max(0, Math.min(100, (state.bottle / 500) * 100));
    resFluid.style.height = fluidPct + '%';
    if (state.bottle <= 40) {
      resFluid.style.background = 'linear-gradient(180deg, #f59e0b 0%, #d97706 100%)';
    } else {
      resFluid.style.background = 'linear-gradient(180deg, #38bdf8 0%, #0284c7 100%)';
    }
  }

  // Battery bar fill
  const batFill = document.getElementById('bat-fill');
  if (batFill) {
    batFill.style.width = Math.max(0, Math.min(100, state.battery_soc)) + '%';
    batFill.style.background = state.battery_soc > 20 ? 'var(--green)' : 'var(--red)';
  }

  // Idle status text
  const idleInfo = document.getElementById('idle-status-text');
  if (idleInfo) {
    if (state.alert_level === 3) idleInfo.innerText = '🔴 Quá hạn nghiêm trọng';
    else if (state.alert_level === 2) idleInfo.innerText = '🟡 Cảnh báo Cấp 2';
    else if (state.alert_level === 1) idleInfo.innerText = '🔵 Nhắc nhở Cấp 1';
    else idleInfo.innerText = '🟢 Hoạt động bình thường';
  }

  // Haptic Vibration Card Visualizer
  const vibeEl = document.getElementById('val-vibe');
  const vibeCard = document.getElementById('card-vibe');
  if (vibeEl && vibeCard) {
    if (state.vibration_motor === 1 || state.vibration_motor === true) {
      vibeEl.innerText = 'Đang Rung 📳';
      vibeEl.style.color = '#f59e0b';
      vibeCard.classList.add('vibrating');
    } else {
      vibeEl.innerText = 'Sẵn sàng';
      vibeEl.style.color = '#fff';
      vibeCard.classList.remove('vibrating');
    }
  }

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
      fill.style.background = 'var(--red)';
      document.getElementById('m-drank').innerText = Math.round(state.drank);
      document.getElementById('m-cap').innerText = Math.round(state.cap);

      if (!state.is_emergency_acked) {
        tag.innerText = '🚨 BÁO ĐỘNG VƯỢT TRẦN';
        document.getElementById('modal').classList.add('active');
        if (!state.is_alarm_muted) {
          playTone(1500, 'sawtooth', 0.3);
        }
      } else {
        tag.innerText = '🚨 ĐÃ CAN THIỆP Y TẾ';
        document.getElementById('modal').classList.remove('active');
      }
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

  // Update ringtone buttons active state
  document.querySelectorAll('.btn-tone').forEach(b => b.classList.remove('active'));
  const toneMap = {
    'CHIME': 'tone-chime',
    'MELODIC': 'tone-melodic',
    'DIGITAL': 'tone-digital',
    'SIREN': 'tone-siren',
    'CUSTOM': 'tone-custom'
  };
  const activeToneBtn = document.getElementById(toneMap[state.ringtone] || 'tone-chime');
  if (activeToneBtn) activeToneBtn.classList.add('active');

  // Update Custom MP3 filename labels
  const mp3Lbl = document.getElementById('custom-mp3-label');
  const mp3Disp = document.getElementById('mp3-display-name');
  if (state.custom_mp3_name) {
    if (mp3Lbl) mp3Lbl.innerText = state.custom_mp3_name;
    if (mp3Disp) mp3Disp.innerText = '🎵 ' + state.custom_mp3_name;
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
  state.is_emergency_acked = false;
  state.is_alarm_muted = false;
  const btn = document.getElementById('btn-mute');
  const txt = document.getElementById('txt-mute');
  if (btn && txt) {
    btn.classList.remove('active');
    txt.innerText = 'Tắt Còi Báo Động';
  }
  sendCommand({ target: 'reset' });
  addChartPoint(0);
  updateUI();
}

function testVibration() {
  log('📳 [CLOUD LỆNH]: Kích hoạt kiểm thử bộ rung xúc giác (300ms)...', 'info');
  playTone(800, 'sine', 0.12);
  sendCommand({ target: 'vibrate', duration_ms: 300 });
}

function refillBottle(amount = 350) {
  state.bottle = Math.min(500, state.bottle + amount);
  state.has_alerted_empty = false;
  log(`💧 [CHÂM NƯỚC]: Đã nạp thêm +${amount}ml nước vào bình (Tổng bình: ${Math.round(state.bottle)}ml).`, 'info');
  playTone(900, 'sine', 0.15);
  setTimeout(() => playTone(1200, 'sine', 0.2), 150);
  sendCommand({ target: 'refill', amount: amount });
  updateUI();
}

// --- RINGTONE STYLE HANDLERS (Tùy biến tiếng chuông) ---
function selectRingtone(tone) {
  state.ringtone = tone;
  localStorage.setItem('hydropod_ringtone', tone);
  updateUI();
  playRingtoneMelody(tone);
  log(`🔔 [ĐỔI TIẾNG CHUÔNG]: Đã đổi kiểu chuông sang ${tone}`, 'info');
  sendCommand({ target: 'ringtone', tone: tone });
}

function previewSelectedRingtone() {
  playRingtoneMelody(state.ringtone);
  log(`🔊 [NGHE THỬ CHUÔNG]: Đang phát chuông ${state.ringtone}...`, 'info');
  sendCommand({ target: 'ringtone', tone: state.ringtone, preview: true });
}

// Upload & Process Custom MP3 Audio File
function handleMp3Upload(event) {
  const file = event.target.files[0];
  if (!file) return;

  if (!file.type.includes('audio') && !file.name.toLowerCase().endsWith('.mp3')) {
    alert('Vui lòng chọn file âm thanh có định dạng .mp3!');
    return;
  }

  log(`⏳ [TẢI ÂM THANH]: Đang xử lý file ${file.name} (${Math.round(file.size / 1024)} KB)...`, 'info');

  const reader = new FileReader();
  reader.onload = function(e) {
    const dataUrl = e.target.result;
    state.custom_mp3_data = dataUrl;
    state.custom_mp3_name = file.name;
    localStorage.setItem('hydropod_custom_mp3', dataUrl);
    localStorage.setItem('hydropod_custom_mp3_name', file.name);

    // Upload to local server.py
    fetch('/api/upload_audio', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ filename: file.name, data: dataUrl })
    }).then(res => res.json()).then(res => {
      log(`✅ [ĐÃ LƯU MP3]: File ${file.name} đã được lưu làm chuông báo động!`, 'ack');
    }).catch(() => {
      log(`ℹ️ [LƯU CỤC BỘ]: File ${file.name} đã được lưu trên trình duyệt!`, 'info');
    });

    selectRingtone('CUSTOM');
  };
  reader.readAsDataURL(file);
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
    state.is_emergency_acked = false;
    state.is_alarm_muted = false;
    const btn = document.getElementById('btn-mute');
    const txt = document.getElementById('txt-mute');
    if (btn && txt) {
      btn.classList.remove('active');
      txt.innerText = 'Tắt Còi Báo Động';
    }
    sendCommand({ command: 'SIM_DEMO_SCENARIO_3' });
    addChartPoint(state.drank);
  }
  updateUI();
}

function ackEmergency() {
  state.is_emergency_acked = true;
  state.is_alarm_muted = true;
  document.getElementById('modal').classList.remove('active');

  const btn = document.getElementById('btn-mute');
  const txt = document.getElementById('txt-mute');
  if (btn && txt) {
    btn.classList.add('active');
    txt.innerText = 'Đã Tắt Chuông Báo';
  }

  log('👨‍⚕️ Bác sĩ / Điều dưỡng đã xác nhận can thiệp báo động! Đã tắt còi báo khẩn cấp trên phần cứng ESP32.', 'info');
  sendCommand({ target: 'alarm', action: 'MUTE' });
  updateUI();
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
