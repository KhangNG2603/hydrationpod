import 'package:flutter_test/flutter_test.dart';
import 'package:hydropod_patient_app/models/telemetry_model.dart';

void main() {
  test('TelemetryModel parses ESP32 JSON and detects empty bottle', () {
    final model = TelemetryModel.fromJson({
      'device_id': 'HYDROPOD_01',
      'drank_today_ml': 600,
      'bottle_ml': 35,
      'goal_ml': 2000,
      'hard_cap_ml': 1000,
      'profile': 'HEART_FAILURE',
      'safety_status': 'SAFE_GREEN',
      'ringtone': 'MELODIC',
    });

    expect(model.drankTodayMl, 600.0);
    expect(model.bottleMl, 35.0);
    expect(model.isEmpty, true);
    expect(model.effectiveTargetMl, 1000.0);
    expect(model.remainingSafeMl, 400.0);
  });
}
