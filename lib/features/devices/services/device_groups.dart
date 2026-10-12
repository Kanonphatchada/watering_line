import 'package:cloud_firestore/cloud_firestore.dart';

// กลุ่มอุปกรณ์ที่ผู้ใช้ตั้งชื่อเอง (เช่น "ผักกาด", "กวางตุ้ง") เพื่อแยกว่าอุปกรณ์
// ตัวไหนปลูกอะไร — คนละเรื่องกับ groupId ของอุปกรณ์ ซึ่งคือ "ฟาร์ม" ที่ผูกตอน
// เพิ่มอุปกรณ์ (device_registry) กลุ่มนี้เป็นแค่ป้ายจัดหมวดฝั่งผู้ใช้
//
// เก็บเป็น array เดียวใน users/{uid}.deviceGroups แทนการเขียน field ใหม่ลง
// ESP32 doc ของอุปกรณ์ เพราะ rules ของ ESP32 จำกัด field ที่ client แก้ได้ และ
// งานแก้ rules ยังพักไว้ (ดู project_firestore_rules_hardening) — อุปกรณ์หนึ่ง
// ตัวอยู่ได้กลุ่มเดียว
const defaultGroupIconKey = 'leaf';

class DeviceGroup {
  final String id;
  final String name;
  final List<String> deviceIds;
  // ไอคอน/สีที่ผู้ใช้เลือกให้การ์ดกลุ่ม (คีย์ไอคอนดูที่ group_style.dart) —
  // กลุ่มที่สร้างไว้ก่อนมีฟีเจอร์นี้ไม่มีสองฟิลด์นี้ ใช้ค่าตั้งต้นแทน
  final String iconKey;
  final int colorIndex;

  const DeviceGroup({
    required this.id,
    required this.name,
    this.deviceIds = const [],
    this.iconKey = defaultGroupIconKey,
    this.colorIndex = 0,
  });

  DeviceGroup copyWith({
    String? name,
    List<String>? deviceIds,
    String? iconKey,
    int? colorIndex,
  }) =>
      DeviceGroup(
        id: id,
        name: name ?? this.name,
        deviceIds: deviceIds ?? this.deviceIds,
        iconKey: iconKey ?? this.iconKey,
        colorIndex: colorIndex ?? this.colorIndex,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'deviceIds': deviceIds,
        'iconKey': iconKey,
        'colorIndex': colorIndex,
      };

  static DeviceGroup? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final name = raw['name'];
    if (id is! String || name is! String) return null;
    final ids = raw['deviceIds'];
    return DeviceGroup(
      id: id,
      name: name,
      deviceIds: ids is List ? ids.whereType<String>().toList() : const [],
      iconKey: raw['iconKey'] is String
          ? raw['iconKey'] as String
          : defaultGroupIconKey,
      colorIndex: raw['colorIndex'] is int ? raw['colorIndex'] as int : 0,
    );
  }
}

List<DeviceGroup> parseDeviceGroups(Map<String, dynamic>? userData) {
  final raw = userData?['deviceGroups'];
  if (raw is! List) return const [];
  return raw.map(DeviceGroup.fromMap).whereType<DeviceGroup>().toList();
}

const maxGroupNameLength = 30;

// ชื่อกลุ่มที่ใช้ได้: ไม่ว่าง ไม่ยาวเกิน และไม่ซ้ำกับกลุ่มอื่น (ไม่สนตัวพิมพ์
// เล็ก/ใหญ่) คืนข้อความ error หรือ null ถ้าใช้ได้ — exceptId = กลุ่มที่กำลังแก้
// ชื่ออยู่ (ไม่นับว่าซ้ำกับตัวเอง)
String? validateGroupName(
  String name,
  List<DeviceGroup> groups, {
  String? exceptId,
}) {
  final n = name.trim();
  if (n.isEmpty) return "ใส่ชื่อกลุ่มก่อน";
  if (n.length > maxGroupNameLength) {
    return "ชื่อยาวเกินไป (ไม่เกิน $maxGroupNameLength ตัวอักษร)";
  }
  final dup = groups.any(
    (g) => g.id != exceptId && g.name.trim().toLowerCase() == n.toLowerCase(),
  );
  return dup ? "มีกลุ่มชื่อนี้อยู่แล้ว" : null;
}

DeviceGroup? groupOfDevice(List<DeviceGroup> groups, String nanoId) {
  for (final g in groups) {
    if (g.deviceIds.contains(nanoId)) return g;
  }
  return null;
}

// ตั้งสมาชิกของกลุ่ม groupId เป็น deviceIds ทั้งชุด — อุปกรณ์ที่ถูกเลือกจะถูก
// ย้ายออกจากกลุ่มเดิมของมันเอง (อยู่ได้กลุ่มเดียว) ส่วนที่เคยอยู่ในกลุ่มนี้แต่
// ไม่ได้เลือกแล้วจะกลับไปเป็น "ไม่ได้จัดกลุ่ม"
List<DeviceGroup> setGroupMembers(
  List<DeviceGroup> groups,
  String groupId,
  Iterable<String> deviceIds,
) {
  final chosen = deviceIds.toSet();
  return [
    for (final g in groups)
      if (g.id == groupId)
        g.copyWith(deviceIds: chosen.toList())
      else
        g.copyWith(
          deviceIds: g.deviceIds.where((d) => !chosen.contains(d)).toList(),
        ),
  ];
}

