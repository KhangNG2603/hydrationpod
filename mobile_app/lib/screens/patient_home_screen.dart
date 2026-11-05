import 'package:flutter/material.dart';
import '../models/telemetry_model.dart';
import '../services/hydropod_service.dart';
import '../widgets/water_bottle_widget.dart';

class PatientHomeScreen extends StatelessWidget {
  final HydropodService service;

  const PatientHomeScreen({super.key, required this.service});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final t = service.telemetry;
        final isOvercap = t.safetyStatus == 'EMERGENCY_OVERCAP' ||
            (t.hardCapMl > 0 && t.drankTodayMl >= t.hardCapMl);

        return Scaffold(
          backgroundColor: const Color(0xFF0B0F17),
          appBar: AppBar(
            backgroundColor: const Color(0xFF111927),
            elevation: 0,
            titleSpacing: 16,
            title: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0EA5E9).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFF38BDF8).withOpacity(0.4),
                    ),
                  ),
                  child: const Icon(
                    Icons.water_drop_rounded,
                    color: Color(0xFF38BDF8),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'HydraPod Patient',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFF8FAFC),
                        ),
                      ),
                      Text(
                        'Trợ lý nhắc uống nước thông minh',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              // Connection Status Chip
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (service.isServerConnected || service.isMqttConnected)
                      ? const Color(0xFF10B981).withOpacity(0.15)
                      : const Color(0xFFF59E0B).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.circle,
                      size: 8,
                      color:
                          (service.isServerConnected || service.isMqttConnected)
                              ? const Color(0xFF10B981)
                              : const Color(0xFFF59E0B),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      service.isMqttConnected
                          ? 'MQTT Live'
                          : (service.isServerConnected ? 'Synced' : 'Offline'),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: (service.isServerConnected ||
                                service.isMqttConnected)
                            ? const Color(0xFF10B981)
                            : const Color(0xFFF59E0B),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.tune_rounded, color: Color(0xFF94A3B8)),
                tooltip: 'Cấu hình kết nối Server',
                onPressed: () => _showServerDialog(context),
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: service.fetchTelemetryRest,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 1. Contextual Medical / Reminder Alert Banner
                if (isOvercap)
                  _buildEmergencyBanner(t)
                else if (t.isEmpty)
                  _buildEmptyBottleBanner()
                else if (t.alertLevel >= 1)
                  _buildIdleReminderBanner(t),

                // 2. Hero Daily Hydration Progress Card
                _buildHydrationRingCard(t, isOvercap),
                const SizedBox(height: 14),

                // 3. Hardware Status Strip (Idle timer, Battery, Haptic Motor)
                _buildHardwareMetricsRow(t),
                const SizedBox(height: 14),

                // 4. Visual Water Bottle Level (HX711 Load Cell)
                WaterBottleWidget(
                  bottleMl: t.bottleMl,
                  isEmpty: t.isEmpty,
                  onQuickRefill: () => service.refillBottle(350),
                ),
                const SizedBox(height: 14),

                // 5. Patient Quick Action Buttons
                _buildQuickActionsCard(t, isOvercap),
                const SizedBox(height: 14),

                // 6. Personal Ringtone Selector
                _buildRingtoneCard(t),
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmergencyBanner(TelemetryModel t) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF450A0A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEF4444), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Color(0xFFF87171)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'CẢNH BÁO Y TẾ: ĐÃ VƯỢT HẠN MỨC NƯỚC!',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFFECACA),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Bạn đã uống ${t.drankTodayMl.toInt()} ml (Vượt trần chỉ định ${t.hardCapMl.toInt()} ml của Bác sĩ). Vui lòng ngưng nạp thêm nước.',
            style: const TextStyle(fontSize: 12.5, color: Color(0xFFFCA5A5)),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: service.acknowledgeAlarm,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.volume_off_rounded, size: 18),
              label: const Text(
                'Đã hiểu & Tắt còi báo động',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyBottleBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF3B0764).withOpacity(0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF43F5E)),
      ),
      child: Row(
        children: [
          const Icon(Icons.Opacity_rounded, color: Color(0xFFF43F5E)),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Bình nước đã cạn (≤ 40ml)! Hãy châm thêm nước để tiếp tục theo dõi.',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFFFDA4AF),
              ),
            ),
          ),
          TextButton(
            onPressed: () => service.refillBottle(350),
            child: const Text(
              '+350ml',
              style: TextStyle(
                color: Color(0xFF38BDF8),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIdleReminderBanner(TelemetryModel t) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF451A03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF59E0B)),
      ),
      child: Row(
        children: [
          const Icon(Icons.notifications_active_rounded,
              color: Color(0xFFFBBF24)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Đã ${t.idleSec} giây bạn chưa uống nước (Nhắc nhở cấp ${t.alertLevel}). Hãy uống 1 ngụm nhỏ nhé!',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFFFDE68A),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHydrationRingCard(TelemetryModel t, bool isOvercap) {
    final target = t.effectiveTargetMl;
    final ratio = (t.drankTodayMl / target).clamp(0.0, 1.0);

    Color ringColor = const Color(0xFF0EA5E9);
    String statusText = 'AN TOÀN';
    if (isOvercap) {
      ringColor = const Color(0xFFEF4444);
      statusText = 'VƯỢT TRẦN Y TẾ';
    } else if (t.safetyStatus == 'DANGER_RED') {
      ringColor = const Color(0xFFF97316);
      statusText = 'SẮP CHẠM TRẦN (90%)';
    } else if (t.safetyStatus == 'APPROACH_YELLOW') {
      ringColor = const Color(0xFFF59E0B);
      statusText = 'TIỆM CẬN TRẦN (80%)';
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF111927),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        children: [
          // Doctor's Prescription Badge (Read-only for Patient)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.medical_Information_outlined,
                        size: 14,
                        color: Color(0xFF38BDF8),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          t.profileDisplayName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFE2E8F0),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: ringColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: ringColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Circular Progress Ring
          SizedBox(
            width: 175,
            height: 175,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 175,
                  height: 175,
                  child: CircularProgressIndicator(
                    value: ratio,
                    strokeWidth: 13,
                    backgroundColor: const Color(0xFF1E293B),
                    valueColor: AlwaysStoppedAnimation<Color>(ringColor),
                    strokeCap: StrokeCap.round,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${t.drankTodayMl.toInt()}',
                      style: const TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFFF8FAFC),
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '/ ${target.toInt()} ml',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: ringColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${t.progressPct.toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: ringColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            isOvercap
                ? '⚠️ Đã vượt mức trần y tế! Tuyệt đối không uống thêm.'
                : 'Còn có thể nạp an toàn hôm nay: ${t.remainingSafeMl.toInt()} ml',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isOvercap
                  ? const Color(0xFFF87171)
                  : const Color(0xFF94A3B8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHardwareMetricsRow(TelemetryModel t) {
    return Row(
      children: [
        Expanded(
          child: _metricTile(
            icon: Icons.timer_outlined,
            label: 'Chưa uống',
            value: '${t.idleSec}s',
            color: t.alertLevel >= 1
                ? const Color(0xFFF59E0B)
                : const Color(0xFF38BDF8),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _metricTile(
            icon: Icons.vibration_rounded,
            label: 'Mô-tơ Rung',
            value: t.vibrationActive ? 'Đang rung' : 'Sẵn sàng',
            color: t.vibrationActive
                ? const Color(0xFFF59E0B)
                : const Color(0xFF10B981),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _metricTile(
            icon: Icons.battery_charging_full_rounded,
            label: 'Pin bình',
            value: '${t.batterySoc}%',
            color: const Color(0xFF10B981),
          ),
        ),
      ],
    );
  }

  Widget _metricTile({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF111927),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: Color(0xFFF8FAFC),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionsCard(TelemetryModel t, bool isOvercap) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111927),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'THAO TÁC NHANH CHO BỆNH NHÂN',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => service.drinkWater(150),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0EA5E9),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.local_drink_rounded, size: 18),
                  label: const Text(
                    'Uống +150ml',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => service.refillBottle(350),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF38BDF8),
                    side: const BorderSide(color: Color(0xFF0284C7)),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
                  label: const Text(
                    'Châm +350ml',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => service.testVibration(300),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFBBF24),
                    side: const BorderSide(color: Color(0xFF78350F)),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.vibration_rounded, size: 17),
                  label: const Text(
                    'Tìm bình (Rung)',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: service.acknowledgeAlarm,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFF87171),
                    side: const BorderSide(color: Color(0xFF7F1D1D)),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.notifications_off_outlined, size: 17),
                  label: const Text(
                    'Tắt còi nhắc',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRingtoneCard(TelemetryModel t) {
    final tones = [
      {'id': 'CHIME', 'label': '🔔 Chuông Đôi'},
      {'id': 'MELODIC', 'label': '🎵 Giai Điệu'},
      {'id': 'DIGITAL', 'label': '📟 Bíp Y Tế'},
      {'id': 'SIREN', 'label': '🚨 Còi Khẩn'},
      {'id': 'CUSTOM', 'label': '🎧 Nhạc MP3'},
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111927),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'TÙY CHỈNH ÂM BÁO NHẮC UỐNG NƯỚC',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: tones.map((item) {
              final isSelected =
                  t.ringtone.toUpperCase() == item['id']!;
              return ChoiceChip(
                label: Text(item['label']!),
                selected: isSelected,
                onSelected: (_) => service.setRingtone(item['id']!),
                selectedColor: const Color(0xFF0EA5E9).withOpacity(0.25),
                backgroundColor: const Color(0xFF0B0F17),
                labelStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isSelected
                      ? const Color(0xFF38BDF8)
                      : const Color(0xFF94A3B8),
                ),
                side: BorderSide(
                  color: isSelected
                      ? const Color(0xFF38BDF8)
                      : const Color(0xFF1E293B),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  void _showServerDialog(BuildContext context) {
    final controller = TextEditingController(text: service.apiBaseUrl);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111927),
        title: const Text(
          'Cấu hình địa chỉ Server IoT',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'REST API URL (VD: http://10.0.2.2:8000)',
            labelStyle: TextStyle(color: Color(0xFF94A3B8)),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF334155)),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () {
              service.updateApiBaseUrl(controller.text);
              Navigator.pop(ctx);
            },
            child: const Text('Lưu & Kết nối'),
          ),
        ],
      ),
    );
  }
}

