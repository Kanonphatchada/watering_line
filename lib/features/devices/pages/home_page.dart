import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'add_device_page.dart';
import 'device_groups_page.dart';
import 'farm_members_page.dart';
import 'group_detail_page.dart';
import 'plant_profile_page.dart';
import 'schedule_page.dart';
import 'weather_page.dart';
import '../../profile/pages/profile_page.dart';
import '../../../shared/widgets/app_popup.dart';
import '../../../shared/widgets/avatar.dart';
import '../services/device_groups.dart';
import '../services/my_devices.dart';
import '../services/remove_device.dart';
import '../widgets/farm_selector.dart' show farmGroupIds;
import '../widgets/device_grid.dart';
import '../widgets/group_card.dart';
import '../widgets/home_summary_widgets.dart';
import '../widgets/recent_activity_card.dart';
import '../widgets/side_nav_rail.dart';
import '../widgets/status_chip.dart' show faultLabel;
import '../widgets/stress_watch_card.dart';
import '../utils/moisture_utils.dart';

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
      body: StreamBuilder<List<QueryDocumentSnapshot>>(
        stream: watchMyDevices(uid),
        builder: (context, snapshot) {
          Widget content;
          final docs = snapshot.data ?? [];

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
              if (isMoistureAlert(moisture, automois)) alertCount++;
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
                    faultLabel(
                      (doc.data() as Map<String, dynamic>)['faultType']
                          as String?,
                    ),
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
                    StressWatchCard(
                      docs: docs,
                      padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
                    ),
                    StreamBuilder<List<DeviceGroup>>(
                      stream: watchDeviceGroups(uid),
                      builder: (context, groupSnap) => _devicesSection(
                        context,
                        allDocs: docs,
                        searchResults: query.isEmpty ? null : filteredDocs,
                        groups: pruneMissingDevices(
                          groupSnap.data ?? const [],
                          docs.map((d) => d.id).toSet(),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final narrow = constraints.maxWidth < 760;
                          final activity = RecentActivityCard(docs: docs);
                          final health = FleetHealthCard(
                            onlineCount: onlineCount,
                            totalCount: docs.length,
                            alertCount: alertCount,
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
                onSchedule: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SchedulePage()),
                ),
                onWeather: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const WeatherPage()),
                ),
                onPlantProfile: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PlantProfilePage(docs: docs),
                  ),
                ),
                onGroups: () => _openGroups(docs),
                onMembers: () => _openMembers(docs),
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

  void _openGroups(List<QueryDocumentSnapshot> docs) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => DeviceGroupsPage(docs: docs)),
      );

  // หน้าสมาชิกเป็นของ "ฟาร์ม" — มีฟาร์มเดียวเปิดเลย หลายฟาร์มให้เลือกก่อน
  Future<void> _openMembers(List<QueryDocumentSnapshot> docs) async {
    final farms = farmGroupIds(docs);
    if (farms.isEmpty) {
      showAppPopup(context, "ยังไม่มีฟาร์ม", kind: PopupKind.info);
      return;
    }
    var farmId = farms.first;
    if (farms.length > 1) {
      final picked = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text("เลือกฟาร์ม"),
          children: [
            for (final f in farms)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, f),
                child: Text(f),
              ),
          ],
        ),
      );
      if (picked == null || !mounted) return;
      farmId = picked;
    }
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => FarmMembersPage(farmId: farmId)),
    );
  }

  void _openGroupDetail(String groupId) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => GroupDetailPage(groupId: groupId)),
      );

  // ส่วนล่างของแดชบอร์ด — มีกลุ่มแล้วแสดงเป็น "การ์ดกลุ่ม" (กดเข้าไปดูอุปกรณ์
  // ในกลุ่ม) แทนที่จะกองการ์ดอุปกรณ์ทุกตัวไว้หน้าเดียวจนรก; ยังไม่มีกลุ่มก็
  // แสดงกริดอุปกรณ์เหมือนเดิม พร้อมชวนให้สร้างกลุ่ม; ตอนค้นหาแสดงผลลัพธ์เป็น
  // การ์ดอุปกรณ์ตรงๆ เพราะผู้ใช้ตั้งใจหาตัวนั้นอยู่
  Widget _devicesSection(
    BuildContext context, {
    required List<QueryDocumentSnapshot> allDocs,
    required List<QueryDocumentSnapshot>? searchResults,
    required List<DeviceGroup> groups,
  }) {
    final muted = Theme.of(context).textTheme.bodySmall?.color;

    Widget header(String title, {List<Widget> actions = const []}) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: muted,
                ),
              ),
            ),
            ...actions,
          ],
        ),
      );
    }

    if (searchResults != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header("ผลการค้นหา (${searchResults.length})"),
          if (searchResults.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  "ไม่พบอุปกรณ์ที่ตรงกับ \"$_searchQuery\"",
                  style: TextStyle(color: muted),
                ),
              ),
            )
          else
            DeviceGrid(docs: searchResults, allDocs: allDocs),
        ],
      );
    }

    if (groups.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header(
            "อุปกรณ์ทั้งหมด",
            actions: [
              TextButton.icon(
                onPressed: () =>
                    openGroupEditor(context, docs: allDocs, groups: groups),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text("สร้างกลุ่ม"),
              ),
            ],
          ),
          DeviceGrid(docs: allDocs, allDocs: allDocs),
        ],
      );
    }

    final memberOf = <String, String>{
      for (final g in groups)
        for (final id in g.deviceIds) id: g.id,
    };
    GroupStats statsOf(Iterable<QueryDocumentSnapshot> members) =>
        computeGroupStats([
          for (final d in members) d.data() as Map<String, dynamic>,
        ]);

    final ungrouped =
        allDocs.where((d) => !memberOf.containsKey(d.id)).toList();

    final cards = <Widget>[
      for (final g in groups)
        GroupCard(
          name: g.name,
          iconKey: g.iconKey,
          colorIndex: g.colorIndex,
          stats: statsOf(allDocs.where((d) => memberOf[d.id] == g.id)),
          onTap: () => _openGroupDetail(g.id),
        ),
      if (ungrouped.isNotEmpty)
        GroupCard(
          name: "ไม่ได้จัดกลุ่ม",
          iconKey: 'house',
          colorIndex: 7,
          stats: statsOf(ungrouped),
          onTap: () => _openGroupDetail(ungroupedGroupId),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header(
          "กลุ่มของฉัน (${groups.length})",
          actions: [
            FilledButton.tonalIcon(
              onPressed: () =>
                  openGroupEditor(context, docs: allDocs, groups: groups),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text("เพิ่มกลุ่ม"),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: "จัดการกลุ่ม",
              icon: const Icon(Icons.tune_rounded),
              onPressed: () => _openGroups(allDocs),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              const gap = 12.0;
              const minCardWidth = 270.0;
              final columns =
                  ((constraints.maxWidth + gap) / (minCardWidth + gap))
                      .floor()
                      .clamp(1, 4);
              final cardWidth =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final c in cards) SizedBox(width: cardWidth, child: c),
                ],
              );
            },
          ),
        ),
      ],
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
      icon: StreamBuilder<List<QueryDocumentSnapshot>>(
        stream: watchMyDevices(uid),
        builder: (context, snapshot) {
          int count = 0;
          if (snapshot.hasData) {
            for (var doc in snapshot.data!) {
              final data = doc.data() as Map<String, dynamic>;
              double moisture = (data['Moisture'] ?? 0).toDouble();
              double automois = (data['Automois'] ?? 20).toDouble();
              if (isMoistureAlert(moisture, automois)) count++;
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
        final myDocs = await getMyDevices(uid);

        List<Widget> alerts = [];

        for (var doc in myDocs) {
          final data = doc.data() as Map<String, dynamic>;
          double moisture = (data['Moisture'] ?? 0).toDouble();
          double automois = (data['Automois'] ?? 20).toDouble();

          if (isMoistureAlert(moisture, automois)) {
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
