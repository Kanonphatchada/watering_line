import 'package:flutter/material.dart';

// โปรไฟล์พืชสำเร็จรูป — ลูกค้าที่ไม่ใช่สายเทคนิคไม่รู้ว่าพืชแต่ละชนิดควรตั้ง
// ความชื้นเป้าหมายกี่ % ให้เลือกชนิดพืชแทน แล้วระบบเขียน Automois ให้เอง
// (ฮาร์ดแวร์ยังอ่าน Automois ตัวเดิม ไม่ต้องแก้ firmware เลย)
//
// หน่วยเป็น % ความชื้นโดยปริมาตร (VWC — น้ำกี่ % ของปริมาตรดิน) ตามที่
// เซนเซอร์ RS485 วัดจากค่าไดอิเล็กทริกของดินแล้วรายงานออกมาตรงๆ ไม่ใช่
// สเกล 0-100 ดินส่วนใหญ่อิ่มน้ำเต็มที่ราว 40-50% เท่านั้น ถ้าตั้งเป้าสูง
// เกินนี้ firmware จะเปิดวาล์วค้างเพราะไม่มีวันถึง — ค่าข้างล่างอิงดินร่วน
// (อุ้มน้ำได้เต็มที่ ~30%, พืชเริ่มเหี่ยวถาวร ~12%) เป็นจุดเริ่มต้น ดิน
// ทรายควรต่ำลง ดินเหนียวควรสูงขึ้น ปรับตัวเลขตรงนี้ที่เดียวพอ
class PlantProfile {
  final String id;
  final String label;
  // คืออะไร — อธิบายหมวดสั้นๆ ให้คนทั่วไปรู้ว่าพืชของตัวเองเข้าหมวดไหน
  final String definition;
  final List<String> examples;
  // วิธีดูแลเรื่องน้ำ — เหตุผลที่ค่าความชื้นของหมวดนี้สูง/ต่ำ
  final String care;
  final IconData icon;
  final Color color;
  final double targetMoisture;

  const PlantProfile({
    required this.id,
    required this.label,
    required this.definition,
    required this.examples,
    required this.care,
    required this.icon,
    required this.color,
    required this.targetMoisture,
  });
}

