import 'package:flutter/material.dart';

// แถบไอคอนถาวรด้านซ้าย แทนที่เมนู hamburger + drawer เดิม — เหมาะกับหน้าจอ
// กว้างแบบเว็บ เข้าถึงเมนูหลักได้ทันทีโดยไม่ต้องกดเปิด/ปิดอีกต่อไป
class SideNavRail extends StatefulWidget {
  final VoidCallback onAddDevice;
  final VoidCallback onFarmSchedule;
  final VoidCallback onScheduleOverview;
  final VoidCallback onWeather;
  final VoidCallback onRemoveDevice;
  final VoidCallback onProfile;

  const SideNavRail({
    super.key,
    required this.onAddDevice,
    required this.onFarmSchedule,
    required this.onScheduleOverview,
    required this.onWeather,
    required this.onRemoveDevice,
    required this.onProfile,
  });

  @override
  State<SideNavRail> createState() => _SideNavRailState();
}

class _SideNavRailState extends State<SideNavRail> {
  // แผงเมนูย่อย "ตารางเวลา" เด้งออกมาเป็นแท็บใหญ่ข้างแถบไอคอน แทนเมนูเล็กๆ
  // แบบ hover เดิม (PopupMenuButton) — เปิด/ปิดด้วย state ตรงๆ ไม่ใช้ overlay
  bool _scheduleOpen = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final railColor =
        isDark ? const Color(0xFF0A0B0C) : scheme.surfaceContainerHighest;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 72,
          color: railColor,
          child: SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 16),
                Icon(Icons.eco_rounded, color: scheme.primary, size: 28),
                const SizedBox(height: 24),
                _NavIcon(
                  icon: Icons.grid_view_rounded,
                  tooltip: "หน้าหลัก",
                  active: true,
                  onTap: () => setState(() => _scheduleOpen = false),
                ),
                const SizedBox(height: 4),
                _NavIcon(
                  icon: Icons.add_circle_outline_rounded,
                  tooltip: "เพิ่มอุปกรณ์",
                  onTap: widget.onAddDevice,
                ),
                const SizedBox(height: 4),
                _NavIcon(
                  icon: Icons.schedule,
                  tooltip: "ตารางเวลา",
                  active: _scheduleOpen,
                  onTap: () => setState(() => _scheduleOpen = !_scheduleOpen),
                ),
                const SizedBox(height: 4),
                _NavIcon(
                  icon: Icons.delete_outline,
                  tooltip: "ลบอุปกรณ์",
                  onTap: widget.onRemoveDevice,
                  color: Colors.red,
                ),
                const Spacer(),
                _NavIcon(
                  icon: Icons.person_outline_rounded,
                  tooltip: "โปรไฟล์",
                  onTap: widget.onProfile,
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          child: _scheduleOpen
              ? _SchedulePanel(
                  onClose: () => setState(() => _scheduleOpen = false),
                  onFarmSchedule: () {
                    setState(() => _scheduleOpen = false);
                    widget.onFarmSchedule();
                  },
                  onScheduleOverview: () {
                    setState(() => _scheduleOpen = false);
                    widget.onScheduleOverview();
                  },
                  onWeather: () {
                    setState(() => _scheduleOpen = false);
                    widget.onWeather();
                  },
                )
              : const SizedBox(width: 0),
        ),
      ],
    );
  }
}

class _NavIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;
  final Color? color;

  const _NavIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final iconColor = color ?? (active ? scheme.primary : scheme.onSurface);

    return Tooltip(
      message: tooltip,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Material(
          color: active
              ? scheme.primary.withValues(alpha: 0.16)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Icon(icon, color: iconColor, size: 22),
            ),
          ),
        ),
      ),
    );
  }
}

// แผงตารางเวลา — แท็บใหญ่ที่เด้งออกมาข้างแถบไอคอนถาวร (ไม่ใช่เมนู hover
// เล็กๆ แบบเดิม) แสดงหัวข้อ + รายการ 3 อันเต็มความกว้าง กดปิดได้ด้วยปุ่ม X
class _SchedulePanel extends StatelessWidget {
  final VoidCallback onClose;
  final VoidCallback onFarmSchedule;
  final VoidCallback onScheduleOverview;
  final VoidCallback onWeather;

  const _SchedulePanel({
    required this.onClose,
    required this.onFarmSchedule,
    required this.onScheduleOverview,
    required this.onWeather,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: 240,
      color: isDark ? const Color(0xFF141517) : Theme.of(context).cardColor,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      "ตารางเวลา",
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: onClose,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.schedule),
              title: const Text("ตั้งเวลาทั้งฟาร์ม"),
              onTap: onFarmSchedule,
            ),
            ListTile(
              leading: const Icon(Icons.fact_check_outlined),
              title: const Text("สรุปตารางเวลา"),
              onTap: onScheduleOverview,
            ),
            ListTile(
              leading: const Icon(Icons.cloud_outlined),
              title: const Text("พยากรณ์อากาศ"),
              onTap: onWeather,
            ),
          ],
        ),
      ),
    );
  }
}
