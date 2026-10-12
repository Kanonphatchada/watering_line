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
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      const Expanded(
                        child: Text(
                          "ต้นที่กำลังงดน้ำ",
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
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
                  const SizedBox(height: 6),
                  for (final (i, g) in rows.indexed) ...[
                    if (i > 0) const Divider(height: 12),
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

// แถวเดียวกะทัดรัด: ผลไม้·ช่วง + แถบความคืบหน้า + วันที่ x/y แล้วบรรทัดเล็กๆ
// ใต้นั้นบอกข้อความสถานะ (แต่ละแถวสูงแค่สองบรรทัด) — รายชื่ออุปกรณ์ไม่โชว์ใน
// การ์ดแล้ว เหลือแค่จำนวน เพราะรายละเอียดอยู่ในหน้า "ชนิดพืช" อยู่แล้ว
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
                FruitIcon(size: 16, color: c),
                const SizedBox(width: 6),
                Flexible(
                  flex: 3,
                  child: Text(
                    "${s.fruit.label} · ${s.stage.label}"
                    "${group.devices.length > 1 ? ' (${group.devices.length} ตัว)' : ''}",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 4,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 6,
                      color: c,
                      backgroundColor: c.withValues(alpha: 0.15),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  "${s.dayNumber}/${s.plannedDays} วัน",
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: c,
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 22, top: 2),
              child: Text(
                message,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: s.level == StressLevel.ok
                      ? FontWeight.w500
                      : FontWeight.w700,
                  color: s.level == StressLevel.ok ? muted : c,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
