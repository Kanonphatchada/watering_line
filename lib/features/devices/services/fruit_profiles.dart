import 'plant_profile.dart';

// ไม้ผลแต่ละชนิดต้องการน้ำไม่เท่ากันตามช่วงของปี (โดยเฉพาะช่วงก่อนออกดอก
// ที่ต้องงดน้ำให้ต้นเครียดถึงจะออกดอก) เลยแยกเป็นช่วงให้เกษตรกรเลือกว่าตอนนี้
// อยู่ช่วงไหน แล้วระบบเขียน Automois ของช่วงนั้นให้ — ช่วงเครียดน้ำไม่ได้ปิด
// การรดน้ำ แต่ตั้งเป้าต่ำใกล้จุดเหี่ยว ต้นได้เครียดแต่ยังมีวาล์วกันตายไว้
//
// ตัวเลขเป็นจุดเริ่มต้นบนสเกลดินร่วน (จุดเหี่ยว ~12%, อุ้มน้ำเต็มที่ ~30%)
// จากหลักปฏิบัติทั่วไป ไม่ได้ทดลองกับสวนจริง หน้าตั้งค่าจึงให้แก้ตัวเลขเองได้
// ทุกช่วง ควรปรับตามดินและคำแนะนำของเกษตรในพื้นที่
class FruitStage {
  final String id;
  final String label;
  final String description;
  final double targetMoisture;
  // true = ช่วงงดน้ำให้ต้นเครียด (แสดงป้ายเตือนในหน้าตั้งค่า + การ์ดนับวัน
  // ที่หน้าหลัก) minDays/maxDays = ช่วงวันที่แนะนำ ใช้กับช่วงเครียดเท่านั้น
  final bool stress;
  final int? minDays;
  final int? maxDays;

  const FruitStage({
    required this.id,
    required this.label,
    required this.description,
    required this.targetMoisture,
    this.stress = false,
    this.minDays,
    this.maxDays,
  });
}

class FruitProfile {
  final String id;
  final String label;
  final List<FruitStage> stages;

  const FruitProfile({
    required this.id,
    required this.label,
    required this.stages,
  });
}

