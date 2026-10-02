import 'package:flutter/material.dart';
import '../../../main.dart' show themeModeNotifier, toggleThemeMode;

// แถบไอคอนถาวรด้านซ้าย แทนที่เมนู hamburger + drawer เดิม — เหมาะกับหน้าจอ
// กว้างแบบเว็บ เข้าถึงเมนูหลักได้ทันทีโดยไม่ต้องกดเปิด/ปิดอีกต่อไป
class SideNavRail extends StatefulWidget {
  final VoidCallback onAddDevice;
  final VoidCallback onSchedule;
  final VoidCallback onWeather;
  final VoidCallback onPlantProfile;
  final VoidCallback onRemoveDevice;
  final VoidCallback onProfile;

  const SideNavRail({
    super.key,
    required this.onAddDevice,
    required this.onSchedule,
    required this.onWeather,
    required this.onPlantProfile,
    required this.onRemoveDevice,
    required this.onProfile,
  });

  @override
  State<SideNavRail> createState() => _SideNavRailState();
}

class _SideNavRailState extends State<SideNavRail> {
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
                  onTap: () {},
                ),
                const SizedBox(height: 4),
                _NavIcon(
                  icon: Icons.add_circle_outline_rounded,
                  tooltip: "เพิ่มอุปกรณ์",
                  onTap: widget.onAddDevice,
                ),
                const SizedBox(height: 4),
                // ตารางเวลา/พยากรณ์อากาศ เป็นหน้าของตัวเองแล้ว (SchedulePage /
                // WeatherPage) ไม่ใช่แผงเมนูย่อยเด้งออกมาเหมือนเดิม
                _NavIcon(
                  icon: Icons.schedule,
                  tooltip: "ตารางเวลา",
                  onTap: widget.onSchedule,
                ),
                const SizedBox(height: 4),
                _NavIcon(
                  icon: Icons.cloud_outlined,
                  tooltip: "พยากรณ์อากาศ",
                  onTap: widget.onWeather,
                ),
                const SizedBox(height: 4),
                _NavIcon(
                  icon: Icons.local_florist_outlined,
                  tooltip: "ชนิดพืช",
                  onTap: widget.onPlantProfile,
                ),
                const SizedBox(height: 4),
                _NavIcon(
                  icon: Icons.delete_outline,
                  tooltip: "ลบอุปกรณ์",
                  onTap: widget.onRemoveDevice,
                  color: Colors.red,
                ),
                const Spacer(),
                ValueListenableBuilder<ThemeMode>(
                  valueListenable: themeModeNotifier,
                  builder: (context, mode, _) {
                    final nowDark = mode == ThemeMode.dark;
                    return _NavIcon(
                      icon: nowDark
                          ? Icons.light_mode_outlined
                          : Icons.dark_mode_outlined,
                      tooltip: nowDark ? "โหมดสว่าง" : "โหมดมืด",
                      onTap: toggleThemeMode,
                    );
                  },
                ),
                const SizedBox(height: 4),
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
