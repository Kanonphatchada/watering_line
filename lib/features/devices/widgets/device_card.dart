import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../pages/calendar_page.dart';
import '../pages/graph_page.dart';
import '../pages/notification_history_page.dart';
import 'moisture_sparkline.dart';
import 'status_chip.dart';
import 'stat_row.dart';
import 'control_chip.dart';
import 'action_button.dart';
import 'last_updated_text.dart';
import 'moisture_gauge.dart';

class DeviceCard extends StatefulWidget {
  final String nanoId;
  final Map<String, dynamic> data;
  final int index;

  const DeviceCard({
    super.key,
    required this.nanoId,
    required this.data,
    this.index = 0,
  });

  @override
  State<DeviceCard> createState() => DeviceCardState();
}

class DeviceCardState extends State<DeviceCard>
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
  void didUpdateWidget(covariant DeviceCard oldWidget) {
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
                        LastUpdatedText(
                          nanoId: nanoId,
                          lastSeen: data['lastSeen'] as Timestamp?,
                        ),
                      ],
                    ),
                  ),
                  StatusChip(
                    isAlert: isAlert,
                    isOffline: isOffline,
                    faultType: faultType,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              MoistureSparkline(nanoId: nanoId),
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
                      child: MoistureGauge(
                        moisture: data['Moisture'] as num?,
                        target: currentTarget,
                        isOffline: isOffline,
                      ),
                    ),
                    const StatDivider(),
                    Expanded(
                      child: StatTile(
                        icon: Icons.flag,
                        label: "Target",
                        value: currentTarget.toString(),
                      ),
                    ),
                    const StatDivider(),
                    Expanded(
                      child: StatTile(
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
                    child: ControlChip(
                      label: "Auto",
                      icon: Icons.auto_mode,
                      value: data['Auto'] ?? false,
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
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ControlChip(
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
                          if (val == true) 'Auto': false,
                        });
                      },
                    ),
                  ),
                ],
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
                    child: ActionButton(
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
                    child: ActionButton(
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
                    child: ActionButton(
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
                      }
                    },
                    itemBuilder: (context) => [
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
