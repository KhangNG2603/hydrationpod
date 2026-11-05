class TelemetryModel {
  final String deviceId;
  final double drankTodayMl;
  final double bottleMl;
  final double goalMl;
  final double hardCapMl;
  final double progressPct;
  final int idleSec;
  final int batterySoc;
  final String safetyStatus;
  final int alertLevel;
  final String profile;
  final String ringtone;
  final bool vibrationActive;
  final String vibrationMode;
  final bool isEmpty;
  final bool isMuted;
  final String lastEvent;

  const TelemetryModel({
    this.deviceId = 'HYDROPOD_01',
    this.drankTodayMl = 0.0,
    this.bottleMl = 500.0,
    this.goalMl = 2000.0,
    this.hardCapMl = 0.0,
    this.progressPct = 0.0,
    this.idleSec = 0,
    this.batterySoc = 85,
    this.safetyStatus = 'SAFE_GREEN',
    this.alertLevel = 0,
    this.profile = 'STANDARD',
    this.ringtone = 'CHIME',
    this.vibrationActive = false,
    this.vibrationMode = 'IDLE',
    this.isEmpty = false,
    this.isMuted = false,
    this.lastEvent = 'System Ready',
  });

  factory TelemetryModel.fromJson(Map<String, dynamic> json) {
    final drank = (json['drank_today_ml'] ?? json['v0'] ?? 0).toDouble();
    final bottle = (json['bottle_ml'] ?? json['v1'] ?? 500).toDouble();
    final goal = (json['goal_ml'] ?? 2000).toDouble();
    final cap = (json['hard_cap_ml'] ?? 0).toDouble();
    final target = cap > 0 ? cap : (goal > 0 ? goal : 2000.0);

    return TelemetryModel(
      deviceId: (json['device_id'] ?? 'HYDROPOD_01').toString(),
      drankTodayMl: drank,
      bottleMl: bottle,
      goalMl: goal,
      hardCapMl: cap,
      progressPct: json['progress_pct'] != null
          ? (json['progress_pct'] as num).toDouble()
          : (drank / target * 100.0).clamp(0.0, 200.0),
      idleSec: (json['idle_sec'] ?? json['v3'] ?? 0) as int,
      batterySoc: (json['battery_soc'] ?? json['v5'] ?? 85) as int,
      safetyStatus:
          (json['safety_status'] ?? json['v4'] ?? 'SAFE_GREEN').toString(),
      alertLevel: (json['alert_level'] ?? 0) as int,
      profile: (json['profile'] ?? json['v6'] ?? 'STANDARD').toString(),
      ringtone: (json['ringtone'] ?? 'CHIME').toString(),
      vibrationActive: json['vibration_active'] == true ||
          json['vibration_motor'] == 1,
      vibrationMode: (json['vibration_mode'] ?? 'IDLE').toString(),
      isEmpty: json['is_empty'] == true || bottle <= 40.0,
      isMuted: json['is_muted'] == true || json['v7'] == 1,
      lastEvent: (json['last_event'] ?? 'Connected').toString(),
    );
  }

  /// Target ml to display on patient ring (uses hardCapMl if medical cap is active)
  double get effectiveTargetMl => hardCapMl > 0 ? hardCapMl : goalMl;

  /// Remaining safe intake in ml
  double get remainingSafeMl =>
      (effectiveTargetMl - drankTodayMl).clamp(0.0, effectiveTargetMl);

  /// Bottle fill ratio (0.0 to 1.0 based on 500ml bottle capacity)
  double get bottleFillRatio => (bottleMl / 500.0).clamp(0.0, 1.0);

  /// Human-readable Vietnamese medical profile label for patient
  String get profileDisplayName {
    switch (profile.toUpperCase()) {
      case 'HEART_FAILURE':
        return 'Phác đồ Suy Tim / Thận (Giới hạn trần ${hardCapMl.toInt()} ml)';
      case 'GOUT':
      case 'KIDNEY_STONE':
        return 'Phác đồ Sỏi Thận / Gout (Tăng cường ${goalMl.toInt()} ml)';
      default:
        return 'Phác đồ Tiêu Chuẩn (${goalMl.toInt()} ml/ngày)';
    }
  }
}
