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
    return Scaffold(
      appBar: AppBar(
        title: Text("🔔 ประวัติแจ้งเตือน $nanoId"),
      ),
      body: StreamBuilder<DocumentSnapshot>(
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

          final deviceData =
              deviceSnapshot.data!.data() as Map<String, dynamic>?;
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
                  child: Text("✅ ไม่พบประวัติการแจ้งเตือน"),
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
                                    padding: const EdgeInsets.fromLTRB(
                                        16, 12, 16, 4),
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
      ),
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
