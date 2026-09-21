import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
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
