import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../main.dart';

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

  Future<void> claimDevice() async {
    if (isLoading) return; // 🔥 กันกดรัว

    setState(() {
      isLoading = true;
    });
    FocusScope.of(context).unfocus(); // 🔥 ซ่อน keyboard

    final deviceId = deviceIdController.text.trim();
    final secret = secretController.text.trim();
    final uid = FirebaseAuth.instance.currentUser!.uid;

    final docRef =
        FirebaseFirestore.instance.collection('device_registry').doc(deviceId);

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

    // เดิมเช็คแค่ "มีเจ้าของหรือยัง" บล็อกแม้เจ้าของจะเป็นคนเดิม (ตัวเอง) ก็
    // ตาม ทำให้เพิ่มเซนเซอร์ตัวใหม่เข้ากลุ่ม/ฟาร์มที่ตัวเองเป็นเจ้าของอยู่
    // แล้วไม่ได้เลย — แก้ให้อนุญาตถ้าเจ้าของเดิมคือ uid ตัวเองด้วย (กรณีซื้อ
    // เซนเซอร์เพิ่มเข้าฟาร์มเดิม) บล็อกเฉพาะตอนเป็นของคนอื่นจริงๆ เท่านั้น
    final alreadyOwnedBySomeoneElse =
        data['ownerUid'] != null && data['ownerUid'] != uid;

    if (alreadyOwnedBySomeoneElse) {
      print("STEP X: ถูกใช้แล้ว");

      await showPopup("อุปกรณ์ถูกใช้แล้ว", isError: true);

      setState(() {
        isLoading = false;
      });
      return;
    }

    print("STEP 3: ผ่านทุกเงื่อนไข");

    // 🔥 หา nano ทั้งหมดที่ groupId ตรงกัน
    final snapshot = await FirebaseFirestore.instance
        .collection('ESP32')
        .where('groupId', isEqualTo: deviceId)
        .get();

    print("เจอ nano: ${snapshot.docs.length}");

    // 🔥 ผูก ownerUid ของ device_registry + uid ของทุก nano ในคำสั่งเดียว (atomic)
    // กันกรณีเน็ตหลุดกลางทาง ที่ทำให้ device ถูก mark ว่า "ถูกใช้แล้ว"
    // ทั้งที่ ESP32 บางตัวยังไม่ถูกผูก uid จริง
    //
    // สำคัญ: ใส่แค่ document ที่ "ยังไม่ตรง" ลงใน batch เท่านั้น — Firestore
    // rule อนุญาตให้ตั้ง ownerUid/uid ได้เฉพาะตอนที่ยังเป็น null/ไม่มีอยู่
    // เท่านั้น ถ้าใส่ document ที่ตั้งค่าตรงอยู่แล้ว (เช่น Nano1-3 ตอนเพิ่ม
    // Nano4 เข้ากลุ่มเดิม) เข้าไปเขียนซ้ำ จะโดน rule ปฏิเสธ แล้วทำให้ batch
    // ทั้งก้อนพังไปด้วย (batch เป็น all-or-nothing)
    final batch = FirebaseFirestore.instance.batch();
    if (data['ownerUid'] == null) {
      batch.update(docRef, {'ownerUid': uid});
    }
    for (final nanoDoc in snapshot.docs) {
      final nanoData = nanoDoc.data();
      if (nanoData['uid'] != uid) {
        // ผูก uid ให้ พร้อมเติมค่าเริ่มต้นของฟีลด์ที่ยังไม่มี (เช่นตอนสร้าง
        // ESP32 doc เองใหม่ผ่าน Console แล้วมีแค่ groupId) ให้ครบพอจะแสดงผล
        // ในหน้าเว็บได้ปกติ — เติมเฉพาะฟีลด์ที่ "ไม่มีอยู่ก่อน" เท่านั้น กัน
        // เผลอทับค่าจริงจากฮาร์ดแวร์ของอุปกรณ์ที่ใช้งานอยู่แล้ว (เช่น
        // Nano1-3) ด้วยค่า default
        final update = <String, dynamic>{'uid': uid};
        if (!nanoData.containsKey('Moisture')) update['Moisture'] = 0;
        if (!nanoData.containsKey('Automois')) update['Automois'] = 20;
        if (!nanoData.containsKey('Valve')) update['Valve'] = false;
        batch.update(nanoDoc.reference, update);
      }
    }
    await batch.commit();

    print("STEP 4: ผูกอุปกรณ์สำเร็จ (atomic)");
    // 🔥 แก้สำคัญ: ให้ user กดก่อน

    await showPopup("เชื่อมต่อสำเร็จ");

    if (!mounted) return;

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
