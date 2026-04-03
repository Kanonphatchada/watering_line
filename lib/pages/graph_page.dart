import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';

class GraphPage extends StatefulWidget {
  final String nanoId;

  const GraphPage({super.key, required this.nanoId});

  @override
  State<GraphPage> createState() => _GraphPageState();
}

class _GraphPageState extends State<GraphPage> {
  List<FlSpot> spots = [];
  double targetMoisture = 0;

  double minY = 0;
  double maxY = 100;

  @override
  void initState() {
    super.initState();
    loadData();
  }

  Future<void> loadData() async {
    // 🔥 โหลด target
    final doc = await FirebaseFirestore.instance
        .collection('ESP32')
        .doc(widget.nanoId)
        .get();

    final data = doc.data();
    if (data != null && data['Automois'] != null) {
      targetMoisture = (data['Automois'] as num).toDouble();
    }

    // 🔥 โหลด logs
    final logs = await FirebaseFirestore.instance
        .collection('ESP32')
        .doc(widget.nanoId)
        .collection('Logs')
        .orderBy('timestamp')
        .get();

    int index = 0;
    spots.clear();

    for (var doc in logs.docs) {
      final data = doc.data();
      final moisture = (data['moisture'] as num).toDouble();

      spots.add(FlSpot(index.toDouble(), moisture));
      index++;
    }

    // 🔥 ป้องกัน crash ถ้าไม่มีข้อมูล
    if (spots.isNotEmpty) {
      minY = spots.map((e) => e.y).reduce((a, b) => a < b ? a : b) - 5;
      maxY = spots.map((e) => e.y).reduce((a, b) => a > b ? a : b) + 5;
    }

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("📈 ${widget.nanoId}"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text("🎯 ตั้งค่าความชื้น : $targetMoisture"),

            const SizedBox(height: 20),

            Expanded(
              child: LineChart(
                LineChartData(
                  minY: minY,
                  maxY: maxY,

                  gridData: FlGridData(show: true),

                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: true),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),

                  lineBarsData: [
                    // 🔵 เส้น target
                    LineChartBarData(
                      spots: [
                        FlSpot(0, targetMoisture),
                        FlSpot(spots.length.toDouble(), targetMoisture),
                      ],
                      isCurved: false,
                      color: Colors.blue,
                      barWidth: 2,
                      dotData: FlDotData(show: false),
                    ),

                    // 📈 เส้น moisture จริง
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      barWidth: 3,
                      dotData: FlDotData(show: false),
                      gradient: const LinearGradient(
                        colors: [
                          Colors.green,
                          Colors.orange,
                          Colors.red,
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}