import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/schedule_utils.dart';

// ตารางเวลารดน้ำระดับกลุ่ม/ฟาร์ม (เก็บใน device_registry/{groupId}) — ให้ทุก
// อุปกรณ์ในกลุ่มเดียวกัน (อาจเป็นร้อยตัว) ใช้ตารางเดียวกันโดย default ไม่ต้อง
// ตั้งทีละตัว อุปกรณ์ที่ตั้ง scheduleOverride ของตัวเองไว้แล้วจะไม่ถูกทับ (ดู
// resolveScheduleSource ฝั่ง checkDevices.js) — UI อยู่ที่ SchedulePage
class FarmSchedule {
  bool enabled;
  String mode; // 'allow' = รดได้เฉพาะช่วงนี้, 'block' = ห้ามรดช่วงนี้
  TimeOfDay start;
  TimeOfDay end;
  bool exceptEnabled; // ช่วงห้ามรดพิเศษ ซ้อนอยู่ในช่วงหลัก
  TimeOfDay exceptStart;
  TimeOfDay exceptEnd;

  FarmSchedule({
    required this.enabled,
    required this.mode,
    required this.start,
    required this.end,
    required this.exceptEnabled,
    required this.exceptStart,
    required this.exceptEnd,
  });

  factory FarmSchedule.fromRegistry(Map<String, dynamic> r) => FarmSchedule(
        enabled: r['scheduleEnabled'] == true,
        mode: r['scheduleMode'] == 'block' ? 'block' : 'allow',
        start: parseHHmm(r['scheduleStart'] as String?) ??
            const TimeOfDay(hour: 6, minute: 0),
        end: parseHHmm(r['scheduleEnd'] as String?) ??
            const TimeOfDay(hour: 18, minute: 0),
        exceptEnabled: r['scheduleExceptEnabled'] == true,
        exceptStart: parseHHmm(r['scheduleExceptStart'] as String?) ??
            const TimeOfDay(hour: 12, minute: 0),
        exceptEnd: parseHHmm(r['scheduleExceptEnd'] as String?) ??
            const TimeOfDay(hour: 14, minute: 0),
      );

  FarmSchedule copy() => FarmSchedule(
        enabled: enabled,
        mode: mode,
        start: start,
        end: end,
        exceptEnabled: exceptEnabled,
        exceptStart: exceptStart,
        exceptEnd: exceptEnd,
      );

  Map<String, dynamic> toRegistryFields() => {
        'scheduleEnabled': enabled,
        'scheduleMode': mode,
        'scheduleStart': formatHHmm(start),
        'scheduleEnd': formatHHmm(end),
        'scheduleExceptEnabled': exceptEnabled,
        'scheduleExceptStart': formatHHmm(exceptStart),
        'scheduleExceptEnd': formatHHmm(exceptEnd),
      };

  bool sameAs(FarmSchedule o) =>
      enabled == o.enabled &&
      mode == o.mode &&
      start == o.start &&
      end == o.end &&
      exceptEnabled == o.exceptEnabled &&
      exceptStart == o.exceptStart &&
      exceptEnd == o.exceptEnd;

  // นาทีที่ minute (0-1439) ของวัน รดน้ำได้ไหม — ใช้วาดแถบเวลา 24 ชม. ตรรกะ
  // เดียวกับ resolveScheduleAllowed (ซึ่งต้องตรงกับ checkDevices.js)
  bool allowedAtMinute(int minute) {
    if (!enabled) return true;
    final withinMain = _within(minute, start, end);
    var allowed = mode == 'block' ? !withinMain : withinMain;
    if (exceptEnabled && _within(minute, exceptStart, exceptEnd)) {
      allowed = false;
    }
    return allowed;
  }

  static bool _within(int m, TimeOfDay s, TimeOfDay e) {
    final a = s.hour * 60 + s.minute;
    final b = e.hour * 60 + e.minute;
    if (a == b) return true;
    return a < b ? (m >= a && m < b) : (m >= a || m < b);
  }
}

// บันทึกตารางเวลาทั้งฟาร์ม แล้วอัปเดต Auto ทันทีให้ทุกอุปกรณ์ในกลุ่มที่
// "ไม่ได้" override ไว้เอง — ให้เห็นผลตรงกับที่ตั้งไว้เลย ไม่ต้องรอ backend
// รอบถัดไป
Future<void> saveFarmSchedule(
  String groupId,
  FarmSchedule s,
  List<QueryDocumentSnapshot> docs,
) async {
  final fields = s.toRegistryFields();
  await FirebaseFirestore.instance
      .collection('device_registry')
      .doc(groupId)
      .update(fields);

  final allowedNow = resolveScheduleAllowed(
    mode: s.mode,
    startHHmm: fields['scheduleStart'],
    endHHmm: fields['scheduleEnd'],
    exceptEnabled: s.exceptEnabled,
    exceptStartHHmm: fields['scheduleExceptStart'],
    exceptEndHHmm: fields['scheduleExceptEnd'],
  );

  final batch = FirebaseFirestore.instance.batch();
  for (final doc in docs) {
    final d = doc.data() as Map<String, dynamic>;
    if (d['groupId'] != groupId) continue;
    // ไม่ทับอุปกรณ์ที่ override ไว้
    if (d['scheduleOverride'] == true) continue;

    // เปิดใช้ตารางเวลาทั้งฟาร์ม = ถือว่ายินยอมให้อุปกรณ์ที่ไม่ได้ override
    // เองรดน้ำอัตโนมัติตามตารางนี้ทันที ไม่ต้องรอให้เคยเปิด Auto ของตัวเอง
    // มาก่อน — เดิม fallback ไปดูค่า Auto ปัจจุบันซึ่งมักเป็น false สำหรับ
    // อุปกรณ์ที่ไม่เคยแตะสวิตช์เลย ทำให้ตารางเวลาทั้งฟาร์มไม่มีผลกับ
    // อุปกรณ์พวกนั้นเลยแม้จะเปิดใช้ไว้แล้วก็ตาม
    final desiredAuto =
        s.enabled ? true : (d['desiredAuto'] ?? d['Auto'] ?? false);
    final effective =
        s.enabled ? (desiredAuto == true && allowedNow) : (desiredAuto == true);

    final updates = <String, dynamic>{};
    if (effective != (d['Auto'] == true)) {
      updates['Auto'] = effective;
      if (effective) updates['Valve'] = false;
    }
    if (desiredAuto != (d['desiredAuto'] == true)) {
      updates['desiredAuto'] = desiredAuto;
    }
    if (updates.isEmpty) continue;

    batch.update(doc.reference, updates);
  }
  await batch.commit();
}
