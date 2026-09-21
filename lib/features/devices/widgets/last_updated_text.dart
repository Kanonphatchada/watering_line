import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LastUpdatedText extends StatefulWidget {
  final String nanoId;
  // ประทับจาก /update ตรงๆ ทุกครั้งที่อุปกรณ์รายงานค่าจริง — อัปเดตสดตาม
  // stream ของ ESP32 doc อยู่แล้ว ไม่ต้อง query ซ้ำ ถ้าเป็น null (อุปกรณ์เก่า
  // ที่ยังไม่เคยได้รับ /update รอบใหม่) จะ fallback ไปดู log ล่าสุดแทน
  final Timestamp? lastSeen;

  const LastUpdatedText(
      {super.key, required this.nanoId, required this.lastSeen});

  @override
  State<LastUpdatedText> createState() => LastUpdatedTextState();
}

class LastUpdatedTextState extends State<LastUpdatedText> {
  Future<Timestamp?>? _fallbackFuture;

  @override
  void initState() {
    super.initState();
    if (widget.lastSeen == null) {
      _fallbackFuture = _fetchLatestLogTimestamp();
    }
  }

  @override
  void didUpdateWidget(covariant LastUpdatedText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.lastSeen != null) {
      _fallbackFuture = null;
    } else if (oldWidget.nanoId != widget.nanoId ||
        oldWidget.lastSeen != null) {
      _fallbackFuture = _fetchLatestLogTimestamp();
    }
  }

  Future<Timestamp?> _fetchLatestLogTimestamp() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('ESP32')
        .doc(widget.nanoId)
        .collection('Logs')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) return null;
    return snapshot.docs.first.data()['timestamp'] as Timestamp?;
  }

  String _relativeTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return "เมื่อสักครู่";
    if (diff.inMinutes < 60) return "${diff.inMinutes} นาทีที่แล้ว";
    if (diff.inHours < 24) return "${diff.inHours} ชม. ที่แล้ว";
    return "${diff.inDays} วันที่แล้ว";
  }

  // แสดง Row เดิมเสมอไม่ว่าจะมีข้อมูลหรือไม่ (แค่เปลี่ยนข้อความ) กันสัดส่วน
  // การ์ดเพี้ยนไปเทียบกับอุปกรณ์ตัวอื่นที่มีข้อมูลอยู่แล้ว
  Widget _buildText(BuildContext context, Timestamp? ts) {
    final color = Theme.of(context).textTheme.bodySmall?.color;

    return Row(
      children: [
        Icon(Icons.update, size: 12, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            ts == null
                ? "ยังไม่มีข้อมูล"
                : "อัปเดต: ${_relativeTime(ts.toDate())}",
            style: TextStyle(fontSize: 11, color: color),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.lastSeen != null) {
      return _buildText(context, widget.lastSeen);
    }

    return FutureBuilder<Timestamp?>(
      future: _fallbackFuture,
      builder: (context, snapshot) => _buildText(context, snapshot.data),
    );
  }
}
