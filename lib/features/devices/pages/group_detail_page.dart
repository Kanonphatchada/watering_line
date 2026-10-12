import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/device_groups.dart';
import '../widgets/device_grid.dart';
import '../widgets/group_style.dart';
import 'device_groups_page.dart';

// id สมมติของ "ไม่ได้จัดกลุ่ม" ให้ใช้หน้ารายละเอียดเดียวกับกลุ่มจริงได้
const ungroupedGroupId = '__ungrouped__';

// หน้ารายละเอียดกลุ่ม — อุปกรณ์ทั้งหมดที่อยู่ในกลุ่มนั้น (กดจากการ์ดกลุ่มบน
// หน้าหลัก) ดึงข้อมูลสดเองเพื่อให้ค่าความชื้น/สถานะอัปเดตตลอดที่เปิดหน้านี้อยู่
class GroupDetailPage extends StatelessWidget {
  final String groupId;

  const GroupDetailPage({super.key, required this.groupId});

  bool get _isUngrouped => groupId == ungroupedGroupId;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('ESP32')
          .where('uid', isEqualTo: uid)
          .snapshots(),
      builder: (context, deviceSnap) {
        return StreamBuilder<List<DeviceGroup>>(
          stream: watchDeviceGroups(uid),
          builder: (context, groupSnap) {
            if (deviceSnap.hasError || groupSnap.hasError) {
              return Scaffold(
                appBar: AppBar(),
                body: Center(
                  child: Text(
                    "เกิดข้อผิดพลาด: ${deviceSnap.error ?? groupSnap.error}",
                  ),
                ),
              );
            }
            if (!deviceSnap.hasData || !groupSnap.hasData) {
              return Scaffold(
                appBar: AppBar(),
                body: const Center(child: CircularProgressIndicator()),
              );
            }

            final allDocs = deviceSnap.data!.docs;
            final groups = pruneMissingDevices(
              groupSnap.data!,
              allDocs.map((d) => d.id).toSet(),
            );

            DeviceGroup? group;
            if (!_isUngrouped) {
              for (final g in groups) {
                if (g.id == groupId) group = g;
              }
              if (group == null) {
                // กลุ่มถูกลบไปแล้ว (เช่นจากอีกแท็บ)
                return Scaffold(
                  appBar: AppBar(),
                  body: const Center(child: Text("ไม่พบกลุ่มนี้แล้ว")),
                );
              }
            }

            final members = _isUngrouped
                ? allDocs
                    .where((d) => groupOfDevice(groups, d.id) == null)
                    .toList()
                : allDocs.where((d) => group!.deviceIds.contains(d.id)).toList();
            final stats = computeGroupStats([
              for (final d in members) d.data() as Map<String, dynamic>,
            ]);

            final title = _isUngrouped ? "ไม่ได้จัดกลุ่ม" : group!.name;

            return Scaffold(
              appBar: AppBar(
                title: Row(
                  children: [
                    if (_isUngrouped)
                      const Icon(Icons.folder_off_outlined)
                    else
                      GroupBadge(
                        iconKey: group!.iconKey,
                        colorIndex: group.colorIndex,
                        size: 32,
                      ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(title, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
                actions: [
                  if (!_isUngrouped) ...[
                    IconButton(
                      tooltip: "แก้ไขกลุ่ม",
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => openGroupEditor(
                        context,
                        docs: allDocs,
                        groups: groups,
                        existing: group,
                      ),
                    ),
                    IconButton(
                      tooltip: "ลบกลุ่ม",
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () async {
                        final deleted =
                            await confirmAndDeleteGroup(context, group!);
                        if (deleted && context.mounted) {
                          Navigator.of(context).maybePop();
                        }
                      },
                    ),
                  ],
                  const SizedBox(width: 8),
                ],
              ),
              body: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: ListView(
                    padding: const EdgeInsets.only(top: 12, bottom: 24),
                    children: [
                      _StatsRow(stats: stats),
                      const SizedBox(height: 16),
                      if (members.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(40),
                          child: Column(
                            children: [
                              Icon(
                                Icons.sensors_off,
                                size: 44,
                                color: Theme.of(context).colorScheme.outline,
                              ),
                              const SizedBox(height: 8),
                              const Text("ยังไม่มีอุปกรณ์ในกลุ่มนี้"),
                              if (!_isUngrouped)
                                TextButton(
                                  onPressed: () => openGroupEditor(
                                    context,
                                    docs: allDocs,
                                    groups: groups,
                                    existing: group,
                                  ),
                                  child: const Text("เลือกอุปกรณ์เข้ากลุ่ม"),
                                ),
                            ],
                          ),
                        )
                      else
                        DeviceGrid(docs: members, allDocs: allDocs),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _StatsRow extends StatelessWidget {
  final GroupStats stats;

  const _StatsRow({required this.stats});

  @override
  Widget build(BuildContext context) {
    final avg = stats.avgMoisture;
    final bad = stats.needsAttention > 0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Expanded(
            child: _Tile(
              icon: Icons.sensors,
              color: const Color(0xFF2E7D32),
              label: "อุปกรณ์",
              value: "${stats.count}",
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _Tile(
              icon: Icons.water_drop,
              color: const Color(0xFF1E88E5),
              label: "ความชื้นเฉลี่ย",
              value: avg == null ? "–" : "${avg.toStringAsFixed(0)}%",
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _Tile(
              icon: bad ? Icons.warning_amber_rounded : Icons.check_circle,
              color: bad ? Colors.red : const Color(0xFF2E7D32),
              label: "ต้องดู",
              value: "${stats.needsAttention}",
            ),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  const _Tile({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall?.color;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: muted),
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
