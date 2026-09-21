import 'package:flutter/material.dart';

class MoistureGauge extends StatelessWidget {
  final num? moisture;
  final double target;
  final bool isOffline;

  const MoistureGauge({
    super.key,
    required this.moisture,
    required this.target,
    required this.isOffline,
  });

  @override
  Widget build(BuildContext context) {
    final value = moisture?.toDouble();
    final isAlert = value != null && value > target;
    final color = isOffline
        ? Colors.grey.shade500
        : (isAlert ? Colors.red : const Color(0xFF2E7D32));
    final ratio =
        (value == null || target <= 0) ? 0.0 : (value / target).clamp(0.0, 1.0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 40,
          height: 40,
          // ค่าความชื้นเป็น real-time (มาจาก Firestore stream) เปลี่ยนบ่อย —
          // ใช้ TweenAnimationBuilder ไล่ค่าเก่าไปค่าใหม่ทีละนิด (ทั้งวงแหวน
          // และตัวเลข) แทนการกระตุกเปลี่ยนทันทีทุกครั้งที่ค่าขยับ
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value == null ? 0 : ratio),
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOut,
            builder: (context, animatedRatio, _) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: animatedRatio,
                    strokeWidth: 4,
                    backgroundColor: color.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: value ?? 0),
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOut,
                    builder: (context, animatedValue, _) {
                      return Text(
                        value == null ? '-' : animatedValue.toStringAsFixed(0),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      );
                    },
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 4),
        Text(
          "Moisture",
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).textTheme.bodySmall?.color,
          ),
        ),
      ],
    );
  }
}
