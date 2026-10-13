import 'package:cloud_firestore/cloud_firestore.dart';
import 'farm_members.dart';
import 'my_devices.dart';

// กลุ่มอุปกรณ์ที่ตั้งชื่อเอง (เช่น "ผักกาด", "กวางตุ้ง") เพื่อแยกว่าอุปกรณ์ตัวไหน
// ปลูกอะไร — คนละเรื่องกับ groupId ของอุปกรณ์ ซึ่งคือ "ฟาร์ม" ที่ผูกตอนเพิ่มอุปกรณ์
//
// กลุ่มเป็นของ "ฟาร์ม": เก็บเป็น array ใน device_registry/{farmId}.deviceGroups
// ทุกคนในฟาร์ม (เจ้าของ + สมาชิกทุกระดับ) จึงเห็นกลุ่มเดียวกันเป๊ะ แก้ได้เฉพาะ
// เจ้าของและสมาชิกระดับ "จัดการได้" (Firestore rules: settingsUids) อุปกรณ์หนึ่ง
// ตัวอยู่ได้กลุ่มเดียว กลุ่มหนึ่งมีได้เฉพาะอุปกรณ์ของฟาร์มเดียวกัน
//
// เดิม (รุ่นก่อนมีสมาชิก) เก็บเป็นของแต่ละคนใน users/{uid}.deviceGroups —
// migrateLegacyGroups ย้ายกลุ่มเก่าขึ้นฟาร์มให้เองอัตโนมัติ
const defaultGroupIconKey = 'leaf';

class DeviceGroup {
  final String id;
  final String name;
  final List<String> deviceIds;
  // ไอคอน/สีที่ผู้ใช้เลือกให้การ์ดกลุ่ม (คีย์ไอคอนดูที่ group_style.dart) —
  // กลุ่มที่สร้างไว้ก่อนมีฟีเจอร์นี้ไม่มีสองฟิลด์นี้ ใช้ค่าตั้งต้นแทน
  final String iconKey;
  final int colorIndex;
  // ฟาร์มที่กลุ่มนี้อยู่ (= id ของเอกสาร device_registry ที่เก็บกลุ่มนี้) ไม่ได้ถูก
  // เก็บซ้ำในตัวกลุ่ม — ได้มาจากเอกสารที่อ่าน; null เฉพาะกลุ่มรุ่นเก่าของผู้ใช้
  final String? farmId;

  const DeviceGroup({
    required this.id,
    required this.name,
    this.deviceIds = const [],
    this.iconKey = defaultGroupIconKey,
    this.colorIndex = 0,
    this.farmId,
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
        farmId: farmId,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'deviceIds': deviceIds,
        'iconKey': iconKey,
        'colorIndex': colorIndex,
      };

  static DeviceGroup? fromMap(Object? raw, {String? farmId}) {
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
      farmId: farmId,
    );
  }
}

// อ่านกลุ่มจากเอกสารที่เก็บ (เอกสารฟาร์ม หรือ users ของรุ่นเก่า)
List<DeviceGroup> parseDeviceGroups(Map<String, dynamic>? data,
    {String? farmId}) {
  final raw = data?['deviceGroups'];
  if (raw is! List) return const [];
  return raw
      .map((g) => DeviceGroup.fromMap(g, farmId: farmId))
      .whereType<DeviceGroup>()
      .toList();
}

List<DeviceGroup> groupsOfFarm(List<DeviceGroup> groups, String farmId) =>
    groups.where((g) => g.farmId == farmId).toList();

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

// ฟาร์มของอุปกรณ์แต่ละตัว (nanoId → farmId) — รับข้อมูลอุปกรณ์เป็น (id, map) ล้วนๆ
// (ไม่ผูกกับ Firestore) เพื่อให้เทสได้
Map<String, String> farmOfDevicesFrom(
  Iterable<(String id, Map<String, dynamic> data)> devices,
) =>
    {
      for (final (id, data) in devices)
        if (data['groupId'] is String) id: data['groupId'] as String,
    };

// ฟาร์มที่ผู้ใช้แก้กลุ่มได้ (เจ้าของ หรือสมาชิกระดับจัดการได้) — ตรงกับ Firestore
// rules ที่ให้เขียน deviceGroups ได้เฉพาะ settingsUids
Set<String> editableFarmsFrom(
  Iterable<Map<String, dynamic>> devices,
  String? uid,
) =>
    {
      for (final data in devices)
        if (canSettingsDevice(data, uid) && data['groupId'] is String)
          data['groupId'] as String,
    };

