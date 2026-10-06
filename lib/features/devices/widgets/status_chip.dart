import 'package:flutter/material.dart';

// ชื่อปัญหาจาก faultType ที่ backend (checkDevices.js) เขียนไว้ — เดิมทุกค่า
// ที่ไม่ใช่ valve_stuck_open ถูกโชว์เป็น "วาล์วอาจไม่ทำงาน" หมด รวมถึง
// nano_error/sensor_error ที่ไม่เกี่ยวกับวาล์วเลย ทำให้เข้าใจผิดว่าวาล์วเสีย
String faultLabel(String? faultType) => switch (faultType) {
      "valve_stuck_open" => "วาล์วค้างเปิด",
      "valve_no_flow" => "วาล์วอาจไม่ทำงาน",
      "nano_error" => "ติดต่อ Nano ไม่ได้",
      "sensor_error" => "เซนเซอร์อ่านค่าไม่ได้",
      _ => "อุปกรณ์ผิดปกติ",
    };

class StatusChip extends StatelessWidget {
  final bool isAlert;
  final bool isOffline;
  final String? faultType;

  const StatusChip({
    super.key,
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
      icon = switch (faultType) {
        "nano_error" => Icons.link_off,
        "sensor_error" => Icons.sensors_off,
        _ => Icons.report_problem_outlined,
      };
      label = faultLabel(faultType);
    } else if (isAlert) {
      color = Colors.red;
      icon = Icons.warning_amber_rounded;
      label = "ดินแห้ง";
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
