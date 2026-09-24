import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import '../../../shared/web/web_utils.dart';

// ค้นหาชื่อสถานที่ (อำเภอ/จังหวัด/ชื่อเมือง) แล้วแปลงเป็นพิกัดให้เอง — ผู้ใช้
// ส่วนใหญ่ไม่รู้ละติจูด/ลองจิจูดของตัวเองเลย ใช้ Open-Meteo Geocoding API
// (ผู้ให้บริการเดียวกับที่ backend ใช้เช็คพยากรณ์อยู่แล้ว ฟรี ไม่ต้องมี API
// key) คืน list ผลลัพธ์ให้เลือก เผื่อชื่อซ้ำกันหลายที่ (เช่น มีทั้ง "บางกรวย"
// หลายจังหวัด)
Future<List<Map<String, dynamic>>> _searchPlaces(String query) async {
  final uri = Uri.parse(
    'https://geocoding-api.open-meteo.com/v1/search'
    '?name=${Uri.encodeQueryComponent(query)}&count=5&language=th&format=json',
  );
  final res = await http.get(uri);
  final json = jsonDecode(res.body) as Map<String, dynamic>;
  final results = (json['results'] as List?) ?? [];
  return results.cast<Map<String, dynamic>>();
}

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
  final placeController = TextEditingController();
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
      builder: (context, setDialogState) {
        Future<void> handlePlaceSearch() async {
          final query = placeController.text.trim();
          if (query.isEmpty) return;

          List<Map<String, dynamic>> results;
          try {
            results = await _searchPlaces(query);
          } catch (err) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("ค้นหาไม่สำเร็จ: $err")),
            );
            return;
          }
          if (results.isEmpty) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("ไม่พบสถานที่ที่ค้นหา ลองพิมพ์ชื่ออื่น"),
              ),
            );
            return;
          }

          if (!context.mounted) return;
          final picked = await showDialog<Map<String, dynamic>>(
            context: context,
            builder: (context) => SimpleDialog(
              title: const Text("เลือกสถานที่"),
              children: [
                for (final r in results)
                  SimpleDialogOption(
                    onPressed: () => Navigator.pop(context, r),
                    child: Text(
                      [r['name'], r['admin1'], r['country']]
                          .where((e) => e != null && '$e'.isNotEmpty)
                          .join(', '),
                    ),
                  ),
              ],
            ),
          );
          if (picked == null) return;

          setDialogState(() {
            farmLatController.text = '${picked['latitude']}';
            farmLonController.text = '${picked['longitude']}';
          });
        }

        Future<void> handleUseCurrentLocation() async {
          final pos = await getCurrentPosition();
          if (pos == null) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  "ขอตำแหน่งไม่สำเร็จ (ต้องอนุญาตสิทธิ์ตำแหน่งในเบราว์เซอร์)",
                ),
              ),
            );
            return;
          }
          setDialogState(() {
            farmLatController.text = '${pos['lat']}';
            farmLonController.text = '${pos['lon']}';
          });
        }

        return AlertDialog(
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
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: placeController,
                            decoration: const InputDecoration(
                              labelText: "ค้นหาชื่อสถานที่ (อำเภอ/จังหวัด)",
                              isDense: true,
                            ),
                            onSubmitted: (_) => handlePlaceSearch(),
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.search),
                          tooltip: "ค้นหา",
                          onPressed: handlePlaceSearch,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: handleUseCurrentLocation,
                        icon: const Icon(Icons.my_location, size: 18),
                        label: const Text("ใช้ตำแหน่งปัจจุบัน"),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "หรือกรอกพิกัดเอง:",
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
                    ),
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
        );
      },
    ),
  );

  // ปล่อยให้เฟรมปัจจุบัน (ตอน dialog เพิ่งปิด) render เสร็จก่อนค่อย dispose —
  // dispose ทันทีระหว่างที่ dialog กำลัง animate ปิดจะชน exception (ดูจุดที่
  // เจอบั๊กเดียวกันใน pickerQueryController)
  WidgetsBinding.instance.addPostFrameCallback((_) {
    placeController.dispose();
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
