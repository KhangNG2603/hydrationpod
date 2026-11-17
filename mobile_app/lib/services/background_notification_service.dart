import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import '../models/telemetry_model.dart';

@pragma('vm:entry-point')
class BackgroundNotificationService {
  static const String _alertChannelId = 'hydropod_alerts';
  static const String _mqttBroker = 'broker.emqx.io';
  static const int _mqttPort = 1883;
  static const String _topicTelemetry = 'smartbottle/HYDROPOD_01/telemetry';

  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  static int _lastAlertLevel = 0;
  static DateTime? _lastAlertTime;

  static Future<void> showReminderAlert(TelemetryModel t) async {
    if (kIsWeb || !Platform.isAndroid) return;
    await _notifications.show(
      id: 104,
      title: 'Nhắc nhở uống nước (Cấp ${t.alertLevel})',
      body:
          'Bạn chưa uống nước trong ${t.idleSec}s. Tiến độ hôm nay: ${t.drankTodayMl.toInt()}/${t.goalMl.toInt()} ml.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _alertChannelId,
          'Nhắc nhở uống nước',
          channelDescription: 'Thông báo khi quên uống nước',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
        ),
      ),
    );
  }

  /// Show a phone notification when alert level reaches >= 2 (with 60s cooldown)
  static void handleTelemetryAlert(TelemetryModel t) {
    if (kIsWeb || !Platform.isAndroid) return;
    final now = DateTime.now();
    final cooldownPassed =
        _lastAlertTime == null ||
        now.difference(_lastAlertTime!).inSeconds >= 60;

    if (t.alertLevel >= 2 &&
        (t.alertLevel != _lastAlertLevel || cooldownPassed)) {
      _lastAlertTime = now;
      showReminderAlert(t);
    }
    _lastAlertLevel = t.alertLevel;
  }

  static Future<void> initialize() async {
    if (kIsWeb || !Platform.isAndroid) return;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _notifications.initialize(
      settings: const InitializationSettings(android: androidInit),
    );

    final androidPlugin = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidPlugin != null) {
      await androidPlugin.requestNotificationsPermission();
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          _alertChannelId,
          'Nhắc nhở uống nước',
          description: 'Thông báo khi quên uống nước',
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
        ),
      );
    }

    try {
      final bgService = FlutterBackgroundService();
      await bgService.configure(
        androidConfiguration: AndroidConfiguration(
          onStart: onStart,
          autoStart: true,
          isForegroundMode: false,
        ),
        iosConfiguration: IosConfiguration(autoStart: false),
      );
      await bgService.startService();
    } catch (_) {}
  }

  @pragma('vm:entry-point')
  static Future<void> onStart(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _notifications.initialize(
      settings: const InitializationSettings(android: androidInit),
    );

    int lastAlertLevel = 0;
    DateTime? lastAlertTime;

    void handleTelemetry(TelemetryModel t) {
      final now = DateTime.now();
      final cooldownPassed =
          lastAlertTime == null ||
          now.difference(lastAlertTime!).inSeconds >= 60;

      if (t.alertLevel >= 2 &&
          (t.alertLevel != lastAlertLevel || cooldownPassed)) {
        showReminderAlert(t);
        lastAlertTime = now;
      }
      lastAlertLevel = t.alertLevel;
    }

    final client = MqttServerClient(
      _mqttBroker,
      'FlutterBg_${DateTime.now().millisecondsSinceEpoch}',
    );
    client.port = _mqttPort;
    client.keepAlivePeriod = 30;
    client.autoReconnect = true;
    client.resubscribeOnAutoReconnect = true;
    client.logging(on: false);

    Future<void> connectMqtt() async {
      try {
        await client.connect();
        if (client.connectionStatus?.state == MqttConnectionState.connected) {
          client.subscribe(_topicTelemetry, MqttQos.atMostOnce);
          client.updates?.listen((events) {
            for (final msg in events) {
              if (msg.topic != _topicTelemetry) continue;
              final recMess = msg.payload as MqttPublishMessage;
              final payloadStr = MqttPublishPayload.bytesToStringAsString(
                recMess.payload.message,
              );
              try {
                final map = jsonDecode(payloadStr) as Map<String, dynamic>;
                handleTelemetry(TelemetryModel.fromJson(map));
              } catch (_) {}
            }
          });
        }
      } catch (_) {}
    }

    await connectMqtt();

    final reconnectTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (client.connectionStatus?.state != MqttConnectionState.connected) {
        connectMqtt();
      }
    });

    service.on('stopService').listen((_) {
      reconnectTimer.cancel();
      client.disconnect();
      service.stopSelf();
    });
  }
}
