import 'dart:math' as math;
import 'package:flutter/material.dart';

class WaterBottleWidget extends StatefulWidget {
  final double bottleMl;
  final double maxCapacityMl;
  final bool isEmpty;
  final VoidCallback onQuickRefill;

  const WaterBottleWidget({
    super.key,
    required this.bottleMl,
    this.maxCapacityMl = 500.0,
    required this.isEmpty,
    required this.onQuickRefill,
  });

  @override
  State<WaterBottleWidget> createState() => _WaterBottleWidgetState();
}

class _WaterBottleWidgetState extends State<WaterBottleWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _waveController;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _waveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fillRatio = (widget.bottleMl / widget.maxCapacityMl).clamp(0.0, 1.0);
    final isLow = widget.isEmpty || widget.bottleMl <= 40.0;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF111927),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isLow
              ? const Color(0xFFF43F5E).withOpacity(0.65)
              : const Color(0xFF1E293B),
          width: isLow ? 1.5 : 1.0,
        ),
      ),
      child: Row(
        children: [
          // Visual Bottle Vessel with Animated Wave
          SizedBox(
            width: 76,
            height: 146,
            child: Column(
              children: [
                // Bottle Cap
                Container(
                  width: 34,
                  height: 10,
                  decoration: BoxDecoration(
                    color: const Color(0xFF334155),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(4),
                    ),
                    border: Border.all(color: const Color(0xFF475569)),
                  ),
                ),
                const SizedBox(height: 2),
                // Bottle Body
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(10),
                      bottom: Radius.circular(16),
                    ),
                    child: Container(
                      width: 68,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0B0F17),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(10),
                          bottom: Radius.circular(16),
                        ),
                        border: Border.all(
                          color: isLow
                              ? const Color(0xFFF43F5E)
                              : const Color(0xFF334155),
                          width: 1.5,
                        ),
                      ),
                      child: AnimatedBuilder(
                        animation: _waveController,
                        builder: (context, _) {
                          return CustomPaint(
                            painter: _FluidWavePainter(
                              fillRatio: fillRatio,
                              wavePhase: _waveController.value * 2 * math.pi,
                              isLow: isLow,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          // Bottle Metrics & Quick Refill Action
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: isLow
                            ? const Color(0xFFF43F5E).withOpacity(0.15)
                            : const Color(0xFF0EA5E9).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isLow ? '⚠️ SẮP CẠN BÌNH' : 'CẢM BIẾN HX711 (V1)',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          color: isLow
                              ? const Color(0xFFF43F5E)
                              : const Color(0xFF38BDF8),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Lượng nước còn trong bình',
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF94A3B8),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '${widget.bottleMl.toInt()}',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        color: isLow
                            ? const Color(0xFFF43F5E)
                            : const Color(0xFFF8FAFC),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '/ ${widget.maxCapacityMl.toInt()} ml',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (isLow)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: widget.onQuickRefill,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0EA5E9),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(Icons.water_drop, size: 16),
                      label: const Text(
                        'Châm thêm nước ngay (+350ml)',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  )
                else
                  Text(
                    'Đủ cho khoảng ${(widget.bottleMl / 150).ceil()} lần uống tiêu chuẩn (150ml/lần)',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF64748B),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FluidWavePainter extends CustomPainter {
  final double fillRatio;
  final double wavePhase;
  final bool isLow;

  _FluidWavePainter({
    required this.fillRatio,
    required this.wavePhase,
    required this.isLow,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw graduation marks (400ml, 250ml, 100ml)
    final tickPaint = Paint()
      ..color = const Color(0xFF334155)
      ..strokeWidth = 1;
    for (final ratio in [0.2, 0.5, 0.8]) {
      final y = size.height * (1.0 - ratio);
      canvas.drawLine(
        Offset(size.width - 10, y),
        Offset(size.width, y),
        tickPaint,
      );
    }

    if (fillRatio <= 0.01) return;

    final baseHeight = size.height * (1.0 - fillRatio);
    final path = Path();
    path.moveTo(0, size.height);
    path.lineTo(0, baseHeight);

    for (double x = 0; x <= size.width; x += 2) {
      final waveY =
          baseHeight + math.sin((x / size.width * 2 * math.pi) + wavePhase) * 2.5;
      path.lineTo(x, waveY.clamp(0.0, size.height));
    }

    path.lineTo(size.width, size.height);
    path.close();

    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: isLow
          ? [const Color(0xFFF43F5E), const Color(0xFFBE123C)]
          : [const Color(0xFF38BDF8), const Color(0xFF0284C7)],
    );

    final fillPaint = Paint()
      ..shader = gradient.createShader(Offset.zero & size);

    canvas.drawPath(path, fillPaint);
  }

  @override
  bool shouldRepaint(covariant _FluidWavePainter oldDelegate) {
    return oldDelegate.fillRatio != fillRatio ||
        oldDelegate.wavePhase != wavePhase ||
        oldDelegate.isLow != isLow;
  }
}
