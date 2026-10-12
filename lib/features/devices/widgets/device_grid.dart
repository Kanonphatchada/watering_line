import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../pages/plant_profile_page.dart';
import 'device_card.dart';

// กริดการ์ดอุปกรณ์ — ใช้ร่วมกันทั้งหน้าหลัก (ตอนยังไม่มีกลุ่ม/ค้นหา) และหน้า
// รายละเอียดกลุ่ม
//
// ไม่ล็อกความสูงการ์ดตายตัว — ตอนย่อหน้าจอ/จอโทรศัพท์ ข้อความไทยตัดบรรทัดเพิ่ม
// เนื้อหาสูงขึ้น ถ้าล็อกไว้ที่ 420 จะโดนตัดหรือเพี้ยน เลยจัดเป็นแถวเอง:
// คำนวณจำนวนคอลัมน์จากความกว้างจริง (โทรศัพท์ = 1 คอลัมน์) การ์ดในแถวเดียวกัน
// สูงเท่ากันตามใบที่สูงที่สุด
// allDocs = อุปกรณ์ทั้งหมดของผู้ใช้ (หน้า "ชนิดพืช" ต้องใช้ครบทุกตัว)
class DeviceGrid extends StatelessWidget {
  final List<QueryDocumentSnapshot> docs;
  final List<QueryDocumentSnapshot> allDocs;

  const DeviceGrid({super.key, required this.docs, required this.allDocs});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 16.0;
        const minCardWidth = 340.0;
        final available = constraints.maxWidth - 24;
        final columns =
            ((available + gap) / (minCardWidth + gap)).floor().clamp(1, 3);

        Widget cardAt(int index) {
          final doc = docs[index];
          return DeviceCard(
            key: ValueKey(doc.id),
            nanoId: doc.id,
            data: doc.data() as Map<String, dynamic>,
            index: index,
            onPlantTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PlantProfilePage(
                  docs: allDocs,
                  initialDeviceId: doc.id,
                ),
              ),
            ),
          );
        }

        final rows = <Widget>[];
        for (var start = 0; start < docs.length; start += columns) {
          rows.add(
            Padding(
              padding: const EdgeInsets.only(bottom: gap),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var c = 0; c < columns; c++) ...[
                      if (c > 0) const SizedBox(width: gap),
                      Expanded(
                        child: start + c < docs.length
                            ? cardAt(start + c)
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(children: rows),
        );
      },
    );
  }
}
