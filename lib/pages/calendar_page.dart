import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:shimmer/shimmer.dart';

class CalendarPage extends StatefulWidget {
  final String nanoId; // 🔥 รับ nanoId

  const CalendarPage({super.key, required this.nanoId});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  Map<DateTime, double> moisturePerDay = {};
  double targetMoisture = 0; // 🔥 ไม่ต้อง fix แล้ว
  bool isLoading = true;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    loadData();
  }

  Future<void> loadData() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('ESP32')
          .doc(widget.nanoId) // 🔥 ใช้ nanoId จริง
          .get();

      final data = doc.data();

      if (data != null && data['Automois'] != null) {
        targetMoisture = (data['Automois'] as num).toDouble();
      }

      final now = DateTime.now();
      final past30 = now.subtract(const Duration(days: 30));

      final logs = await FirebaseFirestore.instance
          .collection('ESP32')
          .doc(widget.nanoId)
          .collection('Logs')
          .where('timestamp', isGreaterThan: past30)
          .orderBy('timestamp', descending: true)
          // กันเผื่ออุปกรณ์บันทึกถี่มาก ไม่ให้โหลดเอกสารไม่จำกัดจำนวน
          .limit(2000)
          .get();

      for (var doc in logs.docs) {
        final data = doc.data();

        final rawTimestamp = data['timestamp'];
        final rawMoisture = data['moisture'];
        // ข้าม log ที่ข้อมูลไม่ครบ (เช่น firmware เขียนกลางคัน) กันไม่ให้
        // ทั้งหน้าค้างที่ loading เพราะ log เดียวพัง
        if (rawTimestamp is! Timestamp || rawMoisture is! num) {
          continue;
        }

        final ts = rawTimestamp.toDate();
        final moisture = rawMoisture.toDouble();

        final day = DateTime(ts.year, ts.month, ts.day);
        // เรียงจากใหม่ไปเก่า และเก็บแค่ค่าแรกที่เจอของแต่ละวัน (ค่าล่าสุดของวันนั้น)
        moisturePerDay.putIfAbsent(day, () => moisture);
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  // สถานะ + สีของความชื้นวันนั้น เทียบกับค่าที่กำหนด ใช้ร่วมกันทั้ง
  // จุดสีบนปฏิทินและ dialog รายละเอียดวัน กันไม่ให้ตรรกะ 2 จุดเพี้ยนไม่ตรงกัน
  (Color, String) _statusFor(double moisture) {
    if (moisture < targetMoisture) {
      return (Colors.yellow.shade700, "ต่ำกว่าค่าที่กำหนด");
    } else if (moisture <= targetMoisture + 2) {
      return (Colors.green, "ใกล้เคียงค่าที่กำหนด");
    } else {
      return (Colors.red, "สูงกว่าค่าที่กำหนด");
    }
  }

  Color getColor(double moisture) => _statusFor(moisture).$1;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("📅 ${widget.nanoId}"),
      ),
      body: isLoading ? const _CalendarSkeleton() : _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final theme = Theme.of(context);
    final avgMoisture = moisturePerDay.isEmpty
        ? null
        : moisturePerDay.values.reduce((a, b) => a + b) / moisturePerDay.length;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700),
        child: Column(
          children: [
            Card(
              margin: const EdgeInsets.all(12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.flag, color: Color(0xFF4CAF50)),
                        const SizedBox(width: 8),
                        Text(
                          "ตั้งค่าความชื้น: $targetMoisture",
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    if (avgMoisture != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.show_chart,
                            size: 16,
                            color: theme.textTheme.bodySmall?.color,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            "ค่าเฉลี่ย 30 วัน: ${avgMoisture.toStringAsFixed(1)}",
                            style: TextStyle(
                              fontSize: 13,
                              color: theme.textTheme.bodySmall?.color,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 16,
                      runSpacing: 6,
                      children: [
                        _LegendDot(
                          color: Colors.yellow.shade700,
                          label: "ต่ำกว่าค่าที่กำหนด",
                        ),
                        const _LegendDot(
                          color: Colors.green,
                          label: "ใกล้เคียงค่าที่กำหนด",
                        ),
                        const _LegendDot(
                          color: Colors.red,
                          label: "สูงกว่าค่าที่กำหนด",
                        ),
                        _LegendDot(
                          color:
                              theme.textTheme.bodySmall?.color ?? Colors.grey,
                          label: "ไม่มีข้อมูล",
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Card(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: TableCalendar(
                    // ให้เลื่อนย้อนดูเดือนก่อนๆได้เสมอ (ไม่ใช่แค่ 30 วันล่าสุด)
                    // แม้ข้อมูลจริงจะมีแค่ 30 วันย้อนหลัง เดือนที่เก่ากว่านั้นจะ
                    // โชว์เป็น "ไม่มีข้อมูล" ตามจริง แทนที่จะล็อกไม่ให้เลื่อนไปดูเลย
                    firstDay:
                        DateTime.now().subtract(const Duration(days: 365)),
                    lastDay: DateTime.now(),
                    focusedDay: _focusedDay,
                    selectedDayPredicate: (day) =>
                        _selectedDay != null &&
                        day.year == _selectedDay!.year &&
                        day.month == _selectedDay!.month &&
                        day.day == _selectedDay!.day,
                    onPageChanged: (focusedDay) {
                      _focusedDay = focusedDay;
                    },

                    headerStyle: HeaderStyle(
                      formatButtonVisible: false,
                      titleCentered: true,
                      titleTextStyle: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: theme.textTheme.bodyLarge?.color,
                      ),
                      leftChevronIcon: Icon(
                        Icons.chevron_left,
                        color: theme.iconTheme.color,
                      ),
                      rightChevronIcon: Icon(
                        Icons.chevron_right,
                        color: theme.iconTheme.color,
                      ),
                    ),
                    daysOfWeekStyle: DaysOfWeekStyle(
                      weekdayStyle:
                          TextStyle(color: theme.textTheme.bodySmall?.color),
                      weekendStyle:
                          TextStyle(color: theme.textTheme.bodySmall?.color),
                    ),
                    calendarStyle: CalendarStyle(
                      defaultTextStyle:
                          TextStyle(color: theme.textTheme.bodyMedium?.color),
                      weekendTextStyle:
                          TextStyle(color: theme.textTheme.bodyMedium?.color),
                      outsideTextStyle:
                          TextStyle(color: theme.textTheme.bodySmall?.color),
                      todayDecoration: BoxDecoration(
                        color: const Color(0xFF2E7D32).withValues(alpha: 0.3),
                        shape: BoxShape.circle,
                      ),
                    ),

                    // 🔥 กดวันดู detail
                    onDaySelected: (selectedDay, focusedDay) {
                      final d = DateTime(
                          selectedDay.year, selectedDay.month, selectedDay.day);

                      setState(() {
                        _selectedDay = d;
                        _focusedDay = focusedDay;
                      });

                      final moisture = moisturePerDay[d];

                      showDialog(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: Text(
                            "วันที่ ${selectedDay.day}/${selectedDay.month}/${selectedDay.year}",
                          ),
                          content: moisture == null
                              ? const Text("ไม่มีข้อมูลบันทึกในวันนี้")
                              : Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text("💧 ความชื้น: $moisture"),
                                    const SizedBox(height: 4),
                                    Text("🎯 ค่าที่กำหนด: $targetMoisture"),
                                    const SizedBox(height: 10),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.circle,
                                          size: 12,
                                          color: _statusFor(moisture).$1,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          _statusFor(moisture).$2,
                                          style: TextStyle(
                                            color: _statusFor(moisture).$1,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
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

                    calendarBuilders: CalendarBuilders(
                      defaultBuilder: (context, day, focusedDay) {
                        final d = DateTime(day.year, day.month, day.day);
                        final isSelected = _selectedDay != null &&
                            d.year == _selectedDay!.year &&
                            d.month == _selectedDay!.month &&
                            d.day == _selectedDay!.day;
                        final selectionBorder = isSelected
                            ? Border.all(
                                color: theme.colorScheme.primary,
                                width: 2,
                              )
                            : null;

                        if (moisturePerDay.containsKey(d)) {
                          final moisture = moisturePerDay[d]!;

                          return Container(
                            margin: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: getColor(moisture),
                              shape: BoxShape.circle,
                              border: selectionBorder,
                            ),
                            child: Center(
                              child: Text(
                                '${day.day}',
                                style: const TextStyle(color: Colors.black87),
                              ),
                            ),
                          );
                        }

                        // ไม่มีข้อมูลบันทึกวันนี้ — ใส่วงกลมจางๆ ให้ต่างจาก
                        // วันที่ตรงเป้าหมายพอดี (ซึ่งใช้สีเขียวเหมือนกัน)
                        return Container(
                          margin: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: theme.brightness == Brightness.dark
                                ? Colors.white.withValues(alpha: 0.06)
                                : Colors.black.withValues(alpha: 0.05),
                            shape: BoxShape.circle,
                            border: selectionBorder,
                          ),
                          child: Center(
                            child: Text(
                              '${day.day}',
                              style: TextStyle(
                                color: theme.textTheme.bodySmall?.color,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).textTheme.bodySmall?.color,
          ),
        ),
      ],
    );
  }
}

class _CalendarSkeleton extends StatelessWidget {
  const _CalendarSkeleton();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? Colors.grey.shade800 : Colors.grey.shade300;
    final highlight = isDark ? Colors.grey.shade700 : Colors.grey.shade100;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Shimmer.fromColors(
        baseColor: base,
        highlightColor: highlight,
        child: Column(
          children: [
            Container(
              height: 90,
              decoration: BoxDecoration(
                color: base,
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: base,
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
