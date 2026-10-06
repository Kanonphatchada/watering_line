import 'dart:math' as math;
import 'package:flutter/material.dart';

// ไอคอนผลไม้วาดเอง — Material Icons ไม่มีรูปผลไม้ (Icons.apple คือโลโก้
// บริษัท Apple) และรูปต้นไม้ดูเหมือนต้นคริสต์มาส จึงวาดผลกลมมีก้านกับใบ
// ใช้แทน Icon() ได้ตรงๆ (ขนาด/สีเหมือนกัน)
class FruitIcon extends StatelessWidget {
  final double size;
  final Color? color;

  const FruitIcon({super.key, this.size = 24, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color ?? Colors.black;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _FruitPainter(c)),
    );
  }
}

class _FruitPainter extends CustomPainter {
  final Color color;

  _FruitPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final fill = Paint()
      ..color = color
      ..isAntiAlias = true;

    // ผล — กลมกว้างเล็กน้อย เว้าตรงขั้วด้านบนให้ดูเป็นผลไม้ ไม่ใช่วงกลมเฉยๆ
    final body = Path()
      ..moveTo(s * 0.50, s * 0.34)
      ..cubicTo(s * 0.30, s * 0.22, s * 0.08, s * 0.32, s * 0.10, s * 0.58)
      ..cubicTo(s * 0.12, s * 0.82, s * 0.32, s * 0.95, s * 0.50, s * 0.92)
      ..cubicTo(s * 0.68, s * 0.95, s * 0.88, s * 0.82, s * 0.90, s * 0.58)
      ..cubicTo(s * 0.92, s * 0.32, s * 0.70, s * 0.22, s * 0.50, s * 0.34)
      ..close();
    canvas.drawPath(body, fill);

    // ก้าน
    canvas.drawLine(
      Offset(s * 0.50, s * 0.34),
      Offset(s * 0.54, s * 0.12),
      Paint()
        ..color = color
        ..strokeWidth = s * 0.07
        ..strokeCap = StrokeCap.round,
    );

    // ใบ — วงรีเอียงข้างก้าน
    canvas.save();
    canvas.translate(s * 0.70, s * 0.16);
    canvas.rotate(-math.pi / 7);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: s * 0.30, height: s * 0.14),
      fill,
    );
    canvas.restore();

    // จุดเงาสะท้อนแสงบนผล ให้ดูมีมิติ
    canvas.drawCircle(
      Offset(s * 0.33, s * 0.56),
      s * 0.07,
      Paint()..color = Colors.white.withValues(alpha: 0.35),
    );
  }

  @override
  bool shouldRepaint(_FruitPainter old) => old.color != color;
}
