import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shimmer/shimmer.dart';
import '../services/rain_skip.dart';

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
  final List<QueryDocumentSnapshot> docs;
  final int totalDevices;
  final int alertCount;
  final double avgMoisture;

  const SummaryBar({
    super.key,
    required this.docs,
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
          Expanded(child: WeatherForecastCard(docs: docs)),
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
          const SizedBox(width: 10),
          Expanded(
            child: _KpiCard(
              icon: Icons.warning_amber_rounded,
              // ไม่ใช้เขียวตอนไม่มีแจ้งเตือน กันซ้ำกับสีการ์ด "อุปกรณ์ทั้งหมด"
              iconColor: alertCount > 0
                  ? Colors.red
                  : Theme.of(context).colorScheme.outline,
              label: "แจ้งเตือน",
              numericValue: alertCount.toDouble(),
              format: (v) => v.round().toString(),
            ),
          ),
        ],
      ),
    );
  }
}

// การ์ดสรุปสถานะพยากรณ์อากาศ — อยู่ในแถวการ์ดสรุปเดียวกับอุปกรณ์ทั้งหมด/
// ความชื้นเฉลี่ยแล้ว (แทนที่การ์ดแจ้งเตือนเดิม) อ่านจาก device_registry ของ
// ทุกกลุ่ม/ฟาร์มที่อุปกรณ์ผู้ใช้สังกัดอยู่ แตะแล้วเปิดไดอะล็อกตั้งค่าได้เลย
class WeatherForecastCard extends StatelessWidget {
  final List<QueryDocumentSnapshot> docs;

  const WeatherForecastCard({super.key, required this.docs});

  @override
  Widget build(BuildContext context) {
    final groupIds = docs
        .map((d) => (d.data() as Map<String, dynamic>)['groupId'] as String?)
        .whereType<String>()
        .toSet()
        .toList();

    if (groupIds.isEmpty) {
      return _WeatherKpiCard(
        icon: Icons.cloud_outlined,
        color: Theme.of(context).colorScheme.outline,
        status: "ไม่พบฟาร์ม",
        onTap: () => openRainSkipDialog(context, docs),
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('device_registry')
          .where(FieldPath.documentId, whereIn: groupIds)
          .snapshots(),
      builder: (context, snapshot) {
        final regs = snapshot.data?.docs ?? [];
        final enabled = regs
            .where(
              (d) =>
                  (d.data() as Map<String, dynamic>)['rainSkipEnabled'] == true,
            )
            .toList();

        // สีเดียวคงที่สำหรับการ์ดนี้ (ไม่ไปซ้ำกับเขียวของ "อุปกรณ์ทั้งหมด"
        // หรือฟ้าของ "ความชื้นเฉลี่ย") เปลี่ยนแค่ไอคอนตามสถานะ ไม่เปลี่ยนสี
        const weatherColor = Color(0xFF00897B); // teal

        late final IconData icon;
        late final Color color;
        late final String status;

        if (enabled.isEmpty) {
          icon = Icons.cloud_outlined;
          color = Theme.of(context).colorScheme.outline;
          status = "ยังไม่เปิดใช้";
        } else {
          final rainSoon = enabled.any(
            (d) => (d.data() as Map<String, dynamic>)['_rainForecast'] == true,
          );
          if (rainSoon) {
            icon = Icons.thunderstorm;
            color = weatherColor;
            status = "ฝนอาจตก";
          } else {
            icon = Icons.wb_sunny_outlined;
            color = weatherColor;
            status = "ไม่มีฝน";
          }
        }

        return _WeatherKpiCard(
          icon: icon,
          color: color,
          status: status,
          onTap: () => openRainSkipDialog(context, docs),
        );
      },
    );
  }
}

class _WeatherKpiCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String status;
  final VoidCallback onTap;

  const _WeatherKpiCard({
    required this.icon,
    required this.color,
    required this.status,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [color.withValues(alpha: 0.14), Colors.transparent],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                right: -18,
                bottom: -18,
                child: Icon(
                  icon,
                  size: 100,
                  color: color.withValues(alpha: 0.08),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color.withValues(alpha: 0.16),
                      ),
                      child: Icon(icon, size: 18, color: color),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      "พยากรณ์อากาศ",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      status,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 22,
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [iconColor.withValues(alpha: 0.14), Colors.transparent],
          ),
        ),
        child: Stack(
          children: [
            // ไอคอนใหญ่จางๆ เป็นลายน้ำพื้นหลัง — ให้ความรู้สึกมีภาพประกอบ
            // โดยไม่แย่งความสนใจจากตัวเลขจริง
            Positioned(
              right: -18,
              bottom: -18,
              child: Icon(
                icon,
                size: 100,
                color: iconColor.withValues(alpha: 0.08),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: iconColor.withValues(alpha: 0.16),
                    ),
                    child: Icon(icon, size: 18, color: iconColor),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
                  ),
                  const SizedBox(height: 4),
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
          ],
        ),
      ),
    );
  }
}

