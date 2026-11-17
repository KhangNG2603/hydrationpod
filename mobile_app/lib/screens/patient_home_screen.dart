// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import '../models/telemetry_model.dart';
import '../services/hydropod_service.dart';
import '../widgets/water_bottle_widget.dart';

class PatientHomeScreen extends StatefulWidget {
  final HydropodService service;

  const PatientHomeScreen({super.key, required this.service});

  @override
  State<PatientHomeScreen> createState() => _PatientHomeScreenState();
}

class _PatientHomeScreenState extends State<PatientHomeScreen> {
  int _currentIndex = 0;
  String? _draftProfile;
  double? _draftHardCap;

  HydropodService get service => widget.service;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final t = service.telemetry;
        final isOvercap = t.safetyStatus == 'EMERGENCY_OVERCAP' ||
            (t.hardCapMl > 0 && t.drankTodayMl >= t.hardCapMl);

        return Scaffold(
          backgroundColor: const Color(0xFF0B0D14),
          appBar: AppBar(
            backgroundColor: const Color(0xFF11141C),
            elevation: 0,
            titleSpacing: 16,
            title: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0EA5E9).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFF38BDF8).withValues(alpha: 0.4),
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
                margin: const EdgeInsets.only(top: 12, bottom: 12, right: 16),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (service.isServerConnected || service.isMqttConnected)
                      ? const Color(0xFF10B981).withValues(alpha: 0.15)
                      : const Color(0xFFF59E0B).withValues(alpha: 0.15),
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
            ],
          ),
          body: IndexedStack(
            index: _currentIndex,
            children: [
              // PAGE 0: HOME
              RefreshIndicator(
                onRefresh: service.fetchTelemetryRest,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (isOvercap)
                      _buildEmergencyBanner(t)
                    else if (t.isEmpty)
                      _buildEmptyBottleBanner()
                    else if (t.alertLevel >= 1)
                      _buildIdleReminderBanner(t),
                    _buildHydrationRingCard(t, isOvercap),
                    const SizedBox(height: 14),
                    _buildHardwareMetricsRow(t),
                    const SizedBox(height: 14),
                    WaterBottleWidget(
                      bottleMl: t.bottleMl,
                      isEmpty: t.isEmpty,
                      onQuickRefill: () => service.refillBottle(350),
                    ),
                    const SizedBox(height: 14),
                    _buildQuickActionsCard(t, isOvercap),
                    const SizedBox(height: 24),
                  ],
                ),
              ),

              // PAGE 1: HISTORY CHART & TREND
              ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildTrendCard(t),
                  const SizedBox(height: 14),
                  _buildHistoryTimelineCard(),
                  const SizedBox(height: 24),
                ],
              ),

              // PAGE 2: SETTINGS (Medical Directive + Ringtone + Reset)
              _buildSettingsPage(t),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            backgroundColor: const Color(0xFF11141C),
            indicatorColor: const Color(0xFF0EA5E9).withValues(alpha: 0.18),
            selectedIndex: _currentIndex,
            onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded, color: Color(0xFF38BDF8)),
                label: 'Trang chủ',
              ),
              NavigationDestination(
                icon: Icon(Icons.show_chart_rounded),
                selectedIcon: Icon(Icons.show_chart_rounded, color: Color(0xFF38BDF8)),
                label: 'Biểu đồ',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings_rounded, color: Color(0xFF38BDF8)),
                label: 'Cài đặt',
              ),
            ],
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
                  'Vượt hạn mức nước chỉ định',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
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
        color: const Color(0xFF3B0764).withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF43F5E)),
      ),
      child: Row(
        children: [
          const Icon(Icons.opacity_rounded, color: Color(0xFFF43F5E)),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Bình nước sắp cạn (≤ 40 ml). Hãy châm thêm nước để tiếp tục theo dõi',
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
                        Icons.medical_information_outlined,
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
                  color: ringColor.withValues(alpha: 0.15),
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
                        color: ringColor.withValues(alpha: 0.15),
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
                ? 'Đã vượt mức trần y tế. Ngưng nạp thêm nước'
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
                  onPressed: () => service.testVibration(500, true),
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
                    'Tìm bình',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: service.toggleMute,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: t.isMuted
                        ? const Color(0xFF4CC38A)
                        : const Color(0xFFF87171),
                    side: BorderSide(
                      color: t.isMuted
                          ? const Color(0xFF14532D)
                          : const Color(0xFF7F1D1D),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: Icon(
                    t.isMuted
                        ? Icons.notifications_active_outlined
                        : Icons.notifications_off_outlined,
                    size: 17,
                  ),
                  label: Text(
                    t.isMuted ? 'Bật lại còi' : 'Tắt còi nhắc',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
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
      {'id': 'CHIME', 'label': 'Chuông đôi'},
      {'id': 'MELODIC', 'label': 'Giai điệu'},
      {'id': 'DIGITAL', 'label': 'Bíp y tế'},
      {'id': 'SIREN', 'label': 'Còi khẩn'},
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF11141C),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E2430)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Âm báo nhắc uống nước',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFFA3A9B8),
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
                selectedColor: const Color(0xFF0EA5E9).withValues(alpha: 0.25),
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

  Widget _buildTrendCard(TelemetryModel t) {
    final pts = service.history;
    final values = pts.isEmpty
        ? <double>[0.0, t.drankTodayMl]
        : (pts.length == 1
            ? <double>[0.0, pts.first.drankMl]
            : pts.map((p) => p.drankMl).toList());
    final maxVal = values.fold<double>(
      t.goalMl > 0 ? t.goalMl : 2000.0,
      (a, b) => a > b ? a : b,
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF11141C),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E2430)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Biểu đồ lũy kế nạp dịch',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFA3A9B8),
                ),
              ),
              Text(
                '${service.ratePerHourMl.toInt()} ml/h',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF38BDF8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            service.trendSummary,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Color(0xFFEEF0F5),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 180,
            width: double.infinity,
            child: CustomPaint(
              painter: _HydrationChartPainter(
                values: values,
                maxY: maxVal,
                goalY: t.goalMl > 0 ? t.goalMl : 2000.0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTimelineCard() {
    final pts = service.history.reversed.toList();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF11141C),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E2430)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Lịch sử ghi nhận gần đây',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFFA3A9B8),
            ),
          ),
          const SizedBox(height: 10),
          if (pts.isEmpty)
            const Text(
              'Chưa có dữ liệu mới trong phiên này',
              style: TextStyle(fontSize: 12.5, color: Color(0xFF7A8296)),
            )
          else
            ...pts.take(12).map((p) {
              final hh = p.time.hour.toString().padLeft(2, '0');
              final mm = p.time.minute.toString().padLeft(2, '0');
              final ss = p.time.second.toString().padLeft(2, '0');
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$hh:$mm:$ss',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF7A8296),
                      ),
                    ),
                    Text(
                      '${p.drankMl.toInt()} ml',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFEEF0F5),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildSettingsPage(TelemetryModel t) {
    final currentProfile = _draftProfile ??
        (['STANDARD', 'HEART_FAILURE', 'GOUT'].contains(t.profile.toUpperCase())
            ? t.profile.toUpperCase()
            : 'STANDARD');
    final currentCap = _draftHardCap ??
        (t.hardCapMl > 0 ? t.hardCapMl.clamp(600, 2000).toDouble() : 1000.0);

    final profiles = [
      {'id': 'STANDARD', 'label': 'Tiêu chuẩn (2000 ml)'},
      {'id': 'HEART_FAILURE', 'label': 'Suy tim / Thận (Giới hạn trần)'},
      {'id': 'GOUT', 'label': 'Sỏi thận / Gout (2500 ml)'},
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF11141C),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF1E2430)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Điều chỉnh chỉ thị y tế',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFA3A9B8),
                ),
              ),
              const SizedBox(height: 10),
              ...profiles.map((item) {
                final isSelected = currentProfile == item['id'];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _draftProfile = item['id'];
                      });
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 11,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF0EA5E9).withValues(alpha: 0.16)
                            : const Color(0xFF0B0D14),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFF38BDF8)
                              : const Color(0xFF1E2430),
                        ),
                      ),
                      child: Text(
                        item['label']!,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isSelected
                              ? const Color(0xFF38BDF8)
                              : const Color(0xFFA3A9B8),
                        ),
                      ),
                    ),
                  ),
                );
              }),
              if (currentProfile == 'HEART_FAILURE') ...[
                const SizedBox(height: 6),
                Text(
                  'Trần cứng tối đa: ${currentCap.toInt()} ml/ngày',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFF87171),
                  ),
                ),
                Slider(
                  value: currentCap,
                  min: 600,
                  max: 2000,
                  divisions: 28,
                  activeColor: const Color(0xFFE5484D),
                  onChanged: (val) => setState(() => _draftHardCap = val),
                ),
              ],
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    await service.setProfile(
                      currentProfile,
                      hardCap: currentProfile == 'HEART_FAILURE'
                          ? currentCap.toInt()
                          : 0,
                    );
                    if (mounted) {
                      setState(() {
                        _draftProfile = null;
                        _draftHardCap = null;
                      });
                    }
                  },
                  child: const Text('Áp dụng chỉ thị y tế'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _buildRingtoneCard(t),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF11141C),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF1E2430)),
          ),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: service.resetDay,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFF87171),
                side: const BorderSide(color: Color(0xFF7F1D1D)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 17),
              label: const Text(
                'Đặt lại dữ liệu ngày (Reset)',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _HydrationChartPainter extends CustomPainter {
  final List<double> values;
  final double maxY;
  final double goalY;

  const _HydrationChartPainter({
    required this.values,
    required this.maxY,
    required this.goalY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const leftPad = 42.0;
    const rightPad = 8.0;
    const topPad = 10.0;
    const bottomPad = 14.0;

    final chartW = (size.width - leftPad - rightPad).clamp(10.0, size.width);
    final chartH = (size.height - topPad - bottomPad).clamp(10.0, size.height);
    final safeMax = maxY > 0 ? maxY : 2000.0;

    final gridPaint = Paint()
      ..color = const Color(0xFF1E2430)
      ..strokeWidth = 1;

    const labelStyle = TextStyle(
      color: Color(0xFF7A8296),
      fontSize: 10,
      fontWeight: FontWeight.w500,
    );

    // Draw 3 horizontal grid lines (0%, 50%, 100%)
    for (final frac in [0.0, 0.5, 1.0]) {
      final y = topPad + chartH * (1.0 - frac);
      canvas.drawLine(
        Offset(leftPad, y),
        Offset(leftPad + chartW, y),
        gridPaint,
      );
      final valTxt = '${(safeMax * frac).toInt()}';
      final tp = TextPainter(
        text: TextSpan(text: valTxt, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(leftPad - tp.width - 6, y - tp.height / 2));
    }

    // Draw line + area fill
    final points = <Offset>[];
    final count = values.length;
    for (int i = 0; i < count; i++) {
      final x = count == 1
          ? leftPad + chartW
          : leftPad + (chartW * i / (count - 1));
      final norm = (values[i] / safeMax).clamp(0.0, 1.0);
      final y = topPad + chartH * (1.0 - norm);
      points.add(Offset(x, y));
    }

    if (points.length >= 2) {
      final linePath = Path()..moveTo(points.first.dx, points.first.dy);
      for (int i = 1; i < points.length; i++) {
        linePath.lineTo(points[i].dx, points[i].dy);
      }

      final fillPath = Path.from(linePath)
        ..lineTo(points.last.dx, topPad + chartH)
        ..lineTo(points.first.dx, topPad + chartH)
        ..close();

      final fillPaint = Paint()
        ..color = const Color(0xFF0EA5E9).withValues(alpha: 0.14)
        ..style = PaintingStyle.fill;
      canvas.drawPath(fillPath, fillPaint);

      final linePaint = Paint()
        ..color = const Color(0xFF38BDF8)
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(linePath, linePaint);
    }

    final dotPaint = Paint()..color = const Color(0xFF38BDF8);
    for (final pt in points) {
      canvas.drawCircle(pt, 3.2, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _HydrationChartPainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.maxY != maxY ||
        oldDelegate.goalY != goalY;
  }
}

