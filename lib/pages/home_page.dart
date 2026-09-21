import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:shimmer/shimmer.dart';
import 'package:fl_chart/fl_chart.dart';
import 'calendar_page.dart';
import 'graph_page.dart';
import 'notification_history_page.dart';
import 'add_device_page.dart';
import 'profile_page.dart';
import '../widgets/avatar.dart';

// 🔥 [เพิ่ม] สำหรับกลับไปหน้า login
import 'login_page.dart';
import '../main.dart';

// ตรงกับ isWithinScheduleWindow ใน functions/checkDevices.js เป๊ะๆ — ใช้ฝั่ง
// แอปเพื่อให้สวิตช์ Auto ตอบสนองทันทีตอนกด ไม่ต้องรอ backend รอบถัดไป (ทุก
// 15 นาที) backend จะคอยเช็คซ้ำเผื่อข้ามช่วงเวลาไปเองโดยไม่มีใครแตะสวิตช์
bool isWithinScheduleWindow(String startHHmm, String endHHmm) {
  int toMinutes(String hhmm) {
    final parts = hhmm.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  final nowBangkok = DateTime.now().toUtc().add(const Duration(hours: 7));
  final nowMinutes = nowBangkok.hour * 60 + nowBangkok.minute;

  final startMinutes = toMinutes(startHHmm);
  final endMinutes = toMinutes(endHHmm);

  if (startMinutes == endMinutes) return true;
  if (startMinutes < endMinutes) {
    return nowMinutes >= startMinutes && nowMinutes < endMinutes;
  }
  return nowMinutes >= startMinutes || nowMinutes < endMinutes;
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // กันไม่ให้ popup แจ้งเตือนอุปกรณ์มีปัญหาเด้งซ้ำทุกครั้งที่ stream ยิง
  // ค่าใหม่มา — โชว์แค่ครั้งเดียวต่อการเปิดหน้านี้หนึ่งรอบ
  bool _alertShown = false;

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
          // ปุ่มเพิ่มอุปกรณ์ถาวรใน AppBar — เมื่อก่อนมีทางเข้าหน้า
          // AddDevicePage แค่ตอนยังไม่มีอุปกรณ์เลยสักตัว (empty state) พอมี
          // อุปกรณ์แรกแล้วหาทางเพิ่มเครื่องที่ 2 ไม่เจอเลย
          IconButton(
            tooltip: "เพิ่มอุปกรณ์",
            icon: const Icon(Icons.add_circle_outline_rounded),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AddDevicePage()),
              );
            },
          ),
          ValueListenableBuilder<ThemeMode>(
            valueListenable: themeModeNotifier,
            builder: (context, mode, _) {
              return IconButton(
                tooltip: mode == ThemeMode.dark ? "โหมดสว่าง" : "โหมดมืด",
                icon: Icon(
                  mode == ThemeMode.dark ? Icons.light_mode : Icons.dark_mode,
                ),
                onPressed: toggleThemeMode,
              );
            },
          ),
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

                          if (!context.mounted) return;

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
            return const _HomeSkeleton();
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

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Column(
                children: [
                  _SummaryBar(
                    totalDevices: docs.length,
                    alertCount: alertCount,
                    avgMoisture: avgMoisture,
                  ),
                  Expanded(
                    child: GridView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 420,
                        mainAxisExtent: 480,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                      ),
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final doc = docs[index];
                        final data = doc.data() as Map<String, dynamic>;

                        return _DeviceCard(
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

class _DeviceCard extends StatefulWidget {
  final String nanoId;
  final Map<String, dynamic> data;
  final int index;

  const _DeviceCard({
    super.key,
    required this.nanoId,
    required this.data,
    this.index = 0,
  });

  @override
  State<_DeviceCard> createState() => _DeviceCardState();
}

class _DeviceCardState extends State<_DeviceCard>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _controller;
  final _focusNode = FocusNode();

  // อนิเมชั่นตอนการ์ดเพิ่งปรากฏขึ้นครั้งแรก (fade + เลื่อนขึ้นเล็กน้อย) หน่วง
  // เวลาเริ่มตามตำแหน่งในกริด ให้ดูเป็นการ "ไล่โผล่" ทีละใบแทนที่จะโผล่มา
  // พร้อมกันหมดทุกใบ
  late final AnimationController _entranceController;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  double get _currentTarget => (widget.data['Automois'] ?? 20).toDouble();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _currentTarget.toString());

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _fadeAnim = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOut,
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(_fadeAnim);

    Future.delayed(
      Duration(milliseconds: (widget.index * 60).clamp(0, 600)),
      () {
        if (mounted) _entranceController.forward();
      },
    );
  }

  @override
  void didUpdateWidget(covariant _DeviceCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // ซิงก์ค่าจาก Firestore เข้า field เฉพาะตอนที่ user ไม่ได้กำลังพิมพ์อยู่
    // กันไม่ให้ค่าที่พิมพ์ค้างถูกทับตอน snapshot ใหม่เข้ามาระหว่างพิมพ์
    if (!_focusNode.hasFocus) {
      _controller.text = _currentTarget.toString();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  // ยกเลิกการผูกอุปกรณ์ (ลบออกจากบัญชีตัวเอง ไม่ได้ลบ document ทิ้ง) — ยิงผ่าน
  // backend route /unclaim-device ด้วย Firebase ID token แทนที่จะเขียน
  // Firestore ตรงๆ จาก client เพื่อไม่ต้องเปิด rule เพิ่มให้ client เคลียร์
  // uid/ownerUid เอง (ดูเหตุผลเต็มๆ ที่ index.js)
  Future<void> _confirmAndRemoveDevice(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.red.withValues(alpha: 0.1),
          ),
          child: const Icon(
            Icons.warning_amber_rounded,
            color: Colors.red,
            size: 30,
          ),
        ),
        title: const Text(
          "ลบอุปกรณ์นี้?",
          textAlign: TextAlign.center,
        ),
        content: Text(
          "จะยกเลิกการผูก \"${widget.nanoId}\" กับบัญชีนี้ "
          "ต้องเชื่อมต่อใหม่ด้วย Device ID/Password ถึงจะใช้งานได้อีกครั้ง",
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("ยกเลิก"),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("ลบอุปกรณ์"),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    if (!context.mounted) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final idToken = await user.getIdToken();
      final res = await http.post(
        Uri.parse("https://line-auth-server.onrender.com/unclaim-device"),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $idToken",
        },
        body: jsonEncode({"nanoId": widget.nanoId}),
      );

      if (!context.mounted) return;

      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF2E7D32),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
            content: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 20),
                SizedBox(width: 10),
                Text(
                  "ลบอุปกรณ์แล้ว",
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("ลบอุปกรณ์ไม่สำเร็จ ลองใหม่อีกครั้ง")),
        );
      }
    } catch (err) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("ลบอุปกรณ์ไม่สำเร็จ ลองใหม่อีกครั้ง")),
      );
    }
  }

  // ตั้งค่าตารางเวลารดน้ำอัตโนมัติ — ปิดอยู่โดย default ต่ออุปกรณ์ ไม่กระทบ
  // อุปกรณ์ที่ไม่ได้เปิดใช้เลย พอกด "บันทึก" จะคำนวณ Auto ที่แท้จริงใหม่
  // ทันที (ไม่ต้องรอ backend รอบถัดไป) ให้เห็นผลตรงกับที่ตั้งค่าไว้เลย
  Future<void> _openScheduleDialog(
    BuildContext context,
    String nanoId,
    Map<String, dynamic> data,
  ) async {
    bool enabled = data['scheduleEnabled'] == true;
    TimeOfDay start = _parseHHmm(data['scheduleStart'] as String?) ??
        const TimeOfDay(hour: 6, minute: 0);
    TimeOfDay end = _parseHHmm(data['scheduleEnd'] as String?) ??
        const TimeOfDay(hour: 18, minute: 0);

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("ตั้งเวลารดน้ำ"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "อนุญาตให้โหมด Auto รดน้ำได้เฉพาะช่วงเวลาที่กำหนดเท่านั้น "
                "นอกช่วงเวลานี้ระบบจะปิดโหมด Auto ให้ชั่วคราว",
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text("เปิดใช้ตารางเวลา"),
                value: enabled,
                onChanged: (v) => setDialogState(() => enabled = v),
              ),
              if (enabled) ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.wb_sunny_outlined),
                  title: const Text("เริ่ม"),
                  trailing: Text(start.format(context)),
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: start,
                    );
                    if (picked != null) {
                      setDialogState(() => start = picked);
                    }
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.nights_stay_outlined),
                  title: const Text("สิ้นสุด"),
                  trailing: Text(end.format(context)),
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: end,
                    );
                    if (picked != null) {
                      setDialogState(() => end = picked);
                    }
                  },
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("ยกเลิก"),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("บันทึก"),
            ),
          ],
        ),
      ),
    );

    if (saved != true) return;

    final startHHmm = _formatHHmm(start);
    final endHHmm = _formatHHmm(end);
    // desiredAuto: ถ้ายังไม่เคยมีมาก่อน ให้เริ่มจากค่า Auto ปัจจุบัน กัน
    // ไม่ให้ผู้ใช้เปิดตารางเวลาแล้ว Auto ที่เปิดอยู่ก่อนหน้าหายไปเฉยๆ
    final desiredAuto = data['desiredAuto'] ?? data['Auto'] ?? false;
    final effective = enabled
        ? (desiredAuto == true && isWithinScheduleWindow(startHHmm, endHHmm))
        : (desiredAuto == true);

    await FirebaseFirestore.instance.collection('ESP32').doc(nanoId).update({
      'scheduleEnabled': enabled,
      'scheduleStart': startHHmm,
      'scheduleEnd': endHHmm,
      'desiredAuto': desiredAuto,
      'Auto': effective,
      if (effective) 'Valve': false,
    });
  }

  TimeOfDay? _parseHHmm(String? hhmm) {
    if (hhmm == null) return null;
    final parts = hhmm.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  String _formatHHmm(TimeOfDay time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final nanoId = widget.nanoId;
    final data = widget.data;
    final currentTarget = _currentTarget;
    final moisture = (data['Moisture'] ?? 0).toDouble();
    final automois = (data['Automois'] ?? 20).toDouble();
    final isAlert = moisture > automois;
    final isOffline = data['offline'] == true;
    final faultType = data['faultType'] as String?;
    final hasValveFault = !isOffline && faultType != null;

    final card = Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        // การ์ดทุกใบสูงเท่ากันตายตัว (กำหนดจาก GridView) — ห่อด้วย
        // SingleChildScrollView กันไว้ ถ้าเนื้อหาในอนาคตยาวเกินพื้นที่การ์ด
        // จะแค่ scroll ข้างในการ์ดเอง ไม่มีทาง overflow ล้นออกมาอีก
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isOffline
                          ? Colors.grey.shade200
                          : (hasValveFault
                              ? Colors.orange.shade50
                              : (isAlert
                                  ? Colors.red.shade50
                                  : const Color(0xFFE8F5E9))),
                    ),
                    child: Icon(
                      isOffline
                          ? Icons.cloud_off
                          : (hasValveFault
                              ? Icons.report_problem_outlined
                              : Icons.water_drop),
                      color: isOffline
                          ? Colors.grey.shade600
                          : (hasValveFault
                              ? Colors.orange.shade800
                              : (isAlert
                                  ? Colors.red
                                  : const Color(0xFF2E7D32))),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          nanoId,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (data['groupId'] != null)
                          Text(
                            "กลุ่ม: ${data['groupId']}",
                            style: TextStyle(
                              fontSize: 12,
                              color:
                                  Theme.of(context).textTheme.bodySmall?.color,
                            ),
                          ),
                        const SizedBox(height: 2),
                        _LastUpdatedText(
                          nanoId: nanoId,
                          lastSeen: data['lastSeen'] as Timestamp?,
                        ),
                      ],
                    ),
                  ),
                  _StatusChip(
                    isAlert: isAlert,
                    isOffline: isOffline,
                    faultType: faultType,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _MoistureSparkline(nanoId: nanoId),
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _MoistureGauge(
                        moisture: data['Moisture'] as num?,
                        target: currentTarget,
                        isOffline: isOffline,
                      ),
                    ),
                    const _StatDivider(),
                    Expanded(
                      child: _StatTile(
                        icon: Icons.flag,
                        label: "Target",
                        value: currentTarget.toString(),
                      ),
                    ),
                    const _StatDivider(),
                    Expanded(
                      child: _StatTile(
                        icon: Icons.schedule,
                        label: "Time",
                        value: "${data['Time'] ?? '-'}",
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _ControlChip(
                      label: "Auto",
                      icon: Icons.auto_mode,
                      // ถ้าเปิดใช้ตารางเวลาไว้ โชว์ "ความตั้งใจ" ของผู้ใช้
                      // (desiredAuto) แทนค่า Auto จริงที่อาจถูกตารางเวลา
                      // บังคับปิดชั่วคราวอยู่ — ไม่งั้นสวิตช์จะดูเหมือน
                      // ปิดเองโดยไม่มีเหตุผลตอนอยู่นอกช่วงเวลา
                      value: (data['scheduleEnabled'] == true)
                          ? (data['desiredAuto'] ?? data['Auto'] ?? false)
                          : (data['Auto'] ?? false),
                      onChanged: (val) async {
                        final scheduleEnabled = data['scheduleEnabled'] == true;

                        if (!scheduleEnabled) {
                          // ของเดิม ไม่เปลี่ยนพฤติกรรมเลยถ้าไม่ได้เปิดใช้
                          // ตารางเวลา
                          await FirebaseFirestore.instance
                              .collection('ESP32')
                              .doc(nanoId)
                              .update({
                            'Auto': val,
                            if (val == true) 'Valve': false,
                          });
                          return;
                        }

                        final scheduleStart = data['scheduleStart'] as String?;
                        final scheduleEnd = data['scheduleEnd'] as String?;
                        final effective = val &&
                            (scheduleStart == null ||
                                scheduleEnd == null ||
                                isWithinScheduleWindow(
                                    scheduleStart, scheduleEnd));

                        await FirebaseFirestore.instance
                            .collection('ESP32')
                            .doc(nanoId)
                            .update({
                          'desiredAuto': val,
                          'Auto': effective,
                          if (effective) 'Valve': false,
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ControlChip(
                      label: "Valve",
                      icon: Icons.water,
                      value: data['Valve'] ?? false,
                      onChanged: (val) async {
                        await FirebaseFirestore.instance
                            .collection('ESP32')
                            .doc(nanoId)
                            .update({
                          'Valve': val,
                          // เปิด Valve มือ = ปิด Auto กันชนกัน แต่ปิด Valve ไม่ควร
                          // ไปเปิด Auto กลับให้เอง เพราะผู้ใช้อาจตั้งใจแค่จะหยุด
                          // รดน้ำ ไม่ได้ต้องการให้ระบบตัดสินใจเปิดวาล์วเองอีก
                          //
                          // ต้องเคลียร์ desiredAuto ไปด้วย ไม่งั้นถ้าเปิดใช้
                          // ตารางเวลาไว้ checkDevices.js รอบถัดไปจะเห็นว่า
                          // desiredAuto ยังเป็น true แล้วเปิด Auto กลับมาเอง
                          // ทับการเปิดวาล์วมือที่เพิ่งสั่งไป
                          if (val == true) 'Auto': false,
                          if (val == true) 'desiredAuto': false,
                        });
                      },
                    ),
                  ),
                ],
              ),
              // ถ้าเปิดตารางเวลาไว้ และผู้ใช้ตั้งใจเปิด Auto แต่ตอนนี้ไม่ใช่
              // ช่วงเวลาที่อนุญาต — บอกให้ชัดว่าทำไม Auto ถึงไม่ทำงานตอนนี้
              // กันสับสนว่าสวิตช์เสียหรือระบบพัง
              if (data['scheduleEnabled'] == true &&
                  (data['desiredAuto'] ?? data['Auto'] ?? false) == true &&
                  data['Auto'] != true)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      Icon(Icons.schedule,
                          size: 14,
                          color: Theme.of(context).textTheme.bodySmall?.color),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          "Auto หยุดชั่วคราวตามตารางเวลา "
                          "(${data['scheduleStart']} - ${data['scheduleEnd']})",
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).textTheme.bodySmall?.color,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 14),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).dividerColor,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.tune,
                        size: 18,
                        color: Theme.of(context).textTheme.bodySmall?.color),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        "ตั้งค่าความชื้น",
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                    SizedBox(
                      width: 70,
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 13),
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 36,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                        ),
                        onPressed: () async {
                          final newValue = double.tryParse(_controller.text);

                          if (newValue != null) {
                            await FirebaseFirestore.instance
                                .collection('ESP32')
                                .doc(nanoId)
                                .update({
                              'Automois': newValue,
                            });

                            if (!context.mounted) return;

                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                behavior: SnackBarBehavior.floating,
                                backgroundColor: const Color(0xFF2E7D32),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                margin: const EdgeInsets.all(16),
                                content: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.check_circle,
                                        color: Colors.white, size: 20),
                                    SizedBox(width: 10),
                                    Text(
                                      "อัปเดตค่าความชื้นแล้ว",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }
                        },
                        child: const Text("บันทึก"),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.calendar_month,
                      label: "Calendar",
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CalendarPage(nanoId: nanoId),
                          ),
                        );
                      },
                    ),
                  ),
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.show_chart,
                      label: "Graph",
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => GraphPage(nanoId: nanoId),
                          ),
                        );
                      },
                    ),
                  ),
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.notifications_outlined,
                      label: "History",
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => NotificationHistoryPage(
                              nanoId: nanoId,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  // ซ่อนตัวเลือกลบไว้หลังเมนู ไม่ใช่ปุ่มถังขยะสีแดงลอยเด่น
                  // เพราะกลัวกดโดนโดยไม่ตั้งใจ — ต้องกดเปิดเมนูก่อน แล้วค่อย
                  // เลือก "ลบอุปกรณ์" แล้วค่อยกดยืนยันอีกที รวม 3 ขั้นตอน
                  PopupMenuButton<String>(
                    tooltip: "ตัวเลือกเพิ่มเติม",
                    icon: const Icon(Icons.more_vert),
                    onSelected: (value) {
                      if (value == 'remove') {
                        _confirmAndRemoveDevice(context);
                      } else if (value == 'schedule') {
                        _openScheduleDialog(context, nanoId, data);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'schedule',
                        child: Row(
                          children: [
                            Icon(Icons.schedule),
                            SizedBox(width: 8),
                            Text("ตั้งเวลารดน้ำ"),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'remove',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, color: Colors.red),
                            SizedBox(width: 8),
                            Text(
                              "ลบอุปกรณ์",
                              style: TextStyle(color: Colors.red),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(position: _slideAnim, child: card),
    );
  }
}

class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? Colors.grey.shade800 : Colors.grey.shade300;
    final highlight = isDark ? Colors.grey.shade700 : Colors.grey.shade100;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: Shimmer.fromColors(
          baseColor: base,
          highlightColor: highlight,
          child: Wrap(
            alignment: WrapAlignment.center,
            children: List.generate(
              3,
              (_) => Container(
                width: 420,
                height: 320,
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: base,
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryBar extends StatelessWidget {
  final int totalDevices;
  final int alertCount;
  final double avgMoisture;

  const _SummaryBar({
    required this.totalDevices,
    required this.alertCount,
    required this.avgMoisture,
  });

  @override
  Widget build(BuildContext context) {
    const okColor = Color(0xFF2E7D32);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: _KpiCard(
              icon: Icons.sensors,
              iconColor: okColor,
              label: "อุปกรณ์ทั้งหมด",
              numericValue: totalDevices.toDouble(),
              format: (v) => v.round().toString(),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _KpiCard(
              icon: Icons.warning_amber_rounded,
              iconColor: alertCount > 0 ? Colors.red : okColor,
              label: "แจ้งเตือน",
              numericValue: alertCount.toDouble(),
              format: (v) => v.round().toString(),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _KpiCard(
              icon: Icons.water_drop,
              iconColor: const Color(0xFF1E88E5),
              label: "ความชื้นเฉลี่ย",
              numericValue: avgMoisture,
              format: (v) => v.toStringAsFixed(1),
            ),
          ),
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final double numericValue;
  final String Function(double) format;

  const _KpiCard({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.numericValue,
    required this.format,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // แถบสีบอกตัวตนของการ์ดตั้งแต่แรกเห็น ผูกทั้งการ์ดเข้ากับสีของ
            // ไอคอน แทนที่จะปล่อยให้ไอคอนลอยเดี่ยวๆ เหนือค่าตัวเลข
            Container(width: 4, color: iconColor),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: iconColor.withValues(alpha: 0.14),
                          ),
                          child: Icon(icon, size: 16, color: iconColor),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color:
                                  Theme.of(context).textTheme.bodySmall?.color,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // ตัวเลขไล่จากค่าเดิมไปค่าใหม่ (นับขึ้น/ลง) แทนกระโดด
                    // ทันที ทุกครั้งที่ Firestore stream ส่งค่าใหม่เข้ามา
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: numericValue),
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.easeOut,
                      builder: (context, animatedValue, _) {
                        return Text(
                          format(animatedValue),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 26,
                            height: 1,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final bool isAlert;
  final bool isOffline;
  final String? faultType;

  const _StatusChip({
    required this.isAlert,
    this.isOffline = false,
    this.faultType,
  });

  @override
  Widget build(BuildContext context) {
    final hasValveFault = !isOffline && faultType != null;

    // ลำดับความสำคัญ: ขาดการติดต่อ > วาล์วผิดปกติ > ความชื้นเกิน > ปกติ
    // เพราะค่าที่โชว์อยู่อาจเป็นค่าเก่าที่ค้างมาจากก่อนจะเกิดปัญหา
    final Color color;
    final IconData icon;
    final String label;

    if (isOffline) {
      color = Colors.grey.shade600;
      icon = Icons.cloud_off;
      label = "ขาดการติดต่อ";
    } else if (hasValveFault) {
      color = Colors.orange.shade800;
      icon = Icons.report_problem_outlined;
      label = faultType == "valve_stuck_open"
          ? "วาล์วค้างเปิด"
          : "วาล์วอาจไม่ทำงาน";
    } else if (isAlert) {
      color = Colors.red;
      icon = Icons.warning_amber_rounded;
      label = "แจ้งเตือน";
    } else {
      color = Colors.green;
      icon = Icons.check_circle;
      label = "ปกติ";
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 18, color: const Color(0xFF2E7D32)),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          textAlign: TextAlign.center,
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).textTheme.bodySmall?.color,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 36,
      color: Theme.of(context).dividerColor,
    );
  }
}

class _ControlChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ControlChip({
    required this.label,
    required this.icon,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    const activeColor = Color(0xFF2E7D32);
    final mutedColor = Theme.of(context).textTheme.bodySmall?.color;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: value
            ? activeColor.withValues(alpha: 0.10)
            : Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: value
              ? activeColor.withValues(alpha: 0.4)
              : Theme.of(context).dividerColor,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: value ? activeColor : mutedColor),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: value ? activeColor : mutedColor,
              ),
            ),
          ),
          Transform.scale(
            scale: 0.8,
            child: Switch(
              value: value,
              activeThumbColor: activeColor,
              inactiveThumbColor: Colors.grey,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            Icon(icon, size: 20, color: const Color(0xFF2E7D32)),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).textTheme.bodyMedium?.color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LastUpdatedText extends StatefulWidget {
  final String nanoId;
  // ประทับจาก /update ตรงๆ ทุกครั้งที่อุปกรณ์รายงานค่าจริง — อัปเดตสดตาม
  // stream ของ ESP32 doc อยู่แล้ว ไม่ต้อง query ซ้ำ ถ้าเป็น null (อุปกรณ์เก่า
  // ที่ยังไม่เคยได้รับ /update รอบใหม่) จะ fallback ไปดู log ล่าสุดแทน
  final Timestamp? lastSeen;

  const _LastUpdatedText({required this.nanoId, required this.lastSeen});

  @override
  State<_LastUpdatedText> createState() => _LastUpdatedTextState();
}

class _LastUpdatedTextState extends State<_LastUpdatedText> {
  Future<Timestamp?>? _fallbackFuture;

  @override
  void initState() {
    super.initState();
    if (widget.lastSeen == null) {
      _fallbackFuture = _fetchLatestLogTimestamp();
    }
  }

  @override
  void didUpdateWidget(covariant _LastUpdatedText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.lastSeen != null) {
      _fallbackFuture = null;
    } else if (oldWidget.nanoId != widget.nanoId ||
        oldWidget.lastSeen != null) {
      _fallbackFuture = _fetchLatestLogTimestamp();
    }
  }

  Future<Timestamp?> _fetchLatestLogTimestamp() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('ESP32')
        .doc(widget.nanoId)
        .collection('Logs')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) return null;
    return snapshot.docs.first.data()['timestamp'] as Timestamp?;
  }

  String _relativeTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return "เมื่อสักครู่";
    if (diff.inMinutes < 60) return "${diff.inMinutes} นาทีที่แล้ว";
    if (diff.inHours < 24) return "${diff.inHours} ชม. ที่แล้ว";
    return "${diff.inDays} วันที่แล้ว";
  }

  // แสดง Row เดิมเสมอไม่ว่าจะมีข้อมูลหรือไม่ (แค่เปลี่ยนข้อความ) กันสัดส่วน
  // การ์ดเพี้ยนไปเทียบกับอุปกรณ์ตัวอื่นที่มีข้อมูลอยู่แล้ว
  Widget _buildText(BuildContext context, Timestamp? ts) {
    final color = Theme.of(context).textTheme.bodySmall?.color;

    return Row(
      children: [
        Icon(Icons.update, size: 12, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            ts == null
                ? "ยังไม่มีข้อมูล"
                : "อัปเดต: ${_relativeTime(ts.toDate())}",
            style: TextStyle(fontSize: 11, color: color),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.lastSeen != null) {
      return _buildText(context, widget.lastSeen);
    }

    return FutureBuilder<Timestamp?>(
      future: _fallbackFuture,
      builder: (context, snapshot) => _buildText(context, snapshot.data),
    );
  }
}

class _MoistureGauge extends StatelessWidget {
  final num? moisture;
  final double target;
  final bool isOffline;

  const _MoistureGauge({
    required this.moisture,
    required this.target,
    required this.isOffline,
  });

  @override
  Widget build(BuildContext context) {
    final value = moisture?.toDouble();
    final isAlert = value != null && value > target;
    final color = isOffline
        ? Colors.grey.shade500
        : (isAlert ? Colors.red : const Color(0xFF2E7D32));
    final ratio =
        (value == null || target <= 0) ? 0.0 : (value / target).clamp(0.0, 1.0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 40,
          height: 40,
          // ค่าความชื้นเป็น real-time (มาจาก Firestore stream) เปลี่ยนบ่อย —
          // ใช้ TweenAnimationBuilder ไล่ค่าเก่าไปค่าใหม่ทีละนิด (ทั้งวงแหวน
          // และตัวเลข) แทนการกระตุกเปลี่ยนทันทีทุกครั้งที่ค่าขยับ
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value == null ? 0 : ratio),
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOut,
            builder: (context, animatedRatio, _) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: animatedRatio,
                    strokeWidth: 4,
                    backgroundColor: color.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: value ?? 0),
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOut,
                    builder: (context, animatedValue, _) {
                      return Text(
                        value == null ? '-' : animatedValue.toStringAsFixed(0),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      );
                    },
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 4),
        Text(
          "Moisture",
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).textTheme.bodySmall?.color,
          ),
        ),
      ],
    );
  }
}

