import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';

class NotificationHistoryPage extends StatelessWidget {
  final String nanoId;

  const NotificationHistoryPage({
    super.key,
    required this.nanoId,
  });

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              const Icon(Icons.notifications_active_rounded),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  "ประวัติแจ้งเตือน $nanoId",
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          bottom: const TabBar(
            tabs: [
              Tab(text: "อุปกรณ์มีปัญหา"),
              Tab(text: "ความชื้นเกิน"),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _IncidentHistoryTab(nanoId: nanoId),
            _MoistureAlertHistoryTab(nanoId: nanoId),
          ],
        ),
      ),
    );
  }
}

// แท็บใหม่ — ประวัติขาดการติดต่อ/วาล์วผิดปกติ อ่านจาก
// ESP32/{nanoId}/Incidents ที่ checkDevices.js บันทึกไว้ทุกครั้งที่เริ่ม/
// หายจากปัญหา ต่างจากแท็บความชื้นเกินซึ่งมาจาก log ค่าความชื้นล้วนๆ
class _IncidentHistoryTab extends StatelessWidget {
  final String nanoId;

  const _IncidentHistoryTab({required this.nanoId});

  static const _typeLabels = {
    "offline": ("ขาดการติดต่อ", Icons.cloud_off, Colors.grey),
    "valve_stuck_open": (
      "วาล์วค้างเปิด",
      Icons.report_problem_outlined,
      Colors.orange
    ),
    "valve_no_flow": (
      "วาล์วอาจไม่ทำงาน",
      Icons.report_problem_outlined,
      Colors.orange
    ),
    "sensor_error": (
      "เซนเซอร์อ่านค่าไม่สำเร็จ",
      Icons.sensors_off,
      Colors.red,
    ),
    "nano_error": (
      "ติดต่อ Nano ไม่ได้",
      Icons.developer_board_off,
      Colors.red,
    ),
  };

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('ESP32')
          .doc(nanoId)
          .collection('Incidents')
          .orderBy('startedAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text("ERROR : ${snapshot.error}"));
        }

        if (!snapshot.hasData) {
          return const _HistorySkeleton();
        }

        final docs = snapshot.data!.docs;

        if (docs.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_outline_rounded,
                    size: 48, color: Colors.green),
                SizedBox(height: 8),
                Text("ไม่พบประวัติปัญหาของอุปกรณ์นี้"),
              ],
            ),
          );
        }

        final now = DateTime.now();
        final thisMonthCount = docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final startedAt = data['startedAt'] as Timestamp?;
          if (startedAt == null) return false;
          final d = startedAt.toDate();
          return d.year == now.year && d.month == now.month;
        }).length;

        final openCount = docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return data['resolvedAt'] == null;
        }).length;

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Column(
              children: [
                Card(
                  margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: openCount > 0
                              ? Colors.red.shade50
                              : Colors.green.shade50,
                          child: Icon(
                            openCount > 0
                                ? Icons.warning_amber_rounded
                                : Icons.check_circle,
                            color: openCount > 0 ? Colors.red : Colors.green,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "พังทั้งหมด $thisMonthCount ครั้งเดือนนี้",
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                openCount > 0
                                    ? "มีปัญหาที่ยังไม่หาย $openCount รายการ"
                                    : "ไม่มีปัญหาที่ยังค้างอยู่",
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.color,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final grouped = <String, List<QueryDocumentSnapshot>>{};
                      for (final doc in docs) {
                        final data = doc.data() as Map<String, dynamic>;
                        final ts = data['startedAt'] as Timestamp?;
                        final dateKey = ts != null
                            // ใช้รูปแบบตัวเลขล้วน (ไม่ใช่ MMMM/ชื่อเดือน)
                            // เพราะแอปนี้ยังไม่ได้ initializeDateFormatting
                            // ให้ locale 'th' ไว้ ใช้ชื่อเดือนจะ throw runtime
                            // error ทันที
                            ? DateFormat('MM/yyyy').format(ts.toDate())
                            : 'ไม่ทราบวันที่';
                        grouped.putIfAbsent(dateKey, () => []).add(doc);
                      }

                      return ListView(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        children: [
                          for (final entry in grouped.entries) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                              child: Text(
                                "${entry.key} · ${entry.value.length} ครั้ง",
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.color,
                                ),
                              ),
                            ),
                            for (final doc in entry.value)
                              _IncidentTile(
                                data: doc.data() as Map<String, dynamic>,
                              ),
                          ],
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _IncidentTile extends StatelessWidget {
  final Map<String, dynamic> data;

  const _IncidentTile({required this.data});

  @override
  Widget build(BuildContext context) {
    final type = data['type'] as String? ?? '';
    final cause = data['cause'] as String? ?? '-';
    final startedAt = data['startedAt'] as Timestamp?;
    final resolvedAt = data['resolvedAt'] as Timestamp?;

    final (label, icon, color) = _IncidentHistoryTab._typeLabels[type] ??
        ("ไม่ทราบสาเหตุ", Icons.error_outline, Colors.grey);

    final startText = startedAt != null
        ? DateFormat('HH:mm').format(startedAt.toDate())
        : '-';
    final String durationText;
    if (startedAt == null) {
      durationText = '';
    } else if (resolvedAt == null) {
      durationText = 'ยังไม่หาย · เริ่ม $startText';
    } else {
      final duration = resolvedAt.toDate().difference(startedAt.toDate());
      final endText = DateFormat('HH:mm').format(resolvedAt.toDate());
      final durationLabel = duration.inHours > 0
          ? '${duration.inHours} ชม. ${duration.inMinutes % 60} นาที'
          : '${duration.inMinutes} นาที';
      durationText = '$startText - $endText · นาน $durationLabel';
    }

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          child: Icon(icon, color: color),
        ),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text("$cause\n$durationText"),
        isThreeLine: true,
      ),
    );
  }
}

