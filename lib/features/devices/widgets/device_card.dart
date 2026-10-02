import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../pages/calendar_page.dart';
import '../pages/graph_page.dart';
import '../pages/notification_history_page.dart';
import '../utils/schedule_utils.dart';
import '../services/device_schedule.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/fruit_profiles.dart';
import '../services/plant_profile.dart';
import '../utils/moisture_utils.dart';
import 'status_chip.dart';
import 'stat_row.dart';
import 'control_chip.dart';
import 'action_button.dart';
import 'last_updated_text.dart';
import 'fruit_icon.dart';
import 'moisture_gauge.dart';
import 'stress_watch_card.dart' show stressLevelColor;

class DeviceCard extends StatefulWidget {
  final String nanoId;
  final Map<String, dynamic> data;
  final int index;
  // กดกล่องชนิดพืชบนการ์ด (หน้าหลักส่งมา เพราะต้องใช้รายการอุปกรณ์ทั้งหมด)
  final VoidCallback? onPlantTap;

  const DeviceCard({
    super.key,
    required this.nanoId,
    required this.data,
    this.index = 0,
    this.onPlantTap,
  });

  @override
  State<DeviceCard> createState() => DeviceCardState();
}

class DeviceCardState extends State<DeviceCard>
    with SingleTickerProviderStateMixin {
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
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nanoId = widget.nanoId;
    final data = widget.data;
    final currentTarget = _currentTarget;
    final moisture = (data['Moisture'] ?? 0).toDouble();
    final automois = (data['Automois'] ?? 20).toDouble();
    final isAlert = isMoistureAlert(moisture, automois);
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
                          LastUpdatedText(
                            nanoId: nanoId,
                            lastSeen: data['lastSeen'] as Timestamp?,
                          ),
                        ],
                      ),
                    ),
                    StatusChip(
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
                        child: MoistureGauge(
                          moisture: data['Moisture'] as num?,
                          target: currentTarget,
                          isOffline: isOffline,
                        ),
                      ),
                      const StatDivider(),
                      Expanded(
                        child: StatTile(
                          icon: Icons.flag,
                          label: "Target",
                          value: currentTarget.toString(),
                        ),
                      ),
                      const StatDivider(),
                      Expanded(
                        child: StatTile(
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
                      child: ControlChip(
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
                      child: ControlChip(
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
                // ถ้าเปิดตารางเวลาไว้ (ของตัวเองหรือของฟาร์มที่สังกัดอยู่ก็ได้)
                // และผู้ใช้ตั้งใจเปิด Auto แต่ตอนนี้ไม่ใช่ โชว์ตารางเวลาที่
                // ตั้งไว้เสมอเมื่อเปิดใช้ (ไม่ใช่โชว์แค่ตอนถูกบังคับปิดอยู่)
                // จะได้เห็นว่าตั้งไว้กี่โมงถึงกี่โมงโดยไม่ต้องกดเข้าไปดู — ถ้า
                // ตอนนี้กำลังถูกตารางเวลาบังคับปิด Auto อยู่ จะเปลี่ยนสีเป็น
                // ส้มเน้นให้เห็นชัดว่าทำไม Auto ไม่ทำงาน — อุปกรณ์ที่ไม่ได้
                // override เอง (ใช้ตารางเวลาของฟาร์มล้วนๆ) เดิมไม่โชว์อะไรเลย
                // เพราะ field ตารางเวลาอยู่ที่ device_registry ไม่ใช่ตัว
                // อุปกรณ์เอง ทำให้ดูเหมือนตั้งเวลาทั้งฟาร์มไปแล้ว "ไม่มีอะไร
                // เกิดขึ้น" ทั้งที่จริงๆทำงานถูกต้องอยู่เบื้องหลัง
                _ScheduleStatusLabel(data: data),
                _PlantProfileLabel(
                  nanoId: nanoId,
                  data: data,
                  onTap: widget.onPlantTap,
                ),
                const SizedBox(height: 14),
                const Divider(height: 1),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ActionButton(
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
                      child: ActionButton(
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
                      child: ActionButton(
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
                      child: _ScheduleActionButton(nanoId: nanoId, data: data),
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

// หาว่า "ตารางเวลาที่มีผลจริง" ของอุปกรณ์นี้ตอนนี้คืออะไร (หรือ null ถ้าไม่มี
// เลย) — ใช้ร่วมกันทั้งป้ายบอกตารางเวลาบนการ์ด (_ScheduleStatusLabel) และจุด
// สีเขียวบนปุ่ม "ตั้งเวลา" (_ScheduleActionButton) กันตรรกะสองที่ไม่ตรงกัน
// เหมือนที่เคยเกิดมาก่อน (ป้ายเช็ค override+ฟาร์มแล้ว แต่จุดเขียวเช็คแค่ field
// ของอุปกรณ์เองอย่างเดียว เลยไม่ตรงกัน)
Map<String, dynamic>? _resolveEffectiveSchedule(
  Map<String, dynamic> data,
  Map<String, dynamic>? groupData,
) {
  if (data['scheduleOverride'] == true) {
    if (data['scheduleEnabled'] != true ||
        data['scheduleStart'] == null ||
        data['scheduleEnd'] == null) {
      return null;
    }
    return data;
  }

  if (groupData == null ||
      groupData['scheduleEnabled'] != true ||
      groupData['scheduleStart'] == null ||
      groupData['scheduleEnd'] == null) {
    return null;
  }
  return {
    'desiredAuto': data['desiredAuto'],
    'Auto': data['Auto'],
    'scheduleEnabled': groupData['scheduleEnabled'],
    'scheduleMode': groupData['scheduleMode'],
    'scheduleStart': groupData['scheduleStart'],
    'scheduleEnd': groupData['scheduleEnd'],
    'scheduleExceptEnabled': groupData['scheduleExceptEnabled'],
    'scheduleExceptStart': groupData['scheduleExceptStart'],
    'scheduleExceptEnd': groupData['scheduleExceptEnd'],
  };
}

// ถ้า override เอง ไม่ต้อง query เพิ่ม (ใช้ field บนตัวอุปกรณ์ตรงๆ) ถ้าไม่ได้
// override แต่มี groupId ค่อย listen device_registry/{groupId} เพิ่มเพื่อดึง
// ตารางเวลาของฟาร์มมาคำนวณแทน — คืนค่า null (ผ่าน builder) ถ้าไม่มีตารางเวลา
// จากที่ไหนเลย ให้ widget ที่ใช้ตัดสินใจเองว่าจะโชว์อะไรตอนไม่มี
Widget _withEffectiveSchedule(
  Map<String, dynamic> data,
  Widget Function(BuildContext context, Map<String, dynamic>? schedule) builder,
) {
  if (data['scheduleOverride'] == true) {
    return Builder(
      builder: (context) =>
          builder(context, _resolveEffectiveSchedule(data, null)),
    );
  }

  final groupId = data['groupId'] as String?;
  if (groupId == null) {
    return Builder(builder: (context) => builder(context, null));
  }

  return StreamBuilder<DocumentSnapshot>(
    stream: FirebaseFirestore.instance
        .collection('device_registry')
        .doc(groupId)
        .snapshots(),
    builder: (context, snapshot) {
      final groupData = snapshot.data?.data() as Map<String, dynamic>?;
      return builder(context, _resolveEffectiveSchedule(data, groupData));
    },
  );
}

// แสดงป้ายตารางเวลาที่กำลังมีผลจริงกับอุปกรณ์นี้ ไม่ว่าจะมาจากตารางเวลาของ
// อุปกรณ์เอง (scheduleOverride: true) หรือมาจากตารางเวลาของฟาร์มที่สังกัดอยู่
// (device_registry) ก็ตาม
class _ScheduleStatusLabel extends StatelessWidget {
  final Map<String, dynamic> data;

  const _ScheduleStatusLabel({required this.data});

  @override
  Widget build(BuildContext context) {
    return _withEffectiveSchedule(data, (context, s) {
      if (s == null) return const SizedBox.shrink();

      final isSuppressed =
          (s['desiredAuto'] ?? s['Auto'] ?? false) == true && s['Auto'] != true;
      final isBlockMode = s['scheduleMode'] == 'block';
      final hasException = s['scheduleExceptEnabled'] == true &&
          s['scheduleExceptStart'] != null &&
          s['scheduleExceptEnd'] != null;
      final label = (isBlockMode
              ? "ห้ามรด ${s['scheduleStart']}-${s['scheduleEnd']}"
              : "รดได้ ${s['scheduleStart']}-${s['scheduleEnd']}") +
          (hasException
              ? " (ยกเว้น ${s['scheduleExceptStart']}-${s['scheduleExceptEnd']})"
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
                isSuppressed ? "$label (Auto หยุดชั่วคราวตอนนี้)" : label,
                style: TextStyle(fontSize: 11, color: color),
              ),
            ),
          ],
        ),
      );
    });
  }
}

// ปุ่ม "ตั้งเวลา" พร้อมจุดสีเขียวบอกว่ามีตารางเวลากำลังใช้งานอยู่จริงมั้ย —
// ใช้ตรรกะเดียวกับ _ScheduleStatusLabel เป๊ะๆ (เดิมเช็คแค่ field ของอุปกรณ์
// เอง ทำให้อุปกรณ์ที่ใช้ตารางเวลาของฟาร์มไม่ขึ้นจุดเขียว และอุปกรณ์ที่เคย
// override แล้วปิดสวิตช์ไปยังขึ้นจุดเขียวค้างจาก field เก่าที่ไม่ได้ล้าง)
class _ScheduleActionButton extends StatelessWidget {
  final String nanoId;
  final Map<String, dynamic> data;

  const _ScheduleActionButton({required this.nanoId, required this.data});

  @override
  Widget build(BuildContext context) {
    return _withEffectiveSchedule(data, (context, s) {
      return ActionButton(
        icon: Icons.schedule,
        label: "ตั้งเวลา",
        showBadge: s != null,
        onTap: () => openDeviceScheduleDialog(context, nanoId, data),
      );
    });
  }
}

// กล่องชนิดพืชบนการ์ด — บอกพืช/ความชื้นเป้าหมาย กด "เปลี่ยน" แล้วเปิดหน้า
// ชนิดพืชโดยติ๊กอุปกรณ์ตัวนี้ไว้ให้เลย ตั้งค่าเฉพาะการ์ดนี้ได้ในไม่กี่คลิก
// (พิมพ์ % เองได้ที่ "กำหนดเอง") ไม่ต้องไปไล่หาในรายการอุปกรณ์
class _PlantProfileLabel extends StatelessWidget {
  final String nanoId;
  final Map<String, dynamic> data;
  final VoidCallback? onTap;

  const _PlantProfileLabel({
    required this.nanoId,
    required this.data,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final profile = resolvePlantProfile(data);
    final target = (data['Automois'] ?? 20).toDouble();
    final scheme = Theme.of(context).colorScheme;
    final muted = Theme.of(context).textTheme.bodySmall?.color;
    final uid = FirebaseAuth.instance.currentUser?.uid;

    // ผลไม้/ช่วงที่เลือกไว้เก็บใน users/{uid}.plantSettings (ดู
    // PlantProfilePage) — การ์ดทุกใบฟัง doc เดียวกัน SDK รวมเป็น listener
    // เดียวให้เอง ไม่ได้ยิง read เพิ่มตามจำนวนการ์ด
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: uid == null
          ? null
          : FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snapshot) {
        final settings = snapshot.data?.data()?['plantSettings'];
        final setting = settings is Map ? settings[nanoId] : null;
        final label = plantLabelFor(
          target,
          setting is Map<String, dynamic> ? setting : null,
        );
        final isFruit = setting is Map && setting['plant'] == 'fruit';
        final stress = stressStatusFor(
          target,
          setting is Map<String, dynamic> ? setting : null,
        );

        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.8),
                  ),
                ),
                child: Row(
                  children: [
                    if (isFruit)
                      FruitIcon(size: 20, color: scheme.primary)
                    else
                      Icon(
                        profile?.icon ?? Icons.tune,
                        size: 20,
                        color: scheme.primary,
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                "ชนิดพืช",
                                style: TextStyle(fontSize: 11, color: muted),
                              ),
                              if (stress != null) ...[
                                const SizedBox(width: 6),
                                _StressBadge(status: stress),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            "$label · ${formatMoisture(target)}%",
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (onTap != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        "เปลี่ยน",
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: scheme.primary,
                        ),
                      ),
                      Icon(Icons.chevron_right,
                          size: 20, color: scheme.primary),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ป้ายนับวันงดน้ำบนการ์ดอุปกรณ์ — สีเดียวกับการ์ด "ต้นที่กำลังงดน้ำ"
class _StressBadge extends StatelessWidget {
  final StressStatus status;

  const _StressBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final c = stressLevelColor(status.level);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.withValues(alpha: 0.6)),
      ),
      child: Text(
        "งดน้ำ ${status.dayNumber}/${status.plannedDays} วัน",
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: c),
      ),
    );
  }
}
