import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/schedule_utils.dart';

// ตั้งค่าตารางเวลารดน้ำอัตโนมัติ — ปิดอยู่โดย default ต่ออุปกรณ์ ไม่กระทบ
// อุปกรณ์ที่ไม่ได้เปิดใช้เลย พอกด "บันทึก" จะคำนวณ Auto ที่แท้จริงใหม่
// ทันที (ไม่ต้องรอ backend รอบถัดไป) ให้เห็นผลตรงกับที่ตั้งค่าไว้เลย
Future<void> openDeviceScheduleDialog(
  BuildContext context,
  String nanoId,
  Map<String, dynamic> data,
) async {
  final initialOverride = data['scheduleOverride'] == true;
  final initialEnabled = data['scheduleEnabled'] == true;
  // 3 ทางเลือกตรงๆแทนสวิตช์ซ้อนสวิตช์ 2 ชั้นแบบเดิม (ตั้งเวลาเฉพาะอุปกรณ์นี้
  // + เปิดใช้ตารางเวลา) ที่ผู้ใช้จริงงงว่าทำไมต้อง "เปิด" สวิตช์นึงเพื่อจะ
  // "ปิด" ตารางเวลาไปเลย — ตัวแปรนี้แค่กำหนดว่า UI จะโชว์อะไร ตอนบันทึกจะ
  // แปลงกลับเป็น useOverride/enabled เหมือนเดิมเป๊ะ ไม่กระทบโครงสร้างข้อมูล
  // ใน Firestore เลย:
  //   'farm'   -> useOverride: false (ตามตารางเวลาของฟาร์ม)
  //   'custom' -> useOverride: true, enabled: true (ตั้งเวลาของตัวเอง)
  //   'none'   -> useOverride: true, enabled: false (ยกเลิกตารางเวลา,
  //               รดน้ำตามความชื้นอย่างเดียวเหมือนก่อนมีฟีเจอร์นี้)
  String choice =
      !initialOverride ? 'farm' : (initialEnabled ? 'custom' : 'none');
  // "allow" = รดได้เฉพาะในช่วงนี้เท่านั้น, "block" = รดได้ตลอดยกเว้นในช่วง
  // นี้ (เช่น เช้า-เย็น ยกเว้นเที่ยง แค่ตั้ง block 11:00-14:00 พอ) ถ้าต้องการ
  // รดได้เฉพาะช่วงหนึ่งแล้วยังห้ามรดซ้อนอีกช่วงย่อยข้างใน (เช่น รดได้
  // 08:00-18:00 แต่ห้ามรดตอน 12:00-14:00) ใช้ "เพิ่มช่วงห้ามรดพิเศษ" ข้างล่าง
  String mode = data['scheduleMode'] == 'block' ? 'block' : 'allow';
  TimeOfDay start = parseHHmm(data['scheduleStart'] as String?) ??
      const TimeOfDay(hour: 6, minute: 0);
  TimeOfDay end = parseHHmm(data['scheduleEnd'] as String?) ??
      const TimeOfDay(hour: 18, minute: 0);
  bool exceptEnabled = data['scheduleExceptEnabled'] == true;
  TimeOfDay exceptStart = parseHHmm(data['scheduleExceptStart'] as String?) ??
      const TimeOfDay(hour: 12, minute: 0);
  TimeOfDay exceptEnd = parseHHmm(data['scheduleExceptEnd'] as String?) ??
      const TimeOfDay(hour: 14, minute: 0);

  // อุปกรณ์ทุกตัวอยู่ในกลุ่ม/ฟาร์มเดียวกันได้ ตั้งเวลาไว้ที่กลุ่มแล้วอาจ
  // ครอบทุกอุปกรณ์อยู่แล้ว — ดึงมาโชว์เป็นข้อมูลตอนไม่ได้ override เอง
  final groupId = data['groupId'] as String?;
  Map<String, dynamic>? groupSchedule;
  if (groupId != null) {
    final registryDoc = await FirebaseFirestore.instance
        .collection('device_registry')
        .doc(groupId)
        .get();
    groupSchedule = registryDoc.data();
  }

  if (!context.mounted) return;

  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text("ตั้งเวลารดน้ำ"),
        // ล็อกความกว้างไว้คงที่ ไม่งั้น AlertDialog จะห่อความกว้างตาม
        // เนื้อหาที่ยาวที่สุด ตอนสลับโหมด allow/block ข้อความอธิบายยาว
        // ไม่เท่ากัน ทำให้กล่องขยับบีบ/ขยายไปมาเวลาสลับ — ห่อด้วย
        // SingleChildScrollView ด้วย เพราะเนื้อหายาวขึ้นมากหลังเพิ่มช่วง
        // ห้ามรดพิเศษ อาจเกินพื้นที่ dialog บนหน้าจอเล็กจนล้น (overflow)
        content: SizedBox(
          width: 320,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  title: const Text("ตามตารางเวลาของฟาร์ม"),
                  value: 'farm',
                  groupValue: choice,
                  onChanged: (v) => setDialogState(() => choice = v!),
                ),
                if (choice == 'farm') ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
                    child: Text(
                      groupSchedule?['scheduleEnabled'] == true
                          ? "ตอนนี้ใช้ตารางเวลาของฟาร์ม: "
                              "${groupSchedule?['scheduleMode'] == 'block' ? 'ห้ามรด' : 'รดได้'} "
                              "${groupSchedule?['scheduleStart']}-${groupSchedule?['scheduleEnd']}"
                          : "ฟาร์มยังไม่ได้ตั้งตารางเวลาไว้ — อุปกรณ์นี้จะรดน้ำ "
                              "ตามปกติไม่มีข้อจำกัดเรื่องเวลา",
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  title: const Text("ตั้งเวลาเฉพาะการ์ดนี้"),
                  value: 'custom',
                  groupValue: choice,
                  onChanged: (v) => setDialogState(() => choice = v!),
                ),
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  title: const Text("ยกเลิกการตั้งเวลา"),
                  subtitle: const Text(
                    "รดน้ำตามความชื้นอย่างเดียว ไม่มีข้อจำกัดเรื่องเวลา",
                  ),
                  value: 'none',
                  groupValue: choice,
                  onChanged: (v) => setDialogState(() => choice = v!),
                ),
                if (choice == 'custom') ...[
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
                  Text(
                    mode == 'allow'
                        ? "รดน้ำอัตโนมัติได้เฉพาะช่วงเวลานี้เท่านั้น "
                            "นอกช่วงนี้ระบบจะปิดโหมด Auto ให้ชั่วคราว"
                        : "รดน้ำอัตโนมัติได้ตามปกติ ยกเว้นช่วงเวลานี้ที่จะปิด "
                            "โหมด Auto ให้ชั่วคราว",
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 8),
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
                      if (picked != null) {
                        setDialogState(() => end = picked);
                      }
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

  // แปลงตัวเลือกกลับเป็น useOverride/enabled เดิมตอนบันทึก — 'none' คือ
  // override: true, enabled: false (ยกเลิกตารางเวลา ใช้ desiredAuto ตรงๆ
  // ไม่มีการเช็คเวลาเลย เหมือนก่อนมีฟีเจอร์นี้)
  final useOverride = choice != 'farm';
  final enabled = choice == 'custom';

  bool effective;
  bool desiredAuto;
  if (useOverride) {
    // desiredAuto: ถ้ายังไม่เคยมีมาก่อน ให้เริ่มจากค่า Auto ปัจจุบัน กัน
    // ไม่ให้ผู้ใช้เปิดตารางเวลาแล้ว Auto ที่เปิดอยู่ก่อนหน้าหายไปเฉยๆ
    desiredAuto = data['desiredAuto'] ?? data['Auto'] ?? false;

    final startHHmm = formatHHmm(start);
    final endHHmm = formatHHmm(end);
    final exceptStartHHmm = formatHHmm(exceptStart);
    final exceptEndHHmm = formatHHmm(exceptEnd);

    if (!enabled) {
      effective = desiredAuto == true;
    } else {
      final allowedNow = resolveScheduleAllowed(
        mode: mode,
        startHHmm: startHHmm,
        endHHmm: endHHmm,
        exceptEnabled: exceptEnabled,
        exceptStartHHmm: exceptStartHHmm,
        exceptEndHHmm: exceptEndHHmm,
      );
      effective = desiredAuto == true && allowedNow;
    }
  } else {
    // ไม่ override — ใช้ตารางเวลาของฟาร์มที่ดึงมาแสดงไว้ในไดอะล็อกนี้แล้ว
    // เปิดใช้ตารางเวลาของฟาร์มอยู่แล้ว = ถือว่ายินยอมให้อุปกรณ์นี้รดน้ำ
    // อัตโนมัติตามตารางนั้นทันที ไม่ต้องรอให้เคยเปิด Auto มาก่อน (เหมือนกับ
    // ตอนเปิด/บันทึกตารางเวลาทั้งฟาร์มจากเมนูรวม)
    final groupScheduleEnabled = groupSchedule?['scheduleEnabled'] == true;
    desiredAuto = groupScheduleEnabled
        ? true
        : (data['desiredAuto'] ?? data['Auto'] ?? false);

    if (groupScheduleEnabled) {
      final gStart = groupSchedule?['scheduleStart'] as String?;
      final gEnd = groupSchedule?['scheduleEnd'] as String?;
      if (gStart != null && gEnd != null) {
        final allowedNow = resolveScheduleAllowed(
          mode: groupSchedule?['scheduleMode'] == 'block' ? 'block' : 'allow',
          startHHmm: gStart,
          endHHmm: gEnd,
          exceptEnabled: groupSchedule?['scheduleExceptEnabled'] == true,
          exceptStartHHmm: groupSchedule?['scheduleExceptStart'] as String?,
          exceptEndHHmm: groupSchedule?['scheduleExceptEnd'] as String?,
        );
        effective = desiredAuto == true && allowedNow;
      } else {
        effective = desiredAuto == true;
      }
    } else {
      effective = desiredAuto == true;
    }
  }

  final Map<String, dynamic> update = {
    'scheduleOverride': useOverride,
    'desiredAuto': desiredAuto,
  };
  if (useOverride) {
    update['scheduleEnabled'] = enabled;
    update['scheduleMode'] = mode;
    update['scheduleStart'] = formatHHmm(start);
    update['scheduleEnd'] = formatHHmm(end);
    update['scheduleExceptEnabled'] = exceptEnabled;
    update['scheduleExceptStart'] = formatHHmm(exceptStart);
    update['scheduleExceptEnd'] = formatHHmm(exceptEnd);
  }
  update['Auto'] = effective;
  if (effective) update['Valve'] = false;

  // เคยเจอบั๊กจริงมาก่อน: Firestore rule ปฏิเสธ field ใหม่แบบเงียบๆ ไม่มี
  // อะไรโผล่ให้เห็นในแอปเลย ผู้ใช้กดบันทึกแล้วงงว่าทำไมไม่มีอะไรเกิดขึ้น —
  // ต้อง try/catch แล้วแจ้งชัดๆ ทุกครั้งไป ไม่ให้เงียบแบบนั้นอีก
  try {
    await FirebaseFirestore.instance
        .collection('ESP32')
        .doc(nanoId)
        .update(update);

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
              "บันทึกตารางเวลาแล้ว",
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