const fruitProfiles = <FruitProfile>[
  FruitProfile(id: 'durian', label: 'ทุเรียน', stages: [
    FruitStage(
      id: 'recover',
      label: 'บำรุงต้นหลังเก็บเกี่ยว',
      description: 'ตัดแต่งกิ่ง ใส่ปุ๋ย เร่งแตกใบอ่อน ให้น้ำสม่ำเสมอ',
      targetMoisture: 24,
    ),
    FruitStage(
      id: 'store',
      label: 'สะสมอาหาร',
      description: 'ใบอ่อนเริ่มแก่ ลดน้ำลงเล็กน้อยให้ต้นสะสมอาหาร',
      targetMoisture: 20,
    ),
    FruitStage(
      id: 'induce',
      label: 'ชักนำดอก (ทำให้ต้นเครียด)',
      description: 'งดน้ำให้ดินแห้งจนต้นเครียด จะเริ่มออกตาดอก '
          'ทั่วไปใช้เวลาราว 1–3 สัปดาห์',
      targetMoisture: 14,
      stress: true,
      minDays: 7,
      maxDays: 21,
    ),
    FruitStage(
      id: 'bloom',
      label: 'ออกดอก',
      description: 'ค่อยๆ เพิ่มน้ำทีละน้อย ถ้าให้มากทันทีดอกอาจร่วง '
          'หรือแตกเป็นใบอ่อนแทน',
      targetMoisture: 18,
    ),
    FruitStage(
      id: 'fruiting',
      label: 'ติดผลและขยายผล',
      description: 'ต้องการน้ำมากและสม่ำเสมอ ห้ามขาดน้ำ ผลจะร่วงหรือบิดเบี้ยว',
      targetMoisture: 25,
    ),
    FruitStage(
      id: 'preharvest',
      label: 'ก่อนเก็บเกี่ยว',
      description: 'ราว 1 เดือนก่อนตัด ลดน้ำลงช่วยให้เนื้อแห้ง ลดอาการไส้ซึม',
      targetMoisture: 20,
    ),
  ]),
  FruitProfile(id: 'mango', label: 'มะม่วง', stages: [
    FruitStage(
      id: 'recover',
      label: 'บำรุงต้นหลังเก็บเกี่ยว',
      description: 'ตัดแต่งกิ่ง ใส่ปุ๋ย ให้น้ำสม่ำเสมอเพื่อแตกใบอ่อน',
      targetMoisture: 23,
    ),
    FruitStage(
      id: 'store',
      label: 'สะสมอาหาร',
      description: 'ใบแก่เต็มที่ ลดน้ำลงให้ต้นพักตัว',
      targetMoisture: 19,
    ),
    FruitStage(
      id: 'induce',
      label: 'ชักนำดอก (ทำให้ต้นเครียด)',
      description: 'งดน้ำช่วงอากาศแห้งเย็น ต้นเครียดแล้วจะออกช่อดอก',
      targetMoisture: 14,
      stress: true,
      minDays: 14,
      maxDays: 28,
    ),
    FruitStage(
      id: 'bloom',
      label: 'ออกดอก',
      description: 'ให้น้ำน้อยๆ พอดินไม่แห้งจัด น้ำมากไปช่อดอกร่วง',
      targetMoisture: 17,
    ),
    FruitStage(
      id: 'fruiting',
      label: 'ติดผลและขยายผล',
      description: 'เพิ่มน้ำให้สม่ำเสมอ ผลจะโตเต็มที่และไม่ร่วง',
      targetMoisture: 24,
    ),
    FruitStage(
      id: 'preharvest',
      label: 'ก่อนเก็บเกี่ยว',
      description: 'ลดน้ำลง ผลหวานขึ้น และลดผลแตก',
      targetMoisture: 19,
    ),
  ]),
  FruitProfile(id: 'longan', label: 'ลำไย', stages: [
    FruitStage(
      id: 'recover',
      label: 'บำรุงต้นหลังเก็บเกี่ยว',
      description: 'ตัดแต่งกิ่ง ใส่ปุ๋ย ให้น้ำสม่ำเสมอเร่งใบอ่อน',
      targetMoisture: 23,
    ),
    FruitStage(
      id: 'store',
      label: 'สะสมอาหาร',
      description: 'ใบแก่เต็มที่ ลดน้ำลงเล็กน้อย',
      targetMoisture: 20,
    ),
    FruitStage(
      id: 'induce',
      label: 'ชักนำดอก (ทำให้ต้นเครียด)',
      description: 'ลดน้ำให้ต้นพักตัวก่อนออกดอก ถ้าใช้สารราดเร่งดอก '
          'ให้ให้น้ำตามคำแนะนำของสารนั้นแทน',
      targetMoisture: 15,
      stress: true,
      minDays: 7,
      maxDays: 21,
    ),
    FruitStage(
      id: 'bloom',
      label: 'ออกดอก',
      description: 'ให้น้ำพอประมาณ สม่ำเสมอ',
      targetMoisture: 19,
    ),
    FruitStage(
      id: 'fruiting',
      label: 'ติดผลและขยายผล',
      description: 'ต้องการน้ำมาก ขาดน้ำผลเล็กและร่วง',
      targetMoisture: 24,
    ),
    FruitStage(
      id: 'preharvest',
      label: 'ก่อนเก็บเกี่ยว',
      description: 'ลดน้ำลงเล็กน้อย ช่วยให้เนื้อหวานกรอบ',
      targetMoisture: 21,
    ),
  ]),
  FruitProfile(id: 'rambutan', label: 'เงาะ', stages: [
    FruitStage(
      id: 'recover',
      label: 'บำรุงต้นหลังเก็บเกี่ยว',
      description: 'ตัดแต่งกิ่ง ใส่ปุ๋ย ให้น้ำสม่ำเสมอ',
      targetMoisture: 24,
    ),
    FruitStage(
      id: 'store',
      label: 'สะสมอาหาร',
      description: 'ใบแก่ ลดน้ำลงเล็กน้อยให้ต้นสะสมอาหาร',
      targetMoisture: 20,
    ),
    FruitStage(
      id: 'induce',
      label: 'ชักนำดอก (ทำให้ต้นเครียด)',
      description: 'ต้องการช่วงแล้งราว 2–3 สัปดาห์ งดน้ำจนใบเริ่มสลด',
      targetMoisture: 14,
      stress: true,
      minDays: 14,
      maxDays: 21,
    ),
    FruitStage(
      id: 'bloom',
      label: 'ออกดอก',
      description: 'เริ่มให้น้ำทีละน้อยแล้วค่อยๆ เพิ่ม',
      targetMoisture: 19,
    ),
    FruitStage(
      id: 'fruiting',
      label: 'ติดผลและขยายผล',
      description: 'ให้น้ำสม่ำเสมอ ขาดน้ำผลเล็ก ขนแห้งไม่สวย',
      targetMoisture: 25,
    ),
    FruitStage(
      id: 'preharvest',
      label: 'ก่อนเก็บเกี่ยว',
      description: 'ให้น้ำสม่ำเสมอต่อ ไม่ลดมากเพราะผลจะเล็ก',
      targetMoisture: 23,
    ),
  ]),
  FruitProfile(id: 'mangosteen', label: 'มังคุด', stages: [
    FruitStage(
      id: 'recover',
      label: 'บำรุงต้นหลังเก็บเกี่ยว',
      description: 'ใส่ปุ๋ย ให้น้ำสม่ำเสมอ มังคุดชอบดินชื้น',
      targetMoisture: 25,
    ),
    FruitStage(
      id: 'store',
      label: 'สะสมอาหาร',
      description: 'ใบแก่ ลดน้ำลงเล็กน้อย',
      targetMoisture: 21,
    ),
    FruitStage(
      id: 'induce',
      label: 'ชักนำดอก (ทำให้ต้นเครียด)',
      description: 'ต้องการช่วงแล้งราว 2–4 สัปดาห์ งดน้ำจนใบเริ่มสลด',
      targetMoisture: 15,
      stress: true,
      minDays: 14,
      maxDays: 28,
    ),
    FruitStage(
      id: 'bloom',
      label: 'ออกดอก',
      description: 'กลับมาให้น้ำ ค่อยๆ เพิ่มขึ้น',
      targetMoisture: 20,
    ),
    FruitStage(
      id: 'fruiting',
      label: 'ติดผลและขยายผล',
      description: 'ให้น้ำมากและสม่ำเสมอ',
      targetMoisture: 26,
    ),
    FruitStage(
      id: 'preharvest',
      label: 'ก่อนเก็บเกี่ยว',
      description: 'ให้น้ำสม่ำเสมอ อย่าปล่อยแห้งแล้วรดหนักทันที '
          'จะเกิดเนื้อแก้วยางไหล',
      targetMoisture: 23,
    ),
  ]),
];

