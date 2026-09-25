import 'package:flutter/material.dart';

// แถบไอคอนถาวรด้านซ้าย แทนที่เมนู hamburger + drawer เดิม — เหมาะกับหน้าจอ
// กว้างแบบเว็บ เข้าถึงเมนูหลักได้ทันทีโดยไม่ต้องกดเปิด/ปิดอีกต่อไป
class SideNavRail extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: 72,
      color: isDark ? const Color(0xFF0A0B0C) : scheme.surfaceContainerHighest,
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
              onTap: () {},
            ),
            const SizedBox(height: 4),
            _NavIcon(
              icon: Icons.add_circle_outline_rounded,
              tooltip: "เพิ่มอุปกรณ์",
              onTap: onAddDevice,
            ),
            const SizedBox(height: 4),
            _ScheduleMenuIcon(
              onFarmSchedule: onFarmSchedule,
              onScheduleOverview: onScheduleOverview,
              onWeather: onWeather,
            ),
            const SizedBox(height: 4),
            _NavIcon(
              icon: Icons.delete_outline,
              tooltip: "ลบอุปกรณ์",
              onTap: onRemoveDevice,
              color: Colors.red,
            ),
            const Spacer(),
            _NavIcon(
              icon: Icons.person_outline_rounded,
              tooltip: "โปรไฟล์",
              onTap: onProfile,
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
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

// ไอคอน "ตารางเวลา" กดแล้วขึ้นเมนูย่อย 3 อัน (ตั้งเวลาทั้งฟาร์ม/สรุปตาราง
// เวลา/พยากรณ์อากาศ) แทนการพาไปหน้าใดหน้าหนึ่งตรงๆ — ใช้ PopupMenuButton
// แทนแถบ Drawer เดิมที่ไม่มีให้ใช้แล้วในโครงสร้างใหม่นี้
class _ScheduleMenuIcon extends StatelessWidget {
  final VoidCallback onFarmSchedule;
  final VoidCallback onScheduleOverview;
  final VoidCallback onWeather;

  const _ScheduleMenuIcon({
    required this.onFarmSchedule,
    required this.onScheduleOverview,
    required this.onWeather,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Tooltip(
      message: "ตารางเวลา",
      child: PopupMenuButton<VoidCallback>(
        tooltip: '',
        position: PopupMenuPosition.under,
        onSelected: (callback) => callback(),
        itemBuilder: (context) => [
          PopupMenuItem(
            value: onFarmSchedule,
            child: const Row(
              children: [
                Icon(Icons.schedule, size: 20),
                SizedBox(width: 12),
                Text("ตั้งเวลาทั้งฟาร์ม"),
              ],
            ),
          ),
          PopupMenuItem(
            value: onScheduleOverview,
            child: const Row(
              children: [
                Icon(Icons.fact_check_outlined, size: 20),
                SizedBox(width: 12),
                Text("สรุปตารางเวลา"),
              ],
            ),
          ),
          PopupMenuItem(
            value: onWeather,
            child: const Row(
              children: [
                Icon(Icons.cloud_outlined, size: 20),
                SizedBox(width: 12),
                Text("พยากรณ์อากาศ"),
              ],
            ),
          ),
        ],
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(Icons.schedule, color: scheme.onSurface, size: 22),
        ),
      ),
    );
  }
}
