import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../pages/calendar_page.dart';
import '../pages/graph_page.dart';
import '../pages/notification_history_page.dart';
import '../utils/schedule_utils.dart';
import '../services/device_schedule.dart';
import 'status_chip.dart';
import 'stat_row.dart';
import 'control_chip.dart';
import 'action_button.dart';
import 'last_updated_text.dart';
import 'moisture_gauge.dart';

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
                      child: ActionButton(
                        icon: Icons.schedule,
                        label: "ตั้งเวลา",
                        showBadge: data['scheduleEnabled'] == true,
                        onTap: () =>
                            openDeviceScheduleDialog(context, nanoId, data),
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

// แสดงป้ายตารางเวลาที่กำลังมีผลจริงกับอุปกรณ์นี้ ไม่ว่าจะมาจากตารางเวลาของ
// อุปกรณ์เอง (scheduleOverride: true) หรือมาจากตารางเวลาของฟาร์มที่สังกัดอยู่
// (device_registry) ก็ตาม — ถ้า override เอง ใช้ field บนตัวอุปกรณ์ตรงๆ
// (ไม่ต้อง query เพิ่ม) ถ้าไม่ได้ override แต่มี groupId ค่อย listen
// device_registry/{groupId} เพิ่มเพื่อดึงตารางเวลาของฟาร์มมาโชว์
class _ScheduleStatusLabel extends StatelessWidget {
  final Map<String, dynamic> data;

  const _ScheduleStatusLabel({required this.data});

  @override
  Widget build(BuildContext context) {
    if (data['scheduleOverride'] == true) {
      return _buildFromSchedule(context, data);
    }

    final groupId = data['groupId'] as String?;
    if (groupId == null) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('device_registry')
          .doc(groupId)
          .snapshots(),
      builder: (context, snapshot) {
        final groupData = snapshot.data?.data() as Map<String, dynamic>?;
        if (groupData == null) return const SizedBox.shrink();
        return _buildFromSchedule(context, {
          'desiredAuto': data['desiredAuto'],
          'Auto': data['Auto'],
          'scheduleEnabled': groupData['scheduleEnabled'],
          'scheduleMode': groupData['scheduleMode'],
          'scheduleStart': groupData['scheduleStart'],
          'scheduleEnd': groupData['scheduleEnd'],
          'scheduleExceptEnabled': groupData['scheduleExceptEnabled'],
          'scheduleExceptStart': groupData['scheduleExceptStart'],
          'scheduleExceptEnd': groupData['scheduleExceptEnd'],
        });
      },
    );
  }

  Widget _buildFromSchedule(BuildContext context, Map<String, dynamic> s) {
    if (s['scheduleEnabled'] != true ||
        s['scheduleStart'] == null ||
        s['scheduleEnd'] == null) {
      return const SizedBox.shrink();
    }

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
  }
}
