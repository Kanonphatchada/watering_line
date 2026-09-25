import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class _ActivityItem {
  final String nanoId;
  final Map<String, dynamic> data;
  const _ActivityItem(this.nanoId, this.data);

  Timestamp? get startedAt => data['startedAt'] as Timestamp?;
  bool get resolved => data['resolvedAt'] != null;
  String get label =>
      (data['cause'] as String?) ??
      (data['type'] as String?) ??
      "ไม่ทราบสาเหตุ";
}

String _relativeTime(Timestamp? t) {
  if (t == null) return "";
  final diff = DateTime.now().difference(t.toDate());
  if (diff.inMinutes < 1) return "เมื่อสักครู่";
  if (diff.inMinutes < 60) return "${diff.inMinutes} นาทีที่แล้ว";
  if (diff.inHours < 24) return "${diff.inHours} ชม.ที่แล้ว";
  return "${diff.inDays} วันที่แล้ว";
}

// กิจกรรมล่าสุด (ขาดการติดต่อ/วาล์วผิดปกติ/เซนเซอร์ผิดพลาด ฯลฯ) รวมจากทุก
// อุปกรณ์ของผู้ใช้ — ใช้ข้อมูลจริงจาก ESP32/{nanoId}/Incidents ที่มีอยู่แล้ว
// (ไม่ใช่ข้อมูลสมมติ) ดึงแบบ fan-out ทีละอุปกรณ์แล้วรวม+เรียงเวลาเอง เพราะ
// Firestore ไม่มี collectionGroup query ที่กรองด้วย uid ได้ตรงๆ (Incidents
// ไม่มี field uid เก็บไว้ อาศัย rule ผูกกับ parent doc แทน)
class RecentActivityCard extends StatefulWidget {
  final List<QueryDocumentSnapshot> docs;

  const RecentActivityCard({super.key, required this.docs});

  @override
  State<RecentActivityCard> createState() => _RecentActivityCardState();
}

class _RecentActivityCardState extends State<RecentActivityCard> {
  late Future<List<_ActivityItem>> _future;
  List<String> _lastIds = [];

  @override
  void initState() {
    super.initState();
    _lastIds = widget.docs.map((d) => d.id).toList()..sort();
    _future = _fetch();
  }

  @override
  void didUpdateWidget(covariant RecentActivityCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newIds = widget.docs.map((d) => d.id).toList()..sort();
    if (!listEquals(_lastIds, newIds)) {
      _lastIds = newIds;
      _future = _fetch();
    }
  }

  Future<List<_ActivityItem>> _fetch() async {
    if (widget.docs.isEmpty) return [];

    final results = await Future.wait(
      widget.docs.map((d) async {
        final snap = await d.reference
            .collection('Incidents')
            .orderBy('startedAt', descending: true)
            .limit(5)
            .get();
        return snap.docs.map((i) => _ActivityItem(d.id, i.data())).toList();
      }),
    );

    final all = results.expand((x) => x).toList()
      ..sort((a, b) {
        final at = a.startedAt?.millisecondsSinceEpoch ?? 0;
        final bt = b.startedAt?.millisecondsSinceEpoch ?? 0;
        return bt.compareTo(at);
      });

    return all.take(6).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "กิจกรรมล่าสุด",
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: 8),
            FutureBuilder<List<_ActivityItem>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                }

                final items = snapshot.data ?? [];
                if (items.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      "ยังไม่มีเหตุการณ์ผิดปกติ",
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
                    ),
                  );
                }

                return Column(
                  children: [
                    for (final item in items) _ActivityRow(item: item),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  final _ActivityItem item;
  const _ActivityRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final color = item.resolved ? const Color(0xFF2E7D32) : Colors.red;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            item.resolved ? Icons.check_circle_outline : Icons.error_outline,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.nanoId,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13),
                ),
                Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).textTheme.bodySmall?.color,
                  ),
                ),
              ],
            ),
          ),
          Text(
            _relativeTime(item.startedAt),
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).textTheme.bodySmall?.color,
            ),
          ),
        ],
      ),
    );
  }
}
