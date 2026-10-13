import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../../../main.dart';
import 'join_farm_dialog.dart';

class AddDevicePage extends StatefulWidget {
  const AddDevicePage({super.key});

  @override
  State<AddDevicePage> createState() => _AddDevicePageState();
}

class _AddDevicePageState extends State<AddDevicePage>
    with SingleTickerProviderStateMixin {
  final deviceIdController = TextEditingController();
  final secretController = TextEditingController();
  bool isLoading = false; // 🔥 ใช้ควบคุม loading + ปุ่ม

  // การ์ด fade + เลื่อนขึ้นตอนเปิดหน้านี้ครั้งแรก ให้ความรู้สึกเป็นขั้นตอน
  // onboarding ที่ตั้งใจออกแบบ ไม่ใช่แค่โผล่มาเฉยๆ
  late final AnimationController _entranceController;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnim =
        CurvedAnimation(parent: _entranceController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(_fadeAnim);
    _entranceController.forward();
  }

  @override
  void dispose() {
    deviceIdController.dispose();
    secretController.dispose();
    _entranceController.dispose();
    super.dispose();
  }

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

  // เชื่อมอุปกรณ์ผ่าน backend (/claim-device) แทนที่จะอ่านรหัสลับและตั้ง uid เอง
  // ฝั่งแอป — รหัสลับไม่ออกจากเซิร์ฟเวอร์อีก และ Firestore rules ก็ไม่เปิดให้
  // client เขียน uid/ownerUid เองแล้ว (ปิดช่องโหว่ที่ใครก็ผูกอุปกรณ์ได้โดยไม่ต้อง
  // ใช้รหัส) ผู้เรียกยืนยันตัวตนด้วย Firebase ID token
  Future<void> claimDevice() async {
    if (isLoading) return; // 🔥 กันกดรัว

    final deviceId = deviceIdController.text.trim();
    final secret = secretController.text.trim();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (deviceId.isEmpty || secret.isEmpty) {
      await showPopup("กรอก Device ID และรหัสผ่านให้ครบ", isError: true);
      return;
    }

    setState(() {
      isLoading = true;
    });
    FocusScope.of(context).unfocus(); // 🔥 ซ่อน keyboard

    // backend เป็น Render free tier — ถ้าไม่มีใครเรียกนานๆ จะ sleep เอง ตื่น
    // ครั้งแรก (cold start) ใช้เวลาได้ถึง 30-60 วิ จึงรอได้นานและมี isLoading
    // โชว์ให้เห็นว่ากำลังทำงานอยู่
    String? errorMessage;
    try {
      final idToken = await user.getIdToken();
      final res = await http
          .post(
            Uri.parse("https://line-auth-server.onrender.com/claim-device"),
            headers: {
              "Content-Type": "application/json",
              "Authorization": "Bearer $idToken",
            },
            body: jsonEncode({"deviceId": deviceId, "secret": secret}),
          )
          .timeout(const Duration(seconds: 60));

      if (res.statusCode != 200) {
        errorMessage = switch (res.statusCode) {
          404 => "ไม่เจออุปกรณ์",
          403 => "รหัสผ่านไม่ถูกต้อง",
          409 => "อุปกรณ์ถูกใช้แล้ว",
          429 => "ลองรหัสผิดหลายครั้งเกินไป รอสักครู่แล้วลองใหม่",
          _ => "เชื่อมต่ออุปกรณ์ไม่สำเร็จ ลองใหม่อีกครั้ง",
        };
      }
    } on TimeoutException {
      errorMessage =
          "เชื่อมต่อ server ไม่ได้ (server อาจกำลัง sleep) ลองใหม่อีกครั้ง";
    } catch (_) {
      errorMessage = "เชื่อมต่ออุปกรณ์ไม่สำเร็จ ลองใหม่อีกครั้ง";
    }

    if (!mounted) return;

    if (errorMessage != null) {
      await showPopup(errorMessage, isError: true);
      if (!mounted) return;
      setState(() {
        isLoading = false;
      });
      return;
    }

    // 🔥 แก้สำคัญ: ให้ user กดก่อน
    await showPopup("เชื่อมต่อสำเร็จ");

    if (!mounted) return;

    setState(() {
      isLoading = false;
    });

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const CheckDevicePage()),
      (route) => false,
    );
  }

  // เข้าร่วมฟาร์มของคนอื่นด้วยรหัสเชิญ — ผ่านแล้วไปหน้าหลักเหมือนตอนผูกอุปกรณ์สำเร็จ
  Future<void> joinWithInvite() async {
    if (isLoading) return;
    final farmId = await showJoinFarmDialog(context);
    if (farmId == null || !mounted) return;
    await showPopup("เข้าร่วมฟาร์ม \"$farmId\" สำเร็จ");
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const CheckDevicePage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.add_circle_outline_rounded),
            SizedBox(width: 8),
            Text("เพิ่มอุปกรณ์"),
          ],
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: FadeTransition(
            opacity: _fadeAnim,
            child: SlideTransition(
              position: _slideAnim,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ไอคอนใส่กรอบวงกลมไล่สีแทนไอคอนลอยเดี่ยวๆ ให้ดูเป็น
                        // จุดเริ่มต้นของขั้นตอน onboarding มากขึ้น
                        Center(
                          child: Container(
                            width: 72,
                            height: 72,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color(0xFF4CAF50),
                                  Color(0xFF2E7D32),
                                ],
                              ),
                            ),
                            child: const Icon(
                              Icons.sensors,
                              size: 36,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          "เชื่อมต่ออุปกรณ์ของคุณ",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          "กรอก Device ID และรหัสผ่านที่พิมพ์อยู่บน"
                          "สติกเกอร์ของอุปกรณ์",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.4,
                            color: Theme.of(context).textTheme.bodySmall?.color,
                          ),
                        ),
                        const SizedBox(height: 28),
                        TextField(
                          controller: deviceIdController,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: "Device ID",
                            hintText: "เช่น farm_1_ab12",
                            prefixIcon: Icon(Icons.badge_outlined),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: secretController,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) {
                            if (!isLoading) claimDevice();
                          },
                          decoration: const InputDecoration(
                            labelText: "Password",
                            hintText: "รหัสผ่านของอุปกรณ์",
                            prefixIcon: Icon(Icons.lock_outline),
                          ),
                          obscureText: true,
                        ),
                        const SizedBox(height: 28),
                        SizedBox(
                          height: 50,
                          child: ElevatedButton.icon(
                            onPressed: isLoading ? null : claimDevice,
                            icon: isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.link_rounded),
                            label: Text(
                              isLoading
                                  ? "กำลังเชื่อมต่อ..."
                                  : "เชื่อมต่ออุปกรณ์",
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Divider(),
                        const SizedBox(height: 4),
                        Text(
                          "มีคนเชิญคุณเข้าฟาร์มของเขา?",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context).textTheme.bodySmall?.color,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: isLoading ? null : joinWithInvite,
                          icon: const Icon(Icons.group_add_outlined, size: 18),
                          label: const Text("เข้าร่วมฟาร์มด้วยรหัสเชิญ"),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
