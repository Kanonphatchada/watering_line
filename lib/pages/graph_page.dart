import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shimmer/shimmer.dart';

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
  bool isLoading = true;

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

    // 🔥 โหลด logs (แสดงแค่ 30 รายการล่าสุด ไม่ให้กราฟรกเกินไป)
    final logs = await FirebaseFirestore.instance
        .collection('ESP32')
        .doc(widget.nanoId)
        .collection('Logs')
        .orderBy('timestamp')
        .limitToLast(30)
        .get();

    int index = 0;
    spots.clear();

    for (var doc in logs.docs) {
      final data = doc.data();
      final moisture = (data['moisture'] as num).toDouble();

      spots.add(FlSpot(index.toDouble(), moisture));
      index++;
    }

    // 🔥 ป้องกัน crash ถ้าไม่มีข้อมูล และรวมเส้นค่าที่กำหนดไว้ในช่วงแกน Y ด้วย
    // เพื่อไม่ให้เส้นประหลุดจากพื้นที่กราฟ
    final values = [...spots.map((e) => e.y), targetMoisture];
    final lowest = values.reduce((a, b) => a < b ? a : b);
    final highest = values.reduce((a, b) => a > b ? a : b);

    // ความชื้นไม่ควรติดลบ เลยยึดขอบล่างไว้ที่ 0 เป็นอย่างน้อย
    minY = lowest - 5 < 0 ? 0 : lowest - 5;
    maxY = highest + 5;

    setState(() {
      isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("📈 ${widget.nanoId}"),
      ),
      body: isLoading ? const _GraphSkeleton() : _buildContent(),
    );
  }

  Widget _buildContent() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Card(
            margin: EdgeInsets.zero,
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
                        "ตั้งค่าความชื้น : $targetMoisture",
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Wrap(
                    spacing: 16,
                    runSpacing: 6,
                    children: [
                      _LegendSwatch(color: Colors.blue, label: "ค่าที่กำหนด"),
                      _LegendSwatch(color: Colors.green, label: "ปกติ"),
                      _LegendSwatch(
                          color: Colors.red, label: "เกินค่าที่กำหนด"),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
                child: spots.isEmpty
                    ? const Center(child: Text("ยังไม่มีข้อมูล"))
                    : BarChart(
                        BarChartData(
                          minY: minY,
                          maxY: maxY,
                          gridData: const FlGridData(show: true),
                          titlesData: FlTitlesData(
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(showTitles: true),
                            ),
                            bottomTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            topTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            rightTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                          ),
                          extraLinesData: ExtraLinesData(
                            horizontalLines: [
                              HorizontalLine(
                                y: targetMoisture,
                                color: Colors.blue,
                                strokeWidth: 2,
                                dashArray: [8, 4],
                              ),
                            ],
                          ),
                          barGroups: [
                            for (final spot in spots)
                              BarChartGroupData(
                                x: spot.x.toInt(),
                                barRods: [
                                  BarChartRodData(
                                    toY: spot.y,
                                    width: spots.length > 20 ? 6 : 12,
                                    color: spot.y > targetMoisture
                                        ? Colors.red
                                        : Colors.green,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendSwatch extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendSwatch({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
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

class _GraphSkeleton extends StatelessWidget {
  const _GraphSkeleton();

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
              height: 80,
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
