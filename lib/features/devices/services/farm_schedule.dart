import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/schedule_utils.dart';

// ตั้งเวลารดน้ำทั้งกลุ่ม/ฟาร์มในครั้งเดียว — ให้ทุกอุปกรณ์ในกลุ่มเดียวกัน
// (อาจเป็นร้อยตัว) ใช้ตารางเวลาเดียวกันโดย default โดยไม่ต้องตั้งทีละตัว
// อุปกรณ์ที่ตั้ง scheduleOverride ของตัวเองไว้แล้วจะไม่ถูกทับ (ดู
// resolveScheduleSource ฝั่ง checkDevices.js)
Future<void> openFarmScheduleDialog(
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
  await showFarmScheduleEditor(context, groupId, docs);
}

Future<void> showFarmScheduleEditor(
  BuildContext context,
  String groupId,
  List<QueryDocumentSnapshot> docs,
) async {
  final registryDoc = await FirebaseFirestore.instance
      .collection('device_registry')
      .doc(groupId)
      .get();
  final registryData = registryDoc.data() ?? {};

  bool enabled = registryData['scheduleEnabled'] == true;
  String mode = registryData['scheduleMode'] == 'block' ? 'block' : 'allow';
  TimeOfDay start = parseHHmm(registryData['scheduleStart'] as String?) ??
      const TimeOfDay(hour: 6, minute: 0);
  TimeOfDay end = parseHHmm(registryData['scheduleEnd'] as String?) ??
      const TimeOfDay(hour: 18, minute: 0);
  bool exceptEnabled = registryData['scheduleExceptEnabled'] == true;
  TimeOfDay exceptStart =
      parseHHmm(registryData['scheduleExceptStart'] as String?) ??
          const TimeOfDay(hour: 12, minute: 0);
  TimeOfDay exceptEnd =
      parseHHmm(registryData['scheduleExceptEnd'] as String?) ??
          const TimeOfDay(hour: 14, minute: 0);

  final deviceCount = docs
      .where((d) => (d.data() as Map<String, dynamic>)['groupId'] == groupId)
      .length;

  if (!context.mounted) return;

  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text("ตั้งเวลารดน้ำทั้งฟาร์ม"),
        // ล็อกความกว้างไว้คงที่ เหมือนกับ dialog ตั้งเวลารายอุปกรณ์ — ห่อ
        // ด้วย SingleChildScrollView ด้วย เพราะเนื้อหายาวขึ้นมากหลังเพิ่ม
        // ช่วงห้ามรดพิเศษ อาจเกินพื้นที่ dialog บนหน้าจอเล็กจนล้น (overflow)
        content: SizedBox(
          width: 320,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "ใช้กับอุปกรณ์ $deviceCount ตัวในกลุ่ม \"$groupId\" "
                  "(อุปกรณ์ที่ตั้งเวลาเฉพาะตัวไว้แล้วจะไม่ถูกทับ)",
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text("เปิดใช้ตารางเวลา"),
                  value: enabled,
                  onChanged: (v) => setDialogState(() => enabled = v),
                ),
                if (enabled) ...[
                  const SizedBox(height: 4),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'allow',
                        label: Text("รดได้เฉพาะช่วงนี้"),
                      ),
                      ButtonSegment(
                        value: 'block',
                        label: Text("ห้ามรดช่วงนี้"),
                      ),
                    ],
                    selected: {mode},
                    onSelectionChanged: (s) =>
                        setDialogState(() => mode = s.first),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.wb_sunny_outlined),
                    title: const Text("เริ่ม"),
                    trailing: Text(start.format(context)),
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: start,
                      );
                      if (picked != null) {
                        setDialogState(() => start = picked);
                      }
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.nights_stay_outlined),
                    title: const Text("สิ้นสุด"),
                    trailing: Text(end.format(context)),
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: end,
                      );
                      if (picked != null) setDialogState(() => end = picked);
                    },
                  ),
                  const Divider(height: 24),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text("เพิ่มช่วงห้ามรดพิเศษ"),
                    subtitle: const Text(
                      "ห้ามรดในช่วงนี้เสมอ ซ้อนอยู่ในช่วงเวลาข้างบน",
                    ),
                    value: exceptEnabled,
                    onChanged: (v) => setDialogState(() => exceptEnabled = v),
                  ),
                  if (exceptEnabled) ...[
                    const SizedBox(height: 4),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.wb_sunny_outlined),
                      title: const Text("เริ่มห้ามรด"),
                      trailing: Text(exceptStart.format(context)),
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: exceptStart,
                        );
                        if (picked != null) {
                          setDialogState(() => exceptStart = picked);
                        }
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.nights_stay_outlined),
                      title: const Text("สิ้นสุดห้ามรด"),
                      trailing: Text(exceptEnd.format(context)),
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: exceptEnd,
                        );
                        if (picked != null) {
                          setDialogState(() => exceptEnd = picked);
                        }
                      },
                    ),
                  ],
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

  if (saved != true) return;

  final startHHmm = formatHHmm(start);
  final endHHmm = formatHHmm(end);
  final exceptStartHHmm = formatHHmm(exceptStart);
  final exceptEndHHmm = formatHHmm(exceptEnd);

  try {
    await FirebaseFirestore.instance
        .collection('device_registry')
        .doc(groupId)
        .update({
      'scheduleEnabled': enabled,
      'scheduleMode': mode,
      'scheduleStart': startHHmm,
      'scheduleEnd': endHHmm,
      'scheduleExceptEnabled': exceptEnabled,
      'scheduleExceptStart': exceptStartHHmm,
      'scheduleExceptEnd': exceptEndHHmm,
    });

    // อัปเดต Auto ทันทีให้ทุกอุปกรณ์ในกลุ่มที่ "ไม่ได้" override ไว้เอง —
    // ให้เห็นผลตรงกับที่ตั้งค่าไว้เลย ไม่ต้องรอ backend รอบถัดไป (15 นาที)
    final allowedNow = resolveScheduleAllowed(
      mode: mode,
      startHHmm: startHHmm,
      endHHmm: endHHmm,
      exceptEnabled: exceptEnabled,
      exceptStartHHmm: exceptStartHHmm,
      exceptEndHHmm: exceptEndHHmm,
    );

    final batch = FirebaseFirestore.instance.batch();
    for (final doc in docs) {
      final d = doc.data() as Map<String, dynamic>;
      if (d['groupId'] != groupId) continue;
      if (d['scheduleOverride'] == true) {
        continue; // ไม่ทับอุปกรณ์ที่ override ไว้
      }

      // เปิดใช้ตารางเวลาทั้งฟาร์ม = ถือว่ายินยอมให้อุปกรณ์ที่ไม่ได้ override
      // เองรดน้ำอัตโนมัติตามตารางนี้ทันที ไม่ต้องรอให้เคยเปิด Auto ของตัวเอง
      // มาก่อน — เดิม fallback ไปดูค่า Auto ปัจจุบันซึ่งมักเป็น false สำหรับ
      // อุปกรณ์ที่ไม่เคยแตะสวิตช์เลย ทำให้ตารางเวลาทั้งฟาร์มไม่มีผลกับ
      // อุปกรณ์พวกนั้นเลยแม้จะเปิดใช้ไว้แล้วก็ตาม
      final desiredAuto =
          enabled ? true : (d['desiredAuto'] ?? d['Auto'] ?? false);
      final effective =
          enabled ? (desiredAuto == true && allowedNow) : (desiredAuto == true);

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
              "บันทึกตารางเวลาทั้งฟาร์มแล้ว",
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
