import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class HomeSkeleton extends StatelessWidget {
  const HomeSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? Colors.grey.shade800 : Colors.grey.shade300;
    final highlight = isDark ? Colors.grey.shade700 : Colors.grey.shade100;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: Shimmer.fromColors(
          baseColor: base,
          highlightColor: highlight,
          child: Wrap(
            alignment: WrapAlignment.center,
            children: List.generate(
              3,
              (_) => Container(
                width: 420,
                height: 320,
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: base,
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SummaryBar extends StatelessWidget {
  final int totalDevices;
  final int alertCount;
  final double avgMoisture;

  const SummaryBar({
    super.key,
    required this.totalDevices,
    required this.alertCount,
    required this.avgMoisture,
  });

  @override
  Widget build(BuildContext context) {
    const okColor = Color(0xFF2E7D32);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: _KpiCard(
              icon: Icons.sensors,
              iconColor: okColor,
              label: "อุปกรณ์ทั้งหมด",
              numericValue: totalDevices.toDouble(),
              format: (v) => v.round().toString(),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _KpiCard(
              icon: Icons.warning_amber_rounded,
              iconColor: alertCount > 0 ? Colors.red : okColor,
              label: "แจ้งเตือน",
              numericValue: alertCount.toDouble(),
              format: (v) => v.round().toString(),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _KpiCard(
              icon: Icons.water_drop,
              iconColor: const Color(0xFF1E88E5),
              label: "ความชื้นเฉลี่ย",
              numericValue: avgMoisture,
              format: (v) => v.toStringAsFixed(1),
            ),
          ),
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final double numericValue;
  final String Function(double) format;

  const _KpiCard({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.numericValue,
    required this.format,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // แถบสีบอกตัวตนของการ์ดตั้งแต่แรกเห็น ผูกทั้งการ์ดเข้ากับสีของ
            // ไอคอน แทนที่จะปล่อยให้ไอคอนลอยเดี่ยวๆ เหนือค่าตัวเลข
            Container(width: 4, color: iconColor),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: iconColor.withValues(alpha: 0.14),
                          ),
                          child: Icon(icon, size: 16, color: iconColor),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color:
                                  Theme.of(context).textTheme.bodySmall?.color,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // ตัวเลขไล่จากค่าเดิมไปค่าใหม่ (นับขึ้น/ลง) แทนกระโดด
                    // ทันที ทุกครั้งที่ Firestore stream ส่งค่าใหม่เข้ามา
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: numericValue),
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.easeOut,
                      builder: (context, animatedValue, _) {
                        return Text(
                          format(animatedValue),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 26,
                            height: 1,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