const plantProfiles = <PlantProfile>[
  PlantProfile(
    id: 'vegetable',
    label: 'ผัก',
    definition: 'พืชที่ปลูกไว้กินใบ ลำต้น หรือผล โตเร็วและใช้น้ำมาก',
    examples: ['ผักสลัด', 'คะน้า', 'ผักบุ้ง', 'กวางตุ้ง', 'พริก'],
    care: 'ชอบดินชื้นตลอดเวลา ถ้าดินแห้งใบจะเหี่ยวและขมเร็ว',
    icon: Icons.eco,
    color: Color(0xFF43A047),
    targetMoisture: 25,
  ),
  // ไม้ผลยืนต้น (เช่น สวนทุเรียน) — ดินร่วนยอมให้แห้ง ~40% → 12 + 18×0.6 ≈ 23
  // ค่าต้องไม่ซ้ำโปรไฟล์อื่น เพราะ resolvePlantProfile หาโปรไฟล์จากค่า % ตรงๆ
  PlantProfile(
    id: 'fruit',
    label: 'ไม้ผล',
    definition: 'ไม้ยืนต้นที่ปลูกเพื่อเก็บผล รากลึก ใช้น้ำต่างกันตามช่วงของปี',
    examples: ['ทุเรียน', 'มะม่วง', 'ลำไย', 'เงาะ', 'มังคุด'],
    care: 'ดินชื้นสม่ำเสมอแต่ไม่แฉะ ช่วงก่อนออกดอกหลายชนิดต้องงดน้ำให้ต้น'
        'ออกดอก ให้ปิด Auto ตามคำแนะนำเกษตรในพื้นที่ ช่วงติดผลให้น้ำสม่ำเสมอ',
    // ไอคอนจริงวาดเองใน FruitIcon (ใช้ Icons.nature เป็นค่าสำรอง) สีฟ้าเพื่อ
    // ไม่ให้ซ้ำกับแคคตัส (ส้ม) และสีเตือนช่วงงดน้ำ (ส้มเข้ม/แดง)
    icon: Icons.nature,
    color: Color(0xFF039BE5),
    targetMoisture: 23,
  ),
  PlantProfile(
    id: 'flower',
    label: 'ไม้ดอก',
    definition: 'พืชที่ปลูกเพื่อชมดอก ต้องการน้ำสม่ำเสมอช่วงออกดอก',
    examples: ['ดาวเรือง', 'กุหลาบ', 'บานชื่น', 'เข็ม', 'พุทธรักษา'],
    care: 'ชื้นปานกลาง ไม่แฉะ ถ้าน้ำขังรากจะเน่าและดอกร่วง',
    icon: Icons.local_florist,
    color: Color(0xFFEC407A),
    targetMoisture: 22,
  ),
  PlantProfile(
    id: 'foliage',
    label: 'ไม้ประดับ',
    definition: 'พืชที่ปลูกเพื่อชมใบและทรงต้น มักปลูกในบ้านหรือที่ร่ม',
    examples: ['มอนสเตอร่า', 'พลูด่าง', 'ลิ้นมังกร', 'ยางอินเดีย'],
    care: 'ให้ผิวดินแห้งก่อนค่อยรดรอบใหม่ รดบ่อยเกินรากเน่าง่าย',
    icon: Icons.spa,
    color: Color(0xFF26A69A),
    targetMoisture: 20,
  ),
  PlantProfile(
    id: 'herb',
    label: 'สมุนไพร',
    definition: 'พืชที่ใช้ใบหรือต้นปรุงอาหารและทำยา มีกลิ่นหอมเฉพาะตัว',
    examples: ['กะเพรา', 'โหระพา', 'ตะไคร้', 'สะระแหน่', 'ข่า'],
    care: 'ชอบดินค่อนข้างแห้ง น้ำน้อยทำให้กลิ่นหอมเข้มขึ้น',
    icon: Icons.grass,
    color: Color(0xFF9CCC65),
    targetMoisture: 18,
  ),
  PlantProfile(
    id: 'cactus',
    label: 'แคคตัส',
    definition: 'แคคตัสและไม้อวบน้ำ เก็บน้ำไว้ในลำต้นหรือใบ ทนแล้งได้นาน',
    examples: ['แคคตัส', 'กุหลาบหิน', 'ว่านหางจระเข้', 'โป๊ยเซียน'],
    care: 'รดน้อยมาก ปล่อยให้ดินแห้งสนิทก่อนรด ความชื้นสูงจะเน่า',
    icon: Icons.filter_vintage,
    color: Color(0xFFFFA726),
    targetMoisture: 10,
  ),
];

// หาโปรไฟล์จากค่า Automois ตรงๆ — ค่าของแต่ละโปรไฟล์ไม่ซ้ำกัน เลยไม่ต้อง
// เก็บ id ของโปรไฟล์แยกไว้ใน Firestore (Firestore rules อนุญาตให้ client
// เขียน ESP32 ได้เฉพาะฟิลด์ที่อยู่ในลิสต์ และ Automois อยู่ในลิสต์อยู่แล้ว
// จึงไม่ต้องแก้ rules เลย) ค่าที่ไม่ตรงโปรไฟล์ไหนถือเป็น "กำหนดเอง"
PlantProfile? resolvePlantProfile(Map<String, dynamic> data) =>
    matchPlantProfile((data['Automois'] ?? 20).toDouble());

PlantProfile? matchPlantProfile(double target) {
  for (final p in plantProfiles) {
    if (p.targetMoisture == target) return p;
  }
  return null;
}

String formatMoisture(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
