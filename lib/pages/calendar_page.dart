import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:table_calendar/table_calendar.dart';

class CalendarPage extends StatefulWidget {
  final String nanoId; // 🔥 รับ nanoId

  const CalendarPage({super.key, required this.nanoId});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  Map<DateTime, double> moisturePerDay = {};
  double targetMoisture = 0; // 🔥 ไม่ต้อง fix แล้ว

  @override
  void initState() {
    super.initState();
    loadData();
  }

  Future<void> loadData() async {
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
        .get();

    for (var doc in logs.docs) {
      final data = doc.data();

      final ts = (data['timestamp'] as Timestamp).toDate();
      final moisture = (data['moisture'] as num).toDouble();

      final day = DateTime(ts.year, ts.month, ts.day);
      moisturePerDay[day] = moisture;
    }

    setState(() {});
  }

  Color getColor(double moisture) {
    if (moisture < targetMoisture) {
      return Colors.yellow;
    } else if (moisture <= targetMoisture + 2) {
      return Colors.green;
    } else {
      return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("📅 ${widget.nanoId}"),
      ),
      body: Column(
        children: [
          Text("🎯 ตั้งค่าความชื้น: $targetMoisture"),
          Expanded(
            child: TableCalendar(
              firstDay: DateTime.now().subtract(const Duration(days: 30)),
              lastDay: DateTime.now(),
              focusedDay: DateTime.now(),

              // 🔥 กดวันดู detail
              onDaySelected: (selectedDay, focusedDay) {
                final d = DateTime(
                    selectedDay.year, selectedDay.month, selectedDay.day);

                final moisture = moisturePerDay[d];

                showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: Text("วันที่ ${selectedDay.day}"),
                    content: Text(
                      moisture != null ? "💧 $moisture" : "ไม่มีข้อมูล",
                    ),
                  ),
                );
              },

              calendarBuilders: CalendarBuilders(
                defaultBuilder: (context, day, focusedDay) {
                  final d = DateTime(day.year, day.month, day.day);

                  if (moisturePerDay.containsKey(d)) {
                    final moisture = moisturePerDay[d]!;

                    return Container(
                      margin: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: getColor(moisture),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text('${day.day}'),
                      ),
                    );
                  }

                  return null;
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
