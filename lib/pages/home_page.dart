import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'calendar_page.dart';
import 'graph_page.dart';
import 'notification_history_page.dart';

// 🔥 [เพิ่ม] สำหรับกลับไปหน้า login
import 'login_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user!.uid;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFA5D6A7), // 🌿 เขียวอ่อน
        title: const Text("🌱 หน้าหลัก"),

        actions: [
          IconButton(
            icon: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('ESP32')
                  .where('uid', isEqualTo: uid)
                  .snapshots(),
              builder: (context, snapshot) {
                int count = 0;

                if (snapshot.hasData) {
                  for (var doc in snapshot.data!.docs) {
                    final data = doc.data() as Map<String, dynamic>;

                    double moisture =
                        (data['Moisture'] ?? 0).toDouble();

                    double automois =
                        (data['Automois'] ?? 0).toDouble();

                    if (moisture > automois) {
                      count++;
                    }
                  }
                }

                return Stack(
                  children: [
                    const Icon(Icons.notifications),

                    if (count > 0)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 18,
                            minHeight: 18,
                          ),
                          child: Text(
                            '$count',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            onPressed: () async {
              final snapshot = await FirebaseFirestore.instance
                  .collection('ESP32')
                  .where('uid', isEqualTo: uid)
                  .get();

              List<String> alerts = [];

              for (var doc in snapshot.docs) {
                final data = doc.data();

                double moisture = (data['Moisture'] ?? 0).toDouble();

                double automois = (data['Automois'] ?? 0).toDouble();

                if (moisture > automois) {
                  alerts.add(
                    "⚠️ ${doc.id}\nความชื้น: $moisture\nค่าที่กำหนด: $automois",
                  );
                }
              }

              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text("แจ้งเตือน"),
                  content: SingleChildScrollView(
                    child: Text(
                      alerts.isEmpty
                          ? "✅ ไม่มีการแจ้งเตือน"
                          : alerts.join("\n\n"),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("ปิด"),
                    ),
                  ],
                ),
              );
            },
          ),
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(uid)
                .snapshots(),
            builder: (context, snapshot) {
              print("====== DEBUG USER ======");
              print("UID ตอนนี้: $uid");
              print("Firestore data: ${snapshot.data?.data()}");

              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              final data = snapshot.data?.data() as Map<String, dynamic>?;

              final name = data?['displayName'] ??
                  user.displayName ??
                  user.email?.split('@')[0] ??
                  "User";

              final pic = data?['pictureUrl'] ?? user.photoURL;

              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 80,
                      child: Text(
                        name,
                        style: const TextStyle(fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),

                    const SizedBox(width: 8),
                    CircleAvatar(
                      radius: 16,
                      backgroundImage: pic != null ? NetworkImage(pic) : null,
                      child: pic == null
                          ? const Icon(Icons.person, size: 16)
                          : null,
                    ),

                    // 🔥 =========================
                    // 🔥 [เพิ่ม] ปุ่ม LOGOUT
                    // 🔥 =========================
                    IconButton(
                      icon: const Icon(Icons.logout),
                      onPressed: () async {
                        // 🔥 popup ยืนยัน
                        final confirm = await showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text("ยืนยัน"),
                            content: const Text("ต้องการออกจากระบบหรือไม่"),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text("ยกเลิก"),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text("ออก"),
                              ),
                            ],
                          ),
                        );

                        // 🔥 ถ้ากดยืนยัน
                        if (confirm == true) {
                          await FirebaseAuth.instance.signOut();

                          Navigator.pushAndRemoveUntil(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const LoginPage()),
                            (route) => false,
                          );
                        }
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('ESP32')
            .where('uid', isEqualTo: uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text("❌ ERROR: ${snapshot.error}"));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return const Center(
              child: Text("❌ ยังไม่มีอุปกรณ์ของคุณ"),
            );
          }

          return ListView(
            children: docs.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final nanoId = doc.id;

              double currentTarget = (data['Automois'] ?? 20).toDouble();
              final moisture = (data['Moisture'] ?? 0).toDouble();
              final automois = (data['Automois'] ?? 20).toDouble();

              final isAlert = moisture > automois;
              TextEditingController controller =
                  TextEditingController(text: currentTarget.toString());

              return Card(
                color: isAlert
                    ? Colors.red.shade100
                    : Colors.green.shade50,
                margin: const EdgeInsets.all(12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nanoId,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text("Moisture: ${data['Moisture']}"),

                      Text(
                        isAlert
                            ? "⚠️ สถานะ : ความชื้นสูงกว่าค่าที่กำหนด"
                            : "✅ สถานะ : ปกติ",
                        style: TextStyle(
                          color: isAlert ? Colors.red : Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      Text("Time: ${data['Time']}"),
                      Text("Auto: ${data['Auto']}"),
                      Text("Valve: ${data['Valve']}"),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Text("Auto"),
                              Switch(
                                value: data['Auto'] ?? false,
                                activeColor: Colors.green,
                                inactiveThumbColor: Colors.red,
                                onChanged: (val) async {
                                  await FirebaseFirestore.instance
                                      .collection('ESP32')
                                      .doc(nanoId)
                                      .update({
                                    'Auto': val,
                                    if (val == true) 'Valve': false,
                                  });
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          const Text("Valve"),
                          Switch(
                            value: data['Valve'] ?? false,
                            activeColor: Colors.green,
                            inactiveThumbColor: Colors.red,
                            onChanged: (val) async {
                              await FirebaseFirestore.instance
                                  .collection('ESP32')
                                  .doc(nanoId)
                                  .update({
                                'Valve': val,
                                if (val == true) 'Auto': false,
                                if (val == false) 'Auto': true,
                              });
                            },
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          const Text(" ตั้งค่าความชื้น: "),
                          SizedBox(
                            width: 80,
                            child: TextField(
                              controller: controller,
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton(
                            onPressed: () async {
                              final newValue = double.tryParse(controller.text);

                              if (newValue != null) {
                                await FirebaseFirestore.instance
                                    .collection('ESP32')
                                    .doc(nanoId)
                                    .update({
                                  'Automois': newValue,
                                });

                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text("✅ อัปเดตแล้ว"),
                                  ),
                                );
                              }
                            },
                            child: const Text("บันทึก"),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          ElevatedButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => CalendarPage(nanoId: nanoId),
                                ),
                              );
                            },
                            child: const Text("📅 Calendar"),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => GraphPage(nanoId: nanoId),
                                ),
                              );
                            },
                            child: const Text("📈 Graph"),
                          ),
                          const SizedBox(width: 10),

                          ElevatedButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      NotificationHistoryPage(
                                    nanoId: nanoId,
                                  ),
                                ),
                              );
                            },
                            child: const Text("🔔 History"),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}