Iterable<(String, Map<String, dynamic>)> _pairs(
  List<QueryDocumentSnapshot> docs,
) =>
    docs.map((d) => (d.id, d.data() as Map<String, dynamic>));

Map<String, String> farmOfDevices(List<QueryDocumentSnapshot> docs) =>
    farmOfDevicesFrom(_pairs(docs));

Set<String> editableFarmIds(List<QueryDocumentSnapshot> docs, String? uid) =>
    editableFarmsFrom(_pairs(docs).map((p) => p.$2), uid);

// กลุ่มทั้งหมดของทุกฟาร์มที่ผู้ใช้อยู่ (เป็นเจ้าของหรือสมาชิก) รวมเป็นรายการเดียว
Stream<List<DeviceGroup>> watchMyGroups(String uid) => watchMyFarms(uid).map(
      (farms) => [
        for (final f in farms)
          ...parseDeviceGroups(
            f.data() as Map<String, dynamic>?,
            farmId: f.id,
          ),
      ],
    );

// แก้กลุ่มของฟาร์มหนึ่งฟาร์ม: อ่านค่าล่าสุดในธุรกรรมก่อนแก้ แล้วเขียนกลับทั้งก้อน
// — กันสองคนแก้พร้อมกัน (เจ้าของกับสมาชิกระดับจัดการ) แล้วทับกัน
Future<void> updateFarmGroups(
  String farmId,
  List<DeviceGroup> Function(List<DeviceGroup> current) change,
) {
  final ref =
      FirebaseFirestore.instance.collection('device_registry').doc(farmId);
  return FirebaseFirestore.instance.runTransaction((tx) async {
    final snap = await tx.get(ref);
    final next = change(parseDeviceGroups(snap.data(), farmId: farmId));
    tx.update(ref, {'deviceGroups': next.map((g) => g.toMap()).toList()});
  });
}

String newGroupId() => 'g${DateTime.now().microsecondsSinceEpoch}';

// ───────── ย้ายกลุ่มรุ่นเก่า (ของแต่ละคน) ขึ้นไปไว้ที่ฟาร์ม ─────────

// ชื่อที่ไม่ซ้ำกับกลุ่มที่มีอยู่ในฟาร์ม (ซ้ำก็ต่อท้ายเลข 2, 3, ...) ไม่ยาวเกินกำหนด
String uniqueGroupName(String name, List<DeviceGroup> existing) {
  final taken = existing.map((g) => g.name.trim().toLowerCase()).toSet();
  final base = name.trim();
  if (!taken.contains(base.toLowerCase())) return base;
  for (var i = 2;; i++) {
    final suffix = ' $i';
    final cut = base.length + suffix.length > maxGroupNameLength
        ? base.substring(0, maxGroupNameLength - suffix.length)
        : base;
    final candidate = '$cut$suffix';
    if (!taken.contains(candidate.toLowerCase())) return candidate;
  }
}

// id ที่ได้จากกลุ่มเก่า + ฟาร์ม (คงที่เสมอ) เพื่อให้ย้ายซ้ำกี่รอบก็ไม่ได้กลุ่มซ้ำ
String migratedGroupId(String legacyId, String farmId) =>
    'm_${legacyId}_$farmId';

class LegacyMigrationPlan {
  final Map<String, List<DeviceGroup>> additions; // farmId → กลุ่มที่ต้องเพิ่ม
  final Set<String>
      migratedLegacyIds; // กลุ่มเก่าที่จัดการเสร็จแล้ว (ลบทิ้งได้)

  const LegacyMigrationPlan(this.additions, this.migratedLegacyIds);
}

