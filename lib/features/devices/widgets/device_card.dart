import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../pages/calendar_page.dart';
import '../pages/graph_page.dart';
import '../pages/notification_history_page.dart';
import '../utils/schedule_utils.dart';

class DeviceCard extends StatefulWidget {
  final String nanoId;
  final Map<String, dynamic> data;
  final int index;

  const DeviceCard({
    super.key,
    required this.nanoId,
    required this.data,
    this.index = 0,
  });

  @override
  State<DeviceCard> createState() => DeviceCardState();
}

class DeviceCardState extends State<DeviceCard>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _controller;
  final _focusNode = FocusNode();

  // อนิเมชั่นตอนการ์ดเพิ่งปรากฏขึ้นครั้งแรก (fade + เลื่อนขึ้นเล็กน้อย) หน่วง
  // เวลาเริ่มตามตำแหน่งในกริด ให้ดูเป็นการ "ไล่โผล่" ทีละใบแทนที่จะโผล่มา
  // พร้อมกันหมดทุกใบ
  late final AnimationController _entranceController;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  double get _currentTarget => (widget.data['Automois'] ?? 20).toDouble();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _currentTarget.toString());

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _fadeAnim = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOut,
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(_fadeAnim);

    Future.delayed(
      Duration(milliseconds: (widget.index * 60).clamp(0, 600)),
      () {
        if (mounted) _entranceController.forward();
      },
    );
  }

  @override
  void didUpdateWidget(covariant DeviceCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // ซิงก์ค่าจาก Firestore เข้า field เฉพาะตอนที่ user ไม่ได้กำลังพิมพ์อยู่
    // กันไม่ให้ค่าที่พิมพ์ค้างถูกทับตอน snapshot ใหม่เข้ามาระหว่างพิมพ์
    if (!_focusNode.hasFocus) {
      _controller.text = _currentTarget.toString();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  // ยกเลิกการผูกอุปกรณ์ (ลบออกจากบัญชีตัวเอง ไม่ได้ลบ document ทิ้ง) — ยิงผ่าน
  // backend route /unclaim-device ด้วย Firebase ID token แทนที่จะเขียน
  // Firestore ตรงๆ จาก client เพื่อไม่ต้องเปิด rule เพิ่มให้ client เคลียร์
  // uid/ownerUid เอง (ดูเหตุผลเต็มๆ ที่ index.js)
  // ตั้งค่าตารางเวลารดน้ำอัตโนมัติ — ปิดอยู่โดย default ต่ออุปกรณ์ ไม่กระทบ
  // อุปกรณ์ที่ไม่ได้เปิดใช้เลย พอกด "บันทึก" จะคำนวณ Auto ที่แท้จริงใหม่
  // ทันที (ไม่ต้องรอ backend รอบถัดไป) ให้เห็นผลตรงกับที่ตั้งค่าไว้เลย
  Future<void> _openScheduleDialog(
    BuildContext context,
    String nanoId,
    Map<String, dynamic> data,
  ) async {
    bool useOverride = data['scheduleOverride'] == true;
    bool enabled = data['scheduleEnabled'] == true;
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
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text("ตั้งเวลาเฉพาะอุปกรณ์นี้"),
                    subtitle: const Text("ไม่ใช้ตารางเวลาของฟาร์ม"),
                    value: useOverride,
                    onChanged: (v) => setDialogState(() => useOverride = v),
                  ),
                  if (!useOverride) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
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
                  ],
                  if (useOverride) ...[
                    const SizedBox(height: 4),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text("เปิดใช้ตารางเวลา"),
                      value: enabled,
                      onChanged: (v) => setDialogState(() => enabled = v),
                    ),
                  ],
                  if (useOverride && enabled) ...[
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

    // desiredAuto: ถ้ายังไม่เคยมีมาก่อน ให้เริ่มจากค่า Auto ปัจจุบัน กัน
    // ไม่ให้ผู้ใช้เปิดตารางเวลาแล้ว Auto ที่เปิดอยู่ก่อนหน้าหายไปเฉยๆ
    final desiredAuto = data['desiredAuto'] ?? data['Auto'] ?? false;

    final Map<String, dynamic> update = {
      'scheduleOverride': useOverride,
      'desiredAuto': desiredAuto,
    };

    bool effective;
    if (useOverride) {
      final startHHmm = formatHHmm(start);
      final endHHmm = formatHHmm(end);
      final exceptStartHHmm = formatHHmm(exceptStart);
      final exceptEndHHmm = formatHHmm(exceptEnd);
      update['scheduleEnabled'] = enabled;
      update['scheduleMode'] = mode;
      update['scheduleStart'] = startHHmm;
      update['scheduleEnd'] = endHHmm;
      update['scheduleExceptEnabled'] = exceptEnabled;
      update['scheduleExceptStart'] = exceptStartHHmm;
      update['scheduleExceptEnd'] = exceptEndHHmm;

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
      if (groupSchedule?['scheduleEnabled'] == true) {
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
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

  @override
  Widget build(BuildContext context) {
    final nanoId = widget.nanoId;
    final data = widget.data;
    final currentTarget = _currentTarget;
    final moisture = (data['Moisture'] ?? 0).toDouble();
    final automois = (data['Automois'] ?? 20).toDouble();
    final isAlert = moisture > automois;
    final isOffline = data['offline'] == true;
    final faultType = data['faultType'] as String?;
    final hasValveFault = !isOffline && faultType != null;

    final card = Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        // การ์ดทุกใบสูงเท่ากันตายตัว (กำหนดจาก GridView) — ห่อด้วย
        // SingleChildScrollView กันไว้ ถ้าเนื้อหาในอนาคตยาวเกินพื้นที่การ์ด
        // จะแค่ scroll ข้างในการ์ดเอง ไม่มีทาง overflow ล้นออกมาอีก — ปิด
        // scrollbar ที่โผล่มาด้วย (ตอนนี้เนื้อหาพอดีการ์ดอยู่แล้ว ไม่มีอะไร
        // ต้องเลื่อนจริงๆ) ยังคง scroll ได้เผื่ออนาคตเนื้อหายาวขึ้น แค่ไม่โชว์
        // แถบ scrollbar ให้เกะกะ
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            scrollbars: false,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isOffline
                            ? Colors.grey.shade200
                            : (hasValveFault
                                ? Colors.orange.shade50
                                : (isAlert
                                    ? Colors.red.shade50
                                    : const Color(0xFFE8F5E9))),
                      ),
                      child: Icon(
                        isOffline
                            ? Icons.cloud_off
                            : (hasValveFault
                                ? Icons.report_problem_outlined
                                : Icons.water_drop),
                        color: isOffline
                            ? Colors.grey.shade600
                            : (hasValveFault
                                ? Colors.orange.shade800
                                : (isAlert
                                    ? Colors.red
                                    : const Color(0xFF2E7D32))),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            nanoId,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (data['groupId'] != null)
                            Text(
                              "กลุ่ม: ${data['groupId']}",
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.color,
                              ),
                            ),
                          const SizedBox(height: 2),
                          _LastUpdatedText(
                            nanoId: nanoId,
                            lastSeen: data['lastSeen'] as Timestamp?,
                          ),
                        ],
                      ),
                    ),
                    _StatusChip(
                      isAlert: isAlert,
                      isOffline: isOffline,
                      faultType: faultType,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _MoistureGauge(
                          moisture: data['Moisture'] as num?,
                          target: currentTarget,
                          isOffline: isOffline,
                        ),
                      ),
                      const _StatDivider(),
                      Expanded(
                        child: _StatTile(
                          icon: Icons.flag,
                          label: "Target",
                          value: currentTarget.toString(),
                        ),
                      ),
                      const _StatDivider(),
                      Expanded(
                        child: _StatTile(
                          icon: Icons.schedule,
                          label: "Time",
                          value: "${data['Time'] ?? '-'}",
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _ControlChip(
                        label: "Auto",
                        icon: Icons.auto_mode,
                        // ถ้าเปิดใช้ตารางเวลาไว้ โชว์ "ความตั้งใจ" ของผู้ใช้
                        // (desiredAuto) แทนค่า Auto จริงที่อาจถูกตารางเวลา
                        // บังคับปิดชั่วคราวอยู่ — ไม่งั้นสวิตช์จะดูเหมือน
                        // ปิดเองโดยไม่มีเหตุผลตอนอยู่นอกช่วงเวลา
                        value: (data['scheduleEnabled'] == true)
                            ? (data['desiredAuto'] ?? data['Auto'] ?? false)
                            : (data['Auto'] ?? false),
                        onChanged: (val) async {
                          final scheduleEnabled =
                              data['scheduleEnabled'] == true;

                          if (!scheduleEnabled) {
                            // ของเดิม ไม่เปลี่ยนพฤติกรรมเลยถ้าไม่ได้เปิดใช้
                            // ตารางเวลา
                            await FirebaseFirestore.instance
                                .collection('ESP32')
                                .doc(nanoId)
                                .update({
                              'Auto': val,
                              if (val == true) 'Valve': false,
                            });
                            return;
                          }

                          final scheduleStart =
                              data['scheduleStart'] as String?;
                          final scheduleEnd = data['scheduleEnd'] as String?;
                          bool allowedNow = true;
                          if (scheduleStart != null && scheduleEnd != null) {
                            allowedNow = resolveScheduleAllowed(
                              mode: data['scheduleMode'] == 'block'
                                  ? 'block'
                                  : 'allow',
                              startHHmm: scheduleStart,
                              endHHmm: scheduleEnd,
                              exceptEnabled:
                                  data['scheduleExceptEnabled'] == true,
                              exceptStartHHmm:
                                  data['scheduleExceptStart'] as String?,
                              exceptEndHHmm:
                                  data['scheduleExceptEnd'] as String?,
                            );
                          }
                          final effective = val && allowedNow;

                          await FirebaseFirestore.instance
                              .collection('ESP32')
                              .doc(nanoId)
                              .update({
                            'desiredAuto': val,
                            'Auto': effective,
                            if (effective) 'Valve': false,
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ControlChip(
                        label: "Valve",
                        icon: Icons.water,
                        value: data['Valve'] ?? false,
                        onChanged: (val) async {
                          await FirebaseFirestore.instance
                              .collection('ESP32')
                              .doc(nanoId)
                              .update({
                            'Valve': val,
                            // เปิด Valve มือ = ปิด Auto กันชนกัน แต่ปิด Valve ไม่ควร
                            // ไปเปิด Auto กลับให้เอง เพราะผู้ใช้อาจตั้งใจแค่จะหยุด
                            // รดน้ำ ไม่ได้ต้องการให้ระบบตัดสินใจเปิดวาล์วเองอีก
                            //
                            // ต้องเคลียร์ desiredAuto ไปด้วย ไม่งั้นถ้าเปิดใช้
                            // ตารางเวลาไว้ checkDevices.js รอบถัดไปจะเห็นว่า
                            // desiredAuto ยังเป็น true แล้วเปิด Auto กลับมาเอง
                            // ทับการเปิดวาล์วมือที่เพิ่งสั่งไป
                            if (val == true) 'Auto': false,
                            if (val == true) 'desiredAuto': false,
                          });
                        },
                      ),
                    ),
                  ],
                ),
                // ถ้าเปิดตารางเวลาไว้ และผู้ใช้ตั้งใจเปิด Auto แต่ตอนนี้ไม่ใช่
                // โชว์ตารางเวลาที่ตั้งไว้เสมอเมื่อเปิดใช้ (ไม่ใช่โชว์แค่ตอนถูก
                // บังคับปิดอยู่) จะได้เห็นว่าตั้งไว้กี่โมงถึงกี่โมงโดยไม่ต้อง
                // กดเข้าไปดู — ถ้าตอนนี้กำลังถูกตารางเวลาบังคับปิด Auto อยู่
                // จะเปลี่ยนสีเป็นส้มเน้นให้เห็นชัดว่าทำไม Auto ไม่ทำงาน
                if (data['scheduleEnabled'] == true &&
                    data['scheduleStart'] != null &&
                    data['scheduleEnd'] != null)
                  Builder(builder: (context) {
                    final isSuppressed =
                        (data['desiredAuto'] ?? data['Auto'] ?? false) ==
                                true &&
                            data['Auto'] != true;
                    final isBlockMode = data['scheduleMode'] == 'block';
                    final hasException =
                        data['scheduleExceptEnabled'] == true &&
                            data['scheduleExceptStart'] != null &&
                            data['scheduleExceptEnd'] != null;
                    final label = (isBlockMode
                            ? "ห้ามรด ${data['scheduleStart']}-${data['scheduleEnd']}"
                            : "รดได้ ${data['scheduleStart']}-${data['scheduleEnd']}") +
                        (hasException
                            ? " (ยกเว้น ${data['scheduleExceptStart']}-${data['scheduleExceptEnd']})"
                            : "");
                    final color = isSuppressed
                        ? Colors.orange
                        : Theme.of(context).textTheme.bodySmall?.color;

                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          Icon(Icons.schedule, size: 14, color: color),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              isSuppressed
                                  ? "$label (Auto หยุดชั่วคราวตอนนี้)"
                                  : label,
                              style: TextStyle(fontSize: 11, color: color),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                const SizedBox(height: 14),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context).dividerColor,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.tune,
                          size: 18,
                          color: Theme.of(context).textTheme.bodySmall?.color),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          "ตั้งค่าความชื้น",
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                      SizedBox(
                        width: 70,
                        child: TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 13),
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 36,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                          ),
                          onPressed: () async {
                            final newValue = double.tryParse(_controller.text);

                            if (newValue != null) {
                              await FirebaseFirestore.instance
                                  .collection('ESP32')
                                  .doc(nanoId)
                                  .update({
                                'Automois': newValue,
                              });

                              if (!context.mounted) return;

                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  behavior: SnackBarBehavior.floating,
                                  backgroundColor: const Color(0xFF2E7D32),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  margin: const EdgeInsets.all(16),
                                  content: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.check_circle,
                                          color: Colors.white, size: 20),
                                      SizedBox(width: 10),
                                      Text(
                                        "อัปเดตค่าความชื้นแล้ว",
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }
                          },
                          child: const Text("บันทึก"),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const Divider(height: 1),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _ActionButton(
                        icon: Icons.calendar_month,
                        label: "Calendar",
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CalendarPage(nanoId: nanoId),
                            ),
                          );
                        },
                      ),
                    ),
                    Expanded(
                      child: _ActionButton(
                        icon: Icons.show_chart,
                        label: "Graph",
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => GraphPage(nanoId: nanoId),
                            ),
                          );
                        },
                      ),
                    ),
                    Expanded(
                      child: _ActionButton(
                        icon: Icons.notifications_outlined,
                        label: "History",
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => NotificationHistoryPage(
                                nanoId: nanoId,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    // เดิมซ่อนไว้หลังเมนู "⋮" ทำให้หาไม่เจอ + ดูไม่สมูธเพราะปุ่ม
                    // เล็กแปลกๆ อยู่ปนกับปุ่มใหญ่ 3 ปุ่ม — ย้ายมาเป็นปุ่มแบบ
                    // เดียวกันเลย ให้เห็นชัดว่ากดตั้งเวลาได้ พร้อมจุดเขียวบอกว่า
                    // ตั้งไว้แล้วหรือยัง (อันนี้ยังอยู่ที่การ์ดเหมือนเดิม เพราะ
                    // เป็นการตั้งค่าเฉพาะอุปกรณ์นี้ — ต่างจาก "ลบอุปกรณ์" ที่ย้าย
                    // ไปรวมอยู่ในเมนูรวมของหน้าหลักแทนแล้ว)
                    Expanded(
                      child: _ActionButton(
                        icon: Icons.schedule,
                        label: "ตั้งเวลา",
                        showBadge: data['scheduleEnabled'] == true,
                        onTap: () => _openScheduleDialog(context, nanoId, data),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(position: _slideAnim, child: card),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final bool isAlert;
  final bool isOffline;
  final String? faultType;

  const _StatusChip({
    required this.isAlert,
    this.isOffline = false,
    this.faultType,
  });

  @override
  Widget build(BuildContext context) {
    final hasValveFault = !isOffline && faultType != null;

    // ลำดับความสำคัญ: ขาดการติดต่อ > วาล์วผิดปกติ > ความชื้นเกิน > ปกติ
    // เพราะค่าที่โชว์อยู่อาจเป็นค่าเก่าที่ค้างมาจากก่อนจะเกิดปัญหา
    final Color color;
    final IconData icon;
    final String label;

    if (isOffline) {
      color = Colors.grey.shade600;
      icon = Icons.cloud_off;
      label = "ขาดการติดต่อ";
    } else if (hasValveFault) {
      color = Colors.orange.shade800;
      icon = Icons.report_problem_outlined;
      label = faultType == "valve_stuck_open"
          ? "วาล์วค้างเปิด"
          : "วาล์วอาจไม่ทำงาน";
    } else if (isAlert) {
      color = Colors.red;
      icon = Icons.warning_amber_rounded;
      label = "แจ้งเตือน";
    } else {
      color = Colors.green;
      icon = Icons.check_circle;
      label = "ปกติ";
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 18, color: const Color(0xFF2E7D32)),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          textAlign: TextAlign.center,
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).textTheme.bodySmall?.color,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 36,
      color: Theme.of(context).dividerColor,
    );
  }
}

class _ControlChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ControlChip({
    required this.label,
    required this.icon,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    const activeColor = Color(0xFF2E7D32);
    final mutedColor = Theme.of(context).textTheme.bodySmall?.color;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: value
            ? activeColor.withValues(alpha: 0.10)
            : Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: value
              ? activeColor.withValues(alpha: 0.4)
              : Theme.of(context).dividerColor,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: value ? activeColor : mutedColor),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: value ? activeColor : mutedColor,
              ),
            ),
          ),
          Transform.scale(
            scale: 0.8,
            child: Switch(
              value: value,
              activeThumbColor: activeColor,
              inactiveThumbColor: Colors.grey,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  // จุดเขียวเล็กๆ บอกว่าปุ่มนี้มีการตั้งค่าเปิดใช้อยู่ (เช่น ตั้งเวลารดน้ำ
  // ไว้แล้ว) ให้เห็นชัดเจนโดยไม่ต้องกดเข้าไปดูก่อน
  final bool showBadge;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.showBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, size: 20, color: const Color(0xFF2E7D32)),
                if (showBadge)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).textTheme.bodyMedium?.color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LastUpdatedText extends StatefulWidget {
  final String nanoId;
  // ประทับจาก /update ตรงๆ ทุกครั้งที่อุปกรณ์รายงานค่าจริง — อัปเดตสดตาม
  // stream ของ ESP32 doc อยู่แล้ว ไม่ต้อง query ซ้ำ ถ้าเป็น null (อุปกรณ์เก่า
  // ที่ยังไม่เคยได้รับ /update รอบใหม่) จะ fallback ไปดู log ล่าสุดแทน
  final Timestamp? lastSeen;

  const _LastUpdatedText({required this.nanoId, required this.lastSeen});

  @override
  State<_LastUpdatedText> createState() => _LastUpdatedTextState();
}

