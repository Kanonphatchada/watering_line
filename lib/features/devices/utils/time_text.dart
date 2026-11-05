// ข้อความเวลาภาษาไทยแบบสั้นที่ใช้ร่วมกันหลายหน้า (การ์ดอุปกรณ์, พยากรณ์อากาศ)

// คำสั้นๆ ให้พอดีบรรทัด ("56 นาทีก่อน" แทน "56 นาทีที่แล้ว")
String relativeTimeThai(DateTime time, DateTime now) {
  final diff = now.difference(time);
  if (diff.inMinutes < 1) return "เมื่อสักครู่";
  if (diff.inMinutes < 60) return "${diff.inMinutes} นาทีก่อน";
  if (diff.inHours < 24) return "${diff.inHours} ชม.ก่อน";
  return "${diff.inDays} วันก่อน";
}

const _thaiMonths = [
  'ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.', //
  'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.',
];

// เวลาจริง (เวลาเครื่องผู้ใช้) ให้เทียบกับนาฬิกาตัวเองได้ — วันนี้โชว์แค่
// "15:43 น." วันอื่นเติมวันที่ "29 ก.ย. 15:43 น."
String clockTimeThai(DateTime time, DateTime now) {
  final hhmm = "${time.hour.toString().padLeft(2, '0')}:"
      "${time.minute.toString().padLeft(2, '0')} น.";
  final sameDay =
      time.year == now.year && time.month == now.month && time.day == now.day;
  return sameDay ? hhmm : "${time.day} ${_thaiMonths[time.month - 1]} $hhmm";
}
