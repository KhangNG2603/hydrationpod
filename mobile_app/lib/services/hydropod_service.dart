import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/telemetry_model.dart';
import 'background_notification_service.dart';

class HydrationPoint {
  final DateTime time;
  final double drankMl;
  const HydrationPoint(this.time, this.drankMl);
}

class HydropodService extends ChangeNotifier {
  static const String mqttBroker = 'broker.emqx.io';
  static const int mqttPort = 1883;
  static const int mqttTlsPort = 8883;
  static const bool useTls = false; // Set true when connecting to local TLS broker
  static const String _historyStorageKey = 'hydropod_history_v1';
  static const String topicTelemetry = 'smartbottle/HYDROPOD_01/telemetry';
  static const String topicControl = 'smartbottle/HYDROPOD_01/control';

  String _apiBaseUrl;
  TelemetryModel _telemetry = const TelemetryModel();
  final List<HydrationPoint> _history = [];
  bool _isMqttConnected = false;
  bool _isServerConnected = false;
  bool _isEmergencyDismissed = false;
  MqttServerClient? _mqttClient;
  Timer? _pollTimer;

  HydropodService({String? customApiUrl})
      : _apiBaseUrl = customApiUrl ?? 'http://localhost:8000' {
    initConnections();
  }

  TelemetryModel get telemetry => _telemetry;
  List<HydrationPoint> get history => List.unmodifiable(_history);
  bool get isMqttConnected => _isMqttConnected;
  bool get isServerConnected => _isServerConnected;
  bool get isEmergencyDismissed => _isEmergencyDismissed;
  String get apiBaseUrl => _apiBaseUrl;

  double get ratePerHourMl {
    if (_history.length < 2) return 0.0;
    final first = _history.first;
    final last = _history.last;
    final hours = last.time.difference(first.time).inSeconds / 3600.0;
    if (hours <= 0.01) return 0.0;
    final delta = (last.drankMl - first.drankMl).clamp(0.0, 10000.0);
    return delta / hours;
  }

  String get trendSummary {
    final t = _telemetry;
    if (t.hardCapMl > 0 && t.drankTodayMl >= t.hardCapMl * 0.85) {
      return 'Cận trần y tế (${t.drankTodayMl.toInt()}/${t.hardCapMl.toInt()} ml)';
    }
    if (t.idleSec >= 1800) {
      return 'Nhàn rỗi lâu (${t.idleSec ~/ 60} phút chưa uống)';
    }
    if (t.drankTodayMl >= t.goalMl && t.goalMl > 0) {
      return 'Đã đạt mục tiêu ngày';
    }
    return 'Nhịp uống ổn định (${ratePerHourMl.toInt()} ml/h)';
  }

  void updateApiBaseUrl(String newUrl) {
    _apiBaseUrl = newUrl.trim().replaceAll(RegExp(r'/$'), '');
    fetchTelemetryRest();
    notifyListeners();
  }

  Future<void> initConnections() async {
    await _loadHistory();
    await fetchTelemetryRest();
    _startPolling();
    _connectMqtt();
  }

