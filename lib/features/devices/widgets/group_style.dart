import 'package:flutter/material.dart';
import 'fruit_icon.dart';

// ชุดไอคอน/สีให้ผู้ใช้เลือกให้การ์ดกลุ่มอุปกรณ์ (แยกตามพืชที่ปลูก) — เก็บใน
// Firestore เป็น "คีย์" (iconKey/colorIndex) ไม่ใช่ตัวไอคอนเอง คีย์ที่ไม่รู้จัก
// (เช่นเพิ่มไอคอนใหม่ทีหลังแล้วย้อนเวอร์ชัน) ตกไปใช้ไอคอนตั้งต้นแทนที่จะพัง
class GroupIconOption {
  final String key;
  final String label;
  final IconData? icon; // null = ใช้ FruitIcon ที่วาดเอง

  const GroupIconOption(this.key, this.label, this.icon);
}

const kGroupIcons = <GroupIconOption>[
  GroupIconOption('leaf', 'ผักใบ', Icons.eco_rounded),
  GroupIconOption('herb', 'สมุนไพร', Icons.spa_rounded),
  GroupIconOption('sprout', 'ต้นกล้า', Icons.grass_rounded),
  GroupIconOption('flower', 'ไม้ดอก', Icons.local_florist_rounded),
  GroupIconOption('petal', 'ดอกไม้', Icons.filter_vintage_rounded),
  GroupIconOption('fruit', 'ผลไม้', null),
  GroupIconOption('tree', 'ไม้ยืนต้น', Icons.park_rounded),
  GroupIconOption('forest', 'สวน', Icons.forest_rounded),
  GroupIconOption('nature', 'ต้นไม้', Icons.nature_rounded),
  GroupIconOption('yard', 'สนามหญ้า', Icons.yard_rounded),
  GroupIconOption('plant', 'ใบไม้', Icons.energy_savings_leaf_rounded),
  GroupIconOption('farm', 'แปลงเกษตร', Icons.agriculture_rounded),
  GroupIconOption('house', 'โรงเรือน', Icons.cottage_rounded),
  GroupIconOption('water', 'น้ำ', Icons.water_drop_rounded),
];

// ไม่มีสีแดง — สงวนไว้ให้สถานะแจ้งเตือน จะได้ไม่สับสนกับ "มีปัญหา"
const kGroupColors = <Color>[
  Color(0xFF2E7D32), // เขียว
  Color(0xFF00897B), // เขียวน้ำทะเล
  Color(0xFF1E88E5), // ฟ้า
  Color(0xFF5E35B1), // ม่วง
  Color(0xFFD81B60), // ชมพู
  Color(0xFFF57C00), // ส้ม
  Color(0xFF6D4C41), // น้ำตาล
  Color(0xFF546E7A), // เทาน้ำเงิน
];

Color groupColor(int index) =>
    kGroupColors[(index >= 0 && index < kGroupColors.length) ? index : 0];

GroupIconOption groupIconOption(String key) => kGroupIcons.firstWhere(
      (o) => o.key == key,
      orElse: () => kGroupIcons.first,
    );

// ไอคอนในกรอบสี่เหลี่ยมมนพื้นจาง — ใช้ทั้งบนการ์ดกลุ่ม หน้ารายละเอียด และตัว
// เลือกไอคอน
class GroupBadge extends StatelessWidget {
  final String iconKey;
  final int colorIndex;
  final double size;

  const GroupBadge({
    super.key,
    required this.iconKey,
    required this.colorIndex,
    this.size = 56,
  });

  @override
  Widget build(BuildContext context) {
    final color = groupColor(colorIndex);
    final option = groupIconOption(iconKey);
    final glyph = size * 0.52;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      alignment: Alignment.center,
      child: option.icon == null
          ? FruitIcon(size: glyph, color: color)
          : Icon(option.icon, size: glyph, color: color),
    );
  }
}

// ตัวเลือกไอคอน + สี สำหรับกล่องสร้าง/แก้ไขกลุ่ม
class GroupStylePicker extends StatelessWidget {
  final String iconKey;
  final int colorIndex;
  final ValueChanged<String> onIconChanged;
  final ValueChanged<int> onColorChanged;

  const GroupStylePicker({
    super.key,
    required this.iconKey,
    required this.colorIndex,
    required this.onIconChanged,
    required this.onColorChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = groupColor(colorIndex);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("ไอคอน", style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final o in kGroupIcons)
              Tooltip(
                message: o.label,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => onIconChanged(o.key),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: o.key == iconKey
                          ? color.withValues(alpha: 0.16)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: o.key == iconKey ? color : scheme.outlineVariant,
                        width: o.key == iconKey ? 2 : 1,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: o.icon == null
                        ? FruitIcon(
                            size: 22,
                            color: o.key == iconKey ? color : scheme.onSurface,
                          )
                        : Icon(
                            o.icon,
                            size: 22,
                            color: o.key == iconKey ? color : scheme.onSurface,
                          ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        const Text("สี", style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (var i = 0; i < kGroupColors.length; i++)
              InkWell(
                customBorder: const CircleBorder(),
                onTap: () => onColorChanged(i),
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: kGroupColors[i],
                    shape: BoxShape.circle,
                    border: i == colorIndex
                        ? Border.all(color: scheme.onSurface, width: 2.5)
                        : null,
                  ),
                  child: i == colorIndex
                      ? const Icon(Icons.check, size: 16, color: Colors.white)
                      : null,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
