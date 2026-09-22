import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'add_device_page.dart';
import 'schedule_overview_page.dart';
import '../../profile/pages/profile_page.dart';
import '../../../shared/widgets/avatar.dart';
import '../services/farm_schedule.dart';
import '../services/remove_device.dart';
import '../widgets/device_card.dart';
import '../widgets/home_summary_widgets.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // กันไม่ให้ popup แจ้งเตือนอุปกรณ์มีปัญหาเด้งซ้ำทุกครั้งที่ stream ยิง
  // ค่าใหม่มา — โชว์แค่ครั้งเดียวต่อการเปิดหน้านี้หนึ่งรอบ
  bool _alertShown = false;

  // ค้นหาอุปกรณ์ด้วยชื่อ — กรองแค่ตอนแสดงผลกริดเท่านั้น (ไม่กรองตัวเลขสรุป/
  // popup แจ้งเตือนด้านบน ให้ยังนับครบทุกอุปกรณ์เหมือนเดิมไม่ว่าจะค้นหาอะไร)
  final _searchController = TextEditingController();
  String _searchQuery = '';
  // ซ่อนช่องค้นหาไว้โดย default ตอนนี้ — เปิด/ปิดผ่านเมนูรวมใน AppBar แทน
  // การโชว์ถาวรเหมือนก่อนหน้านี้
  bool _searchBarVisible = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user!.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.eco_rounded),
            SizedBox(width: 8),
            Text("หน้าหลัก"),
          ],
        ),
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

                    double moisture = (data['Moisture'] ?? 0).toDouble();

                    double automois = (data['Automois'] ?? 20).toDouble();

                    if (moisture > automois) {
                      count++;
                    }
                  }
                }

                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.notifications),
                    Positioned(
                      right: -2,
                      top: -2,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        transitionBuilder: (child, anim) =>
                            ScaleTransition(scale: anim, child: child),
                        child: count > 0
                            ? Container(
                                key: ValueKey(count),
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
                              )
                            : const SizedBox.shrink(key: ValueKey('none')),
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

              List<Widget> alerts = [];

              for (var doc in snapshot.docs) {
                final data = doc.data();

                double moisture = (data['Moisture'] ?? 0).toDouble();

                double automois = (data['Automois'] ?? 20).toDouble();

                if (moisture > automois) {
                  alerts.add(
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.warning_amber_rounded,
                              color: Colors.orange, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  doc.id,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600),
                                ),
                                Text(
                                    "ความชื้น: $moisture · ค่าที่กำหนด: $automois"),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
              }

              if (!context.mounted) return;

              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: Row(
                    children: [
                      Icon(
                        alerts.isEmpty
                            ? Icons.check_circle
                            : Icons.warning_amber_rounded,
                        color: alerts.isEmpty ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: 8),
                      const Text("แจ้งเตือน"),
                    ],
                  ),
                  content: SingleChildScrollView(
                    child: alerts.isEmpty
                        ? const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle_outline_rounded,
                                  color: Colors.green, size: 20),
                              SizedBox(width: 8),
                              Text("ไม่มีการแจ้งเตือน"),
                            ],
                          )
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: alerts,
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
                    InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ProfilePage(),
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 4),
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
                            Avatar(photoUrl: pic, size: 32),
                          ],
                        ),
                      ),
                    ),
                    // ปุ่มออกจากระบบเดิมอยู่ตรงนี้ — ย้ายไปไว้ในหน้าโปรไฟล์
                    // (ProfilePage มีอยู่แล้ว) ไม่ต้องมีซ้ำ 2 ที่
                  ],
                ),
              );
            },
          ),
        ],
      ),
      // เมนูรวม — ย้ายจากป็อปอัพเล็กๆมาเป็น side drawer เต็มความสูงแบบที่ขอ
      // (ดูตัวอย่าง Larry analytic) ย้ายมาเปิดจากซ้ายสุดตามที่ขอภายหลัง — ใช้
      // drawer (ไม่ใช่ endDrawer) ทำให้ Scaffold ใส่ปุ่ม hamburger ซ้ายสุดของ
      // AppBar ให้เองอัตโนมัติ ไม่ต้องสร้างปุ่ม/คุม GlobalKey เองอีกต่อไป
      drawer: Drawer(
        // ต้องครอบด้วย StreamBuilder ของตัวเองเพราะ AppBar/drawer สร้าง
        // ก่อน StreamBuilder หลักของหน้า (ที่มี docs) จะยังไม่มีข้อมูล —
        // ใช้ context ตัวนอก (จาก build ของหน้านี้) สำหรับ Navigator.push/
        // เปิด dialog เสมอ ไม่ใช้ context ของ builder นี้ตรงๆ เพราะพอกด
        // Navigator.pop(ปิด drawer) ไปแล้ว widget ของ drawer จะถูกถอดออกจาก
        // ต้นไม้ ทำให้ context นั้นใช้ต่อไม่ได้อีก
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('ESP32')
              .where('uid', isEqualTo: uid)
              .snapshots(),
          builder: (drawerContext, menuSnapshot) {
            final menuDocs = menuSnapshot.data?.docs ?? [];
            return SafeArea(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  DrawerHeader(
                    decoration: BoxDecoration(
                      color:
                          Theme.of(drawerContext).appBarTheme.backgroundColor,
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.eco_rounded,
                            color: Colors.white, size: 32),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            "หน้าหลัก",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.pop(drawerContext),
                        ),
                      ],
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.add_circle_outline_rounded),
                    title: const Text("เพิ่มอุปกรณ์"),
                    onTap: () {
                      Navigator.pop(drawerContext);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AddDevicePage(),
                        ),
                      );
                    },
                  ),
                  ExpansionTile(
                    leading: const Icon(Icons.schedule),
                    title: const Text("ตารางเวลา"),
                    children: [
                      ListTile(
                        contentPadding: const EdgeInsets.only(left: 32),
                        leading: const Icon(Icons.schedule, size: 20),
                        title: const Text("ตั้งเวลาทั้งฟาร์ม"),
                        onTap: () {
                          Navigator.pop(drawerContext);
                          openFarmScheduleDialog(context, menuDocs);
                        },
                      ),
                      ListTile(
                        contentPadding: const EdgeInsets.only(left: 32),
                        leading:
                            const Icon(Icons.fact_check_outlined, size: 20),
                        title: const Text("สรุปตารางเวลา"),
                        onTap: () {
                          Navigator.pop(drawerContext);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  ScheduleOverviewPage(docs: menuDocs),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  ListTile(
                    leading: const Icon(Icons.search),
                    title: const Text("ค้นหาอุปกรณ์"),
                    onTap: () {
                      Navigator.pop(drawerContext);
                      setState(() => _searchBarVisible = !_searchBarVisible);
                    },
                  ),
                  ListTile(
                    leading:
                        const Icon(Icons.delete_outline, color: Colors.red),
                    title: const Text("ลบอุปกรณ์",
                        style: TextStyle(color: Colors.red)),
                    onTap: () {
                      Navigator.pop(drawerContext);
                      openRemoveDevicePicker(context, menuDocs);
                    },
                  ),
                ],
              ),
            );
          },
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('ESP32')
            .where('uid', isEqualTo: uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline_rounded, color: Colors.red),
                  const SizedBox(width: 8),
                  Flexible(child: Text("เกิดข้อผิดพลาด: ${snapshot.error}")),
                ],
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const HomeSkeleton();
          }

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.sensors_off,
                      size: 56,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      "ยังไม่มีอุปกรณ์ของคุณ",
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "เพิ่มอุปกรณ์เพื่อเริ่มติดตามความชื้น",
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AddDevicePage(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.add),
                      label: const Text("เพิ่มอุปกรณ์"),
                    ),
                  ],
                ),
              ),
            );
          }

          int alertCount = 0;
          double moistureSum = 0;
          for (final doc in docs) {
            final data = doc.data() as Map<String, dynamic>;
            final moisture = (data['Moisture'] ?? 0).toDouble();
            final automois = (data['Automois'] ?? 20).toDouble();
            moistureSum += moisture;
            if (moisture > automois) alertCount++;
          }
          final avgMoisture = moistureSum / docs.length;

          // เด้ง popup สรุปอุปกรณ์ที่มีปัญหาอยู่ตอนนี้ทันทีที่เข้าหน้านี้ —
          // แค่ครั้งเดียวต่อการเปิดหน้า ไม่เด้งซ้ำทุกครั้งที่ stream อัปเดต
          final problems = <(String nanoId, String label)>[
            for (final doc in docs)
              if ((doc.data() as Map<String, dynamic>)['offline'] == true)
                (doc.id, "ขาดการติดต่อ")
              else if ((doc.data() as Map<String, dynamic>)['faultType'] !=
                  null)
                (
                  doc.id,
                  (doc.data() as Map<String, dynamic>)['faultType'] ==
                          'valve_stuck_open'
                      ? "วาล์วค้างเปิด"
                      : "วาล์วอาจไม่ทำงาน",
                ),
          ];

          if (problems.isNotEmpty && !_alertShown) {
            _alertShown = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!context.mounted) return;
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.red),
                      SizedBox(width: 8),
                      Text("พบอุปกรณ์มีปัญหา"),
                    ],
                  ),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final p in problems)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text("• ${p.$1}: ${p.$2}"),
                          ),
                      ],
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
            });
          }

          // กรองแค่ตอนแสดงกริดเท่านั้น — ตัวเลขสรุป/popup ด้านบนยังนับจาก
          // docs เต็มทุกตัวเสมอ ไม่ว่าจะค้นหาอะไรอยู่ก็ตาม
          final query = _searchQuery.trim().toLowerCase();
          final filteredDocs = query.isEmpty
              ? docs
              : docs.where((d) => d.id.toLowerCase().contains(query)).toList();

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Column(
                children: [
                  SummaryBar(
                    totalDevices: docs.length,
                    alertCount: alertCount,
                    avgMoisture: avgMoisture,
                  ),
                  // ค้นหาอุปกรณ์ — จำเป็นตอนมีอุปกรณ์เยอะ (เช่น เป็นร้อยตัว)
                  // เลื่อนหาทีละใบไม่ไหว ตอนนี้ซ่อนไว้โดย default เปิด/ปิดผ่าน
                  // เมนูรวมใน AppBar แทน ("ตั้งเวลาทั้งฟาร์ม"/"ลบอุปกรณ์" ย้าย
                  // ไปอยู่ในเมนูรวมแล้ว ไม่ต้องมีปุ่มแยกอยู่แถวนี้อีก)
                  if (_searchBarVisible)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      // ไม่ใช้ Expanded ให้ช่องค้นหายืดเต็มแถว (ยาวเกินไปเมื่อ
                      // เทียบกับการ์ดกว้าง 420px ด้านล่าง) จำกัดความกว้างไว้
                      // แทน ให้ดูเป็นแถบค้นหาปกติ ไม่ใช่แถบยาวพาดตลอดหน้า
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 320),
                        child: TextField(
                          controller: _searchController,
                          autofocus: true,
                          onChanged: (v) => setState(() => _searchQuery = v),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: "ค้นหาชื่ออุปกรณ์...",
                            prefixIcon: const Icon(Icons.search, size: 20),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _searchQuery = '';
                                  _searchBarVisible = false;
                                });
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  Expanded(
                    child: filteredDocs.isEmpty
                        ? Center(
                            child: Text(
                              "ไม่พบอุปกรณ์ที่ตรงกับ \"$_searchQuery\"",
                              style: TextStyle(
                                color: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.color,
                              ),
                            ),
                          )
                        : GridView.builder(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 420,
                              mainAxisExtent: 420,
                              mainAxisSpacing: 16,
                              crossAxisSpacing: 16,
                            ),
                            itemCount: filteredDocs.length,
                            itemBuilder: (context, index) {
                              final doc = filteredDocs[index];
                              final data = doc.data() as Map<String, dynamic>;

                              return DeviceCard(
                                key: ValueKey(doc.id),
                                nanoId: doc.id,
                                data: data,
                                index: index,
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
