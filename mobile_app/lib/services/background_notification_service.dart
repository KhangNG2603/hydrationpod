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

class BackgroundNotificationService {
  static const String _fgChannelId = 'hydropod_fg';
  static const String _alertChannelId = 'hydropod_alerts';
  static const int _fgNotificationId = 888;
  static const String _mqttBroker = 'broker.emqx.io';
  static const int _mqttPort = 1883;
  static const String _topicTelemetry = 'smartbottle/HYDROPOD_01/telemetry';

  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

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
          _fgChannelId,
          'Theo dõi bình nước chạy ngầm',
          description: 'Giữ kết nối MQTT theo dõi bình nước trong nền',
          importance: Importance.low,
        ),
      );
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          _alertChannelId,
          'Cảnh báo & Nhắc uống nước',
          description: 'Thông báo nhắc uống nước, hết nước và cảnh báo y tế',
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
        ),
      );
    }

    final bgService = FlutterBackgroundService();
    await bgService.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: true,
        isForegroundMode: true,
        notificationChannelId: _fgChannelId,
        initialNotificationTitle: 'Smart Hydration Pod',
        initialNotificationContent: 'Đang theo dõi bình nước qua MQTT...',
        foregroundServiceNotificationId: _fgNotificationId,
        foregroundServiceTypes: [AndroidForegroundType.dataSync],
      ),
      iosConfiguration: IosConfiguration(autoStart: false),
    );
    await bgService.startService();
  }

  @pragma('vm:entry-point')
  static Future<void> onStart(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _notifications.initialize(
      settings: const InitializationSettings(android: androidInit),
    );

    String lastSafety = 'NORMAL';
    int lastAlertLevel = 0;
    bool wasEmpty = false;
    DateTime? lastAlertTime;

    Future<void> showAlert({
      required int id,
      required String title,
      required String body,
    }) async {
      await _notifications.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _alertChannelId,
            'Cảnh báo & Nhắc uống nước',
            channelDescription:
                'Thông báo nhắc uống nước, hết nước và cảnh báo y tế',
            importance: Importance.high,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
          ),
        ),
      );
    }

    void handleTelemetry(TelemetryModel t) {
      if (service is AndroidServiceInstance) {
        service.setForegroundNotificationInfo(
          title: 'Smart Hydration Pod • ${t.drankTodayMl}/${t.goalMl} ml',
          content:
              'Trong bình: ${t.bottleMl} ml • Pin: ${t.batterySoc}% • ${t.profile}',
        );
      }

      final now = DateTime.now();
      final cooldownPassed =
          lastAlertTime == null ||
          now.difference(lastAlertTime!).inSeconds >= 60;

      // 1. Medical safety margin alerts
      if (t.safetyStatus != lastSafety ||
          (t.safetyStatus != 'NORMAL' && cooldownPassed)) {
        if (t.safetyStatus == 'EMERGENCY_OVERCAP') {
          showAlert(
            id: 101,
            title: '🚨 KHẨN CẤP: Vượt trần nạp dịch!',
            body:
                'Đã uống ${t.drankTodayMl}/${t.hardCapMl} ml. Ngừng uống ngay và kiểm tra bệnh nhân!',
          );
          lastAlertTime = now;
        } else if (t.safetyStatus == 'DANGER_RED') {
          showAlert(
            id: 102,
            title: '🔴 Cảnh báo nguy hiểm (≥ 90% trần)',
            body:
                'Đã nạp ${t.drankTodayMl}/${t.hardCapMl} ml. Cần hạn chế uống thêm.',
          );
          lastAlertTime = now;
        } else if (t.safetyStatus == 'APPROACH_YELLOW') {
          showAlert(
            id: 103,
            title: '🟡 Tiệm cận hạn mức (≥ 80% trần)',
            body: 'Đã nạp ${t.drankTodayMl}/${t.hardCapMl} ml. Hãy uống chậm lại.',
          );
          lastAlertTime = now;
        }
      }
      lastSafety = t.safetyStatus;

      // 2. Idle hydration reminder alerts
      if (t.alertLevel >= 1 &&
          (t.alertLevel != lastAlertLevel || cooldownPassed)) {
        showAlert(
          id: 104,
          title: '💧 Nhắc nhở uống nước (Cấp ${t.alertLevel})',
          body:
              'Bạn chưa uống nước trong ${t.idleSec}s. Tiến độ hôm nay: ${t.drankTodayMl}/${t.goalMl} ml.',
        );
        lastAlertTime = now;
      }
      lastAlertLevel = t.alertLevel;

      // 3. Empty bottle alert
      if (t.isEmpty && !wasEmpty) {
        showAlert(
          id: 105,
          title: '🚰 Bình nước sắp cạn (${t.bottleMl} ml)',
          body: 'Hãy châm thêm nước vào bình để tiếp tục theo dõi.',
        );
      }
      wasEmpty = t.isEmpty;
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