List<DeviceGroup> addGroup(
  List<DeviceGroup> groups,
  DeviceGroup group,
) =>
    [...groups, group];

List<DeviceGroup> renameGroup(
  List<DeviceGroup> groups,
  String groupId,
  String name,
) =>
    [
      for (final g in groups)
        if (g.id == groupId) g.copyWith(name: name.trim()) else g,
    ];

List<DeviceGroup> restyleGroup(
  List<DeviceGroup> groups,
  String groupId, {
  required String iconKey,
  required int colorIndex,
}) =>
    [
      for (final g in groups)
        if (g.id == groupId)
          g.copyWith(iconKey: iconKey, colorIndex: colorIndex)
        else
          g,
    ];

// สรุปสถานะของอุปกรณ์ในกลุ่มสำหรับการ์ดกลุ่ม/หน้ารายละเอียด — รับ Map ของ
// เอกสารอุปกรณ์ตรงๆ (ไม่ผูกกับ Firestore) จะได้เทสได้ ตรรกะ "ต้องดู" เดียวกับ
// หน้าหลัก: ดินแห้งกว่าเป้า (Automois), ขาดการติดต่อ หรือมี faultType
class GroupStats {
  final int count;
  final double? avgMoisture; // null ถ้าไม่มีอุปกรณ์
  final int dryCount;
  final int offlineCount;
  final int faultCount;
  // อุปกรณ์ที่ต้องดู — นับตัวเดียวครั้งเดียวไม่ว่าจะมีปัญหากี่อย่าง
  final int needsAttention;

  const GroupStats({
    required this.count,
    required this.avgMoisture,
    required this.dryCount,
    required this.offlineCount,
    required this.faultCount,
    required this.needsAttention,
  });
}

GroupStats computeGroupStats(List<Map<String, dynamic>> devices) {
  var moistureSum = 0.0;
  var dry = 0, offline = 0, fault = 0, attention = 0;
  for (final d in devices) {
    final moisture = ((d['Moisture'] ?? 0) as num).toDouble();
    final target = ((d['Automois'] ?? 20) as num).toDouble();
    moistureSum += moisture;
    final isDry = moisture < target;
    final isOffline = d['offline'] == true;
    final isFault = !isOffline && d['faultType'] != null;
    if (isDry) dry++;
    if (isOffline) offline++;
    if (isFault) fault++;
    if (isDry || isOffline || isFault) attention++;
  }
  return GroupStats(
    count: devices.length,
    avgMoisture: devices.isEmpty ? null : moistureSum / devices.length,
    dryCount: dry,
    offlineCount: offline,
    faultCount: fault,
    needsAttention: attention,
  );
}

List<DeviceGroup> removeGroup(List<DeviceGroup> groups, String groupId) =>
    groups.where((g) => g.id != groupId).toList();

// อุปกรณ์ที่ถูกลบ/ยกเลิกการผูกไปแล้วอาจยังค้างอยู่ในรายชื่อสมาชิก — ตัดทิ้งตอน
// แสดงผล/บันทึกเพื่อไม่ให้นับเกินจริง
List<DeviceGroup> pruneMissingDevices(
  List<DeviceGroup> groups,
  Set<String> existingIds,
) =>
    [
      for (final g in groups)
        g.copyWith(
          deviceIds: g.deviceIds.where(existingIds.contains).toList(),
        ),
    ];

Stream<List<DeviceGroup>> watchDeviceGroups(String uid) =>
    FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .map((s) => parseDeviceGroups(s.data()));

// อ่านค่าล่าสุดจากเซิร์ฟเวอร์ในทรานแซกชันก่อนแก้ แล้วเขียนกลับทั้งก้อน — กัน
// เคสเปิดสองแท็บ/สองเครื่องแล้วแก้พร้อมกันจนทับกัน; set+merge เพื่อให้ใช้ได้
// ถึงจะยังไม่มี users doc
Future<void> updateDeviceGroups(
  String uid,
  List<DeviceGroup> Function(List<DeviceGroup> current) change,
) {
  final ref = FirebaseFirestore.instance.collection('users').doc(uid);
  return FirebaseFirestore.instance.runTransaction((tx) async {
    final snap = await tx.get(ref);
    final next = change(parseDeviceGroups(snap.data()));
    tx.set(
      ref,
      {'deviceGroups': next.map((g) => g.toMap()).toList()},
      SetOptions(merge: true),
    );
  });
}

String newGroupId() => 'g${DateTime.now().microsecondsSinceEpoch}';