FruitProfile? fruitById(String? id) =>
    fruitProfiles.where((f) => f.id == id).firstOrNull;

// ชื่อที่แสดงบนการ์ด/รายการอุปกรณ์ — ถ้ามีบันทึกไม้ผลไว้ใน users/{uid}
// .plantSettings และค่า % ยังตรงกับที่บันทึก ให้แสดง "ทุเรียน · ออกดอก"
// ถ้ามีคนแก้ Automois ทางอื่นไปแล้ว (ค่าไม่ตรง) กลับไปเดาจาก % แบบเดิม
String plantLabelFor(double target, Map<String, dynamic>? setting) {
  if (setting != null &&
      setting['plant'] == 'fruit' &&
      (setting['target'] as num?)?.toDouble() == target) {
    final fruit = fruitById(setting['fruit'] as String?);
    final stage =
        fruit?.stages.where((s) => s.id == setting['stage']).firstOrNull;
    if (fruit != null) {
      return stage == null ? fruit.label : "${fruit.label} · ${stage.label}";
    }
  }
  return matchPlantProfile(target)?.label ?? 'กำหนดเอง';
}

enum StressLevel { ok, near, over }

// สถานะช่วงงดน้ำของอุปกรณ์หนึ่งตัว — ใช้ทั้งการ์ด "ต้นที่กำลังงดน้ำ" ที่หน้า
// หลักและป้ายบนการ์ดอุปกรณ์ `since` = วันที่เริ่มงดน้ำ (บันทึกตอนเลือกช่วงนี้
// ครั้งแรก), `days` = จำนวนวันที่ตั้งใจงด (เริ่มจาก maxDays แก้เองได้)
class StressStatus {
  final FruitProfile fruit;
  final FruitStage stage;
  final DateTime since;
  final int plannedDays;

  const StressStatus({
    required this.fruit,
    required this.stage,
    required this.since,
    required this.plannedDays,
  });

  // วันที่เริ่ม = วันที่ 1
  int get dayNumber {
    final now = DateTime.now();
    final start = DateTime(since.year, since.month, since.day);
    return DateTime(now.year, now.month, now.day).difference(start).inDays + 1;
  }

  int get daysLeft => plannedDays - dayNumber;

  // เหลือไม่เกิน 2 วัน = ใกล้ครบ (ส้ม), เกินกำหนด = อันตราย (แดง)
  StressLevel get level => daysLeft < 0
      ? StressLevel.over
      : daysLeft <= 2
          ? StressLevel.near
          : StressLevel.ok;
}

// null ถ้าอุปกรณ์ไม่ได้อยู่ในช่วงงดน้ำ หรือ Automois ถูกเปลี่ยนทางอื่นไปแล้ว
// (ค่าไม่ตรงกับที่บันทึก) — กันการ์ดเตือนค้างทั้งที่เลิกงดน้ำไปแล้ว
StressStatus? stressStatusFor(double target, Map<String, dynamic>? setting) {
  if (setting == null ||
      setting['plant'] != 'fruit' ||
      (setting['target'] as num?)?.toDouble() != target) {
    return null;
  }
  final fruit = fruitById(setting['fruit'] as String?);
  final stage =
      fruit?.stages.where((s) => s.id == setting['stage']).firstOrNull;
  final since = setting['since'];
  if (fruit == null || stage == null || !stage.stress || since is! num) {
    return null;
  }
  return StressStatus(
    fruit: fruit,
    stage: stage,
    since: DateTime.fromMillisecondsSinceEpoch(since.toInt()),
    plannedDays: (setting['days'] as num?)?.toInt() ?? stage.maxDays ?? 14,
  );
}
