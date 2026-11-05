import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import '../models/telemetry_model.dart';

class HydropodService extends ChangeNotifier {
  static const String mqttBroker = 'broker.emqx.io';
  static const int mqttPort = 1883;
  static const String topicTelemetry = 'smartbottle/HYDROPOD_01/telemetry';
  static const String topicControl = 'smartbottle/HYDROPOD_01/control';

  String _apiBaseUrl;
  TelemetryModel _telemetry = const TelemetryModel();
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
  bool get isMqttConnected => _isMqttConnected;
  bool get isServerConnected => _isServerConnected;
  bool get isEmergencyDismissed => _isEmergencyDismissed;
  String get apiBaseUrl => _apiBaseUrl;

  void updateApiBaseUrl(String newUrl) {
    _apiBaseUrl = newUrl.trim().replaceAll(RegExp(r'/$'), '');
    fetchTelemetryRest();
    notifyListeners();
  }

  Future<void> initConnections() async {
    await fetchTelemetryRest();
    _startPolling();
    _connectMqtt();
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
    _mqttClient = MqttServerClient.withPort(mqttBroker, clientId, mqttPort);
    _mqttClient!.keepAlivePeriod = 30;
    _mqttClient!.autoReconnect = true;
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
    _telemetry = next;
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

  /// Patient tests haptic vibration on the bottle (GPIO 5)
  Future<void> testVibration([int durationMs = 300]) async {
    _publishMqttJson({'target': 'vibrate', 'duration': durationMs});
    try {
      await http.post(
        Uri.parse('$_apiBaseUrl/api/vibrate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'duration_ms': durationMs}),
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

  /// Patient acknowledges / silences the active buzzer alarm
  Future<void> acknowledgeAlarm() async {
    _isEmergencyDismissed = true;
    notifyListeners();
    _publishMqttJson({'target': 'alarm', 'action': 'MUTE'});
    try {
      await http.post(
        Uri.parse('$_apiBaseUrl/api/alarm'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'MUTE'}),
      );
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