// แท็บเดิม — ประวัติความชื้นเกินค่าที่กำหนด (จาก log ค่าความชื้นตรงๆ)
class _MoistureAlertHistoryTab extends StatelessWidget {
  final String nanoId;

  const _MoistureAlertHistoryTab({required this.nanoId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('ESP32')
          .doc(nanoId)
          .snapshots(),
      builder: (context, deviceSnapshot) {
        if (deviceSnapshot.hasError) {
          return Center(
            child: Text("ERROR : ${deviceSnapshot.error}"),
          );
        }

        if (!deviceSnapshot.hasData) {
          return const _HistorySkeleton();
        }

        final deviceData = deviceSnapshot.data!.data() as Map<String, dynamic>?;
        final targetMoisture = (deviceData?['Automois'] ?? 20).toDouble();

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('ESP32')
              .doc(nanoId)
              .collection('Logs')
              .orderBy('timestamp', descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Text("ERROR : ${snapshot.error}"),
              );
            }

            if (!snapshot.hasData) {
              return const _HistorySkeleton();
            }

            final docs = snapshot.data!.docs;

            final alerts = docs.where((doc) {
              final data = doc.data() as Map<String, dynamic>;

              double moisture = (data['moisture'] ?? 0).toDouble();

              return moisture > targetMoisture;
            }).toList();
            final totalAlerts = alerts.length;

            if (alerts.isEmpty) {
              return const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_outline_rounded,
                        size: 48, color: Colors.green),
                    SizedBox(height: 8),
                    Text("ไม่พบประวัติการแจ้งเตือน"),
                  ],
                ),
              );
            }

            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 700),
                child: Column(
                  children: [
                    Card(
                      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: Colors.red.shade50,
                              child: const Icon(
                                Icons.warning_amber_rounded,
                                color: Colors.red,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "พบการแจ้งเตือนทั้งหมด $totalAlerts รายการ",
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    "ค่าที่กำหนด $targetMoisture",
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.color,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: Builder(
                        builder: (context) {
                          // Group by day — `alerts` is already newest-first,
                          // so insertion order keeps groups newest-first too.
                          final grouped =
                              <String, List<QueryDocumentSnapshot>>{};
                          for (final doc in alerts) {
                            final data = doc.data() as Map<String, dynamic>;
                            final ts = data['timestamp'] as Timestamp?;
                            final dateKey = ts != null
                                ? DateFormat('dd/MM/yyyy').format(ts.toDate())
                                : 'ไม่ทราบวันที่';
                            grouped.putIfAbsent(dateKey, () => []).add(doc);
                          }

                          return ListView(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            children: [
                              for (final entry in grouped.entries) ...[
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 12, 16, 4),
                                  child: Text(
                                    entry.key,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.color,
                                    ),
                                  ),
                                ),
                                for (final doc in entry.value)
                                  _AlertTile(
                                    data: doc.data() as Map<String, dynamic>,
                                    targetMoisture: targetMoisture,
                                  ),
                              ],
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _AlertTile extends StatelessWidget {
  final Map<String, dynamic> data;
  final double targetMoisture;

  const _AlertTile({required this.data, required this.targetMoisture});

  @override
  Widget build(BuildContext context) {
    final timestamp = data['timestamp'] as Timestamp?;
    String formattedTime = "";
    if (timestamp != null) {
      formattedTime = DateFormat('HH:mm').format(timestamp.toDate());
    }

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.red.shade50,
          child: const Icon(Icons.warning, color: Colors.red),
        ),
        title: Text(
          "ความชื้น ${data['moisture']}",
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text("ค่าที่กำหนด $targetMoisture · $formattedTime"),
      ),
    );
  }
}

class _HistorySkeleton extends StatelessWidget {
  const _HistorySkeleton();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? Colors.grey.shade800 : Colors.grey.shade300;
    final highlight = isDark ? Colors.grey.shade700 : Colors.grey.shade100;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700),
        child: Shimmer.fromColors(
          baseColor: base,
          highlightColor: highlight,
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: List.generate(
              6,
              (_) => Container(
                height: 72,
                margin: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: base,
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
