import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ข้ามรอบรดน้ำอัตโนมัติทั้งฟาร์มถ้าพยากรณ์บอกว่าฝนจะตกเร็วๆนี้ — เช็คจริง
// ฝั่ง backend (checkDevices.js, computeRainSkip) ไฟล์นี้แค่เก็บพิกัดฟาร์ม +
// เปิด/ปิดฟีเจอร์ ไม่ได้คำนวณอะไรฝั่ง client เอง
Future<void> openRainSkipDialog(
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
  await showRainSkipEditor(context, groupId);
}

Future<void> showRainSkipEditor(BuildContext context, String groupId) async {
  final registryDoc = await FirebaseFirestore.instance
      .collection('device_registry')
      .doc(groupId)
      .get();
  final registryData = registryDoc.data() ?? {};

  bool rainSkipEnabled = registryData['rainSkipEnabled'] == true;
  final farmLatController = TextEditingController(
    text: registryData['farmLat'] != null ? '${registryData['farmLat']}' : '',
  );
  final farmLonController = TextEditingController(
    text: registryData['farmLon'] != null ? '${registryData['farmLon']}' : '',
  );

  if (!context.mounted) return;

  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text("พยากรณ์อากาศ"),
        content: SizedBox(
          width: 320,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "ใช้กับกลุ่ม \"$groupId\"",
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text("ข้ามรดน้ำถ้าฝนจะตก"),
                  subtitle: const Text(
                    "เช็คพยากรณ์ฝน 3 ชม.ข้างหน้าก่อนรดน้ำอัตโนมัติทุกรอบ "
                    "ถ้าโอกาสฝนสูงจะข้ามรอบนั้นไป (ไม่ข้าม 2 รอบติดกัน)",
                  ),
                  value: rainSkipEnabled,
                  onChanged: (v) => setDialogState(() => rainSkipEnabled = v),
                ),
                if (rainSkipEnabled) ...[
                  const SizedBox(height: 4),
                  TextField(
                    controller: farmLatController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: "ละติจูดฟาร์ม (Latitude)",
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: farmLonController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: "ลองจิจูดฟาร์ม (Longitude)",
                      isDense: true,
                    ),
                  ),
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

  // ปล่อยให้เฟรมปัจจุบัน (ตอน dialog เพิ่งปิด) render เสร็จก่อนค่อย dispose —
  // dispose ทันทีระหว่างที่ dialog กำลัง animate ปิดจะชน exception (ดูจุดที่
  // เจอบั๊กเดียวกันใน pickerQueryController)
  WidgetsBinding.instance.addPostFrameCallback((_) {
    farmLatController.dispose();
    farmLonController.dispose();
  });

  if (saved != true) return;

  double? farmLat;
  double? farmLon;
  if (rainSkipEnabled) {
    farmLat = double.tryParse(farmLatController.text.trim());
    farmLon = double.tryParse(farmLonController.text.trim());
    final validLat = farmLat != null && farmLat >= -90 && farmLat <= 90;
    final validLon = farmLon != null && farmLon >= -180 && farmLon <= 180;
    if (!validLat || !validLon) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("พิกัดฟาร์มไม่ถูกต้อง กรุณาใส่ละติจูด/ลองจิจูดให้ครบ"),
        ),
      );
      return;
    }
  }

  try {
    await FirebaseFirestore.instance
        .collection('device_registry')
        .doc(groupId)
        .update({
      'rainSkipEnabled': rainSkipEnabled,
      if (rainSkipEnabled) 'farmLat': farmLat,
      if (rainSkipEnabled) 'farmLon': farmLon,
    });

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF2E7D32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        content: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, color: Colors.white, size: 20),
            SizedBox(width: 10),
            Text(
              "บันทึกการตั้งค่าพยากรณ์อากาศแล้ว",
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