class _LastUpdatedTextState extends State<_LastUpdatedText> {
  Future<Timestamp?>? _fallbackFuture;

  @override
  void initState() {
    super.initState();
    if (widget.lastSeen == null) {
      _fallbackFuture = _fetchLatestLogTimestamp();
    }
  }

  @override
  void didUpdateWidget(covariant _LastUpdatedText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.lastSeen != null) {
      _fallbackFuture = null;
    } else if (oldWidget.nanoId != widget.nanoId ||
        oldWidget.lastSeen != null) {
      _fallbackFuture = _fetchLatestLogTimestamp();
    }
  }

  Future<Timestamp?> _fetchLatestLogTimestamp() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('ESP32')
        .doc(widget.nanoId)
        .collection('Logs')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) return null;
    return snapshot.docs.first.data()['timestamp'] as Timestamp?;
  }

  String _relativeTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return "เมื่อสักครู่";
    if (diff.inMinutes < 60) return "${diff.inMinutes} นาทีที่แล้ว";
    if (diff.inHours < 24) return "${diff.inHours} ชม. ที่แล้ว";
    return "${diff.inDays} วันที่แล้ว";
  }

  // แสดง Row เดิมเสมอไม่ว่าจะมีข้อมูลหรือไม่ (แค่เปลี่ยนข้อความ) กันสัดส่วน
  // การ์ดเพี้ยนไปเทียบกับอุปกรณ์ตัวอื่นที่มีข้อมูลอยู่แล้ว
  Widget _buildText(BuildContext context, Timestamp? ts) {
    final color = Theme.of(context).textTheme.bodySmall?.color;

    return Row(
      children: [
        Icon(Icons.update, size: 12, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            ts == null
                ? "ยังไม่มีข้อมูล"
                : "อัปเดต: ${_relativeTime(ts.toDate())}",
            style: TextStyle(fontSize: 11, color: color),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.lastSeen != null) {
      return _buildText(context, widget.lastSeen);
    }

    return FutureBuilder<Timestamp?>(
      future: _fallbackFuture,
      builder: (context, snapshot) => _buildText(context, snapshot.data),
    );
  }
}

class _MoistureGauge extends StatelessWidget {
  final num? moisture;
  final double target;
  final bool isOffline;

  const _MoistureGauge({
    required this.moisture,
    required this.target,
    required this.isOffline,
  });

  @override
  Widget build(BuildContext context) {
    final value = moisture?.toDouble();
    final isAlert = value != null && value > target;
    final color = isOffline
        ? Colors.grey.shade500
        : (isAlert ? Colors.red : const Color(0xFF2E7D32));
    final ratio =
        (value == null || target <= 0) ? 0.0 : (value / target).clamp(0.0, 1.0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 40,
          height: 40,
          // ค่าความชื้นเป็น real-time (มาจาก Firestore stream) เปลี่ยนบ่อย —
          // ใช้ TweenAnimationBuilder ไล่ค่าเก่าไปค่าใหม่ทีละนิด (ทั้งวงแหวน
          // และตัวเลข) แทนการกระตุกเปลี่ยนทันทีทุกครั้งที่ค่าขยับ
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value == null ? 0 : ratio),
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOut,
            builder: (context, animatedRatio, _) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: animatedRatio,
                    strokeWidth: 4,
                    backgroundColor: color.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: value ?? 0),
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOut,
                    builder: (context, animatedValue, _) {
                      return Text(
                        value == null ? '-' : animatedValue.toStringAsFixed(0),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      );
                    },
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 4),
        Text(
          "Moisture",
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).textTheme.bodySmall?.color,
          ),
        ),
      ],
    );
  }
}
