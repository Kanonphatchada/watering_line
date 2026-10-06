import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

List<String> farmGroupIds(List<QueryDocumentSnapshot> docs) => docs
    .map((d) => (d.data() as Map<String, dynamic>)['groupId'] as String?)
    .whereType<String>()
    .toSet()
    .toList()
  ..sort();

// ปุ่มเลือกฟาร์มแบบเม็ดยา (pill) บนหัวหน้า ตารางเวลา/พยากรณ์ — ซ่อนไว้ถ้ามี
// ฟาร์มเดียว ไม่ต้องเด้ง dialog ถามก่อนเข้าหน้าเหมือนแบบเดิม
class FarmSelector extends StatelessWidget {
  final List<String> groupIds;
  final String groupId;
  final ValueChanged<String> onChanged;

  const FarmSelector({
    super.key,
    required this.groupIds,
    required this.groupId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.agriculture_outlined, size: 16, color: scheme.primary),
          const SizedBox(width: 6),
          Text(
            groupId,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: scheme.primary,
            ),
          ),
          if (groupIds.length > 1)
            Icon(Icons.expand_more, size: 18, color: scheme.primary),
        ],
      ),
    );

    if (groupIds.length <= 1) return chip;
    return PopupMenuButton<String>(
      tooltip: "เลือกฟาร์ม",
      onSelected: onChanged,
      itemBuilder: (_) => [
        for (final g in groupIds) PopupMenuItem(value: g, child: Text(g)),
      ],
      child: chip,
    );
  }
}
