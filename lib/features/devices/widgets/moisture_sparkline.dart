import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';

class MoistureSparkline extends StatefulWidget {
  final String nanoId;

  const MoistureSparkline({super.key, required this.nanoId});

  @override
  State<MoistureSparkline> createState() => MoistureSparklineState();
}

class MoistureSparklineState extends State<MoistureSparkline> {
  // แคช future ไว้เหมือน _LastUpdatedText กันยิง query ใหม่ทุกครั้งที่การ์ด
  // rebuild ตามอุปกรณ์ตัวอื่นในกริด
  late Future<List<FlSpot>> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetchRecentReadings();
  }

  @override
  void didUpdateWidget(covariant MoistureSparkline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nanoId != widget.nanoId) {
      _future = _fetchRecentReadings();
    }
  }

  Future<List<FlSpot>> _fetchRecentReadings() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('ESP32')
        .doc(widget.nanoId)
        .collection('Logs')
        .orderBy('timestamp', descending: true)
        .limit(12)
        .get();

    final points = snapshot.docs.reversed
        .map((doc) => doc.data()['moisture'])
        .whereType<num>()
        .toList();

    return [
      for (var i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), points[i].toDouble()),
    ];
  }

  // กรอบตายตัวรอบกราฟ (ความสูงคงที่เสมอ ไม่ขยับตามข้อมูล) ใช้ทั้งตอนมีกราฟ
  // จริงและตอนยังไม่มีข้อมูล กันการ์ดหน้าตาไม่เท่ากันระหว่างอุปกรณ์ที่มี
  // ข้อมูลกับยังไม่มี — แกน Y ข้างในปรับสเกลเข้าหาข้อมูลเอง กราฟเลยไม่มีทาง
  // "โต" จนล้นกรอบนี้
  Widget _frame(BuildContext context, {required Widget child}) {
    // นูนขึ้นมาเหมือนปุ่ม "บันทึก" (ElevatedButton) แทนแบบฝังลึกที่ทำไว้ก่อน
    // — เงาอยู่ด้านล่าง/รอบขอบ ให้ดูเหมือนลอยอยู่เหนือพื้นการ์ด
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<FlSpot>>(
      future: _future,
      builder: (context, snapshot) {
        final spots = snapshot.data;
        if (spots == null || spots.length < 2) {
          return _frame(
            context,
            child: Center(
              child: Text(
                "ยังไม่มีข้อมูลกราฟ",
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
              ),
            ),
          );
        }

        final ys = spots.map((s) => s.y);
        final minY = ys.reduce((a, b) => a < b ? a : b);
        final maxY = ys.reduce((a, b) => a > b ? a : b);
        final pad = (maxY - minY) * 0.15;

        return _frame(
          context,
          child: LineChart(
            LineChartData(
              minY: minY - pad - 1,
              maxY: maxY + pad + 1,
              gridData: const FlGridData(show: false),
              titlesData: const FlTitlesData(show: false),
              borderData: FlBorderData(show: false),
              lineTouchData: const LineTouchData(enabled: false),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  color: const Color(0xFF2E7D32),
                  barWidth: 2,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    color: const Color(0xFF2E7D32).withValues(alpha: 0.08),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
