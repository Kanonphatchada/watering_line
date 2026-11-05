import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/time_text.dart';

class LastUpdatedText extends StatefulWidget {
  final String nanoId;
  // ประทับจาก /update ทุกครั้งที่อุปกรณ์รายงานผ่าน backend — แต่บอร์ดบางตัว
  // เขียน Firestore ตรงๆ ไม่ผ่าน /update เลย lastSeen จะค้างค่าเก่าไว้
  // (เคยเจอค้าง 13 วันทั้งที่ Moisture ยังอัปเดตอยู่) จึงเทียบกับ log
  // ล่าสุดเสมอแล้วใช้อันที่ใหม่กว่า เหมือนที่ checkDevices.js ทำฝั่ง backend
  final Timestamp? lastSeen;

  const LastUpdatedText(
      {super.key, required this.nanoId, required this.lastSeen});

  @override
  State<LastUpdatedText> createState() => LastUpdatedTextState();
}

class LastUpdatedTextState extends State<LastUpdatedText> {
  late Stream<QuerySnapshot<Map<String, dynamic>>> _latestLog = _logStream();

  Stream<QuerySnapshot<Map<String, dynamic>>> _logStream() =>
      FirebaseFirestore.instance
          .collection('ESP32')
          .doc(widget.nanoId)
          .collection('Logs')
          .orderBy('timestamp', descending: true)
          .limit(1)
          .snapshots();

  // "x นาทีที่แล้ว" คำนวณตอน build เท่านั้น — ถ้าไม่มีข้อมูลใหม่เข้ามาการ์ด
  // จะไม่ rebuild ข้อความก็ค้าง (เช่นค้าง "3 นาทีที่แล้ว" ไปเรื่อยๆ) จึงสั่ง
  // วาดใหม่ทุก 30 วินาทีให้ตัวเลขเดินตามเวลาจริง
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant LastUpdatedText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nanoId != widget.nanoId) _latestLog = _logStream();
  }

  // แสดง Row เดิมเสมอไม่ว่าจะมีข้อมูลหรือไม่ (แค่เปลี่ยนข้อความ) กันสัดส่วน
  // การ์ดเพี้ยนไปเทียบกับอุปกรณ์ตัวอื่นที่มีข้อมูลอยู่แล้ว — บรรทัดเดียวเสมอ
  // ถ้ายาวเกินที่ว่าง (เช่นมีวันที่ด้วย) ตัวอักษรย่อลงเล็กน้อยแทนการขึ้นบรรทัดใหม่
  Widget _buildText(BuildContext context, Timestamp? ts) {
    final color = Theme.of(context).textTheme.bodySmall?.color;
    final now = DateTime.now();
    final text = ts == null
        ? "ยังไม่มีข้อมูล"
        : "${clockTimeThai(ts.toDate(), now)} · "
            "${relativeTimeThai(ts.toDate(), now)}";

    return Tooltip(
      message: ts == null ? text : "อัปเดตล่าสุด $text",
      child: Row(
        children: [
          Icon(Icons.update, size: 12, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                text,
                style: TextStyle(fontSize: 11, color: color),
                maxLines: 1,
                softWrap: false,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _latestLog,
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs;
        final logTs = (docs == null || docs.isEmpty)
            ? null
            : docs.first.data()['timestamp'] as Timestamp?;
        final seen = widget.lastSeen;
        final newest = seen == null
            ? logTs
            : logTs == null || seen.compareTo(logTs) >= 0
                ? seen
                : logTs;
        return _buildText(context, newest);
      },
    );
  }
}