  Future<void> _loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_historyStorageKey);
      if (raw == null || raw.isEmpty) return;
      final list = jsonDecode(raw) as List<dynamic>;
      _history.clear();
      for (final item in list) {
        final map = item as Map<String, dynamic>;
        _history.add(
          HydrationPoint(
            DateTime.fromMillisecondsSinceEpoch((map['t'] as num).toInt()),
            (map['v'] as num).toDouble(),
          ),
        );
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _saveHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(
        _history
            .map((p) => {'t': p.time.millisecondsSinceEpoch, 'v': p.drankMl})
            .toList(),
      );
      await prefs.setString(_historyStorageKey, encoded);
    } catch (_) {}
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      fetchTelemetryRest();
    });
  }

  Future<void> fetchTelemetryRest() async {
    try {
      final response = await http
          .get(Uri.parse('$_apiBaseUrl/api/telemetry'))
          .timeout(const Duration(seconds: 2));
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        _updateTelemetry(TelemetryModel.fromJson(data));
        _isServerConnected = true;
      }
    } catch (_) {
      _isServerConnected = false;
      notifyListeners();
    }
  }

  Future<void> _connectMqtt() async {
    if (kIsWeb) return; // On Web, HTTP REST polling handles synchronization
    final clientId =
        'FlutterPatient_${DateTime.now().millisecondsSinceEpoch % 100000}';
    _mqttClient = MqttServerClient.withPort(
      mqttBroker,
      clientId,
      useTls ? mqttTlsPort : mqttPort,
    );
    _mqttClient!.secure = useTls;
    _mqttClient!.keepAlivePeriod = 30;
    _mqttClient!.autoReconnect = true;
    _mqttClient!.resubscribeOnAutoReconnect = true;
    _mqttClient!.logging(on: false);

    _mqttClient!.onConnected = () {
      _isMqttConnected = true;
      _mqttClient!.subscribe(topicTelemetry, MqttQos.atMostOnce);
      notifyListeners();
    };

    _mqttClient!.onDisconnected = () {
      _isMqttConnected = false;
      notifyListeners();
    };

    try {
      await _mqttClient!.connect();
      _mqttClient!.updates?.listen((List<MqttReceivedMessage<MqttMessage>> c) {
        final recMess = c[0].payload as MqttPublishMessage;
        final payloadStr =
            MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
        try {
          final Map<String, dynamic> jsonMap = jsonDecode(payloadStr);
          _updateTelemetry(TelemetryModel.fromJson(jsonMap));
        } catch (_) {}
      });
    } catch (_) {
      _isMqttConnected = false;
      notifyListeners();
    }
  }

  void _updateTelemetry(TelemetryModel next) {
    // Re-arm emergency dialog if patient drops back to safe state
    final isOvercap = next.safetyStatus == 'EMERGENCY_OVERCAP' ||
        (next.hardCapMl > 0 && next.drankTodayMl >= next.hardCapMl);
    if (!isOvercap) {
      _isEmergencyDismissed = false;
    }
    if (_history.isEmpty ||
        (_history.last.drankMl - next.drankTodayMl).abs() >= 1.0) {
      _history.add(HydrationPoint(DateTime.now(), next.drankTodayMl));
      if (_history.length > 30) {
        _history.removeAt(0);
      }
      _saveHistory();
    }
    _telemetry = next;
    BackgroundNotificationService.handleTelemetryAlert(next);
    notifyListeners();
  }

  void _publishMqttJson(Map<String, dynamic> payload) {
    if (_mqttClient != null && _isMqttConnected) {
      final builder = MqttClientPayloadBuilder();
      builder.addString(jsonEncode(payload));
      _mqttClient!.publishMessage(
        topicControl,
        MqttQos.atMostOnce,
        builder.payload!,
      );
    }
  }

  /// Patient records a sip / drink (+150ml default)
  Future<void> drinkWater([int amountMl = 150]) async {
    _publishMqttJson({'target': 'drink', 'amount': amountMl});
    try {
      await http.post(
        Uri.parse('$_apiBaseUrl/api/drink'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'amount_ml': amountMl}),
      );
      await fetchTelemetryRest();
    } catch (_) {}
  }

  /// Patient refills the water bottle (+350ml default)
  Future<void> refillBottle([int amountMl = 350]) async {
    _publishMqttJson({'target': 'refill', 'amount': amountMl});
    try {
      await http.post(
        Uri.parse('$_apiBaseUrl/api/refill'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'amount_ml': amountMl}),
      );
      await fetchTelemetryRest();
    } catch (_) {}
  }

  /// Patient triggers Find Pod (vibration + buzzer) or haptic test on the bottle
  Future<void> testVibration([
    int durationMs = 500,
    bool withBuzzer = true,
  ]) async {
    final pattern = withBuzzer ? 'FIND' : 'CUSTOM';
    _publishMqttJson({
      'target': 'vibrate',
      'duration_ms': durationMs,
      'pattern': pattern,
      'with_buzzer': withBuzzer,
    });
    try {
      await http.post(
        Uri.parse('$_apiBaseUrl/api/vibrate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'duration_ms': durationMs,
          'pattern': pattern,
          'with_buzzer': withBuzzer,
        }),
      );
      await fetchTelemetryRest();
    } catch (_) {}
  }

  /// Patient changes reminder ringtone melody on the bottle
  Future<void> setRingtone(String tone) async {
    _publishMqttJson({'target': 'ringtone', 'tone': tone, 'preview': true});
    try {
      await http.post(
        Uri.parse('$_apiBaseUrl/api/ringtone'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'ringtone': tone}),
      );
      await fetchTelemetryRest();
    } catch (_) {}
  }

  /// Update medical profile & hard cap from mobile Settings
  Future<void> setProfile(String profile, {int hardCap = 0}) async {
    _publishMqttJson({
      'target': 'profile',
      'mode': profile,
      'hard_cap': hardCap,
    });
    try {
      await http.post(
        Uri.parse('$_apiBaseUrl/api/profile'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'profile': profile, 'hard_cap': hardCap}),
      );
      await fetchTelemetryRest();
    } catch (_) {}
  }

  /// Patient acknowledges / silences or unmutes the active buzzer alarm
  Future<void> acknowledgeAlarm() async {
    _isEmergencyDismissed = true;
    notifyListeners();
    _publishMqttJson({'target': 'alarm', 'action': 'MUTE'});
    try {
      await http
          .post(
            Uri.parse('$_apiBaseUrl/api/alarm'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'action': 'MUTE'}),
          )
          .timeout(const Duration(seconds: 2));
      await fetchTelemetryRest();
    } catch (_) {}
  }

  /// Toggle buzzer mute state directly from mobile
  Future<void> toggleMute() async {
    final action = _telemetry.isMuted ? 'UNMUTE' : 'MUTE';
    if (action == 'MUTE') {
      _isEmergencyDismissed = true;
      notifyListeners();
    }
    _publishMqttJson({'target': 'alarm', 'action': action});
    try {
      await http
          .post(
            Uri.parse('$_apiBaseUrl/api/alarm'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'action': action}),
          )
          .timeout(const Duration(seconds: 2));
      await fetchTelemetryRest();
    } catch (_) {}
  }

  /// Reset daily hydration counters directly via MQTT + REST
  Future<void> resetDay() async {
    _history.clear();
    _saveHistory();
    _isEmergencyDismissed = false;
    notifyListeners();
    _publishMqttJson({'target': 'reset'});
    try {
      await http
          .post(
            Uri.parse('$_apiBaseUrl/api/reset'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({}),
          )
          .timeout(const Duration(seconds: 2));
      await fetchTelemetryRest();
    } catch (_) {}
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _mqttClient?.disconnect();
    super.dispose();
  }
}