// แผงสรุปสถานะฟาร์มโดยรวม (อุปกรณ์ออนไลน์กี่ตัว/ความชื้นเฉลี่ย) เป็นแถบ
// progress bar — ใช้ข้อมูลจริงที่มีอยู่แล้วทั้งคู่ ไม่ใช้ค่าสมมติ
class FleetHealthCard extends StatelessWidget {
  final int onlineCount;
  final int totalCount;
  final int alertCount;
  final double avgMoisture;

  const FleetHealthCard({
    super.key,
    required this.onlineCount,
    required this.totalCount,
    required this.alertCount,
    required this.avgMoisture,
  });

  @override
  Widget build(BuildContext context) {
    final onlineRatio = totalCount == 0 ? 0.0 : onlineCount / totalCount;
    final noAlertCount = totalCount - alertCount;
    final noAlertRatio = totalCount == 0 ? 0.0 : noAlertCount / totalCount;
    final isHealthy = onlineRatio == 1.0 && alertCount == 0;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "สถานะระบบ",
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: (isHealthy ? const Color(0xFF2E7D32) : Colors.orange)
                        .withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    isHealthy ? "ปกติ" : "ควรตรวจสอบ",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color:
                          isHealthy ? const Color(0xFF2E7D32) : Colors.orange,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _HealthBar(
              label: "อุปกรณ์ออนไลน์",
              valueText: "$onlineCount/$totalCount",
              ratio: onlineRatio,
              color: const Color(0xFF2E7D32),
            ),
            const SizedBox(height: 16),
            _HealthBar(
              label: "ความชื้นเฉลี่ยฟาร์ม",
              valueText: "${avgMoisture.toStringAsFixed(0)}%",
              ratio: (avgMoisture / 100).clamp(0, 1),
              color: const Color(0xFF1E88E5),
            ),
            const SizedBox(height: 16),
            _HealthBar(
              label: "อุปกรณ์ไม่มีแจ้งเตือน",
              valueText: "$noAlertCount/$totalCount",
              ratio: noAlertRatio,
              color: alertCount == 0 ? const Color(0xFF2E7D32) : Colors.orange,
            ),
          ],
        ),
      ),
    );
  }
}

class _HealthBar extends StatelessWidget {
  final String label;
  final String valueText;
  final double ratio;
  final Color color;

  const _HealthBar({
    required this.label,
    required this.valueText,
    required this.ratio,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            Text(
              valueText,
              style: TextStyle(
                fontSize: 13,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _SegmentedBar(ratio: ratio, color: color),
      ],
    );
  }
}

// แถบสถานะแบบแบ่งช่อง (segmented) แทนเส้น progress ยาวเส้นเดียว — ให้
// ความรู้สึกเหมือนแผงสถานะระบบจริง อ่านง่ายเป็นสัดส่วนกว่าเส้นเรียบๆ
class _SegmentedBar extends StatelessWidget {
  static const int segmentCount = 12;

  final double ratio;
  final Color color;

  const _SegmentedBar({required this.ratio, required this.color});

  @override
  Widget build(BuildContext context) {
    final filled = (ratio * segmentCount).round();
    // เรืองแสง (glow) เฉพาะโหมดมืด — โหมดสว่างพื้นขาวใส่ glow แล้วดูแปลกๆ
    // ไม่เข้ากับพื้นหลัง
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      children: [
        for (var i = 0; i < segmentCount; i++)
          Expanded(
            child: Container(
              height: 10,
              margin: EdgeInsets.only(right: i == segmentCount - 1 ? 0 : 3),
              decoration: BoxDecoration(
                color: i < filled
                    ? color
                    : Theme.of(context).colorScheme.outline.withValues(
                          alpha: 0.2,
                        ),
                borderRadius: BorderRadius.circular(3),
                // ทำให้ช่องที่ติดสว่าง "เรืองแสง" (glow) แทนที่จะแบนราบ —
                // เฉพาะช่องที่ fill แล้วเท่านั้น ช่องว่างไม่มี glow
                boxShadow: i < filled && isDark
                    ? [
                        BoxShadow(
                          color: color.withValues(alpha: 0.7),
                          blurRadius: 6,
                          spreadRadius: 0.5,
                        ),
                      ]
                    : null,
              ),
            ),
          ),
      ],
    );
  }
}
