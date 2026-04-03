import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../main.dart';

class AddDevicePage extends StatefulWidget {
  const AddDevicePage({super.key});

  @override
  State<AddDevicePage> createState() => _AddDevicePageState();
}

class _AddDevicePageState extends State<AddDevicePage> {
  final deviceIdController = TextEditingController();
  final secretController = TextEditingController();
  bool isLoading = false; // 🔥 ใช้ควบคุม loading + ปุ่ม

  // 🔥 [แก้] ทำให้รอ popup ได้
  Future<void> showPopup(String message, {bool isError = false}) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Icon(
              isError ? Icons.error : Icons.check_circle,
              color: isError ? Colors.red : Colors.green,
            ),
            const SizedBox(width: 8),
            Text(isError ? "เกิดข้อผิดพลาด" : "สำเร็จ"),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("ตกลง"),
          ),
        ],
      ),
    );
  }

  Future<void> claimDevice() async {
    if (isLoading) return; // 🔥 กันกดรัว

    setState(() {
      isLoading = true;
    });
    FocusScope.of(context).unfocus(); // 🔥 ซ่อน keyboard

    final deviceId = deviceIdController.text.trim();
    final secret = secretController.text.trim();
    final uid = FirebaseAuth.instance.currentUser!.uid;

    final docRef = FirebaseFirestore.instance
        .collection('device_registry')
        .doc(deviceId);

    print("STEP 1: start");

    final doc = await docRef.get();

    if (!doc.exists) {
      print("STEP X: ไม่เจอ");

      await showPopup("ไม่เจออุปกรณ์", isError: true); // 🔥 await

      setState(() {
        isLoading = false;
      });
      return;
    }

    final data = doc.data()!;
    print("STEP 2: เจอ doc");

    if (data['secret'] != secret) {
      print("STEP X: secret ผิด");

      await showPopup("รหัสผ่านไม่ถูกต้อง", isError: true);

      setState(() {
        isLoading = false;
      });
      return;
    }

    if (data['ownerUid'] != null) {
      print("STEP X: ถูกใช้แล้ว");

      await showPopup("อุปกรณ์ถูกใช้แล้ว", isError: true);

      setState(() {
        isLoading = false;
      });
      return;
    }

    print("STEP 3: ผ่านทุกเงื่อนไข");

    await docRef.update({
      'ownerUid': uid,
    });

    print("STEP 4: update ownerUid แล้ว");

    // 🔥 STEP 1: หา nano ทั้งหมดที่ groupId ตรงกัน
    final snapshot = await FirebaseFirestore.instance
        .collection('ESP32')
        .where('groupId', isEqualTo: deviceId)
        .get();

    print("เจอ nano: ${snapshot.docs.length}");

    // 🔥 STEP 2: update uid เข้า nano ทุกตัว
    for (var nanoDoc in snapshot.docs) {
      await nanoDoc.reference.update({
        'uid': uid,
      });
    }
    // 🔥 แก้สำคัญ: ให้ user กดก่อน

    await showPopup("เชื่อมต่อสำเร็จ");

    setState(() {
      isLoading = false;
    });

    print("STEP 6: ไปหน้า Home");

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const CheckDevicePage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("เพิ่มอุปกรณ์")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: deviceIdController,
              decoration: const InputDecoration(labelText: "Device ID"),
            ),
            TextField(
              controller: secretController,
              decoration: const InputDecoration(labelText: "Secret"),
              obscureText: true,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: claimDevice,
              child: const Text("เชื่อมต่ออุปกรณ์"),
            )
          ],
        ),
      ),
    );
  }
}
