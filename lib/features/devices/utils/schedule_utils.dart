import 'package:flutter/material.dart';

bool isWithinScheduleWindow(String startHHmm, String endHHmm) {
  int toMinutes(String hhmm) {
    final parts = hhmm.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  final nowBangkok = DateTime.now().toUtc().add(const Duration(hours: 7));
  final nowMinutes = nowBangkok.hour * 60 + nowBangkok.minute;

  final startMinutes = toMinutes(startHHmm);
  final endMinutes = toMinutes(endHHmm);

  if (startMinutes == endMinutes) return true;
  if (startMinutes < endMinutes) {
    return nowMinutes >= startMinutes && nowMinutes < endMinutes;
  }
  return nowMinutes >= startMinutes || nowMinutes < endMinutes;
}

TimeOfDay? parseHHmm(String? hhmm) {
  if (hhmm == null) return null;
  final parts = hhmm.split(':');
  if (parts.length != 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  return TimeOfDay(hour: h, minute: m);
}

String formatHHmm(TimeOfDay time) {
  final h = time.hour.toString().padLeft(2, '0');
  final m = time.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

// รองรับช่วง "ห้ามรดพิเศษ" ซ้อนอยู่ในช่วงเวลาหลักได้ เช่น รดได้เฉพาะ
// 08:00-18:00 แต่ห้ามรดตอน 12:00-14:00 — ช่วงพิเศษนี้บังคับห้ามเสมอไม่ว่า
// โหมดหลักจะเป็น allow หรือ block ก็ตาม ต้องตรงกับ resolveScheduleAllowed
// ใน functions/checkDevices.js เป๊ะๆ เหมือน isWithinScheduleWindow
bool resolveScheduleAllowed({
  required String mode,
  required String startHHmm,
  required String endHHmm,
  bool exceptEnabled = false,
  String? exceptStartHHmm,
  String? exceptEndHHmm,
}) {
  final withinMain = isWithinScheduleWindow(startHHmm, endHHmm);
  var allowed = mode == 'block' ? !withinMain : withinMain;
  if (exceptEnabled && exceptStartHHmm != null && exceptEndHHmm != null) {
    if (isWithinScheduleWindow(exceptStartHHmm, exceptEndHHmm)) {
      allowed = false;
    }
  }
  return allowed;
}
