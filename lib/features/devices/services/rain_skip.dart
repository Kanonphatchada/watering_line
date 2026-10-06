import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

// ค้นหาชื่อสถานที่ (อำเภอ/จังหวัด/ชื่อเมือง) แล้วแปลงเป็นพิกัดให้เอง — ผู้ใช้
// ส่วนใหญ่ไม่รู้ละติจูด/ลองจิจูดของตัวเองเลย ใช้ Open-Meteo Geocoding API
// (ผู้ให้บริการเดียวกับที่ backend ใช้เช็คพยากรณ์อยู่แล้ว ฟรี ไม่ต้องมี API
// key) คืน list ผลลัพธ์ให้เลือก เผื่อชื่อซ้ำกันหลายที่ (เช่น มีทั้ง "บางกรวย"
// หลายจังหวัด)
Future<List<Map<String, dynamic>>> searchPlaces(String query) async {
  final uri = Uri.parse(
    'https://geocoding-api.open-meteo.com/v1/search'
    '?name=${Uri.encodeQueryComponent(query)}&count=5&language=th&format=json',
  );
  final res = await http.get(uri);
  final json = jsonDecode(res.body) as Map<String, dynamic>;
  final results = (json['results'] as List?) ?? [];
  return results.cast<Map<String, dynamic>>();
}

String placeLabel(Map<String, dynamic> r) => [
      r['name'],
      r['admin1'],
      r['country']
    ].where((e) => e != null && '$e'.isNotEmpty).join(', ');

// ข้ามรอบรดน้ำอัตโนมัติทั้งฟาร์มถ้าพยากรณ์บอกว่าฝนจะตกเร็วๆนี้ — เช็คจริง
// ฝั่ง backend (checkDevices.js, computeRainSkip) ไฟล์นี้แค่เก็บพิกัดฟาร์ม +
// เปิด/ปิดฟีเจอร์ ไม่ได้ตัดสินใจรดน้ำฝั่ง client เอง
Future<void> saveRainSkip(
  String groupId, {
  required bool enabled,
  double? lat,
  double? lon,
}) =>
    FirebaseFirestore.instance
        .collection('device_registry')
        .doc(groupId)
        .update({
      'rainSkipEnabled': enabled,
      if (enabled) 'farmLat': lat,
      if (enabled) 'farmLon': lon,
    });

class HourlyForecast {
  final DateTime time;
  final int rainProbability; // %
  final double precipitation; // mm
  final double temperature; // °C

  const HourlyForecast({
    required this.time,
    required this.rainProbability,
    required this.precipitation,
    required this.temperature,
  });
}

// พยากรณ์รายชั่วโมงข้างหน้าสำหรับหน้าพยากรณ์อากาศ (แค่แสดงผล) — ตัวที่ตัดสิน
// ข้ามรดน้ำจริงยังเป็น backend ใช้เกณฑ์เดียวกับ checkDevices.js: ฝน 3 ชม.
// ข้างหน้า โอกาส ≥ 70% และรวม ≥ 1 มม.
Future<List<HourlyForecast>> fetchHourlyForecast(
  double lat,
  double lon, {
  int hours = 12,
}) async {
  final uri = Uri.parse(
    'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon'
    '&hourly=precipitation_probability,precipitation,temperature_2m'
    '&forecast_days=2&timezone=auto',
  );
  final res = await http.get(uri);
  final hourly =
      (jsonDecode(res.body) as Map<String, dynamic>)['hourly'] as Map? ?? {};
  final times = (hourly['time'] as List?) ?? [];
  final probs = (hourly['precipitation_probability'] as List?) ?? [];
  final precs = (hourly['precipitation'] as List?) ?? [];
  final temps = (hourly['temperature_2m'] as List?) ?? [];

  final now = DateTime.now();
  final currentHour = DateTime(now.year, now.month, now.day, now.hour);
  final result = <HourlyForecast>[];
  for (var i = 0; i < times.length && result.length < hours; i++) {
    // timezone=auto คืนเวลาท้องถิ่นของพิกัด (ไม่มี offset) — ฟาร์มในไทย
    // กับเครื่องผู้ใช้ในไทยอยู่ timezone เดียวกัน เทียบกับเวลาเครื่องได้เลย
    final t = DateTime.tryParse('${times[i]}');
    if (t == null || t.isBefore(currentHour)) continue;
    result.add(HourlyForecast(
      time: t,
      rainProbability: (probs.elementAtOrNull(i) as num?)?.round() ?? 0,
      precipitation: (precs.elementAtOrNull(i) as num?)?.toDouble() ?? 0,
      temperature: (temps.elementAtOrNull(i) as num?)?.toDouble() ?? 0,
    ));
  }
  return result;
}