class _MoistureSparkline extends StatefulWidget {
  final String nanoId;

  const _MoistureSparkline({required this.nanoId});

  @override
  State<_MoistureSparkline> createState() => _MoistureSparklineState();
}

class _MoistureSparklineState extends State<_MoistureSparkline> {
  // แคช future ไว้เหมือน _LastUpdatedText กันยิง query ใหม่ทุกครั้งที่การ์ด
  // rebuild ตามอุปกรณ์ตัวอื่นในกริด
  late Future<List<FlSpot>> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetchRecentReadings();
  }

  @override
  void didUpdateWidget(covariant _MoistureSparkline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nanoId != widget.nanoId) {
      _future = _fetchRecentReadings();
    }
  }

  Future<List<FlSpot>> _fetchRecentReadings() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('ESP32')
        .doc(widget.nanoId)
        .collection('Logs')
        .orderBy('timestamp', descending: true)
        .limit(12)
        .get();

    final points = snapshot.docs.reversed
        .map((doc) => doc.data()['moisture'])
        .whereType<num>()
        .toList();

    return [
      for (var i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), points[i].toDouble()),
    ];
  }

  // กรอบตายตัวรอบกราฟ (ความสูงคงที่เสมอ ไม่ขยับตามข้อมูล) ใช้ทั้งตอนมีกราฟ
  // จริงและตอนยังไม่มีข้อมูล กันการ์ดหน้าตาไม่เท่ากันระหว่างอุปกรณ์ที่มี
  // ข้อมูลกับยังไม่มี — แกน Y ข้างในปรับสเกลเข้าหาข้อมูลเอง กราฟเลยไม่มีทาง
  // "โต" จนล้นกรอบนี้
  Widget _frame(BuildContext context, {required Widget child}) {
    // นูนขึ้นมาเหมือนปุ่ม "บันทึก" (ElevatedButton) แทนแบบฝังลึกที่ทำไว้ก่อน
    // — เงาอยู่ด้านล่าง/รอบขอบ ให้ดูเหมือนลอยอยู่เหนือพื้นการ์ด
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<FlSpot>>(
      future: _future,
      builder: (context, snapshot) {
        final spots = snapshot.data;
        if (spots == null || spots.length < 2) {
          return _frame(
            context,
            child: Center(
              child: Text(
                "ยังไม่มีข้อมูลกราฟ",
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
              ),
            ),
          );
        }

        final ys = spots.map((s) => s.y);
        final minY = ys.reduce((a, b) => a < b ? a : b);
        final maxY = ys.reduce((a, b) => a > b ? a : b);
        final pad = (maxY - minY) * 0.15;

        return _frame(
          context,
          child: LineChart(
            LineChartData(
              minY: minY - pad - 1,
              maxY: maxY + pad + 1,
              gridData: const FlGridData(show: false),
              titlesData: const FlTitlesData(show: false),
              borderData: FlBorderData(show: false),
              lineTouchData: const LineTouchData(enabled: false),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  color: const Color(0xFF2E7D32),
                  barWidth: 2,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    color: const Color(0xFF2E7D32).withValues(alpha: 0.08),
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