// วางแผนย้ายกลุ่มเก่าของผู้ใช้ไปไว้ที่ฟาร์มของอุปกรณ์ในกลุ่ม (กลุ่มที่มีอุปกรณ์ต่าง
// ฟาร์มจะแตกเป็นหลายกลุ่มชื่อเดียวกัน ฟาร์มละกลุ่ม) ไม่แตะกลุ่มที่ฟาร์มใดฟาร์มหนึ่ง
// ผู้ใช้ยังไม่มีสิทธิ์แก้ (รอไว้ย้ายทีหลัง) อุปกรณ์ที่ถูกจัดกลุ่มในฟาร์มแล้วไม่ถูกย้าย
// ซ้ำ ชื่อซ้ำกับกลุ่มในฟาร์มจะต่อท้ายเลข กลุ่มที่ไม่เหลืออุปกรณ์เลยย้ายเข้าฟาร์มเดียว
// ที่แก้ได้ (ถ้ามีฟาร์มเดียว) ไม่งั้นทิ้ง
LegacyMigrationPlan planLegacyMigration({
  required List<DeviceGroup> legacy,
  required Map<String, String> farmOfDevice,
  required Map<String, List<DeviceGroup>> existingByFarm,
  required Set<String> editableFarms,
}) {
  final additions = <String, List<DeviceGroup>>{};
  final migrated = <String>{};
  final working = {
    for (final e in existingByFarm.entries) e.key: [...e.value],
  };

  for (final g in legacy) {
    final byFarm = <String, List<String>>{};
    for (final d in g.deviceIds) {
      final farm = farmOfDevice[d];
      if (farm != null) (byFarm[farm] ??= []).add(d);
    }
    if (byFarm.isEmpty) {
      if (editableFarms.length == 1) {
        byFarm[editableFarms.first] = [];
      } else if (editableFarms.isNotEmpty) {
        migrated
            .add(g.id); // ไม่รู้ว่าควรอยู่ฟาร์มไหน และไม่มีอุปกรณ์ให้เสียหาย
        continue;
      } else {
        continue; // ยังไม่มีสิทธิ์แก้ที่ไหนเลย รอไว้
      }
    }
    if (!byFarm.keys.every(editableFarms.contains)) continue;

    for (final entry in byFarm.entries) {
      final inFarm = working.putIfAbsent(entry.key, () => []);
      final id = migratedGroupId(g.id, entry.key);
      if (inFarm.any((x) => x.id == id)) continue; // เคยย้ายแล้ว
      final taken = inFarm.expand((x) => x.deviceIds).toSet();
      final moved = DeviceGroup(
        id: id,
        name: uniqueGroupName(g.name, inFarm),
        deviceIds: entry.value.where((d) => !taken.contains(d)).toList(),
        iconKey: g.iconKey,
        colorIndex: g.colorIndex,
        farmId: entry.key,
      );
      inFarm.add(moved);
      (additions[entry.key] ??= []).add(moved);
    }
    migrated.add(g.id);
  }
  return LegacyMigrationPlan(additions, migrated);
}

// ทำจริง: อ่านกลุ่มเก่าใน users/{uid} → เพิ่มเข้าฟาร์ม → ลบกลุ่มเก่าที่ย้ายแล้ว
// ถ้าข้อไหนล้มเหลว (เช่น rules ยังไม่อนุญาต) กลุ่มเก่ายังอยู่ ลองใหม่ได้ครั้งหน้า
// และย้ายซ้ำก็ไม่ได้กลุ่มซ้ำ (id คงที่) — เรียกจากหน้าหลัก ผู้เรียกควรดักข้อผิดพลาดเอง
Future<void> migrateLegacyGroups(
  String uid,
  List<QueryDocumentSnapshot> devices,
) async {
  final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
  final legacy = parseDeviceGroups((await userRef.get()).data());
  if (legacy.isEmpty) return;

  final farmOf = farmOfDevices(devices);
  final editable = editableFarmIds(devices, uid);
  final existing = <String, List<DeviceGroup>>{};
  for (final farm in editable) {
    final snap = await FirebaseFirestore.instance
        .collection('device_registry')
        .doc(farm)
        .get();
    existing[farm] = parseDeviceGroups(snap.data(), farmId: farm);
  }

  final plan = planLegacyMigration(
    legacy: legacy,
    farmOfDevice: farmOf,
    existingByFarm: existing,
    editableFarms: editable,
  );
  for (final entry in plan.additions.entries) {
    await updateFarmGroups(
      entry.key,
      (cur) => [
        ...cur,
        ...entry.value.where((a) => !cur.any((c) => c.id == a.id)),
      ],
    );
  }
  if (plan.migratedLegacyIds.isEmpty) return;
  final remaining = legacy
      .where((g) => !plan.migratedLegacyIds.contains(g.id))
      .map((g) => g.toMap())
      .toList();
  await userRef.set({'deviceGroups': remaining}, SetOptions(merge: true));
}
