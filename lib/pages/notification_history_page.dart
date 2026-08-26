import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
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
        backgroundColor: const Color(0xFFA5D6A7),
      ),
      body: StreamBuilder<QuerySnapshot>(
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
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          final docs = snapshot.data!.docs;

          final alerts = docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;

            double moisture =
                (data['moisture'] ?? 0).toDouble();

            double automois =
                (data['automois'] ?? 0).toDouble();

            return moisture > automois;
          }).toList();
          final totalAlerts = alerts.length;
          if (alerts.isEmpty) {
            return const Center(
              child: Text("✅ ไม่พบประวัติการแจ้งเตือน"),
            );
          }

          return Column(
            children: [

              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  "พบการแจ้งเตือนทั้งหมด $totalAlerts รายการ",
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              Expanded(
                child: ListView.builder(
            itemCount: alerts.length,
            itemBuilder: (context, index) {
              final data =
                  alerts[index].data() as Map<String, dynamic>;

              final timestamp =
                  data['timestamp'] as Timestamp?;
              String formattedDate = "";

                if (timestamp != null) {
                  formattedDate =
                      DateFormat('dd/MM/yyyy HH:mm')
                          .format(timestamp.toDate());
                }

              return Card(
                color: Colors.red.shade100,
                margin: const EdgeInsets.all(10),
                child: ListTile(
                  leading: const Icon(
                    Icons.warning,
                    color: Colors.red,
                  ),
                  title: Text(
                    "ความชื้น ${data['moisture']}",
                  ),
                  subtitle: Text(
                    "ค่าที่กำหนด ${data['automois']}\n"
                    "$formattedDate"
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  },
),
);
}
}