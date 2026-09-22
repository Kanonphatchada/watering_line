import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/device_schedule.dart';

// สรุปว่าอุปกรณ์แต่ละตัวอยู่ในหมวดตารางเวลาไหนบ้าง (ตามฟาร์ม/ตั้งเวลาเฉพาะ/
// ยกเลิกการตั้งเวลา) — มีไว้เพราะถ้ามีอุปกรณ์เป็นร้อยตัว จำไม่ไหวว่าตัวไหน
// ตั้งค่าไว้แบบไหนบ้าง ต้องมีที่ให้ดูภาพรวมทีเดียวแทนไล่เปิดทีละการ์ด ใช้
// ตรรกะแบ่งหมวดเดียวกับ dialog ตั้งเวลารายอุปกรณ์เป๊ะๆ (ดู
// openDeviceScheduleDialog's `choice`)
class ScheduleOverviewPage extends StatefulWidget {
  final List<QueryDocumentSnapshot> docs;

  const ScheduleOverviewPage({super.key, required this.docs});

  @override
  State<ScheduleOverviewPage> createState() => _ScheduleOverviewPageState();
}

class _ScheduleOverviewPageState extends State<ScheduleOverviewPage> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _categoryOf(Map<String, dynamic> data) {
    if (data['scheduleOverride'] != true) return 'farm';
    return data['scheduleEnabled'] == true ? 'custom' : 'none';
  }

  static const _sections = [
    ('farm', 'ตามตารางเวลาของฟาร์ม', Icons.groups_outlined),
    ('custom', 'ตั้งเวลาเฉพาะการ์ด', Icons.edit_calendar_outlined),
    ('none', 'ยกเลิกการตั้งเวลา', Icons.block_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final filtered = widget.docs
        .where((d) => q.isEmpty || d.id.toLowerCase().contains(q))
        .toList();

    final groups = <String, List<QueryDocumentSnapshot>>{
      'farm': [],
      'custom': [],
      'none': [],
    };
    for (final d in filtered) {
      final data = d.data() as Map<String, dynamic>;
      groups[_categoryOf(data)]!.add(d);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.fact_check_outlined),
            SizedBox(width: 8),
            Text("สรุปตารางเวลา"),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              autofocus: false,
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                isDense: true,
                hintText: "ค้นหาชื่ออุปกรณ์...",
                prefixIcon: Icon(Icons.search, size: 20),
              ),
            ),
          ),
          Expanded(
            child: widget.docs.isEmpty
                ? const Center(child: Text("ยังไม่มีอุปกรณ์เลย"))
                : filtered.isEmpty
                    ? const Center(child: Text("ไม่พบอุปกรณ์"))
                    : ListView(
                        children: [
                          for (final (key, title, icon) in _sections)
                            if (groups[key]!.isNotEmpty)
                              _CategorySection(
                                title: title,
                                icon: icon,
                                docs: groups[key]!,
                              ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}

class _CategorySection extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<QueryDocumentSnapshot> docs;

  const _CategorySection({
    required this.title,
    required this.icon,
    required this.docs,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Row(
            children: [
              Icon(icon,
                  size: 18, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                "$title (${docs.length})",
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
            ],
          ),
        ),
        for (final d in docs)
          Builder(builder: (context) {
            final data = d.data() as Map<String, dynamic>;
            return ListTile(
              leading: const Icon(Icons.sensors),
              title: Text(d.id),
              subtitle: data['groupId'] != null
                  ? Text("กลุ่ม: ${data['groupId']}")
                  : null,
              trailing: const Icon(Icons.chevron_right),
              // แตะแล้วเปิด dialog ตั้งเวลาของอุปกรณ์นั้นตรงๆเลย เผื่อเจอตัว
              // ที่ตั้งผิดหมวดจากที่ตั้งใจไว้ จะได้แก้ต่อได้ทันทีไม่ต้องไปหา
              // การ์ดเองอีกที
              onTap: () => openDeviceScheduleDialog(context, d.id, data),
            );
          }),
        const Divider(),
      ],
    );
  }
}
