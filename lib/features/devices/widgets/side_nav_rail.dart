import 'package:flutter/material.dart';
import '../../../main.dart' show themeModeNotifier, toggleThemeMode;

// แถบไอคอนถาวรด้านซ้าย แทนที่เมนู hamburger + drawer เดิม — เหมาะกับหน้าจอ
// กว้างแบบเว็บ เข้าถึงเมนูหลักได้ทันทีโดยไม่ต้องกดเปิด/ปิดอีกต่อไป
// บนมือถือ (asDrawer) แถบกว้าง 72px กินจอเกือบ 1/5 และไอคอนล้นจอเตี้ย จึงใช้
// เมนูชุดเดียวกันแต่แสดงเป็น Drawer มีชื่อเมนูกำกับแทน
class SideNavRail extends StatefulWidget {
  final bool asDrawer;
  final VoidCallback onAddDevice;
  final VoidCallback onSchedule;
  final VoidCallback onWeather;
  final VoidCallback onPlantProfile;
  final VoidCallback onGroups;
  final VoidCallback onMembers;
  final VoidCallback onRemoveDevice;
  final VoidCallback onProfile;

  const SideNavRail({
    super.key,
    this.asDrawer = false,
    required this.onAddDevice,
    required this.onSchedule,
    required this.onWeather,
    required this.onPlantProfile,
    required this.onGroups,
    required this.onMembers,
    required this.onRemoveDevice,
    required this.onProfile,
  });

  @override
  State<SideNavRail> createState() => _SideNavRailState();
}

class _SideNavRailState extends State<SideNavRail> {
  // เมนูหลัก (ไม่รวมโหมดมืด/โปรไฟล์ที่อยู่ล่างสุด) — ใช้ร่วมกันทั้ง rail และ drawer
  List<(IconData, String, VoidCallback, Color?)> get _mainItems => [
        (
          Icons.add_circle_outline_rounded,
          "เพิ่มอุปกรณ์",
          widget.onAddDevice,
          null
        ),
        // ตารางเวลา/พยากรณ์อากาศ เป็นหน้าของตัวเองแล้ว (SchedulePage /
        // WeatherPage) ไม่ใช่แผงเมนูย่อยเด้งออกมาเหมือนเดิม
        (Icons.schedule, "ตารางเวลา", widget.onSchedule, null),
        (Icons.cloud_outlined, "พยากรณ์อากาศ", widget.onWeather, null),
        (Icons.local_florist_outlined, "ชนิดพืช", widget.onPlantProfile, null),
        (Icons.folder_copy_outlined, "กลุ่มอุปกรณ์", widget.onGroups, null),
        (Icons.group_outlined, "สมาชิกของฟาร์ม", widget.onMembers, null),
        (Icons.delete_outline, "ลบอุปกรณ์", widget.onRemoveDevice, Colors.red),
      ];

  Widget _buildDrawer(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // ปิด drawer ก่อนค่อยเปิดหน้าใหม่ — กลับมาแล้วจะไม่เจอ drawer ค้างอยู่
    VoidCallback closeThen(VoidCallback action) => () {
          Navigator.pop(context);
          action();
        };

    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            ListTile(
              leading: Icon(Icons.eco_rounded, color: scheme.primary, size: 28),
              title: const Text(
                "WateringLine",
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            const Divider(),
            ListTile(
              leading: Icon(Icons.grid_view_rounded, color: scheme.primary),
              title: const Text("หน้าหลัก"),
              selected: true,
              onTap: () => Navigator.pop(context),
            ),
            for (final (icon, label, onTap, color) in _mainItems)
              ListTile(
                leading: Icon(icon, color: color),
                title: Text(label, style: TextStyle(color: color)),
                onTap: closeThen(onTap),
              ),
            const Divider(),
            ValueListenableBuilder<ThemeMode>(
              valueListenable: themeModeNotifier,
              builder: (context, mode, _) {
                final nowDark = mode == ThemeMode.dark;
                return ListTile(
                  leading: Icon(nowDark
                      ? Icons.light_mode_outlined
                      : Icons.dark_mode_outlined),
                  title: Text(nowDark ? "โหมดสว่าง" : "โหมดมืด"),
                  onTap: toggleThemeMode,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_outline_rounded),
              title: const Text("โปรไฟล์"),
              onTap: closeThen(widget.onProfile),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.asDrawer) return _buildDrawer(context);
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
                for (final (icon, label, onTap, color) in _mainItems) ...[
                  const SizedBox(height: 4),
                  _NavIcon(
                    icon: icon,
                    tooltip: label,
                    onTap: onTap,
                    color: color,
                  ),
                ],
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
