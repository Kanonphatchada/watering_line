import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shimmer/shimmer.dart';
import 'calendar_page.dart';
import 'graph_page.dart';
import 'notification_history_page.dart';
import 'add_device_page.dart';

// 🔥 [เพิ่ม] สำหรับกลับไปหน้า login
import 'login_page.dart';
import '../main.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user!.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text("🌱 หน้าหลัก"),
        actions: [
          ValueListenableBuilder<ThemeMode>(
            valueListenable: themeModeNotifier,
            builder: (context, mode, _) {
              return IconButton(
                tooltip: mode == ThemeMode.dark ? "โหมดสว่าง" : "โหมดมืด",
                icon: Icon(
                  mode == ThemeMode.dark ? Icons.light_mode : Icons.dark_mode,
                ),
                onPressed: toggleThemeMode,
              );
            },
          ),
          IconButton(
            icon: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('ESP32')
                  .where('uid', isEqualTo: uid)
                  .snapshots(),
              builder: (context, snapshot) {
                int count = 0;

                if (snapshot.hasData) {
                  for (var doc in snapshot.data!.docs) {
                    final data = doc.data() as Map<String, dynamic>;

                    double moisture = (data['Moisture'] ?? 0).toDouble();

                    double automois = (data['Automois'] ?? 20).toDouble();

                    if (moisture > automois) {
                      count++;
                    }
                  }
                }

                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.notifications),
                    Positioned(
                      right: -2,
                      top: -2,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        transitionBuilder: (child, anim) =>
                            ScaleTransition(scale: anim, child: child),
                        child: count > 0
                            ? Container(
                                key: ValueKey(count),
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                                constraints: const BoxConstraints(
                                  minWidth: 18,
                                  minHeight: 18,
                                ),
                                child: Text(
                                  '$count',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              )
                            : const SizedBox.shrink(key: ValueKey('none')),
                      ),
                    ),
                  ],
                );
              },
            ),
            onPressed: () async {
              final snapshot = await FirebaseFirestore.instance
                  .collection('ESP32')
                  .where('uid', isEqualTo: uid)
                  .get();

              List<String> alerts = [];

              for (var doc in snapshot.docs) {
                final data = doc.data();

                double moisture = (data['Moisture'] ?? 0).toDouble();

                double automois = (data['Automois'] ?? 20).toDouble();

                if (moisture > automois) {
                  alerts.add(
                    "⚠️ ${doc.id}\nความชื้น: $moisture\nค่าที่กำหนด: $automois",
                  );
                }
              }

              if (!context.mounted) return;

              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: Row(
                    children: [
                      Icon(
                        alerts.isEmpty
                            ? Icons.check_circle
                            : Icons.warning_amber_rounded,
                        color: alerts.isEmpty ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: 8),
                      const Text("แจ้งเตือน"),
                    ],
                  ),
                  content: SingleChildScrollView(
                    child: Text(
                      alerts.isEmpty
                          ? "✅ ไม่มีการแจ้งเตือน"
                          : alerts.join("\n\n"),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("ปิด"),
                    ),
                  ],
                ),
              );
            },
          ),
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(uid)
                .snapshots(),
            builder: (context, snapshot) {
              print("====== DEBUG USER ======");
              print("UID ตอนนี้: $uid");
              print("Firestore data: ${snapshot.data?.data()}");

              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              final data = snapshot.data?.data() as Map<String, dynamic>?;

              final name = data?['displayName'] ??
                  user.displayName ??
                  user.email?.split('@')[0] ??
                  "User";

              final pic = data?['pictureUrl'] ?? user.photoURL;

              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 80,
                      child: Text(
                        name,
                        style: const TextStyle(fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),

                    const SizedBox(width: 8),
                    CircleAvatar(
                      radius: 16,
                      backgroundImage: pic != null ? NetworkImage(pic) : null,
                      child: pic == null
                          ? const Icon(Icons.person, size: 16)
                          : null,
                    ),

                    // 🔥 =========================
                    // 🔥 [เพิ่ม] ปุ่ม LOGOUT
                    // 🔥 =========================
                    IconButton(
                      icon: const Icon(Icons.logout),
                      onPressed: () async {
                        // 🔥 popup ยืนยัน
                        final confirm = await showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text("ยืนยัน"),
                            content: const Text("ต้องการออกจากระบบหรือไม่"),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text("ยกเลิก"),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text("ออก"),
                              ),
                            ],
                          ),
                        );

                        // 🔥 ถ้ากดยืนยัน
                        if (confirm == true) {
                          await FirebaseAuth.instance.signOut();

                          if (!context.mounted) return;

                          Navigator.pushAndRemoveUntil(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const LoginPage()),
                            (route) => false,
                          );
                        }
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('ESP32')
            .where('uid', isEqualTo: uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text("❌ ERROR: ${snapshot.error}"));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _HomeSkeleton();
          }

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.sensors_off,
                      size: 56,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      "ยังไม่มีอุปกรณ์ของคุณ",
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "เพิ่มอุปกรณ์เพื่อเริ่มติดตามความชื้น",
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AddDevicePage(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.add),
                      label: const Text("เพิ่มอุปกรณ์"),
                    ),
                  ],
                ),
              ),
            );
          }

          int alertCount = 0;
          double moistureSum = 0;
          for (final doc in docs) {
            final data = doc.data() as Map<String, dynamic>;
            final moisture = (data['Moisture'] ?? 0).toDouble();
            final automois = (data['Automois'] ?? 20).toDouble();
            moistureSum += moisture;
            if (moisture > automois) alertCount++;
          }
          final avgMoisture = moistureSum / docs.length;

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Column(
                children: [
                  _SummaryBar(
                    totalDevices: docs.length,
                    alertCount: alertCount,
                    avgMoisture: avgMoisture,
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        runSpacing: 4,
                        children: docs.map((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          final nanoId = doc.id;

                          double currentTarget =
                              (data['Automois'] ?? 20).toDouble();
                          final moisture = (data['Moisture'] ?? 0).toDouble();
                          final automois = (data['Automois'] ?? 20).toDouble();

                          final isAlert = moisture > automois;
                          TextEditingController controller =
                              TextEditingController(
                                  text: currentTarget.toString());

                          return SizedBox(
                            width: 420,
                            child: Card(
                              child: Padding(
                                padding: const EdgeInsets.all(18),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        AnimatedContainer(
                                          duration:
                                              const Duration(milliseconds: 300),
                                          width: 44,
                                          height: 44,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: isAlert
                                                ? Colors.red.shade50
                                                : const Color(0xFFE8F5E9),
                                          ),
                                          child: Icon(
                                            Icons.water_drop,
                                            color: isAlert
                                                ? Colors.red
                                                : const Color(0xFF2E7D32),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
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
                                            ],
                                          ),
                                        ),
                                        _StatusChip(isAlert: isAlert),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 12),
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
                                            child: _StatTile(
                                              icon: Icons.water_drop,
                                              label: "Moisture",
                                              value: "${data['Moisture']}",
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
                                              value: "${data['Time']}",
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
                                            value: data['Auto'] ?? false,
                                            onChanged: (val) async {
                                              await FirebaseFirestore.instance
                                                  .collection('ESP32')
                                                  .doc(nanoId)
                                                  .update({
                                                'Auto': val,
                                                if (val == true) 'Valve': false,
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
                                                if (val == true) 'Auto': false,
                                                if (val == false) 'Auto': true,
                                              });
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 14),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 10),
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
                                              color: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.color),
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
                                              controller: controller,
                                              keyboardType:
                                                  TextInputType.number,
                                              textAlign: TextAlign.center,
                                              style:
                                                  const TextStyle(fontSize: 13),
                                              decoration: const InputDecoration(
                                                isDense: true,
                                                contentPadding:
                                                    EdgeInsets.symmetric(
                                                        vertical: 8),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          SizedBox(
                                            height: 36,
                                            child: ElevatedButton(
                                              style: ElevatedButton.styleFrom(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 14),
                                              ),
                                              onPressed: () async {
                                                final newValue =
                                                    double.tryParse(
                                                        controller.text);

                                                if (newValue != null) {
                                                  await FirebaseFirestore
                                                      .instance
                                                      .collection('ESP32')
                                                      .doc(nanoId)
                                                      .update({
                                                    'Automois': newValue,
                                                  });

                                                  if (!context.mounted) return;

                                                  ScaffoldMessenger.of(context)
                                                      .showSnackBar(
                                                    const SnackBar(
                                                      content:
                                                          Text("✅ อัปเดตแล้ว"),
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
                                                  builder: (_) => CalendarPage(
                                                      nanoId: nanoId),
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
                                                  builder: (_) =>
                                                      GraphPage(nanoId: nanoId),
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
                                                  builder: (_) =>
                                                      NotificationHistoryPage(
                                                    nanoId: nanoId,
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? Colors.grey.shade800 : Colors.grey.shade300;
    final highlight = isDark ? Colors.grey.shade700 : Colors.grey.shade100;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: Shimmer.fromColors(
          baseColor: base,
          highlightColor: highlight,
          child: Wrap(
            alignment: WrapAlignment.center,
            children: List.generate(
              3,
              (_) => Container(
                width: 420,
                height: 320,
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: base,
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryBar extends StatelessWidget {
  final int totalDevices;
  final int alertCount;
  final double avgMoisture;

  const _SummaryBar({
    required this.totalDevices,
    required this.alertCount,
    required this.avgMoisture,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: _StatTile(
                icon: Icons.sensors,
                label: "อุปกรณ์ทั้งหมด",
                value: "$totalDevices",
              ),
            ),
            const _StatDivider(),
            Expanded(
              child: _StatTile(
                icon: Icons.warning_amber_rounded,
                label: "แจ้งเตือน",
                value: "$alertCount",
              ),
            ),
            const _StatDivider(),
            Expanded(
              child: _StatTile(
                icon: Icons.water_drop,
                label: "ความชื้นเฉลี่ย",
                value: avgMoisture.toStringAsFixed(1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final bool isAlert;

  const _StatusChip({required this.isAlert});

  @override
  Widget build(BuildContext context) {
    final color = isAlert ? Colors.red : Colors.green;

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
          Icon(
            isAlert ? Icons.warning_amber_rounded : Icons.check_circle,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            isAlert ? "แจ้งเตือน" : "ปกติ",
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

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
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
            Icon(icon, size: 20, color: const Color(0xFF2E7D32)),
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
