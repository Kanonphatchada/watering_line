import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../pages/plant_profile_page.dart';
import '../services/fruit_profiles.dart';
import 'fruit_icon.dart';

const _okColor = Color(0xFF2E7D32);
const _nearColor = Color(0xFFF57C00);
const _overColor = Color(0xFFD32F2F);

Color stressLevelColor(StressLevel level) => switch (level) {
      StressLevel.ok => _okColor,
      StressLevel.near => _nearColor,
      StressLevel.over => _overColor,
    };

// การ์ด "ต้นที่กำลังงดน้ำ" ที่หน้าหลัก — ช่วงงดน้ำคือช่วงที่ต้นเสี่ยงตายที่สุด
// ถ้าลืมเปลี่ยนช่วง จึงนับวันให้เห็นตลอด ขึ้นเฉพาะตอนมีอุปกรณ์อยู่ในช่วงนี้
// อุปกรณ์ที่ผลไม้ + ช่วง + วันเริ่ม + จำนวนวันเหมือนกันรวมเป็นแถวเดียว
// (เช่น ทั้งแปลงทุเรียนเริ่มพร้อมกัน) หลายแปลงหลายช่วงก็แยกแถวไม่ปนกัน
class StressWatchCard extends StatelessWidget {
  final List<QueryDocumentSnapshot> docs;
  // ใส่ระยะห่างเฉพาะตอนการ์ดแสดง — ตอนซ่อนจะได้ไม่เหลือช่องว่างในหน้าหลัก
  final EdgeInsets padding;

  const StressWatchCard({
    super.key,
    required this.docs,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream:
          FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snapshot) {
        final settings = snapshot.data?.data()?['plantSettings'];
        if (settings is! Map) return const SizedBox.shrink();

        final groups = <String, _Group>{};
        for (final d in docs) {
          final data = d.data() as Map<String, dynamic>;
          final setting = settings[d.id];
          final status = stressStatusFor(
            (data['Automois'] ?? 20).toDouble(),
            setting is Map<String, dynamic> ? setting : null,
          );
          if (status == null) continue;
          final key = "${status.fruit.id}|${status.stage.id}|"
              "${status.dayNumber}|${status.plannedDays}";
          groups.putIfAbsent(key, () => _Group(status)).devices.add(d.id);
        }
        if (groups.isEmpty) return const SizedBox.shrink();

        // แถวที่อันตรายที่สุดขึ้นก่อน
        final rows = groups.values.toList()
          ..sort((a, b) => a.status.daysLeft.compareTo(b.status.daysLeft));
        final worst = rows.first.status.level;
        final accent = stressLevelColor(worst);
        final deviceCount =
            rows.fold<int>(0, (total, g) => total + g.devices.length);

        return Padding(
          padding: padding,
          child: Card(
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: accent.withValues(
                    alpha: worst == StressLevel.ok ? 0.3 : 0.8),
                width: worst == StressLevel.ok ? 1 : 1.5,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        worst == StressLevel.ok
                            ? Icons.water_drop_outlined
                            : Icons.warning_amber_rounded,
                        color: accent,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          "ต้นที่กำลังงดน้ำ",
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          switch (worst) {
                            StressLevel.over => "เกินกำหนด",
                            StressLevel.near => "ใกล้ครบกำหนด",
                            StressLevel.ok => "$deviceCount อุปกรณ์",
                          },
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  for (final (i, g) in rows.indexed) ...[
                    if (i > 0) const Divider(height: 20),
                    _StressRow(
                      group: g,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PlantProfilePage(docs: docs),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Group {
  final StressStatus status;
  final devices = <String>[];

  _Group(this.status);
}

class _StressRow extends StatelessWidget {
  final _Group group;
  final VoidCallback onTap;

  const _StressRow({required this.group, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = group.status;
    final c = stressLevelColor(s.level);
    final muted = Theme.of(context).textTheme.bodySmall?.color;
    final progress = (s.dayNumber / s.plannedDays).clamp(0.0, 1.0);

    final message = switch (s.level) {
      StressLevel.over =>
        "เกินกำหนด ${-s.daysLeft} วัน · ควรเปลี่ยนเป็นช่วงออกดอก",
      StressLevel.near => s.daysLeft == 0
          ? "ครบกำหนดวันนี้ · เช็คตาดอก"
          : "อีก ${s.daysLeft} วันครบกำหนด · เริ่มเช็คตาดอก",
      StressLevel.ok => "เหลืออีกประมาณ ${s.daysLeft} วัน",
    };

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                FruitIcon(size: 18, color: c),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    "${s.fruit.label} · ${s.stage.label}",
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  "วันที่ ${s.dayNumber}/${s.plannedDays}",
                  style: TextStyle(fontWeight: FontWeight.w800, color: c),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              group.devices.join(', '),
              style: TextStyle(fontSize: 12, color: muted),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                color: c,
                backgroundColor: c.withValues(alpha: 0.15),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: s.level == StressLevel.ok
                          ? FontWeight.w500
                          : FontWeight.w700,
                      color: s.level == StressLevel.ok ? muted : c,
                    ),
                  ),
                ),
                Text(
                  "แนะนำ ${s.stage.minDays}–${s.stage.maxDays} วัน",
                  style: TextStyle(fontSize: 11, color: muted),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
