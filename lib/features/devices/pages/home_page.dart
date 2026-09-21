import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'add_device_page.dart';
import '../../profile/pages/profile_page.dart';
import '../../../shared/widgets/avatar.dart';
import '../utils/schedule_utils.dart';
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

  // ลบอุปกรณ์จากเมนูรวม — ต่างจากปุ่มลบที่เคยอยู่ในการ์ด (ตรงนั้นรู้อยู่แล้ว
  // ว่าจะลบตัวไหน) ตรงนี้ต้องให้เลือกอุปกรณ์ก่อน จึงมีช่องค้นหา+รายชื่อให้กด
  // เลือกในไดอะล็อกนี้ พอเลือกแล้วค่อยไปเข้ากล่องยืนยันเดิม
  // (confirmAndRemoveDevice) ต่อ
  Future<void> _openRemoveDevicePicker(
    BuildContext context,
    List<QueryDocumentSnapshot> docs,
  ) async {
    if (docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("ยังไม่มีอุปกรณ์ให้ลบ")),
      );
      return;
    }

    final pickerQueryController = TextEditingController();
    final nanoId = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final q = pickerQueryController.text.trim().toLowerCase();
          final matches = q.isEmpty
              ? docs
              : docs.where((d) => d.id.toLowerCase().contains(q)).toList();

          return AlertDialog(
            title: const Text("เลือกอุปกรณ์ที่จะลบ"),
            content: SizedBox(
              width: 360,
              height: 400,
              child: Column(
                children: [
                  TextField(
                    controller: pickerQueryController,
                    autofocus: true,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: "ค้นหาชื่ออุปกรณ์...",
                      prefixIcon: Icon(Icons.search, size: 20),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: matches.isEmpty
                        ? const Center(child: Text("ไม่พบอุปกรณ์"))
                        : ListView.builder(
                            itemCount: matches.length,
                            itemBuilder: (context, index) {
                              final d = matches[index];
                              final data = d.data() as Map<String, dynamic>;
                              return ListTile(
                                leading: const Icon(Icons.sensors),
                                title: Text(d.id),
                                subtitle: data['groupId'] != null
                                    ? Text("กลุ่ม: ${data['groupId']}")
                                    : null,
                                trailing: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.red,
                                ),
                                onTap: () => Navigator.pop(context, d.id),
                              );
                            },
                          ),
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
          );
        },
      ),
    );

    // ห้าม dispose ทันทีตรงนี้ — Future ของ showDialog จะ resolve ทันทีที่
    // Navigator.pop() เรียก แต่ dialog ยังเล่น animation ปิดอยู่บนจอ (TextField
    // ที่ผูกกับ controller นี้ยังอยู่ใน tree ระหว่าง transition) การ dispose
    // ตอนนั้นเลยไปโดน TextField ที่ยังไม่ถูกถอดออกจาก tree จริงๆ ทำให้ Flutter
    // แจ้ง assertion "_dependents.isEmpty is not true" แครชขึ้นจอแดง — เลื่อน
    // ไปทำหลัง frame ปัจจุบันจบก่อน ให้ transition มีเวลาเคลียร์ตัวเองก่อน
    WidgetsBinding.instance.addPostFrameCallback((_) {
      pickerQueryController.dispose();
    });

    if (nanoId == null) return;
    if (!context.mounted) return;

    await confirmAndRemoveDevice(context, nanoId);
  }

  // ตั้งเวลารดน้ำทั้งกลุ่ม/ฟาร์มในครั้งเดียว — ให้ทุกอุปกรณ์ในกลุ่มเดียวกัน
  // (อาจเป็นร้อยตัว) ใช้ตารางเวลาเดียวกันโดย default โดยไม่ต้องตั้งทีละตัว
  // อุปกรณ์ที่ตั้ง scheduleOverride ของตัวเองไว้แล้วจะไม่ถูกทับ (ดู
  // resolveScheduleSource ฝั่ง checkDevices.js)
  Future<void> _openFarmScheduleDialog(
    BuildContext context,
    List<QueryDocumentSnapshot> docs,
  ) async {
    final groupIds = docs
        .map((d) => (d.data() as Map<String, dynamic>)['groupId'] as String?)
        .whereType<String>()
        .toSet()
        .toList();

    if (groupIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("ไม่พบกลุ่ม/ฟาร์มของอุปกรณ์เลย")),
      );
      return;
    }

    String groupId;
    if (groupIds.length == 1) {
      groupId = groupIds.first;
    } else {
      final picked = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text("เลือกกลุ่ม/ฟาร์ม"),
          children: [
            for (final g in groupIds)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, g),
                child: Text(g),
              ),
          ],
        ),
      );
      if (picked == null) return;
      groupId = picked;
    }

    if (!context.mounted) return;
    await _showFarmScheduleEditor(context, groupId, docs);
  }

  Future<void> _showFarmScheduleEditor(
    BuildContext context,
    String groupId,
    List<QueryDocumentSnapshot> docs,
  ) async {
    final registryDoc = await FirebaseFirestore.instance
        .collection('device_registry')
        .doc(groupId)
        .get();
    final registryData = registryDoc.data() ?? {};

    bool enabled = registryData['scheduleEnabled'] == true;
    String mode = registryData['scheduleMode'] == 'block' ? 'block' : 'allow';
    TimeOfDay start = parseHHmm(registryData['scheduleStart'] as String?) ??
        const TimeOfDay(hour: 6, minute: 0);
    TimeOfDay end = parseHHmm(registryData['scheduleEnd'] as String?) ??
        const TimeOfDay(hour: 18, minute: 0);
    bool exceptEnabled = registryData['scheduleExceptEnabled'] == true;
    TimeOfDay exceptStart =
        parseHHmm(registryData['scheduleExceptStart'] as String?) ??
            const TimeOfDay(hour: 12, minute: 0);
    TimeOfDay exceptEnd =
        parseHHmm(registryData['scheduleExceptEnd'] as String?) ??
            const TimeOfDay(hour: 14, minute: 0);

    final deviceCount = docs
        .where((d) => (d.data() as Map<String, dynamic>)['groupId'] == groupId)
        .length;

    if (!mounted) return;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("ตั้งเวลารดน้ำทั้งฟาร์ม"),
          // ล็อกความกว้างไว้คงที่ เหมือนกับ dialog ตั้งเวลารายอุปกรณ์ — ห่อ
          // ด้วย SingleChildScrollView ด้วย เพราะเนื้อหายาวขึ้นมากหลังเพิ่ม
          // ช่วงห้ามรดพิเศษ อาจเกินพื้นที่ dialog บนหน้าจอเล็กจนล้น (overflow)
          content: SizedBox(
            width: 320,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "ใช้กับอุปกรณ์ $deviceCount ตัวในกลุ่ม \"$groupId\" "
                    "(อุปกรณ์ที่ตั้งเวลาเฉพาะตัวไว้แล้วจะไม่ถูกทับ)",
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text("เปิดใช้ตารางเวลา"),
                    value: enabled,
                    onChanged: (v) => setDialogState(() => enabled = v),
                  ),
                  if (enabled) ...[
                    const SizedBox(height: 4),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'allow',
                          label: Text("รดได้เฉพาะช่วงนี้"),
                        ),
                        ButtonSegment(
                          value: 'block',
                          label: Text("ห้ามรดช่วงนี้"),
                        ),
                      ],
                      selected: {mode},
                      onSelectionChanged: (s) =>
                          setDialogState(() => mode = s.first),
                    ),
                    const SizedBox(height: 12),
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
                        if (picked != null) setDialogState(() => end = picked);
                      },
                    ),
                    const Divider(height: 24),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text("เพิ่มช่วงห้ามรดพิเศษ"),
                      subtitle: const Text(
                        "ห้ามรดในช่วงนี้เสมอ ซ้อนอยู่ในช่วงเวลาข้างบน",
                      ),
                      value: exceptEnabled,
                      onChanged: (v) => setDialogState(() => exceptEnabled = v),
                    ),
                    if (exceptEnabled) ...[
                      const SizedBox(height: 4),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.wb_sunny_outlined),
                        title: const Text("เริ่มห้ามรด"),
                        trailing: Text(exceptStart.format(context)),
                        onTap: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: exceptStart,
                          );
                          if (picked != null) {
                            setDialogState(() => exceptStart = picked);
                          }
                        },
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.nights_stay_outlined),
                        title: const Text("สิ้นสุดห้ามรด"),
                        trailing: Text(exceptEnd.format(context)),
                        onTap: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: exceptEnd,
                          );
                          if (picked != null) {
                            setDialogState(() => exceptEnd = picked);
                          }
                        },
                      ),
                    ],
                  ],
                ],
              ),
            ),
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

    final startHHmm = formatHHmm(start);
    final endHHmm = formatHHmm(end);
    final exceptStartHHmm = formatHHmm(exceptStart);
    final exceptEndHHmm = formatHHmm(exceptEnd);

    try {
      await FirebaseFirestore.instance
          .collection('device_registry')
          .doc(groupId)
          .update({
        'scheduleEnabled': enabled,
        'scheduleMode': mode,
        'scheduleStart': startHHmm,
        'scheduleEnd': endHHmm,
        'scheduleExceptEnabled': exceptEnabled,
        'scheduleExceptStart': exceptStartHHmm,
        'scheduleExceptEnd': exceptEndHHmm,
      });

      // อัปเดต Auto ทันทีให้ทุกอุปกรณ์ในกลุ่มที่ "ไม่ได้" override ไว้เอง —
      // ให้เห็นผลตรงกับที่ตั้งค่าไว้เลย ไม่ต้องรอ backend รอบถัดไป (15 นาที)
      final allowedNow = resolveScheduleAllowed(
        mode: mode,
        startHHmm: startHHmm,
        endHHmm: endHHmm,
        exceptEnabled: exceptEnabled,
        exceptStartHHmm: exceptStartHHmm,
        exceptEndHHmm: exceptEndHHmm,
      );

      final batch = FirebaseFirestore.instance.batch();
      for (final doc in docs) {
        final d = doc.data() as Map<String, dynamic>;
        if (d['groupId'] != groupId) continue;
        if (d['scheduleOverride'] == true) {
          continue; // ไม่ทับอุปกรณ์ที่ override ไว้
        }

        final desiredAuto = d['desiredAuto'] ?? d['Auto'] ?? false;
        final effective = enabled
            ? (desiredAuto == true && allowedNow)
            : (desiredAuto == true);
        if (effective == (d['Auto'] == true)) continue;

        batch.update(doc.reference, {
          'Auto': effective,
          if (effective) 'Valve': false,
        });
      }
      await batch.commit();

      if (!context.mounted) return;
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
                "บันทึกตารางเวลาทั้งฟาร์มแล้ว",
                style:
                    TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      );
    } catch (err) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("บันทึกไม่สำเร็จ: $err")),
      );
    }
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
          // เมนูรวม — เดิมมี "เพิ่มอุปกรณ์" เป็นปุ่มแยก + "ตั้งเวลาทั้งฟาร์ม"
          // กับช่องค้นหาอยู่อีกแถวใต้แถบสรุป รวมเข้าเมนูเดียวให้ดูเป็น
          // ระเบียบขึ้น ต้องครอบด้วย StreamBuilder ของตัวเองเพราะ AppBar
          // สร้างก่อน StreamBuilder หลักของหน้า (ที่มี docs) จะยังไม่มีข้อมูล
          // — ย้ายมาไว้ขวาสุดของแถบ (หลังไอคอนโปรไฟล์) ตามที่ขอ
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('ESP32')
                .where('uid', isEqualTo: uid)
                .snapshots(),
            builder: (context, menuSnapshot) {
              final menuDocs = menuSnapshot.data?.docs ?? [];
              return PopupMenuButton<String>(
                tooltip: "เมนู",
                icon: const Icon(Icons.menu),
                onSelected: (value) {
                  switch (value) {
                    case 'add':
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AddDevicePage(),
                        ),
                      );
                    case 'schedule':
                      _openFarmScheduleDialog(context, menuDocs);
                    case 'search':
                      setState(() => _searchBarVisible = !_searchBarVisible);
                    case 'remove':
                      _openRemoveDevicePicker(context, menuDocs);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'add',
                    child: Row(
                      children: [
                        Icon(Icons.add_circle_outline_rounded),
                        SizedBox(width: 8),
                        Text("เพิ่มอุปกรณ์"),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'schedule',
                    child: Row(
                      children: [
                        Icon(Icons.schedule),
                        SizedBox(width: 8),
                        Text("ตั้งเวลาทั้งฟาร์ม"),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'search',
                    child: Row(
                      children: [
                        Icon(Icons.search),
                        SizedBox(width: 8),
                        Text("ค้นหาอุปกรณ์"),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'remove',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, color: Colors.red),
                        SizedBox(width: 8),
                        Text("ลบอุปกรณ์", style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
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
