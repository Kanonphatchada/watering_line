import 'package:flutter/material.dart';

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
