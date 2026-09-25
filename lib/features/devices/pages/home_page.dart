import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'add_device_page.dart';
import 'schedule_overview_page.dart';
import '../../profile/pages/profile_page.dart';
import '../../../shared/widgets/avatar.dart';
import '../services/farm_schedule.dart';
import '../services/rain_skip.dart';
import '../services/remove_device.dart';
import '../widgets/device_card.dart';
import '../widgets/home_summary_widgets.dart';
import '../widgets/recent_activity_card.dart';
import '../widgets/side_nav_rail.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // กันไม่ให้ popup แจ้งเตือนอุปกรณ์มีปัญหาเด้งซ้ำทุกครั้งที่ stream ยิง
  // ค่าใหม่มา — โชว์แค่ครั้งเดียวต่อการเปิดหน้านี้หนึ่งรอบ
  bool _alertShown = false;

  // ค้นหาอุปกรณ์ด้วยชื่อ — อยู่ในแถบด้านบนแบบถาวรแล้ว (ไม่ต้องกดเปิด/ปิดอีก
  // ต่อไปเหมือนตอนใช้ AppBar/Drawer เดิม)
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return "สวัสดีตอนเช้า";
    if (hour < 18) return "สวัสดีตอนบ่าย";
    return "สวัสดีตอนเย็น";
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user!.uid;

    return Scaffold(
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('ESP32')
            .where('uid', isEqualTo: uid)
            .snapshots(),
        builder: (context, snapshot) {
          Widget content;
          final docs = snapshot.data?.docs ?? [];

          if (snapshot.hasError) {
            content = Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline_rounded, color: Colors.red),
                  const SizedBox(width: 8),
                  Flexible(child: Text("เกิดข้อผิดพลาด: ${snapshot.error}")),
                ],
              ),
            );
          } else if (snapshot.connectionState == ConnectionState.waiting) {
            content = const HomeSkeleton();
          } else if (docs.isEmpty) {
            content = Center(
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
          } else {
            int alertCount = 0;
            int onlineCount = 0;
            double moistureSum = 0;
            for (final doc in docs) {
              final data = doc.data() as Map<String, dynamic>;
              final moisture = (data['Moisture'] ?? 0).toDouble();
              final automois = (data['Automois'] ?? 20).toDouble();
              moistureSum += moisture;
              if (moisture > automois) alertCount++;
              if (data['offline'] != true) onlineCount++;
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
                : docs
                    .where((d) => d.id.toLowerCase().contains(query))
                    .toList();

            content = Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 16),
                  children: [
                    SummaryBar(
                      docs: docs,
                      totalDevices: docs.length,
                      alertCount: alertCount,
                      avgMoisture: avgMoisture,
                    ),
                    WeatherForecastCard(docs: docs),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final narrow = constraints.maxWidth < 760;
                          final activity = RecentActivityCard(docs: docs);
                          final health = FleetHealthCard(
                            onlineCount: onlineCount,
                            totalCount: docs.length,
                            avgMoisture: avgMoisture,
                          );

                          if (narrow) {
                            return Column(
                              children: [
                                activity,
                                const SizedBox(height: 10),
                                health,
                              ],
                            );
                          }

                          return IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(flex: 2, child: activity),
                                const SizedBox(width: 10),
                                Expanded(child: health),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                      child: Text(
                        "อุปกรณ์ทั้งหมด",
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                      ),
                    ),
                    if (filteredDocs.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            "ไม่พบอุปกรณ์ที่ตรงกับ \"$_searchQuery\"",
                            style: TextStyle(
                              color:
                                  Theme.of(context).textTheme.bodySmall?.color,
                            ),
                          ),
                        ),
                      )
                    else
                      GridView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
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
                  ],
                ),
              ),
            );
          }

          return Row(
            children: [
              SideNavRail(
                onAddDevice: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AddDevicePage()),
                ),
                onFarmSchedule: () => openFarmScheduleDialog(context, docs),
                onScheduleOverview: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ScheduleOverviewPage(docs: docs),
                  ),
                ),
                onWeather: () => openRainSkipDialog(context, docs),
                onRemoveDevice: () => openRemoveDevicePicker(context, docs),
                onProfile: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ProfilePage()),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _TopBar(
                      uid: uid,
                      user: user,
                      greeting: _greeting(),
                      searchController: _searchController,
                      onSearchChanged: (v) => setState(() => _searchQuery = v),
                      onAddDevice: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const AddDevicePage()),
                      ),
                    ),
                    Expanded(child: content),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// แถบบนสุดของเนื้อหา (แทน AppBar เดิม) — คำทักทาย + ค้นหา (ถาวร ไม่ต้องกด
// เปิด/ปิดอีกต่อไป) + กระดิ่งแจ้งเตือน + โปรไฟล์
class _TopBar extends StatelessWidget {
  final String uid;
  final User user;
  final String greeting;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onAddDevice;

  const _TopBar({
    required this.uid,
    required this.user,
    required this.greeting,
    required this.searchController,
    required this.onSearchChanged,
    required this.onAddDevice,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // แถวบน: หัวข้อเล็กจางๆ + ค้นหา + กระดิ่ง + โปรไฟล์
          Row(
            children: [
              Text(
                "แดชบอร์ด",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
              ),
              const Spacer(),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: TextField(
                  controller: searchController,
                  onChanged: onSearchChanged,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: "ค้นหาอุปกรณ์...",
                    prefixIcon: Icon(Icons.search, size: 20),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _AlertBell(uid: uid),
              const SizedBox(width: 12),
              StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(uid)
                    .snapshots(),
                builder: (context, snapshot) {
                  final data = snapshot.data?.data() as Map<String, dynamic>?;
                  final pic = data?['pictureUrl'] ?? user.photoURL;

                  return InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ProfilePage()),
                      );
                    },
                    child: Avatar(photoUrl: pic, size: 36),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 20),
          // แถวล่าง: คำทักทาย + ปุ่มเพิ่มอุปกรณ์
          Row(
            children: [
              Expanded(
                child: StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .doc(uid)
                      .snapshots(),
                  builder: (context, snapshot) {
                    final data = snapshot.data?.data() as Map<String, dynamic>?;
                    final name = data?['displayName'] ??
                        user.displayName ??
                        user.email?.split('@')[0] ??
                        "User";

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "$greeting, $name",
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          "นี่คือสรุปสถานะฟาร์มของคุณตอนนี้",
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context).textTheme.bodySmall?.color,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              FilledButton.icon(
                onPressed: onAddDevice,
                icon: const Icon(Icons.add, size: 18),
                label: const Text("เพิ่มอุปกรณ์"),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AlertBell extends StatelessWidget {
  final String uid;
  const _AlertBell({required this.uid});

  @override
  Widget build(BuildContext context) {
    return IconButton(
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
              if (moisture > automois) count++;
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
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text("ความชื้น: $moisture · ค่าที่กำหนด: $automois"),
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
    );
  }
}
