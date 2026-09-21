import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

// ยกเลิกการผูกอุปกรณ์ (ลบออกจากบัญชีตัวเอง ไม่ได้ลบ document ทิ้ง) — ยิงผ่าน
// backend route /unclaim-device ด้วย Firebase ID token แทนที่จะเขียน
// Firestore ตรงๆ จากฝั่ง client เพื่อไม่ต้องเปิด rule เพิ่มให้ client เคลียร์
// uid/ownerUid เอง เป็น top-level function ไม่ใช่ method ของ _DeviceCardState
// เพราะเรียกใช้ได้ทั้งจากปุ่มลบในการ์ด และจากเมนูรวมที่เลือกอุปกรณ์ก่อนลบ
Future<void> confirmAndRemoveDevice(BuildContext context, String nanoId) async {
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
        "จะยกเลิกการผูก \"$nanoId\" กับบัญชีนี้ "
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

  // backend เป็น Render free tier — ถ้าไม่มีใครเรียกนานๆ จะ sleep เอง ตื่น
  // ครั้งแรก (cold start) ใช้เวลาได้ถึง 30-60 วิ ถ้าไม่โชว์ loading ไว้ก่อน
  // ผู้ใช้จะคิดว่ากดแล้วไม่มีอะไรเกิดขึ้นเลย (เจอเคสนี้จริงมาแล้ว)
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      duration: Duration(seconds: 60),
      content: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 12),
          Expanded(
            child:
                Text("กำลังลบอุปกรณ์... อาจใช้เวลาสักครู่ถ้า server เพิ่งตื่น"),
          ),
        ],
      ),
    ),
  );

  try {
    final idToken = await user.getIdToken();
    final res = await http
        .post(
          Uri.parse("https://line-auth-server.onrender.com/unclaim-device"),
          headers: {
            "Content-Type": "application/json",
            "Authorization": "Bearer $idToken",
          },
          body: jsonEncode({"nanoId": nanoId}),
        )
        .timeout(const Duration(seconds: 60));

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

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
                style:
                    TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
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
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    final message = err is TimeoutException
        ? "เชื่อมต่อ server ไม่ได้ (server อาจกำลัง sleep) ลองใหม่อีกครั้ง"
        : "ลบอุปกรณ์ไม่สำเร็จ ลองใหม่อีกครั้ง";
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

// เลือกอุปกรณ์ก่อนลบจากเมนูรวม — ต่างจากปุ่มลบที่เคยอยู่ในการ์ด (ตรงนั้นรู้อยู่แล้ว
// ว่าจะลบตัวไหน) ตรงนี้ต้องให้เลือกอุปกรณ์ก่อน จึงมีช่องค้นหา+รายชื่อให้กด
// เลือกในไดอะล็อกนี้ พอเลือกแล้วค่อยไปเข้ากล่องยืนยัน (confirmAndRemoveDevice) ต่อ
Future<void> openRemoveDevicePicker(
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
